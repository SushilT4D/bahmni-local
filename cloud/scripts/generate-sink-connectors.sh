#!/bin/bash
# Generates the hub's up sinks for every clinic in sync/clinics.json, three per clinic, into
# ./connectors/:
#   openmrs-<slug>-sink   reads <slug>.bahmni-<slug>.openmrs.all, writes each record to its own table
#   odoo-<slug>-sink      reads <slug>.bahmni-<slug>.odoo.all, claims origin clinic_<slug>_odoo
#   clinlims-<slug>-sink  reads <slug>.bahmni-<slug>.clinlims.all, claims origin clinic_<slug>_clinlims
# usage: generate-sink-connectors.sh [slug ...]   (default: every clinic in sync/clinics.json)
set -e

# the configs hold the hub's database passwords: written mode 600
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

TABLES_CONF="${TABLES_CONF:-${PROJECT_DIR}/../sync/tables/openmrs.conf}"
CLINICS_JSON="${CLINICS_JSON:-${PROJECT_DIR}/../sync/clinics.json}"
ENV_FILE="${ENV_FILE:-$PWD/.env}"
TEMPLATES_DIR="${PROJECT_DIR}/scripts/templates"
OUT_DIR="${OUT_DIR:-$PWD/connectors}"


# ---- inputs: the clinic's [up] list, the clinics and cloud/.env -----------------

[ -f "${TABLES_CONF}" ]  || { echo "Error: ${TABLES_CONF} not found"; exit 1; }
[ -f "${CLINICS_JSON}" ] || { echo "Error: ${CLINICS_JSON} not found"; exit 1; }
[ -f "${ENV_FILE}" ]     || { echo "Error: ${ENV_FILE} not found"; exit 1; }

# the [up] list, read by the shared reader (a refused list stops the run)
# shellcheck source=../../sync/tables/tables.sh
. "${PROJECT_DIR}/../sync/tables/tables.sh"
TABLE_RECS="$(up_tables_read "${TABLES_CONF}")" \
  || { echo "Error: ${TABLES_CONF} cannot be read as the clinic's table list (reason above)"; exit 1; }

set -a
source "${ENV_FILE}"
set +a


# ---- settings from cloud/.env -------------------------------------------------

export OPENMRS_DB_HOST="${OPENMRS_DB_HOST:?OPENMRS_DB_HOST is not set in .env}"
export OPENMRS_DB_PORT="${OPENMRS_DB_PORT:-3306}"
export OPENMRS_DB_NAME="${OPENMRS_DB_NAME:?OPENMRS_DB_NAME is not set in .env}"
export DEBEZIUM_DB_USER="${DEBEZIUM_DB_USER:-debezium}"
export DEBEZIUM_DB_PASSWORD="${DEBEZIUM_DB_PASSWORD:?DEBEZIUM_DB_PASSWORD is not set in .env}"
export ODOO_DB_HOST="${ODOO_DB_HOST:?ODOO_DB_HOST is not set in .env}"
export ODOO_DB_NAME="${ODOO_DB_NAME:?ODOO_DB_NAME is not set in .env}"
export ODOO_SINK_PASSWORD="${ODOO_SINK_PASSWORD:?ODOO_SINK_PASSWORD is not set in .env}"
export OPENELIS_DB_HOST="${OPENELIS_DB_HOST:?OPENELIS_DB_HOST is not set in .env}"
export CLINLIMS_SINK_PASSWORD="${CLINLIMS_SINK_PASSWORD:?CLINLIMS_SINK_PASSWORD is not set in .env}"

USE_SSL_UPPER=$(echo "${REMOTE_MYSQL_USE_SSL:-false}" | tr '[:lower:]' '[:upper:]')
case "${USE_SSL_UPPER}" in
  TRUE|FALSE|YES|NO) ;;
  *)
    echo "Warning: REMOTE_MYSQL_USE_SSL='${REMOTE_MYSQL_USE_SSL:-}' invalid; using FALSE."
    USE_SSL_UPPER="FALSE"
    ;;
esac

mkdir -p "${OUT_DIR}"
WANTED="$*"
total=0


# ---- the clinics: every clinic in sync/clinics.json with a site number, but the cloud

clinics="$(jq -r 'to_entries[] | select(.key != "cloud" and .value.site_number != null) | .key' "${CLINICS_JSON}")" \
  || { echo "Error: ${CLINICS_JSON} is not valid JSON"; exit 1; }
[ -n "$clinics" ] || { echo "Error: ${CLINICS_JSON} lists no clinic with a site number"; exit 1; }

if [ -n "$WANTED" ]; then
  for w in $WANTED; do
    printf '%s\n' "$clinics" | grep -qx "$w" || { echo "Error: ${w} is not a clinic with a site number in ${CLINICS_JSON}"; exit 1; }
  done
  clinics="$WANTED"
