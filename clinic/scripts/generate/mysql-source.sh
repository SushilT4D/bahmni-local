#!/usr/bin/env bash
# Part of generate-connectors.sh: the MySQL (OpenMRS) source connector, capturing the [up] tables of
# sync/tables/openmrs.conf into one ordered topic, <server>.openmrs.all. Writes
# connectors/mysql-source-connector.json; the Debezium password stays a placeholder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"
ENV_FILE="${PROJECT_DIR}/.env"
TABLES_CONF="${PROJECT_DIR}/../sync/tables/openmrs.conf"
TEMPLATE="${PROJECT_DIR}/scripts/templates/mysql-source-connector.json"
OUT_PRIMARY="${CONNECTORS_DIR}/mysql-source-connector.json"

[[ -f "${ENV_FILE}" ]] || { echo "Error: .env not found at ${ENV_FILE}"; exit 1; }
[[ -f "${TABLES_CONF}" ]] || { echo "Error: ${TABLES_CONF} not found"; exit 1; }
[[ -f "${TEMPLATE}" ]] || { echo "Error: template not found: ${TEMPLATE}"; exit 1; }
command -v envsubst >/dev/null 2>&1 || { echo "Error: envsubst not found (brew install gettext)"; exit 1; }

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

MYSQL_SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
# Template uses LOCAL_* / DEBEZIUM_* names; map from root .env conventions.
DEBEZIUM_USER="${DEBEZIUM_USER:-debezium}"

export MYSQL_SERVER_NAME
export DEBEZIUM_USER

table_include_list=()
kafka_topics=()
filter_recs=""

# shellcheck source=../../sync/tables/tables.sh
. "${PROJECT_DIR}/../sync/tables/tables.sh"
# shellcheck source=../../sync/origin-filter.sh
. "${PROJECT_DIR}/../sync/origin-filter.sh"
recs="$(up_tables_read "${TABLES_CONF}")" || { echo "Error: ${TABLES_CONF} cannot be read as the clinic's table list (reason above)" >&2; exit 1; }
while read -r table _pk _kind _arg; do
  [[ -n "${table}" ]] || continue
  table_include_list+=("openmrs.${table}")
  kafka_topics+=("${MYSQL_SERVER_NAME}.openmrs.${table}")
  case "${_kind}" in seed|floor) filter_recs="${filter_recs}${table} ${_pk}
" ;; esac
done <<EOF
${recs}
EOF

# Apply ownership filters to tables with seed-derived floors.
filter_lines=""
if [[ -n "${filter_recs}" ]]; then
  FLOORS_FILE="${SEED_MANIFEST:-${PROJECT_DIR}/.install-state}"
  case "${BHS_SITE_NUMBER:-}" in
    [1-9]) ;;
    *) echo "Error: BHS_SITE_NUMBER in ${ENV_FILE} is '${BHS_SITE_NUMBER:-}', not a clinic residue (1 to 9); the capture filter of $(printf '%s' "${filter_recs}" | awk '{print $1}' | tr '\n' ' ')needs it. Nothing was written." >&2; exit 1 ;;
  esac
  floor_recs=""
  while read -r table pk; do
    [[ -n "${table}" ]] || continue
    fl="$(up_floor_of "${TABLES_CONF}" "${table}" "${FLOORS_FILE}")" || { echo "Error: the ${table} capture filter needs its floor (reason above). Nothing was written." >&2; exit 1; }
    floor_recs="${floor_recs}${table} ${pk} ${fl}
"
  done <<EOF
${filter_recs}
EOF
  filter_lines="$(printf '%s' "${floor_recs}" | origin_filter_lines "${MYSQL_SERVER_NAME}" "openmrs" "${BHS_SITE_NUMBER}")" \
    || { echo "Error: the capture filter cannot be rendered (reason above). Nothing was written." >&2; exit 1; }
  [[ -n "${filter_lines}" ]] || { echo "Error: the capture filter rendered empty for $(printf '%s' "${filter_recs}" | awk '{print $1}' | tr '\n' ' '); nothing was written." >&2; exit 1; }
