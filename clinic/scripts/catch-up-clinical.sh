#!/usr/bin/env bash
# Request incremental snapshots of clinic-owned clinical rows.
#
# Usage (from the clinic directory):
#   scripts/catch-up-clinical.sh --dry-run [--id RUN] [TABLE ...]   print what would be signalled; touches nothing
#   scripts/catch-up-clinical.sh [--id RUN] [TABLE ...]             count the rows, then insert one signal per table
#   scripts/catch-up-clinical.sh --status                           what the connector's offsets say is in progress
# TABLE defaults to seeded tables; RUN defaults to the current UTC time.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PROJECT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
TABLES_CONF="${REPO_ROOT}/sync/tables/openmrs.conf"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTOR=mysql-source-connector

usage(){ sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//'; }
die(){ printf 'catch-up: %s\n' "$*" >&2; exit 1; }

DRY=0; STATUS=0; RUN=""; want=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --status) STATUS=1; shift ;;
    --id) RUN="${2:-}"; [ -n "$RUN" ] || die "--id needs a value"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option $1" ;;
    *) want="${want} $1"; shift ;;
  esac
done
case "$RUN" in '') RUN="$(date -u +%Y%m%dT%H%M%SZ)" ;; *[!A-Za-z0-9_-]*) die "--id takes letters, digits, _ and - only" ;; esac

# Report the source connector's incremental-snapshot progress when requested.
if [ "$STATUS" = 1 ]; then
  # Kafka Connect returns the connector's source offsets; while an incremental
  # snapshot runs they carry the collections it still has to read
  offs="$(curl -sf --max-time 10 "${CONNECT_URL}/connectors/${CONNECTOR}/offsets")" || die "could not read ${CONNECTOR}'s offsets from ${CONNECT_URL}"
  printf '%s' "$offs" | python3 -c '
import json, sys
d = json.load(sys.stdin)
busy = []
for o in d.get("offsets", []):
    c = o.get("offset", {}).get("incremental_snapshot_collections")
    if c:
        try:
            busy += [x.get("incremental_snapshot_collections_id", "?") for x in json.loads(c)]
        except Exception:
            busy.append(str(c))
if busy:
    print("in progress: " + ", ".join(busy))
else:
    print("no incremental snapshot in progress (the source offsets name no collection still to read)")
'
  exit 0
fi

[ -f "${ENV_FILE}" ] || die ".env not found at ${ENV_FILE}"
# Load clinic identity and seed-derived table floors.
set -a; . "${ENV_FILE}"; set +a
DB=openmrs
case "${BHS_SITE_NUMBER:-}" in [1-9]) ;; *) die "BHS_SITE_NUMBER in ${ENV_FILE} is '${BHS_SITE_NUMBER:-}', not a clinic residue (1 to 9)" ;; esac
FLOORS_FILE="${SEED_MANIFEST:-${PROJECT_DIR}/.install-state}"
. "${REPO_ROOT}/sync/tables/tables.sh"
recs="$(up_tables_read "${TABLES_CONF}")" || die "${TABLES_CONF} cannot be read (reason above)"
SIGNAL="$(up_signal_collection "${DB}")"

# Build the selected table plan as "table pk floor" records.
plan=""
while read -r t pk kind _arg; do
  [ -n "$t" ] || continue
  case "$kind" in seed|floor) ;; *) continue ;; esac
  if [ -n "$want" ]; then case " ${want} " in *" ${t} "*) ;; *) continue ;; esac; fi
  fl="$(up_floor_of "${TABLES_CONF}" "$t" "${FLOORS_FILE}")" || die "the ${t} floor cannot be read (reason above)"
  plan="${plan}${t} ${pk} ${fl}
"
done <<EOF
${recs}
EOF
for t in $want; do
  printf '%s' "$plan" | awk -v t="$t" '$1==t {f=1} END {exit !f}' \
    || die "${t} is not a table of ${TABLES_CONF} whose floor comes from the seed or from another table; only those are caught up"
