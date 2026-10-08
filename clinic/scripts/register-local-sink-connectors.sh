#!/bin/bash
# register-local-sink-connectors.sh — POST the DOWN-direction sinks to the CLINIC's
# Kafka Connect worker (the same worker that hosts the up-direction Debezium source).
#
# Idempotent: an existing connector is updated via PUT /config rather than failing.
# Verifies TASK state, not connector state (the connector object reads
# RUNNING over a FAILED task).
#
# Refuses before it contacts Connect when the clinic's sink database user lacks
# SELECT, INSERT, UPDATE or DELETE on any table a generated sink writes, and
# names the tables: such a sink would register, start, and fail on its first
# write. Grants are read as root inside <COMPOSE_PROJECT_NAME>-bahmni-mysql-1
# (COMPOSE_PROJECT_NAME from clinic/.env); scripts/grant-down-tables.sh is the fix.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:-${ROOT}/../sync/local/connectors/generated}"
CONNECT="${LOCAL_CONNECT_URL:-http://localhost:8083}"
CLINIC_DIR="${CLINIC_DIR:-${ROOT}}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${ROOT}/.." && pwd)}"; export REPO_DIR
# shellcheck disable=SC1091
. "${ROOT}/install/lib.sh"

shopt -s nullglob
files=("$DIR"/mysql-local-sink-*.json)
(( ${#files[@]} )) || { echo "no connector configs in $DIR — run generate-local-sink-connectors.sh first" >&2; exit 1; }

# --- the sink user's grants, before anything is registered -------------------
tables="$(python3 -c 'import json,sys
for f in sys.argv[1:]: print(json.load(open(f))["config"]["table.name.format"])' "${files[@]}")" \
  || fail "could not read table.name.format from the configs in ${DIR}"
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: the sink user's grants cannot be read, so nothing was registered"
COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
[ -n "${COMPOSE_PROJECT_NAME}" ] || fail "clinic/.env has no COMPOSE_PROJECT_NAME: the sink user's grants cannot be read, so nothing was registered"
[ -n "${CT:-}" ] || setup_compose
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
granted="$(printf '%s\n' "${SINK_GRANTS_READ_SQL}" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N')" \
  || fail "could not read the sink user's grants in ${MY} (is MySQL running?); nothing was registered"
# shellcheck disable=SC2086
missing="$(printf '%s\n' "$granted" | sink_grants_missing $tables)" || fail "could not judge the sink user's grants"
if [ -n "$missing" ]; then
    fail "REFUSING to register the down sinks: the sink user lacks SELECT, INSERT, UPDATE or DELETE on: $(printf '%s' "$missing" | tr '\n' ' ')
       Each of those sinks would fail on its first write. Nothing was registered.
       Grant them first:  bash scripts/grant-down-tables.sh   (then run this again)"
fi
echo "  sink user holds SELECT, INSERT, UPDATE, DELETE on all ${#files[@]} down sink table(s)"

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

echo; echo "settling..."; sleep "${SINK_SETTLE_S:-12}"
echo
exec "${ROOT}/scripts/check-sink-tasks.sh" "$(printf '%s' "$CONNECT" | sed -E 's#https?://##; s#:.*##')"
