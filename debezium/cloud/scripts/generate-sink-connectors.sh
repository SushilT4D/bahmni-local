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

    "//pool": "BL-039 durable fix, 2026-08-28. Second layer only -- the primary defence is",
    "//pool2": "server-side: wait_timeout is now 604800 on both nodes (was the stock 28800,",
    "//pool3": "which nobody ever chose). Note the shipped default here is already 1800 and",
    "//pool4": "it did NOT prevent a 45,376,505 ms stale connection, so do not treat this",
    "//pool5": "key as load-bearing until it has been measured over a real idle gap.",
    "//pool6": "DO NOT set connection.pool.min_size=0: tried on 2026-08-28, and 4 of 13 sinks",
    "//pool7": "died on boot with 'Unable to determine Dialect without JDBC metadata'.",
    "//pool8": "Hibernate needs a connection at startup to probe the dialect; an empty pool",
    "//pool9": "has none. min_size stays at its default of 5.",
    "//pool-measured": "MEASURED INERT 2026-08-28. Two samples 317s apart on both nodes:",
    "//pool-measured2": "cloud 60 conns aged 512-517s then 829-834s; clinic 35 conns aged 836s.",
    "//pool-measured3": "Ages tracked wall-clock 1:1 and NOT ONE connection was recycled, so this",
    "//pool-measured4": "key does not expire idle connections at min_size. Kept for the record, but",
    "//pool-measured5": "it protects nothing: wait_timeout=604800 is the entire defence. Do not",
    "//pool-measured6": "count this as a second layer when reasoning about BL-039.",
    "//c3p0": "F-007 REAL FIX, 2026-09-02. connection.pool.timeout above is INERT --",
    "//c3p02": "confirmed from the debezium-connector-jdbc 3.2.4 bytecode: min_size,",
    "//c3p03": "max_size and acquire_increment each have a matching hibernate.c3p0.* literal,",
    "//c3p04": "connection.pool.timeout has NONE, so it is parsed and silently dropped.",
    "//c3p05": "The four keys below DO reach c3p0 via the hibernate.* passthrough and are the",
    "//c3p06": "only client-side defence; they survive a MySQL restart, which wait_timeout",
    "//c3p07": "does not -- the 2026-08-28 wait_timeout=604800 fix was written to compose but",
    "//c3p08": "the container was never RECREATED, so Rawach and the cloud were still on the",
    "//c3p09": "stock 28800 on 2026-09-02 and the sinks died again after a 13h idle gap.",
    "//c3p010": "PROVEN 2026-09-02: killed all 45 sink connections server-side and the next",
    "//c3p011": "write landed in 5s, every task RUNNING. Unfixed control sink FAILED same batch.",
    "hibernate.c3p0.timeout": "1800",
    "hibernate.c3p0.idle_test_period": "300",
    "hibernate.c3p0.preferredTestQuery": "SELECT 1",
    "hibernate.c3p0.testConnectionOnCheckout": "true",
    "//pool-cap": "F-013 REAL FIX, 2026-09-02. The lever is max_size, NOT min_size.",
    "//pool-cap2": "Measured on the cloud: min_size=5 with an unbounded max held 120 conns for 25",
    "//pool-cap3": "sinks. Lowering to min_size=1 alone made it WORSE -- 493 conns, ceiling hit, 5",
    "//pool-cap4": "sinks FAILED -- because c3p0 then grows by acquire_increment, whose Debezium",
    "//pool-cap5": "default is 32 (25 sinks x 32 = 800 potential). The high min_size had been",
    "//pool-cap6": "accidentally CAPPING the pool by keeping it pre-filled and stable.",
    "//pool-cap7": "min=1 + max=2 + acquire_increment=1 gives a hard bound: 25 sinks -> 48 conns",
    "//pool-cap8": "measured, all tasks RUNNING, cloud->clinic round trip 10s. Per clinic the cost",
    "//pool-cap9": "falls 60 -> 24, so 7 clinics need ~168 + ~30 app, well inside 500.",
    "//pool-cap10": "Do NOT set min_size=0: 4 sinks die on boot with 'Unable to determine Dialect'.",
    "connection.pool.max_size": "2",
    "connection.pool.acquire_increment": "1",
    "connection.pool.timeout": "300",

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
        #
        # The checks now live in validate-sink-config.py, which also DIFFS this
        # config against known-good.json - making the "SHAPE IS AUTHORITATIVE"
        # claim above executable instead of advisory. It is a separate file
        # because validator source has to contain $, backslashes and quotes, and
        # this script's heredoc is unquoted: exactly the blast radius that
        # produced the three silent bugs documented above.
        python3 "${SCRIPT_DIR}/validate-sink-config.py" "${config_file}" \
            --known-good "${CONNECTORS_DIR}/known-good.json" \
            --database-name "${DATABASE_NAME}" || exit 1
        
        echo "Generated: ${config_file} (table: ${table}, topic: ${topic}, pk: ${pk})"
        connector_count=$((connector_count + 1))
    fi
done < "${TABLES_CONF}"

echo ""
echo "Generated ${connector_count} sink connector configuration(s)"
echo ""
echo "To register connectors, use:"
echo "  ./scripts/register-all-sink-connectors.sh"