done
[ -n "$plan" ] || { echo "catch-up: no table of ${TABLES_CONF} has a floor from the seed or from another table; nothing to catch up"; exit 0; }

cond_of(){ printf '%s >= %s AND %s %% 10 = %s' "$1" "$2" "$1" "${BHS_SITE_NUMBER}"; }
signal_sql(){ # TABLE PK FLOOR
  local data
  data="$(printf '{"data-collections": ["%s.%s"], "type": "incremental", "additional-conditions": [{"data-collection": "%s.%s", "filter": "%s"}]}' "$DB" "$1" "$DB" "$1" "$(cond_of "$2" "$3")")"
  printf "INSERT INTO %s (id, type, data) VALUES ('catch-up-%s-%s', 'execute-snapshot', '%s');\n" "$SIGNAL" "$1" "$RUN" "$data"
}
count_sql(){ printf 'SELECT COUNT(*) FROM %s.`%s` WHERE %s;\n' "$DB" "$1" "$(cond_of "$2" "$3")"; }

# Print the SQL without touching MySQL in dry-run mode.
if [ "$DRY" = 1 ]; then
  echo "-- catch-up, residue ${BHS_SITE_NUMBER}, run ${RUN} (dry run: nothing counted, nothing inserted)"
  printf '%s' "$plan" | while read -r t pk fl; do
    [ -n "$t" ] || continue
    printf -- '-- %s: rows this clinic owns\n' "$t"
    count_sql "$t" "$pk" "$fl"
    signal_sql "$t" "$pk" "$fl"
  done
  exit 0
fi

# Verify the connector captures every table and its signal channel.
cfg="$(curl -sf --max-time 10 "${CONNECT_URL}/connectors/${CONNECTOR}/config")" || die "could not read ${CONNECTOR}'s configuration from ${CONNECT_URL}; is Kafka Connect up?"
inc="$(printf '%s' "$cfg" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("table.include.list",""))')"
for t in "${SIGNAL#*.}" $(printf '%s' "$plan" | awk '{print $1}'); do
  case ",${inc}," in *",${DB}.${t},"*) ;; *) die "${CONNECTOR} does not capture ${DB}.${t}; regenerate and register it first (scripts/generate-connectors.sh, then scripts/register-connectors.sh mysql-source-connector). Nothing was signalled." ;; esac
done

CT="${CONTAINER_TOOL:-}"
if [ -z "$CT" ]; then for c in docker podman; do command -v "$c" >/dev/null 2>&1 && "$c" ps >/dev/null 2>&1 && { CT="$c"; break; }; done; fi
[ -n "$CT" ] || die "no working container engine (tried docker, podman)"
MY="${MYSQL_CONTAINER:-${COMPOSE_PROJECT_NAME:-bahmni}-bahmni-mysql-1}"
mysql_root(){ "$CT" exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }

echo "catch-up: residue ${BHS_SITE_NUMBER}, run ${RUN}"
# Count clinic-owned rows and submit one snapshot signal per table.
total=0
while read -r t pk fl; do
  [ -n "$t" ] || continue
  n="$(count_sql "$t" "$pk" "$fl" | mysql_root | tail -1)" || die "could not count ${t} rows on ${MY}"
  case "$n" in ''|*[!0-9]*) die "could not count ${t} rows on ${MY} (got '${n}')" ;; esac
  signal_sql "$t" "$pk" "$fl" | mysql_root >/dev/null || die "could not insert the ${t} signal into ${SIGNAL}; ${total} row(s) signalled before it"
  printf '  %s: %s row(s) with %s, signalled as catch-up-%s-%s\n' "$t" "$n" "$(cond_of "$pk" "$fl")" "$t" "$RUN"
  total=$((total + n))
done <<EOF
${plan}
EOF
echo "catch-up: ${total} row(s) in all. The hub should then hold each count above for this clinic's residue at or above the floor."
echo "Progress: scripts/catch-up-clinical.sh --status (done when no collection is left in progress)."
