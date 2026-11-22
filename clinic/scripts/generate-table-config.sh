#!/usr/bin/env bash
# Print table include lists and topic names.
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

  local   Read sync/tables/openmrs.conf [up]      (clinic → cloud CDC)
  cloud   Read sync/tables/openmrs.conf [down]             (cloud → clinic)

  --include-relay   Also emit tables marked `:relay` -- clinic-owned tables the
                    hub relays. A CLINIC needs these, because they
                    arrive and must be sunk. The hub must NOT publish them while
                    the relay rule is unratified.

Prints TABLE_INCLUDE_LIST, KAFKA_TOPICS, and PRIMARY_KEYS.
EOF
}

SIDE="${1:-}"
INCLUDE_RELAY="no"
for a in "$@"; do [[ "$a" == "--include-relay" ]] && INCLUDE_RELAY="yes"; done
case "${SIDE}" in
  local|cloud) ;;
  -h|--help|"") usage; [[ -n "${SIDE}" ]] || exit 1; exit 0 ;;
  *) usage; echo "Error: unknown side '${SIDE}' (use local or cloud)" >&2; exit 1 ;;
esac

# Resolve the selected table list relative to the clinic directory.
# local reads the OpenMRS [up] section, cloud its [down] section.
TABLES_CONF="${PROJECT_DIR}/../sync/tables/openmrs.conf"
# shellcheck source=../../sync/tables/tables.sh
. "${PROJECT_DIR}/../sync/tables/tables.sh"
[[ -f "${TABLES_CONF}" ]] || { echo "Error: ${TABLES_CONF} not found"; exit 1; }

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ "${SIDE}" == "local" ]]; then
  SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
else
  # Cloud topic prefix (see connectors/mysql-local-sink-connector-users.json)
  SERVER_NAME="${CLOUD_MYSQL_SERVER_NAME:-${REMOTE_SOURCE_SERVER_NAME:-bahmni-cloud}}"
fi

table_include_list=()
kafka_topics=()
primary_keys=()

# Use the shared parser for the clinic table list.
if [[ "${SIDE}" == "local" ]]; then
  # shellcheck source=../../sync/tables/tables.sh
  . "${PROJECT_DIR}/../sync/tables/tables.sh"
  recs="$(up_tables_read "${TABLES_CONF}")" || { echo "Error: ${TABLES_CONF} cannot be read as the clinic's table list (reason above)" >&2; exit 1; }
  while read -r table pk _kind _arg; do
    [[ -n "${table}" ]] || continue
    table_include_list+=("openmrs.${table}")
    kafka_topics+=("${SERVER_NAME}.openmrs.${table}")
    primary_keys+=("$pk")
  done <<EOF
${recs}
EOF
  # the source connector's signal table: captured, but no topic goes up for it
  # and it has no key list here (sync/tables/tables.sh)
  table_include_list+=("$(up_signal_collection "openmrs")")
else
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Cloud rows may specify routing roles; relay rows are opt-in.
    if [[ "$line" =~ ^([^:]+):([^:]+)(:([A-Za-z0-9_]+|hub-rows|clinic=[a-z_][a-z0-9_]*))?$ ]]; then
      table="${BASH_REMATCH[1]}"
      pk="${BASH_REMATCH[2]}"
      role="${BASH_REMATCH[4]:-}"
      if [[ "${role}" == "relay" && "${INCLUDE_RELAY}" != "yes" ]]; then
        continue
      fi
      table_include_list+=("openmrs.${table}")
      kafka_topics+=("${SERVER_NAME}.openmrs.${table}")
      primary_keys+=("$pk")
    else
      echo "Warning: skipping malformed line: ${line}" >&2
    fi
  done < <(tables_section "${TABLES_CONF}" down)
fi

echo "# Generated from ${TABLES_CONF#${PROJECT_DIR}/}"
echo "# Side: ${SIDE}"
echo "# Server: ${SERVER_NAME}"
echo "# Database: openmrs"
echo "# Tables: ${#table_include_list[@]}"
echo ""
echo "TABLE_INCLUDE_LIST=$(IFS=','; echo "${table_include_list[*]}")"
echo ""
echo "KAFKA_TOPICS=$(IFS=','; echo "${kafka_topics[*]}")"
echo ""
echo "# Primary keys (in table order; | separates tables)"
echo "# PRIMARY_KEYS=$(IFS='|'; echo "${primary_keys[*]}")"
