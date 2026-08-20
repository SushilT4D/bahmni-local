#!/bin/bash
# generate-local-sink-connectors.sh — render the DOWN-direction (cloud → clinic) sinks.
#
# One connector per cloud-owned table from debezium/cloud/tables.conf. These run ON THE
# CLINIC and write into the clinic's OpenMRS DB.
#
# Deliberate differences from the up-direction generator (debezium/cloud/scripts/
# generate-sink-connectors.sh), each one a defect we hit:
#   BL-030  that script used an UNQUOTED heredoc, so the shell expanded the RegexRouter
#           replacement "$1" to empty and every connector died with `Invalid identifier:`.
#           Here the template is a FILE and substitution is explicit — "$1" is never
#           exposed to the shell.
#   BL-032  that script hardcodes the topic prefix `source.bahmni-local.openmrs.`, which
#           blocks clinic #2. Here every prefix component is a variable.
#   BL-039  connection.restart.on.errors is set in the template (see it for why).
#
# Usage: ./scripts/generate-local-sink-connectors.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/debezium/local/connectors/generated}"
TEMPLATE="${ROOT}/debezium/local/connectors/mysql-local-sink-connector.json.template"
TABLES_CONF="${ROOT}/debezium/cloud/tables.conf"

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

mkdir -p "$OUT"
count=0
while read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    TABLE="$(printf '%s' "$line" | awk '{print $1}' | cut -d: -f1)"
    [[ -n "$TABLE" ]] || continue
    TOPIC="${SRC_PREFIX}${TABLE}"

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
    sys.exit("RegexRouter replacement is not literal $1 — the BL-030 defect has reappeared")

json.dump(doc, open(sys.argv[1], 'w'), indent=2)
PYEOF
    echo "  ✓ $(basename "$OUT")/mysql-local-sink-${TABLE}.json   ← ${TOPIC}"
    count=$((count+1))
done < "$TABLES_CONF"

echo
echo "generated ${count} DOWN-direction sink connector(s) in ${OUT}"
echo "  mirrored-topic prefix : ${SRC_PREFIX}"
echo "  target                : ${LOCAL_MYSQL_HOST}:${LOCAL_MYSQL_PORT}/${LOCAL_MYSQL_DATABASE}"
