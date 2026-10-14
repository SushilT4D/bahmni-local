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
TABLES=(); PATIENT_COLS=()
while read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    f="$(printf '%s' "$line" | awk '{print $1}')"
    t="$(printf '%s' "$f" | cut -d: -f1)"
    role="$(printf '%s' "$f" | cut -s -d: -f3)"
    [[ -n "$t" ]] || continue
    TABLES+=("$t")
    case "$role" in patient=*) PATIENT_COLS+=("${role#patient=}") ;; *) PATIENT_COLS+=("") ;; esac
done < "$TABLES_CONF"

# A `patient=<column>` row carries the hub's rows for clinics' patients (lab
# results entered at the hub). This clinic keeps only the rows whose patient
# ends in its own residue, at or above the person base: another clinic's
# patient and visit do not exist here. The residue comes from this clinic's
# .env; without it nothing is generated.
need_residue=no
for c in "${PATIENT_COLS[@]}"; do [[ -n "$c" ]] && need_residue=yes; done
RESIDUE_OWN=""; PERSON_BASE=""
if [[ "$need_residue" == yes ]]; then
    RESIDUE_OWN="${RESIDUE:-}"
    [[ -n "$RESIDUE_OWN" ]] || { [[ -n "${MYSQL_AUTO_INCREMENT_OFFSET:-}" ]] && RESIDUE_OWN=$(( MYSQL_AUTO_INCREMENT_OFFSET % 10 )); }
    [[ "$RESIDUE_OWN" =~ ^[1-9]$ ]] || { echo "this clinic's residue (RESIDUE, 1-9) is not set: the lab-result sinks keep only this clinic's patients and cannot be generated without it" >&2; exit 1; }
    PERSON_BASE="$(grep -E '^[[:space:]]*person:person_id:[0-9]+' "$UP_TABLES_CONF" | head -1 | cut -d: -f3 | tr -cd '0-9')"
    [[ -n "$PERSON_BASE" ]] || { echo "${UP_TABLES_CONF} gives no person base (person:person_id:<base>); the lab-result sinks need it" >&2; exit 1; }
fi

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

    PATIENT_COL="${PATIENT_COLS[$i]}" RESIDUE_OWN="$RESIDUE_OWN" PERSON_BASE="$PERSON_BASE" \
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

col = os.environ.get('PATIENT_COL', '')
if col:
    # this clinic's patients only; tombstones carry no row and are dropped, a
    # delete still arrives as its own change event with the row in `before`
    cfg = doc['config']; r = os.environ['RESIDUE_OWN']; base = os.environ['PERSON_BASE']
    cfg['transforms'] = cfg['transforms'] + ',thisClinicsPatients'
    cfg['transforms.thisClinicsPatients.type'] = 'io.debezium.transforms.Filter'
    cfg['transforms.thisClinicsPatients.language'] = 'jsr223.groovy'
    cfg['transforms.thisClinicsPatients.null.handling.mode'] = 'drop'
    cfg['transforms.thisClinicsPatients.condition'] = (
        "def r = value.get('after') != null ? value.get('after') : value.get('before'); "
        f"r != null && r.get('{col}') instanceof Number && r.get('{col}').longValue() >= {base}L "
        f"&& r.get('{col}').longValue() % 10 == {r}")

json.dump(doc, open(sys.argv[1], 'w'), indent=2)
PYEOF
    echo "  ✓ $(basename "$OUT")/mysql-local-sink-${TABLE}.json   ← ${TOPIC}"
    count=$((count+1))
done

echo
echo "generated ${count} DOWN-direction sink connector(s) in ${OUT}"
echo "  mirrored-topic prefix : ${SRC_PREFIX}"
echo "  target                : ${LOCAL_MYSQL_HOST}:${LOCAL_MYSQL_PORT}/${LOCAL_MYSQL_DATABASE}"
