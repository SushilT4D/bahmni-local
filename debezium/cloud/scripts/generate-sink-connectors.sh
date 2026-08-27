#!/bin/bash

# Script to generate sink connector configuration for each table
# Creates separate connector configs for better control

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# These sinks apply UP-direction data: they consume source.<clinic>.openmrs.* topics
# and write clinic-authored rows into the cloud. So the table list is the CLINIC's
# (debezium/local/tables.conf), NOT this directory's tables.conf -- which lists the
# seven CLOUD-OWNED tables that flow the other way.
#
# Until 2026-08-27 this defaulted to ${PROJECT_DIR}/tables.conf, so it generated
# up-direction sinks for users/role/role_privilege/role_role/user_property/user_role/
# provider. Those seven sinks are live on the cloud today, subscribed to
# source.bahmni-local.openmrs.<table> topics that the clinic never publishes: all seven
# measured 0 messages on 2026-08-27, while person/patient/visit carried 122k/122k/478k.
# Inert, but they report RUNNING and inflate any "all sinks green" check -- and if those
# tables are ever added to the clinic whitelist they would begin writing clinic-origin
# rows into cloud-owned tables, which no striding residue guards (L-008).
TABLES_CONF="${TABLES_CONF:-${PROJECT_DIR}/../local/tables.conf}"
DOWN_TABLES_CONF="${PROJECT_DIR}/tables.conf"
ENV_FILE="${PROJECT_DIR}/.env"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"

if [ ! -f "${TABLES_CONF}" ]; then
    echo "Error: tables.conf not found!"
    exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# Source environment variables
set -a
source "${ENV_FILE}"
set +a

# Normalize MySQL SSL flag (must be TRUE/FALSE/YES/NO for JDBC driver)
USE_SSL_RAW="${REMOTE_MYSQL_USE_SSL:-false}"
USE_SSL_UPPER=$(echo "${USE_SSL_RAW}" | tr '[:lower:]' '[:upper:]')
case "${USE_SSL_UPPER}" in
    TRUE|FALSE|YES|NO) ;;
    *)
        echo "Warning: REMOTE_MYSQL_USE_SSL='${USE_SSL_RAW}' is invalid. Defaulting to FALSE."
        USE_SSL_UPPER="FALSE"
        ;;
esac

# Server name should match MYSQL_SERVER_NAME from local setup
# This is used to construct topic names: {server-name}.{database}.{table}
SERVER_NAME="${MYSQL_SERVER_NAME:-${REMOTE_SOURCE_SERVER_NAME:-bahmni-local}}"
DATABASE_NAME="${DATABASE_NAME:-openmrs}"

# Create connectors directory if it doesn't exist
mkdir -p "${CONNECTORS_DIR}"