fi

[[ ${#table_include_list[@]} -gt 0 ]] || { echo "Error: no tables parsed from ${TABLES_CONF}"; exit 1; }
# the signal table: in the include list (Debezium's source signal channel reads
# it from the binlog), never in the topics MirrorMaker sends to the hub
SIGNAL_DATA_COLLECTION="$(up_signal_collection "openmrs")"
table_include_list+=("${SIGNAL_DATA_COLLECTION}")
export SIGNAL_DATA_COLLECTION

export TABLE_INCLUDE_LIST
TABLE_INCLUDE_LIST="$(IFS=','; echo "${table_include_list[*]}")"
KAFKA_TOPICS="$(IFS=','; echo "${kafka_topics[*]}")"

mkdir -p "${CONNECTORS_DIR}"
# ${DEBEZIUM_PASSWORD} stays a placeholder: register-connectors.sh fills it from .env.
SUBST_VARS='${DEBEZIUM_USER} ${MYSQL_SERVER_NAME} ${TABLE_INCLUDE_LIST} ${DEBEZIUM_SERVER_ID} ${DEBEZIUM_SNAPSHOT_MODE} ${SIGNAL_DATA_COLLECTION}'
rendered="${OUT_PRIMARY}.new"
envsubst "${SUBST_VARS}" < "${TEMPLATE}" > "${rendered}"
if [[ -n "${filter_lines}" ]]; then
  printf '%s\n' "${filter_lines}" > "${rendered}.filter"
  origin_filter_merge "${rendered}" "${rendered}.filter" \
    || { rm -f "${rendered}" "${rendered}.filter"; echo "Error: could not add the capture filter to the source configuration; nothing was written." >&2; exit 1; }
  rm -f "${rendered}.filter"
fi
# Route every captured table into one ordered topic, <server>.openmrs.all, after the filters.
UP_ALTERNATION="$(printf '%s\n' "${kafka_topics[@]}" | sed "s/^.*\.//" | paste -sd'|' -)"
python3 - "${rendered}" "${MYSQL_SERVER_NAME}" "openmrs" "${UP_ALTERNATION}" <<'PY' \
  || { rm -f "${rendered}"; echo "Error: could not add the routing step to the source configuration; nothing was written." >&2; exit 1; }
import json, re, sys
path, server, db, alt = sys.argv[1:5]
doc = json.load(open(path)); cfg = doc["config"]
names = [n for n in cfg.get("transforms", "").split(",") if n] + ["agg"]
cfg["transforms"] = ",".join(names)
cfg["transforms.agg.type"] = "org.apache.kafka.connect.transforms.RegexRouter"
cfg["transforms.agg.regex"] = re.escape(server) + r"\." + re.escape(db) + r"\.(" + alt + r")$"
cfg["transforms.agg.replacement"] = f"{server}.{db}.all"
json.dump(doc, open(path, "w"), indent=2)
PY
python3 "${PROJECT_DIR}/scripts/_fill_template.py" --mark "${rendered}" "${TEMPLATE}" \
  || { rm -f "${rendered}"; echo "Error: could not mark ${OUT_PRIMARY} as generated; nothing was written." >&2; exit 1; }
mv "${rendered}" "${OUT_PRIMARY}"

echo "  mysql-source-connector.json: $(( ${#table_include_list[@]} - 1 )) tables into ${MYSQL_SERVER_NAME}.openmrs.all, and the signal table ${SIGNAL_DATA_COLLECTION}"
if [[ -n "${filter_lines}" ]]; then
  echo "  Capture filter (residue ${BHS_SITE_NUMBER}):"
  printf '%s' "${floor_recs}" | while read -r table pk fl; do [[ -n "${table}" ]] && echo "    ${table}: ${pk} at or above ${fl}"; done
fi