fi

tables="$(printf '%s\n' "${TABLE_RECS}" | awk 'NF {print $1}')"


# ---- the OpenMRS sink --------------------------------------------------------------

write_openmrs_sink() {
  local slug="$1" name="openmrs-$1-sink" topic="$1.bahmni-$1.${OPENMRS_DB_NAME}.all"
  local file="${OUT_DIR}/${name}.json"

  cat > "$file" <<EOF
{
  "name": "${name}",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",

    "//order": "One task, one connection and one record per write keep the clinic's commit order.",
    "tasks.max": "1",
    "batch.size": "1",
    "connection.pool.min_size": "1",
    "connection.pool.max_size": "1",
    "connection.pool.timeout": "1800",

    "//topics": "One ordered topic for every OpenMRS table the clinic sends; each record goes to the table it came from.",
    "topics": "${topic}",
    "collection.name.format": "${OPENMRS_DB_NAME}.\${source.table}",

    "//binlog": "sql_log_bin=0 keeps the clinic's rows out of the hub's binlog, so the hub's source never sends them back down.",
    "connection.url": "jdbc:mysql://${OPENMRS_DB_HOST}:${OPENMRS_DB_PORT}/${OPENMRS_DB_NAME}?useSSL=${USE_SSL_UPPER}&allowPublicKeyRetrieval=true&sessionVariables=sql_log_bin=0",
    "connection.username": "${DEBEZIUM_DB_USER}",
    "connection.password": "${DEBEZIUM_DB_PASSWORD}",

    "//keys": "The strided integer key from the Kafka record key, never the UUID or a value field.",
    "insert.mode": "upsert",
    "primary.key.mode": "record_key",
    "delete.enabled": "true",
    "//schema": "Never alter a hub table to fit a record: a schema mismatch stops this sink.",
    "schema.evolution": "none",

    "//restart": "Survive MySQL restarts and idle-connection closes; without it a closed connection kills the task for good.",
    "connection.restart.on.errors": "true",
    "errors.retry.timeout": "-1",
    "errors.retry.delay.max.ms": "60000",
    "flush.max.retries": "10",
    "hibernate.agroal.validateOnBorrow": "true",
    "hibernate.agroal.idleValidation_s": "300",

    "//tolerance": "Never errors.tolerance=all: it silently drops a failing record.",
    "errors.tolerance": "none",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",

    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true"
  }
}
EOF

  # check it against scripts/templates/known-good.json; an unvalidated config is never kept
  python3 "${SCRIPT_DIR}/validate-sink-config.py" "$file" \
      --known-good "${TEMPLATES_DIR}/known-good.json" \
      --database-name "${OPENMRS_DB_NAME}" \
    || { rm -f "$file"; exit 1; }
}


# ---- the Odoo and OpenELIS sinks, from their templates -----------------------------

write_postgres_sink() {
  local db="$1" slug="$2"
  SLUG="$slug" python3 - "${TEMPLATES_DIR}/${db}-sink.json.template" "${OUT_DIR}/${db}-${slug}-sink.json" <<'PY' \
    || exit 1
import json, os, re, sys
raw = open(sys.argv[1]).read()
keys = ('SLUG', 'ODOO_DB_HOST', 'ODOO_DB_NAME', 'ODOO_SINK_PASSWORD', 'OPENELIS_DB_HOST', 'CLINLIMS_SINK_PASSWORD')
for k in keys:
    raw = raw.replace('${%s}' % k, os.environ[k])
left = sorted(set(re.findall(r'\$\{(\w+)\}', raw)) - {'source'})
if left:
    sys.exit(f"{sys.argv[1]}: unfilled placeholder(s): {left}")
doc = json.loads(raw)
doc['config'] = {k: v for k, v in doc['config'].items() if not k.startswith('//')}
json.dump(doc, open(sys.argv[2], 'w'), indent=2)
PY
}


# ---- one set of sinks per clinic ---------------------------------------------------

for slug in $clinics; do
  rm -f "${OUT_DIR}"/*-"${slug}"-sink.json

  write_openmrs_sink "$slug"
  write_postgres_sink odoo "$slug"
  write_postgres_sink clinlims "$slug"

  echo "== ${slug}: openmrs-${slug}-sink, odoo-${slug}-sink, clinlims-${slug}-sink"
  echo "   openmrs tables: $(printf '%s ' $tables)"
  total=$((total + 1))
done


# ---- summary -------------------------------------------------------------------

echo ""
echo "Generated sinks for ${total} clinic(s) in ${OUT_DIR}."
echo "Before a clinic's sinks start, create its replication origins (cloud/postgres/apply-sink-origin.sql)."
echo "Register with: HUB_MYSQL_CONTAINER=<the hub's OpenMRS MySQL container> ./scripts/register-all-sink-connectors.sh"
