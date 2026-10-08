#!/usr/bin/env bash
# Generate local Debezium source connector config from sync/local/tables.conf.
#
# Every table line is included in CDC. The third field (a floor, see the
# format comment in tables.conf) sets the id counters in configure-pk-offsets.sh;
# here, a floor taken from the seed or from another table adds that table's
# capture filter (sync/origin-filter.sh). The lines are read by
# sync/local/tables-conf.sh, the reader every script of that file shares.
#
# Usage: ./scripts/generate-connectors.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"
ENV_FILE="${PROJECT_DIR}/.env"
TABLES_CONF="${PROJECT_DIR}/../sync/local/tables.conf"
TEMPLATE="${PROJECT_DIR}/../sync/local/connectors/mysql-source-connector.template.json"
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
filter_recs=""

# shellcheck source=../../sync/local/tables-conf.sh
. "${PROJECT_DIR}/../sync/local/tables-conf.sh"
# shellcheck source=../../sync/origin-filter.sh
. "${PROJECT_DIR}/../sync/origin-filter.sh"
recs="$(up_tables_read "${TABLES_CONF}")" || { echo "Error: ${TABLES_CONF} cannot be read as the clinic's table list (reason above)" >&2; exit 1; }
while read -r table _pk _kind _arg; do
  [[ -n "${table}" ]] || continue
  table_include_list+=("${DATABASE_NAME}.${table}")
  kafka_topics+=("${MYSQL_SERVER_NAME}.${DATABASE_NAME}.${table}")
  case "${_kind}" in seed|floor) filter_recs="${filter_recs}${table} ${_pk}
" ;; esac
done <<EOF
${recs}
EOF

# The capture filter (sync/origin-filter.sh): a table whose floor comes from
# the seed, or from another table's floor, is published only for rows this
# clinic wrote -- key at or above the floor, on this clinic's residue. Its
# floors come from SEED_MANIFEST (the seed's manifest.env), or else from the
# floors the seed gate recorded on this machine from it; its residue is
# RESIDUE from .env, which must agree with the offset MySQL is started with.
# A floor or residue that cannot be read stops here: the configuration is
# never written without the filter.
filter_lines=""
if [[ -n "${filter_recs}" ]]; then
  FLOORS_FILE="${SEED_MANIFEST:-${PROJECT_DIR}/.install-state}"
  case "${RESIDUE:-}" in
    [1-9]) ;;
    *) echo "Error: RESIDUE in ${ENV_FILE} is '${RESIDUE:-}', not a clinic residue (1 to 9); the capture filter of $(printf '%s' "${filter_recs}" | awk '{print $1}' | tr '\n' ' ')needs it. Nothing was written." >&2; exit 1 ;;
  esac
  if [[ -n "${MYSQL_AUTO_INCREMENT_OFFSET:-}" ]] && { [[ "${MYSQL_AUTO_INCREMENT_OFFSET}" == *[!0-9]* ]] || [[ "$(( 10#${MYSQL_AUTO_INCREMENT_OFFSET} % 10 ))" != "${RESIDUE}" ]]; }; then
    echo "Error: RESIDUE=${RESIDUE} but MYSQL_AUTO_INCREMENT_OFFSET=${MYSQL_AUTO_INCREMENT_OFFSET} in ${ENV_FILE}: MySQL would issue ids on another residue than the capture filter keeps. Nothing was written." >&2
    exit 1
  fi
  floor_recs=""
  while read -r table pk; do
    [[ -n "${table}" ]] || continue
    fl="$(up_floor_of "${TABLES_CONF}" "${table}" "${FLOORS_FILE}")" || { echo "Error: the ${table} capture filter needs its floor (reason above). Nothing was written." >&2; exit 1; }
    floor_recs="${floor_recs}${table} ${pk} ${fl}
"
  done <<EOF
${filter_recs}
EOF
  filter_lines="$(printf '%s' "${floor_recs}" | origin_filter_lines "${MYSQL_SERVER_NAME}" "${DATABASE_NAME}" "${RESIDUE}")" \
    || { echo "Error: the capture filter cannot be rendered (reason above). Nothing was written." >&2; exit 1; }
  [[ -n "${filter_lines}" ]] || { echo "Error: the capture filter rendered empty for $(printf '%s' "${filter_recs}" | awk '{print $1}' | tr '\n' ' '); nothing was written." >&2; exit 1; }
fi

[[ ${#table_include_list[@]} -gt 0 ]] || { echo "Error: no tables parsed from ${TABLES_CONF}"; exit 1; }

export TABLE_INCLUDE_LIST
TABLE_INCLUDE_LIST="$(IFS=','; echo "${table_include_list[*]}")"
KAFKA_TOPICS="$(IFS=','; echo "${kafka_topics[*]}")"

mkdir -p "${CONNECTORS_DIR}"
SUBST_VARS='${LOCAL_MYSQL_HOST} ${LOCAL_MYSQL_PORT} ${LOCAL_DEBEZIUM_USER} ${LOCAL_DEBEZIUM_PASSWORD} ${MYSQL_SERVER_NAME} ${DATABASE_INCLUDE_LIST} ${TABLE_INCLUDE_LIST} ${DEBEZIUM_SERVER_ID} ${DEBEZIUM_SNAPSHOT_MODE}'
rendered="${OUT_PRIMARY}.new"
envsubst "${SUBST_VARS}" < "${TEMPLATE}" > "${rendered}"
if [[ -n "${filter_lines}" ]]; then
  printf '%s\n' "${filter_lines}" > "${rendered}.filter"
  origin_filter_merge "${rendered}" "${rendered}.filter" \
    || { rm -f "${rendered}" "${rendered}.filter"; echo "Error: could not add the capture filter to the source configuration; nothing was written." >&2; exit 1; }
  rm -f "${rendered}.filter"
fi
mv "${rendered}" "${OUT_PRIMARY}"
cp "${OUT_PRIMARY}" "${OUT_ALIAS}"

echo "Generated: ${OUT_PRIMARY}"
echo "Generated: ${OUT_ALIAS}"
echo "  Tables: ${#table_include_list[@]}"
if [[ -n "${filter_lines}" ]]; then
  echo "  Capture filter (residue ${RESIDUE}):"
  printf '%s' "${floor_recs}" | while read -r table pk fl; do [[ -n "${table}" ]] && echo "    ${table}: ${pk} at or above ${fl}"; done
fi
echo "  TABLE_INCLUDE_LIST=${TABLE_INCLUDE_LIST}"
echo "  KAFKA_TOPICS=${KAFKA_TOPICS}"
echo ""
echo "Next:"
echo "  1. Copy TABLE_INCLUDE_LIST / KAFKA_TOPICS into .env if you keep them there"
echo "  2. ./scripts/register-source-connector.sh"
echo "  3. Cloud→local tables live in hub/tables.conf (separate list)"
