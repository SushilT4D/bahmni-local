#!/usr/bin/env bash
# Uploads connector configs from clinic/connectors/ to Kafka Connect.
#
# usage: scripts/register-connectors.sh [NAME...]
#   NAME is a file in connectors/ without .json, or a pattern such as
#   'mysql-local-sink-*'; with no NAME, every file there.
#
# Each config's passwords are ${...} placeholders, filled in here from .env, so
# no file on disk holds one. A config is created or, if it exists, updated.
# Before the MySQL down sink (mysql-local-sink-all) is uploaded, the sink database
# user's grants on every [down] table are checked, and nothing is uploaded if one is missing; after
# them, their tasks are checked.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECT="${CONNECT_URL:-${LOCAL_CONNECT_URL:-http://localhost:8083}}"
CLINIC_DIR="${CLINIC_DIR:-${ROOT}}"; export CLINIC_DIR
DIR="${CLINIC_DIR}/connectors"
REPO_DIR="${REPO_DIR:-$(cd "${ROOT}/.." && pwd)}"; export REPO_DIR
# shellcheck disable=SC1091
. "${ROOT}/install/lib.sh"
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: the passwords cannot be read, so nothing was registered"

# Which configs.
shopt -s nullglob
files=()
if [ $# -gt 0 ]; then
  for n in "$@"; do
    # shellcheck disable=SC2206
    m=("${DIR}"/${n}.json)
    (( ${#m[@]} )) || fail "no ${DIR}/${n}.json: run scripts/generate-connectors.sh first"
    files+=("${m[@]}")
  done
else
  files=("${DIR}"/*.json)
fi
(( ${#files[@]} )) || fail "no connector configs in ${DIR}: run scripts/generate-connectors.sh first"

# The passwords, from the environment or .env.
pw(){ local v="${!1:-}"; [ -n "$v" ] || v="$(env_get "$E" "$1")"; printf '%s' "$v"; }
DEBEZIUM_PASSWORD="$(pw DEBEZIUM_PASSWORD)"
OPENMRS_SINK_PASSWORD="$(pw OPENMRS_SINK_PASSWORD)"
ODOO_SOURCE_PASSWORD="$(pw ODOO_SOURCE_PASSWORD)"; ODOO_SINK_PASSWORD="$(pw ODOO_SINK_PASSWORD)"
CLINLIMS_SOURCE_PASSWORD="$(pw CLINLIMS_SOURCE_PASSWORD)"; CLINLIMS_SINK_PASSWORD="$(pw CLINLIMS_SINK_PASSWORD)"
export DEBEZIUM_PASSWORD OPENMRS_SINK_PASSWORD ODOO_SOURCE_PASSWORD ODOO_SINK_PASSWORD CLINLIMS_SOURCE_PASSWORD CLINLIMS_SINK_PASSWORD
for v in DEBEZIUM_PASSWORD OPENMRS_SINK_PASSWORD ODOO_SOURCE_PASSWORD ODOO_SINK_PASSWORD CLINLIMS_SOURCE_PASSWORD CLINLIMS_SINK_PASSWORD; do
  [ -n "${!v}" ] || unset "$v"
done

# The MySQL down sink needs the sink user's grants on every [down] table it writes.
sinks=()
for f in "${files[@]}"; do case "${f##*/}" in mysql-local-sink-*) sinks+=("$f") ;; esac; done
if (( ${#sinks[@]} )); then
  tables="$(bash "${REPO_DIR}/sync/tables/tables.sh" openmrs down | cut -d: -f1)" \
    || fail "could not read the OpenMRS [down] list (reason above); nothing was registered"
  COMPOSE_PROJECT_NAME=bahmni   # name: in docker-compose.yml
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
  echo "  sink user holds SELECT, INSERT, UPDATE, DELETE on all $(printf '%s\n' $tables | grep -c .) [down] table(s)"
fi

curl -sf --connect-timeout 5 "${CONNECT}/connectors" >/dev/null || fail "cannot reach Kafka Connect at ${CONNECT}"

# Upload each config. Connect's reply echoes the config, passwords included, so
# only its status and error message are shown.
mask(){ sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*(")/\1***\4/g'; }
failed=0
for f in "${files[@]}"; do
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$f")"
  body="$(python3 "${ROOT}/scripts/_render_connector.py" "$f")" || { echo "  ${name}: not uploaded (above)" >&2; failed=1; continue; }
  if curl -sf "${CONNECT}/connectors/${name}" >/dev/null 2>&1; then verb=updated; else verb=created; fi
  resp="$(printf '%s' "$body" | curl -s -w '\n%{http_code}' -X PUT -H 'Content-Type: application/json' \
          --data-binary @- "${CONNECT}/connectors/${name}/config")"
  code="${resp##*$'\n'}"
  if [ "${code:-0}" -lt 300 ] 2>/dev/null; then
    echo "  ${verb}  ${name}  (HTTP ${code})"
  else
    echo "  FAILED   ${name}  (HTTP ${code:-none})" >&2
    printf '%s\n' "${resp%$'\n'*}" | mask | sed 's/^/    /' >&2
    failed=1
  fi
done
[ "$failed" = 0 ] || fail "one or more connectors were not registered (above)"

if (( ${#sinks[@]} )); then
  echo; echo "settling..."; sleep "${SINK_SETTLE_S:-12}"; echo
  "${ROOT}/scripts/check-sink-tasks.sh" "$(printf '%s' "$CONNECT" | sed -E 's#https?://##; s#:.*##')"
fi
