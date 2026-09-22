#!/usr/bin/env bash
# Print TABLE_INCLUDE_LIST and KAFKA_TOPICS from sync/local/tables.conf or hub/tables.conf.
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

  local   Read sync/local/tables.conf      (clinic → cloud CDC)
  cloud   Read hub/tables.conf             (cloud → clinic)

  --include-relay   Also emit tables marked `:relay` -- clinic-owned tables the
                    hub relays (ADR-003 s7). A CLINIC needs these, because they
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

# Stage 4: this script lives in clinic/scripts/, the hub tree is hub/
# and the shared sync definitions are sync/ -- all siblings of PROJECT_DIR (clinic/).
case "${SIDE}" in
  cloud) TABLES_CONF="${PROJECT_DIR}/../hub/tables.conf" ;;
  *)     TABLES_CONF="${PROJECT_DIR}/../sync/${SIDE}/tables.conf" ;;
esac
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

  # table:pk[:base_id|:role]   (pk may contain commas for composite keys)
  #
  # The optional third field is a NUMBER on the local side (a table's base_id
  # floor) and a WORD on the cloud side (a role). The only role today is `relay`:
  # a CLINIC-owned table that travels down because the hub relays it (ADR-003
  # section 7), as opposed to a table the cloud AUTHORS.
  #
  # That distinction is the entire point of this field. Both kinds arrive at a
  # clinic and both need a down-direction sink, so the clinic's generators want
  # the FULL list -- but the hub's own source connector must publish only what the
  # cloud authors, because the relay rule is recorded as designed-but-unratified.
  # One file, two correct answers. Before this field existed there was no way to
  # say that, so adding person/person_name for BL-042 made the cloud source
  # generator refuse outright and the two branches drifted to different answers.
  if [[ "$line" =~ ^([^:]+):([^:]+)(:([A-Za-z0-9_]+))?$ ]]; then
    table="${BASH_REMATCH[1]}"
    pk="${BASH_REMATCH[2]}"
    role="${BASH_REMATCH[4]:-}"
    if [[ "${role}" == "relay" && "${INCLUDE_RELAY}" != "yes" ]]; then
      continue
    fi
    table_include_list+=("${DATABASE_NAME}.${table}")
    kafka_topics+=("${SERVER_NAME}.${DATABASE_NAME}.${table}")
    primary_keys+=("$pk")
  else
    echo "Warning: skipping malformed line: ${line}" >&2
  fi
done < "${TABLES_CONF}"

echo "# Generated from ${TABLES_CONF#${PROJECT_DIR}/}"
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
