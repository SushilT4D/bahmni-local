#!/usr/bin/env bash
# The physical foreign keys on obs, orders and drug_order in the hub's
# OpenMRS schema, read from information_schema. Read-only.
#
#   hub/scripts/check-clinical-fks.sh --container NAME [--database DB]
#   hub/scripts/check-clinical-fks.sh --from FILE
#
# Two checks:
#   OUT  No foreign key may point OUT of obs, orders or drug_order. The hub's
#        up sinks write one table each, in arrival order, and a clinic's obs
#        can arrive before the encounter it belongs to; with no FK out of the
#        table the early row is written and its parent follows. One FK out
#        turns that ordinary early arrival into a stopped sink. Any such FK
#        fails the check, named. A module upgrade can add one, so run this
#        before and after every hub upgrade, and before any up sink for these
#        tables is registered.
#   IN   The FKs pointing INTO the three tables are compared with
#        hub/clinical-fks-in.conf. These do not stop a sink on an early
#        arrival, but each makes a clinic's delete of a referenced row fail
#        the sink. A difference is reported, added or gone.
#
# --container  the hub's MySQL container (queried as root inside it)
# --database   the OpenMRS schema (default openmrs)
# --from       a file holding the query's output instead (tab-separated:
#              table, column, referenced table, referenced column, constraint)
#
# Exit status: 0 both checks pass; 1 an FK out of a clinical table (or the
# read failed); 2 no FK out, but the FKs in differ from the recorded list.
# RUNTIME=docker|podman picks the container engine (default: whichever answers).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "${HERE}/.." && pwd)"
BASELINE="${CLINICAL_FKS_IN:-${HUB_DIR}/clinical-fks-in.conf}"
CLINICAL="obs orders drug_order"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
die(){ printf 'FAIL %s\n' "$*"; exit 1; }
MY=""; DB=openmrs; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --container) MY="${2:?--container needs a name}"; shift 2 ;;
    --database) DB="${2:?--database needs a name}"; shift 2 ;;
    --from) FROM="${2:?--from needs a file}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || die "bad database name: $DB"
[ -f "$BASELINE" ] || die "no ${BASELINE}: the recorded FKs into the clinical tables are required"

SQL="SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME, CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = '${DB}' AND REFERENCED_TABLE_NAME IS NOT NULL AND (TABLE_NAME IN ('obs', 'orders', 'drug_order') OR REFERENCED_TABLE_NAME IN ('obs', 'orders', 'drug_order')) ORDER BY 1, 2;
SELECT 'schema', COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '${DB}' AND TABLE_NAME IN ('obs', 'orders', 'drug_order');"
if [ -n "$FROM" ]; then
  [ -f "$FROM" ] || die "no such file: $FROM"
  rows="$(cat "$FROM")"
else
  [ -n "$MY" ] || { usage >&2; die "--container or --from is required"; }
  CT="${RUNTIME:-}"
  if [ -z "$CT" ]; then for c in docker podman; do command -v "$c" >/dev/null 2>&1 && "$c" ps >/dev/null 2>&1 && { CT="$c"; break; }; done; fi
  [ -n "$CT" ] || die "no working container engine (tried docker, podman)"
  rows="$(printf '%s\n' "$SQL" | "$CT" exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B' 2>/dev/null)" \
    || die "could not read information_schema in ${MY}; nothing was checked"
fi
# the three tables must be there, or "no FK out" would be a check of nothing
n="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="schema" {print $2}')"
[ "${n:-}" = 3 ] || die "${DB} does not hold obs, orders and drug_order (found ${n:-no answer}); nothing was checked"
rows="$(printf '%s\n' "$rows" | awk -F'\t' 'NF >= 4 && $1 != "schema"')"

rc=0
for t in $CLINICAL; do
  out="$(printf '%s\n' "$rows" | awk -F'\t' -v t="$t" '$1==t {print $1 "." $2 " -> " $3 "." $4 " (" $5 ")"}')"
  if [ -n "$out" ]; then
    printf 'FAIL %s has %s foreign key(s) out of it; an early-arriving row would stop its up sink:\n' "$t" "$(printf '%s\n' "$out" | grep -c .)"
    printf '%s\n' "$out" | sed 's/^/       /'
    rc=1
  else
    printf 'ok   %s: no foreign key out\n' "$t"
  fi
done
want="$(awk '{ sub(/#.*/, "") } NF == 4 { print $1, $2, $3, $4 }' "$BASELINE" | LC_ALL=C sort)"
got="$(printf '%s\n' "$rows" | awk -F'\t' '$3=="obs" || $3=="orders" || $3=="drug_order" {print $1, $2, $3, $4}' | LC_ALL=C sort)"
added="$(LC_ALL=C comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | grep . || true)"
gone="$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | grep . || true)"
if [ -z "$added" ] && [ -z "$gone" ]; then
  printf 'ok   %s foreign key(s) into obs, orders and drug_order, as recorded in %s\n' "$(printf '%s\n' "$got" | grep -c . || true)" "${BASELINE##*/}"
else
  [ -z "$added" ] || { printf 'CHANGED foreign key(s) into the clinical tables not in %s (a clinic'"'"'s delete of a row they reference would stop that sink):\n' "${BASELINE##*/}"; printf '%s\n' "$added" | awk '{print "       + " $1 "." $2 " -> " $3 "." $4}'; }
  [ -z "$gone" ] || { printf 'CHANGED foreign key(s) into the clinical tables recorded in %s but no longer on this hub:\n' "${BASELINE##*/}"; printf '%s\n' "$gone" | awk '{print "       - " $1 "." $2 " -> " $3 "." $4}'; }
  [ "$rc" = 1 ] || rc=2
fi
exit "$rc"
