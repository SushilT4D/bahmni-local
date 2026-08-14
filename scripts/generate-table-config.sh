#!/usr/bin/env bash
# Print TABLE_INCLUDE_LIST and KAFKA_TOPICS from debezium/{local|cloud}/tables.conf.
#
# Usage:
#   ./scripts/generate-table-config.sh local
#   ./scripts/generate-table-config.sh cloud
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

usage() {
  cat <<EOF
Usage: $(basename "$0") <local|cloud>

  local   Read debezium/local/tables.conf  (clinic → cloud CDC)
  cloud   Read debezium/cloud/tables.conf  (cloud → clinic)

Prints TABLE_INCLUDE_LIST, KAFKA_TOPICS, and PRIMARY_KEYS.
EOF
}

SIDE="${1:-}"
case "${SIDE}" in
  local|cloud) ;;
  -h|--help|"") usage; [[ -n "${SIDE}" ]] || exit 1; exit 0 ;;
  *) usage; echo "Error: unknown side '${SIDE}' (use local or cloud)" >&2; exit 1 ;;
esac

TABLES_CONF="${PROJECT_DIR}/debezium/${SIDE}/tables.conf"
[[ -f "${TABLES_CONF}" ]] || { echo "Error: ${TABLES_CONF} not found"; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

DATABASE_NAME="${DATABASE_NAME:-openmrs}"
if [[ "${SIDE}" == "local" ]]; then
  SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
else
  # Cloud topic prefix (see connectors/mysql-local-sink-connector-users.json)
  SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-${REMOTE_SOURCE_SERVER_NAME:-bahmni-cloud}}"
fi

table_include_list=()
kafka_topics=()
primary_keys=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue

  # table:pk or table:pk:base_id  (pk may contain commas for composite keys)
  if [[ "$line" =~ ^([^:]+):([^:]+)(:([0-9]+))?$ ]]; then
    table="${BASH_REMATCH[1]}"
    pk="${BASH_REMATCH[2]}"
    table_include_list+=("${DATABASE_NAME}.${table}")
    kafka_topics+=("${SERVER_NAME}.${DATABASE_NAME}.${table}")
    primary_keys+=("$pk")
  else
    echo "Warning: skipping malformed line: ${line}" >&2
  fi
done < "${TABLES_CONF}"

echo "# Generated from debezium/${SIDE}/tables.conf"
echo "# Side: ${SIDE}"
echo "# Server: ${SERVER_NAME}"
echo "# Database: ${DATABASE_NAME}"
echo "# Tables: ${#table_include_list[@]}"
echo ""
echo "TABLE_INCLUDE_LIST=$(IFS=','; echo "${table_include_list[*]}")"
echo ""
echo "KAFKA_TOPICS=$(IFS=','; echo "${kafka_topics[*]}")"
echo ""
echo "# Primary keys (in table order; | separates tables)"
echo "# PRIMARY_KEYS=$(IFS='|'; echo "${primary_keys[*]}")"