# Parse tables.conf and generate connector configs
connector_count=0
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Parse table:pk or table:pk:base_id
    if [[ "$line" =~ ^([^:]+):([^:]+)(:([0-9]+))?$ ]]; then
        table="${BASH_REMATCH[1]}"
        pk="${BASH_REMATCH[2]}"
        
        # L-008 ownership guard: a cloud-OWNED table must never get an up-direction
        # sink, or the cloud would apply clinic-origin rows to a table it authors.
        if [ -f "${DOWN_TABLES_CONF}" ] && grep -qE "^[[:space:]]*${table}:" "${DOWN_TABLES_CONF}"; then
            echo "REFUSING ${table}: it is cloud-owned (listed in ${DOWN_TABLES_CONF})." >&2
            echo "  An up-direction sink for it would write clinic rows into a cloud-owned table." >&2
            exit 1
        fi

        topic="${SERVER_NAME}.${DATABASE_NAME}.${table}"
        connector_name="mysql-sink-${table}"
        config_file="${CONNECTORS_DIR}/${connector_name}.json"
        
        # Generate connector config (pk.fields must be the real column, not ${table}_id)
        # Generate connector config.
        #
        # SHAPE IS AUTHORITATIVE: debezium/cloud/connectors/known-good.json is the
        # committed record of a sink that actually works. Keep this heredoc matching it.
        # Before 2026-08-27 this block diverged from it in six ways and emitted configs
        # that could never have worked -- see the three escaping/interpolation bugs below.
        #
        # Heredoc is UNQUOTED, so bash expands $ and collapses \\ . Therefore:
        #   - a literal $1 for RegexRouter must be written \$1  (bare $1 expands to the
        #     script's first positional arg -- i.e. EMPTY, silently routing to no table)
        #   - a JSON \\. must be written \\\\.  (\\. collapses to \. which is not a
        #     valid JSON escape)
        cat > "${config_file}" <<EOF
{
  "name": "${connector_name}",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",

    "topics": "source.${topic}",
    "transforms": "dropPrefix",
    "transforms.dropPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.dropPrefix.regex": "source\\\\.${SERVER_NAME}\\\\.${DATABASE_NAME}\\\\.(.*)",
    "transforms.dropPrefix.replacement": "\$1",
    "table.name.format.default": "${table}",

    "connection.url": "jdbc:mysql://${REMOTE_MYSQL_HOST}:${REMOTE_MYSQL_PORT}/${REMOTE_MYSQL_DATABASE}?useSSL=${USE_SSL_UPPER}&allowPublicKeyRetrieval=true",
    "connection.username": "${REMOTE_MYSQL_USER}",
    "connection.password": "${REMOTE_MYSQL_PASSWORD}",

    "insert.mode": "upsert",
    "primary.key.mode": "record_value",
    "primary.key.fields": "${pk}",
    "delete.enabled": "false",
    "schema.evolution": "basic",

    "//BL-039": "connection.restart.on.errors defaults to FALSE, so MySQL closing an idle",
    "//BL-039b": "pooled connection (wait_timeout) or a DB restart is treated as UNRECOVERABLE:",
    "//BL-039c": "the task dies permanently while connector.state still reads RUNNING.",
    "//BL-039d": "This block was added to the sink TEMPLATE on 2026-08-20 but not here --",
    "//BL-039e": "and this generator, not the template, is what register-all-sink-connectors.sh",
    "//BL-039f": "registers. Six cloud sinks were found FAILED on 2026-08-27 as a result.",
    "connection.restart.on.errors": "true",
    "errors.retry.timeout": "-1",
    "errors.retry.delay.max.ms": "60000",
    "flush.max.retries": "10",

    "//BL-005": "NOT errors.tolerance=all. 'all' silently DROPS a failing record -- an",
    "//BL-005b": "out-of-order FK row vanishes with no park, no DLQ, no trace. That defeats",
    "//BL-005c": "L-004 (park-and-retry) and L-010. known-good.json omits the key entirely,",
    "//BL-005d": "which defaults to none; we set it explicitly so the intent is visible.",
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

        # Fail loudly rather than emit a config that cannot work (the pre-2026-08-27
        # failure mode was silent: three bugs, valid-looking output, dead pipeline).
        python3 -c "
import json,sys
c = json.load(open('${config_file}'))['config']
errs = []
if c['topics'].count('${DATABASE_NAME}') > 1: errs.append('doubled topic prefix: ' + c['topics'])
if not c['transforms.dropPrefix.replacement']: errs.append('empty RegexRouter replacement (bare \$1 was expanded by bash)')
if c.get('errors.tolerance') == 'all': errs.append('errors.tolerance=all silently drops records (BL-005)')
if c.get('connection.restart.on.errors') != 'true': errs.append('missing BL-039 connection.restart.on.errors')
if not c.get('primary.key.fields'): errs.append('empty primary.key.fields')
if errs:
    sys.exit('INVALID CONFIG ${config_file}:\n  - ' + '\n  - '.join(errs))
" || exit 1
        
        echo "Generated: ${config_file} (table: ${table}, topic: ${topic}, pk: ${pk})"
        connector_count=$((connector_count + 1))
    fi
done < "${TABLES_CONF}"

echo ""
echo "Generated ${connector_count} sink connector configuration(s)"
echo ""
echo "To register connectors, use:"
echo "  ./scripts/register-all-sink-connectors.sh"

