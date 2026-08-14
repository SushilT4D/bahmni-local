#!/usr/bin/env bash
# Generate local Debezium source connector config from debezium/local/tables.conf.
#
# tables.conf lines:
#   table:pk:base_id   — included in CDC (base_id used only by configure-pk-offsets.sh)
#   table:pk           — included in CDC only
#
# Usage: ./scripts/generate-connectors.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"
ENV_FILE="${PROJECT_DIR}/.env"
TABLES_CONF="${PROJECT_DIR}/debezium/local/tables.conf"
TEMPLATE="${PROJECT_DIR}/debezium/local/connectors/mysql-source-connector.template.json"
# Operators historically register from either filename; write both.
OUT_PRIMARY="${CONNECTORS_DIR}/mysql-local-source-connector.json"
OUT_ALIAS="${CONNECTORS_DIR}/mysql-source-connector.json"

echo "Setting up connector configurations..."

[[ -f "${ENV_FILE}" ]] || { echo "Error: .env not found at ${ENV_FILE}"; exit 1; }
[[ -f "${TABLES_CONF}" ]] || { echo "Error: ${TABLES_CONF} not found"; exit 1; }
[[ -f "${TEMPLATE}" ]] || { echo "Error: template not found: ${TEMPLATE}"; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "Error: envsubst not found (brew install gettext)"; exit 1; }

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

DATABASE_NAME="${DATABASE_NAME:-openmrs}"
MYSQL_SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
# Template uses LOCAL_* / DEBEZIUM_* names; map from root .env conventions.
LOCAL_MYSQL_HOST="${LOCAL_MYSQL_HOST:-${BAHMNI_MYSQL_HOST:-bahmni-mysql}}"
LOCAL_MYSQL_PORT="${LOCAL_MYSQL_PORT:-3306}"
LOCAL_DEBEZIUM_USER="${LOCAL_DEBEZIUM_USER:-${DEBEZIUM_USER:-debezium}}"
LOCAL_DEBEZIUM_PASSWORD="${LOCAL_DEBEZIUM_PASSWORD:-${DEBEZIUM_PASSWORD:-}}"
DATABASE_INCLUDE_LIST="${DATABASE_INCLUDE_LIST:-${DATABASE_NAME}}"

export DATABASE_NAME MYSQL_SERVER_NAME
export LOCAL_MYSQL_HOST LOCAL_MYSQL_PORT LOCAL_DEBEZIUM_USER LOCAL_DEBEZIUM_PASSWORD
export DATABASE_INCLUDE_LIST

table_include_list=()
kafka_topics=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue

  # table:pk or table:pk:base_id
  if [[ "$line" =~ ^([^:]+):([^:]+)(:([0-9]+))?$ ]]; then
    table="${BASH_REMATCH[1]}"
    table_include_list+=("${DATABASE_NAME}.${table}")
    kafka_topics+=("${MYSQL_SERVER_NAME}.${DATABASE_NAME}.${table}")
  else
    echo "Warning: skipping malformed line: ${line}" >&2
  fi
done < "${TABLES_CONF}"

[[ ${#table_include_list[@]} -gt 0 ]] || { echo "Error: no tables parsed from ${TABLES_CONF}"; exit 1; }

export TABLE_INCLUDE_LIST
TABLE_INCLUDE_LIST="$(IFS=','; echo "${table_include_list[*]}")"
KAFKA_TOPICS="$(IFS=','; echo "${kafka_topics[*]}")"

mkdir -p "${CONNECTORS_DIR}"
SUBST_VARS='${LOCAL_MYSQL_HOST} ${LOCAL_MYSQL_PORT} ${LOCAL_DEBEZIUM_USER} ${LOCAL_DEBEZIUM_PASSWORD} ${MYSQL_SERVER_NAME} ${DATABASE_INCLUDE_LIST} ${TABLE_INCLUDE_LIST}'
envsubst "${SUBST_VARS}" < "${TEMPLATE}" > "${OUT_PRIMARY}"
cp "${OUT_PRIMARY}" "${OUT_ALIAS}"

echo "Generated: ${OUT_PRIMARY}"
echo "Generated: ${OUT_ALIAS}"
echo "  Tables: ${#table_include_list[@]}"
echo "  TABLE_INCLUDE_LIST=${TABLE_INCLUDE_LIST}"
echo "  KAFKA_TOPICS=${KAFKA_TOPICS}"
echo ""
echo "Next:"
echo "  1. Copy TABLE_INCLUDE_LIST / KAFKA_TOPICS into .env if you keep them there"
echo "  2. ./scripts/register-source-connector.sh"
echo "  3. Cloud→local tables live in debezium/cloud/tables.conf (separate list)"
