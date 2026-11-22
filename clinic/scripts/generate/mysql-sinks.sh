#!/bin/bash
# Part of generate-connectors.sh: the MySQL (OpenMRS) down sink, one for every table in the
# [down] section of sync/tables/openmrs.conf, reading cloud.<cloud>.openmrs.all, written to
# connectors/mysql-local-sink-all.json. The sink password stays a placeholder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${ROOT}/connectors"
TEMPLATE="${ROOT}/scripts/templates/mysql-local-sink-connector.json"
# The [down] section of TABLES_CONF is the list of tables the sink writes.
TABLES_CONF="${TABLES_CONF:-${ROOT}/../sync/tables/openmrs.conf}"
# The clinic's OWN capture list ([up]). Read only to refuse overlap — see the ownership guard below.
UP_TABLES_CONF="${UP_TABLES_CONF:-${ROOT}/../sync/tables/openmrs.conf}"
# shellcheck source=../../sync/tables/tables.sh
. "${ROOT}/../sync/tables/tables.sh"

[[ -f "$TEMPLATE"    ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
[[ -f "$TABLES_CONF" ]] || { echo "missing table list: $TABLES_CONF" >&2; exit 1; }
DOWN_LINES="$(tables_section "$TABLES_CONF" down)" || exit 1
UP_LINES=""; [[ -f "$UP_TABLES_CONF" ]] && { UP_LINES="$(tables_section "$UP_TABLES_CONF" up)" || exit 1; }
up_lines(){ printf '%s\n' "$UP_LINES"; }

# shellcheck disable=SC1091
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

CLOUD_SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}"
CLOUD_DB="${CLOUD_MYSQL_DATABASE:-openmrs}"

# the mirrored name on the clinic, e.g. cloud.bahmni-cloud.openmrs.all
SRC_PREFIX="cloud.${CLOUD_SERVER_NAME}.${CLOUD_DB}."

# ---------------------------------------------------------------------------
# Validate the complete table list before writing configs.
# ---------------------------------------------------------------------------
TABLES=(); ROUTE_COLS=(); CHANGES_ONLY=()
while read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    f="$(printf '%s' "$line" | awk '{print $1}')"
    t="$(printf '%s' "$f" | cut -d: -f1)"
    keycols="$(printf '%s' "$f" | cut -s -d: -f2)"
    role="$(printf '%s' "$f" | cut -s -d: -f3)"
    [[ -n "$t" ]] || continue
    TABLES+=("$t")
    case "$role" in clinic=*) ROUTE_COLS+=("${role#clinic=}") ;; *) ROUTE_COLS+=("") ;; esac
    case "$role" in changes) CHANGES_ONLY+=(1) ;; *) CHANGES_ONLY+=(0) ;; esac
done <<EOF_DOWN
$DOWN_LINES
EOF_DOWN

# Route rows only when their referenced clinic-owned ID meets its floor/residue.
need_residue=no
for c in "${ROUTE_COLS[@]}"; do [[ -n "$c" ]] && need_residue=yes; done
RESIDUE_OWN=""
declare -a ROUTE_BASES=()
route_table(){ case "$1" in visit_id) echo visit ;; order_id) echo orders ;; *) return 1 ;; esac; }
route_base(){ # COLUMN -> the base of the table it points at
    local t b k
    t="$(route_table "$1")" || { echo "sync/tables/openmrs.conf [down] routes by '$1'; a clinic can route only by visit_id or order_id" >&2; return 1; }
    b="$(up_lines | grep -E "^[[:space:]]*${t}:[^:]+:" | head -1 | awk '{print $1}' | cut -d: -f3)"
    if [[ "$b" == seed ]]; then
        k="FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
        b="${!k:-}"
        [[ -n "$b" ]] || b="$(sed -n "s/^${k}=//p" "${ROOT}/.install-state" 2>/dev/null | tail -1)"
        [[ "$b" =~ ^[1-9][0-9]*$ ]] || { echo "${k} (the ${t} floor recorded at seeding) is not in ${ROOT}/.env or ${ROOT}/.install-state; the lab-result sinks need it" >&2; return 1; }
    fi
    [[ "$b" =~ ^[1-9][0-9]*$ ]] || { echo "${UP_TABLES_CONF} gives no base for ${t}; the lab-result sinks need it" >&2; return 1; }
    printf '%s' "$b"
}
if [[ "$need_residue" == yes ]]; then
    RESIDUE_OWN="${BHS_SITE_NUMBER:-}"
    [[ -n "$RESIDUE_OWN" ]] || { [[ -n "${BHS_SITE_NUMBER:-}" ]] && RESIDUE_OWN=$(( BHS_SITE_NUMBER % 10 )); }
    [[ "$RESIDUE_OWN" =~ ^[1-9]$ ]] || { echo "this clinic's residue (BHS_SITE_NUMBER, 1-9) is not set: the lab-result sinks keep only this clinic's rows and cannot be generated without it" >&2; exit 1; }
