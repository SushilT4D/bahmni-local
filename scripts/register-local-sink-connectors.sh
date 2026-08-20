#!/bin/bash
# register-local-sink-connectors.sh — POST the DOWN-direction sinks to the CLINIC's
# Kafka Connect worker (the same worker that hosts the up-direction Debezium source).
#
# Idempotent: an existing connector is updated via PUT /config rather than failing.
# Verifies TASK state, not connector state (BL-038 — the connector object reads
# RUNNING over a FAILED task).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${ROOT}/debezium/local/connectors/generated}"
CONNECT="${LOCAL_CONNECT_URL:-http://localhost:8083}"

shopt -s nullglob
files=("$DIR"/mysql-local-sink-*.json)
(( ${#files[@]} )) || { echo "no connector configs in $DIR — run generate-local-sink-connectors.sh first" >&2; exit 1; }

curl -sf --connect-timeout 5 "${CONNECT}/connectors" >/dev/null \
  || { echo "cannot reach Kafka Connect at ${CONNECT}" >&2; exit 2; }

for f in "${files[@]}"; do
    name=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['name'])" "$f")
    if curl -sf "${CONNECT}/connectors/${name}" >/dev/null 2>&1; then
        body=$(python3 -c "import json,sys;print(json.dumps(json.load(open(sys.argv[1]))['config']))" "$f")
        code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json' \
               --data "$body" "${CONNECT}/connectors/${name}/config")
        echo "  updated  ${name}  (HTTP ${code})"
    else
        code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
               --data @"$f" "${CONNECT}/connectors")
        echo "  created  ${name}  (HTTP ${code})"
    fi
done

echo; echo "settling..."; sleep 12
echo
exec "${ROOT}/scripts/check-sink-tasks.sh" "$(printf '%s' "$CONNECT" | sed -E 's#https?://##; s#:.*##')"
