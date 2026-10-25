#!/bin/bash
# generate-local-sink-connectors.sh — render the DOWN-direction (cloud → clinic) sinks.
#
# One connector per cloud-owned table from hub/tables.conf. These run ON THE
# CLINIC and write into the clinic's OpenMRS DB.
#
# Deliberate choices, each one closing a defect a generator can have:
#   - the template is a FILE and substitution is explicit, so the RegexRouter
#     replacement "$1" is never exposed to the shell (an unquoted heredoc expands
#     it to empty and every connector dies with `Invalid identifier:`);
#   - every topic-prefix component is a variable, so a second clinic is not
#     blocked by a hardcoded `source.<clinic>.openmrs.`;
#   - connection.restart.on.errors is set in the template (see it for why).
#
# Usage: ./scripts/generate-local-sink-connectors.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/../sync/local/connectors/generated}"
TEMPLATE="${ROOT}/../sync/local/connectors/mysql-local-sink-connector.json.template"
TABLES_CONF="${TABLES_CONF:-${ROOT}/../hub/tables.conf}"
# The clinic's OWN capture list. Read only to refuse overlap — see the ownership guard below.
UP_TABLES_CONF="${UP_TABLES_CONF:-${ROOT}/../sync/local/tables.conf}"

[[ -f "$TEMPLATE"    ]] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
[[ -f "$TABLES_CONF" ]] || { echo "missing table list: $TABLES_CONF" >&2; exit 1; }

# shellcheck disable=SC1091
[[ -f "${ROOT}/.env" ]] && set -a && source "${ROOT}/.env" && set +a

CLOUD_SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}"
CLOUD_DB="${CLOUD_MYSQL_DATABASE:-openmrs}"
MM2_REMOTE_ALIAS="${MM2_REMOTE_ALIAS:-remote}"     # MM2 cluster alias for the cloud
LOCAL_MYSQL_HOST="${LOCAL_MYSQL_HOST:-bahmni-mysql}"
LOCAL_MYSQL_PORT="${LOCAL_MYSQL_PORT:-3306}"
LOCAL_MYSQL_DATABASE="${LOCAL_MYSQL_DATABASE:-openmrs}"
LOCAL_MYSQL_USE_SSL="${LOCAL_MYSQL_USE_SSL:-false}"
LOCAL_MYSQL_USER="${LOCAL_MYSQL_USER:-${SINK_DB_USER:-sink}}"
LOCAL_MYSQL_PASSWORD="${LOCAL_MYSQL_PASSWORD:-${SINK_DB_PASSWORD:-}}"

[[ -n "$LOCAL_MYSQL_PASSWORD" ]] || { echo "LOCAL_MYSQL_PASSWORD (or SINK_DB_PASSWORD) is unset — refusing to emit a passwordless connector" >&2; exit 1; }

# the mirrored name on the clinic, e.g. remote.bahmni-cloud.openmrs.users
SRC_PREFIX="${MM2_REMOTE_ALIAS}.${CLOUD_SERVER_NAME}.${CLOUD_DB}."
PREFIX_REGEX="^$(printf '%s' "$SRC_PREFIX" | sed 's/\./\\\\./g')(.*)\$"

# ---------------------------------------------------------------------------
# Read the table list ONCE, then validate the whole list before writing anything.
#
# `read` needs the `|| [[ -n "$line" ]]` fallback or a final line with no trailing
# newline is silently dropped — one table would lose its sink while the run still
# reported success. The up-direction generator already guards this; this one did not.
# ---------------------------------------------------------------------------
TABLES=(); ROUTE_COLS=(); CHANGES_ONLY=()
while read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    f="$(printf '%s' "$line" | awk '{print $1}')"
    t="$(printf '%s' "$f" | cut -d: -f1)"
    role="$(printf '%s' "$f" | cut -s -d: -f3)"
    [[ -n "$t" ]] || continue
    TABLES+=("$t")
    case "$role" in clinic=*) ROUTE_COLS+=("${role#clinic=}") ;; *) ROUTE_COLS+=("") ;; esac
    case "$role" in changes) CHANGES_ONLY+=(1) ;; *) CHANGES_ONLY+=(0) ;; esac
done < "$TABLES_CONF"