fi
for i in "${!ROUTE_COLS[@]}"; do
    if [[ -n "${ROUTE_COLS[$i]}" ]]; then ROUTE_BASES[$i]="$(route_base "${ROUTE_COLS[$i]}")" || exit 1
    else ROUTE_BASES[$i]=""; fi
done

(( ${#TABLES[@]} )) || { echo "no tables found in $TABLES_CONF" >&2; exit 1; }

# Refuse clinic-owned sinks unless binlogging is disabled to prevent sync loops.
if [[ -n "$UP_LINES" ]] && ! grep -q 'sql_log_bin=0' "$TEMPLATE"; then
    for t in "${TABLES[@]}"; do
        if up_lines | grep -qE "^[[:space:]]*${t}:"; then
            {
              echo "REFUSING ${t}: it is clinic-owned (listed in ${UP_TABLES_CONF})."
              echo "  A down-direction sink would write cloud rows into a table the clinic authors."
              echo "  The clinic also captures that table, so the write would re-enter the binlog and"
              echo "  loop back through the cloud — with no MySQL row filter to stop it."
              echo "  Nothing was generated."
            } >&2
            exit 1
        fi
    done
fi

mkdir -p "$OUT"
rm -f "$OUT"/mysql-local-sink-*.json

# One sink for every [down] table; each table's filter runs inside one Filter step keyed on the table name.
SPECS=""
for i in "${!TABLES[@]}"; do
    SPECS="${SPECS}${TABLES[$i]}	${CHANGES_ONLY[$i]}	${ROUTE_COLS[$i]}	${ROUTE_BASES[$i]}
"
done

SPECS="$SPECS" RESIDUE_OWN="$RESIDUE_OWN" \
TEMPLATE="$TEMPLATE" KAFKA_TOPICS="${SRC_PREFIX}all" \
python3 - "$OUT/mysql-local-sink-all.json" <<'PYEOF'
import json, os, re, sys

raw = open(os.environ['TEMPLATE']).read()
for key in ('KAFKA_TOPICS',):
    raw = raw.replace('${%s}' % key, os.environ[key])

doc = json.loads(raw)
# drop the //-prefixed documentation keys: Connect would report them as unknown configs
doc['config'] = {k: v for k, v in doc['config'].items() if not k.startswith('//')}
cfg = doc['config']

# ${OPENMRS_SINK_PASSWORD} stays a placeholder: register-connectors.sh fills it from .env;
# ${source.table} is the sink's own routing variable.
leftover = [k for k, v in cfg.items()
            if '${' in str(v).replace('${OPENMRS_SINK_PASSWORD}', '').replace('${source.table}', '')]
if leftover:
    sys.exit(f"unsubstituted placeholder(s) in {leftover}")

def route(col, base, r):
    # only rows whose column points at a row this clinic wrote; tombstones carry no row and are dropped
    return ("{ -> def r = value == null ? null : (value.get('after') != null ? value.get('after') : value.get('before')); "
            f"r != null && r.get('{col}') instanceof Number && r.get('{col}').longValue() >= {base}L "
            f"&& r.get('{col}').longValue() % 10 == {r} }}()")

# changes-only tables keep no deletes or tombstones
NO_DELETES = "(value != null && value.get('op') != 'd')"

branches = []
for line in os.environ['SPECS'].splitlines():
    if not line:
        continue
    t, ch, rc, rb = (line.split('\t') + [''] * 4)[:4]
    conds = []
    if rc:
        conds.append(route(rc, rb, os.environ['RESIDUE_OWN']))
    if ch == '1':
        conds.append(NO_DELETES)
    if conds:
        branches.append(f"t == '{t}' ? ({' && '.join(conds)})")

if branches:
    cfg['transforms'] = 'rowsThisClinicKeeps'
    cfg['transforms.rowsThisClinicKeeps.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.rowsThisClinicKeeps.language'] = 'jsr223.groovy'
    cfg['transforms.rowsThisClinicKeeps.null.handling.mode'] = 'evaluate'
    cfg['transforms.rowsThisClinicKeeps.condition'] = (
        "def t = keySchema?.name()?.tokenize('.')?.getAt(-2); " + " : ".join(branches) + " : true")

json.dump(doc, open(sys.argv[1], 'w'), indent=2)
PYEOF
python3 "${ROOT}/scripts/_fill_template.py" --mark "$OUT/mysql-local-sink-all.json" "$TEMPLATE"

echo "  mysql-local-sink-all.json: one down sink for ${#TABLES[@]} tables"
echo "  mirrored topic : ${SRC_PREFIX}all"
echo "  target         : bahmni-mysql:3306/openmrs"