# A `clinic=<column>` row carries the hub's own rows (lab results entered at
# the hub) for whichever clinic <column> names. This clinic keeps a row only
# when <column> points at a row this clinic wrote: it ends in this clinic's
# residue and is at or above that table's base. Below the base a residue says
# nothing about who wrote the row (older rows were numbered before striding),
# so those rows are not kept anywhere. The column says which table it points
# at: visit_id -> visit, order_id -> orders. The base is that table's in
# sync/local/tables.conf; a table whose base comes from the seed (orders) takes
# the floor recorded at seeding (FLOOR_ORDERS, in .env or .install-state). The
# residue comes from this clinic's .env. Without either nothing is generated.
need_residue=no
for c in "${ROUTE_COLS[@]}"; do [[ -n "$c" ]] && need_residue=yes; done
RESIDUE_OWN=""
declare -a ROUTE_BASES=()
route_table(){ case "$1" in visit_id) echo visit ;; order_id) echo orders ;; *) return 1 ;; esac; }
route_base(){ # COLUMN -> the base of the table it points at
    local t b k
    t="$(route_table "$1")" || { echo "hub/tables.conf routes by '$1'; a clinic can route only by visit_id or order_id" >&2; return 1; }
    b="$(grep -E "^[[:space:]]*${t}:[^:]+:" "$UP_TABLES_CONF" | head -1 | awk '{print $1}' | cut -d: -f3)"
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
    RESIDUE_OWN="${RESIDUE:-}"
    [[ -n "$RESIDUE_OWN" ]] || { [[ -n "${MYSQL_AUTO_INCREMENT_OFFSET:-}" ]] && RESIDUE_OWN=$(( MYSQL_AUTO_INCREMENT_OFFSET % 10 )); }
    [[ "$RESIDUE_OWN" =~ ^[1-9]$ ]] || { echo "this clinic's residue (RESIDUE, 1-9) is not set: the lab-result sinks keep only this clinic's rows and cannot be generated without it" >&2; exit 1; }
fi
for i in "${!ROUTE_COLS[@]}"; do
    if [[ -n "${ROUTE_COLS[$i]}" ]]; then ROUTE_BASES[$i]="$(route_base "${ROUTE_COLS[$i]}")" || exit 1
    else ROUTE_BASES[$i]=""; fi
done

(( ${#TABLES[@]} )) || { echo "no tables found in $TABLES_CONF" >&2; exit 1; }

# Ownership guard — the mirror image of the one in
# hub/scripts/generate-sink-connectors.sh, which refuses to give a
# CLOUD-owned table an up-direction sink. Same rule, other direction: a table the
# CLINIC authors must never get a down-direction sink.
#
# Why this mattered. The clinic captures its own tables, so a sink write that lands
# in the clinic binlog ships up to the cloud, is applied there, and — because the
# table is in BOTH capture lists — comes straight back down. Unbounded, and unlike
# clinlims on Postgres there is no publication row filter on MySQL to break it.
#
# That hazard is closed when the sink writes with sessionVariables=sql_log_bin=0
# (the engine-native loop guard): the write never enters the binlog, so it
# cannot loop. The template carries that setting, and every mysql-local-sink-*
# connector uses it — including person and person_name, which an unconditional
# refusal here would never generate.
#
# An unconditional refusal here would also enforce PER-TABLE ownership, which is
# not the rule: a table MAY be written by more than one node provided no two
# nodes write the same row, which is what the residue and base_id striding
# guarantee for person/person_name.
#
# So: still refuse — loudly, before writing anything — but only when the sink would
# genuinely go out without the guard. If the template ever loses sql_log_bin=0 this
# reverts to the old absolute behaviour, which is the safe direction to fail in.
if [[ -f "$UP_TABLES_CONF" ]] && ! grep -q 'sql_log_bin=0' "$TEMPLATE"; then
    for t in "${TABLES[@]}"; do
        if grep -qE "^[[:space:]]*${t}:" "$UP_TABLES_CONF"; then
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
count=0
for i in "${!TABLES[@]}"; do
    TABLE="${TABLES[$i]}"
    TOPIC="${SRC_PREFIX}${TABLE}"

    CHANGES="${CHANGES_ONLY[$i]}" ROUTE_COL="${ROUTE_COLS[$i]}" ROUTE_BASE="${ROUTE_BASES[$i]}" RESIDUE_OWN="$RESIDUE_OWN" \
    TEMPLATE="$TEMPLATE" TABLE="$TABLE" KAFKA_TOPICS="$TOPIC" \
    TOPIC_PREFIX_REGEX="$PREFIX_REGEX" \
    LOCAL_MYSQL_HOST="$LOCAL_MYSQL_HOST" LOCAL_MYSQL_PORT="$LOCAL_MYSQL_PORT" \
    LOCAL_MYSQL_DATABASE="$LOCAL_MYSQL_DATABASE" LOCAL_MYSQL_USE_SSL="$LOCAL_MYSQL_USE_SSL" \
    LOCAL_MYSQL_USER="$LOCAL_MYSQL_USER" LOCAL_MYSQL_PASSWORD="$LOCAL_MYSQL_PASSWORD" \
    python3 - "$OUT/mysql-local-sink-${TABLE}.json" <<'PYEOF'
import json, os, re, sys

raw = open(os.environ['TEMPLATE']).read()
for key in ('TABLE','KAFKA_TOPICS','TOPIC_PREFIX_REGEX','LOCAL_MYSQL_HOST','LOCAL_MYSQL_PORT',
            'LOCAL_MYSQL_DATABASE','LOCAL_MYSQL_USE_SSL','LOCAL_MYSQL_USER','LOCAL_MYSQL_PASSWORD'):
    raw = raw.replace('${%s}' % key, os.environ[key])

doc = json.loads(raw)
# drop the //-prefixed documentation keys: Connect would report them as unknown configs
doc['config'] = {k: v for k, v in doc['config'].items() if not k.startswith('//')}

leftover = [k for k, v in doc['config'].items() if '${' in str(v)]
if leftover:
    sys.exit(f"unsubstituted placeholder(s) in {leftover}")
if doc['config'].get('transforms.dropPrefix.replacement') != '$1':
    sys.exit("RegexRouter replacement is not literal $1 — the shell expanded it")

col = os.environ.get('ROUTE_COL', '')
if col:
    # only rows whose column points at a row this clinic wrote; tombstones carry
    # no row and are dropped, a delete still arrives as its own change event
    # with the row in `before`
    cfg = doc['config']; r = os.environ['RESIDUE_OWN']; base = os.environ['ROUTE_BASE']
    cfg['transforms'] = cfg['transforms'] + ',rowsForThisClinic'
    cfg['transforms.rowsForThisClinic.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.rowsForThisClinic.language'] = 'jsr223.groovy'
    cfg['transforms.rowsForThisClinic.null.handling.mode'] = 'drop'
    cfg['transforms.rowsForThisClinic.condition'] = (
        "def r = value.get('after') != null ? value.get('after') : value.get('before'); "
        f"r != null && r.get('{col}') instanceof Number && r.get('{col}').longValue() >= {base}L "
        f"&& r.get('{col}').longValue() % 10 == {r}")

if os.environ.get('CHANGES') == '1':
    # a `changes` table (hub/tables.conf): inserts and updates are applied,
    # never a delete. The hub retires such a row rather than deleting it, and a
    # delete here would fail on, or orphan, the clinic's own rows that point to
    # it. Tombstones carry no row and are dropped with the deletes.
    cfg = doc['config']
    cfg['delete.enabled'] = 'false'
    cfg['transforms'] = cfg['transforms'] + ',noDeletes'
    cfg['transforms.noDeletes.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.noDeletes.language'] = 'jsr223.groovy'
    cfg['transforms.noDeletes.null.handling.mode'] = 'drop'
    cfg['transforms.noDeletes.condition'] = "value.get('op') != 'd'"

json.dump(doc, open(sys.argv[1], 'w'), indent=2)
PYEOF
    echo "  ✓ $(basename "$OUT")/mysql-local-sink-${TABLE}.json   ← ${TOPIC}"
    count=$((count+1))
done

echo
echo "generated ${count} DOWN-direction sink connector(s) in ${OUT}"
echo "  mirrored-topic prefix : ${SRC_PREFIX}"
echo "  target                : ${LOCAL_MYSQL_HOST}:${LOCAL_MYSQL_PORT}/${LOCAL_MYSQL_DATABASE}"
