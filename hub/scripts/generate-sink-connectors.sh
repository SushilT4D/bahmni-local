#!/bin/bash
# Generate the hub's UP-direction JDBC sink configs, one per clinic per table.
#
# Usage: generate-sink-connectors.sh [clinic ...]     (default: every clinic)
#
# Every connector is named mysql-sink-<clinic>-<table>: a name without the clinic
# component would let a second clinic's run overwrite the first clinic's files
# and, on registration, PUT over its live connectors. The table list is the
# CLINIC's (see below); a table listed in both directions is warned about, not
# refused -- see the ownership note in the loop.
set -e
# Every file this script writes carries REMOTE_MYSQL_PASSWORD in plaintext, so
# they are created mode 600, not the default 644.
# umask rather than a chmod per file: a chmod leaves a window in which the
# rendered config is world-readable, however short.
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# These sinks apply UP-direction data: they consume <clinic>.<server>.openmrs.*
# topics and write clinic-authored rows into the cloud. So the table list is the
# CLINIC's (sync/local/tables.conf), NOT this directory's tables.conf --
# which lists the tables that flow the other way.
#
# Generating up-direction sinks from this directory's tables.conf instead would
# produce sinks for users/role/role_privilege/role_role/user_property/user_role/
# provider, all subscribed to topics the clinic never publishes: inert, but
# reporting RUNNING and inflating any "all sinks green" check.
TABLES_CONF="${TABLES_CONF:-${PROJECT_DIR}/../sync/local/tables.conf}"
DOWN_TABLES_CONF="${PROJECT_DIR}/tables.conf"
CLINICS_CONF="${CLINICS_CONF:-${PROJECT_DIR}/clinics.conf}"
ENV_FILE="${PROJECT_DIR}/.env"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"

[ -f "${TABLES_CONF}" ]  || { echo "Error: ${TABLES_CONF} not found"; exit 1; }
[ -f "${CLINICS_CONF}" ] || { echo "Error: ${CLINICS_CONF} not found"; exit 1; }
[ -f "${ENV_FILE}" ]     || { echo "Error: .env not found"; exit 1; }

set -a
source "${ENV_FILE}"
set +a

USE_SSL_UPPER=$(echo "${REMOTE_MYSQL_USE_SSL:-false}" | tr '[:lower:]' '[:upper:]')
case "${USE_SSL_UPPER}" in
    TRUE|FALSE|YES|NO) ;;
    *) echo "Warning: REMOTE_MYSQL_USE_SSL='${REMOTE_MYSQL_USE_SSL:-}' invalid; using FALSE."
       USE_SSL_UPPER="FALSE" ;;
esac

DATABASE_NAME="${DATABASE_NAME:-openmrs}"
mkdir -p "${CONNECTORS_DIR}"

WANTED="$*"
total=0

while IFS= read -r cline || [ -n "$cline" ]; do
    [[ "$cline" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${cline// }" ]] && continue
    IFS=':' read -r clinic name_prefix mm_prefix server_name <<< "$cline"
    [ -n "$clinic" ] && [ -n "$name_prefix" ] && [ -n "$mm_prefix" ] && [ -n "$server_name" ] || {
        echo "Skipping malformed clinics.conf line: $cline" >&2; continue; }
    if [ -n "$WANTED" ]; then
        case " $WANTED " in *" $clinic "*) ;; *) continue ;; esac
    fi

    echo "== ${clinic} (${mm_prefix}.${server_name}.${DATABASE_NAME}.*) =="
    count=0

    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        [[ "$line" =~ ^([^:]+):([^:]+)(:([0-9]+))?$ ]] || continue
        table="${BASH_REMATCH[1]}"
        pk="${BASH_REMATCH[2]}"

        # A table appearing in BOTH directions is legitimate: ownership is per
        # ROW, and more than one node may write a table provided no two nodes
        # write the same row, which the strided PK guarantees. Refusing such a
        # table (per-table ownership) would stop the generator dead on
        # person/person_name, which the hub relays. It warns instead, because a
        # bidirectional table is still worth a human glance -- it is only safe
        # ABOVE that table's base_id floor (rows below it occupy all ten residues).
        if [ -f "${DOWN_TABLES_CONF}" ] && grep -qE "^[[:space:]]*${table}:" "${DOWN_TABLES_CONF}"; then
            echo "  NOTE ${table}: bidirectional (also in ${DOWN_TABLES_CONF##*/}). Safe only above its base_id floor." >&2
        fi

        connector_name="${name_prefix}${table}"
        topic="${mm_prefix}.${server_name}.${DATABASE_NAME}.${table}"
        config_file="${CONNECTORS_DIR}/${connector_name}.json"

        # SHAPE IS AUTHORITATIVE: connectors/known-good.json is the committed
        # record of a sink that actually works, and the validator diffs against
        # it. Both were taken from a LIVE hub.
        #
        # Heredoc is UNQUOTED, so bash expands $ and collapses \\ . Therefore:
        #   - a literal $1 for RegexRouter must be written \$1 (bare $1 expands
        #     to the script's first positional arg, silently routing nowhere)
        #   - a JSON \\. must be written \\\\.
        cat > "${config_file}" <<EOF
{
  "name": "${connector_name}",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",

    "topics": "${topic}",
    "transforms": "dropPrefix",
    "transforms.dropPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.dropPrefix.regex": "${mm_prefix}\\\\.${server_name}\\\\.${DATABASE_NAME}\\\\.(.*)",
    "transforms.dropPrefix.replacement": "\$1",
    "table.name.format.default": "${DATABASE_NAME}.${table}",

    "connection.url": "jdbc:mysql://${REMOTE_MYSQL_HOST}:${REMOTE_MYSQL_PORT}/${REMOTE_MYSQL_DATABASE}?useSSL=${USE_SSL_UPPER}&allowPublicKeyRetrieval=true",
    "connection.username": "${REMOTE_MYSQL_USER}",
    "connection.password": "${REMOTE_MYSQL_PASSWORD}",

    "insert.mode": "upsert",

    "//pkmode": "record_key, NOT record_value. The sync key must be",
    "//pkmode2": "collision-free by construction: that is the STRIDED",
    "//pkmode3": "INTEGER PK carried in the Kafka record key, never the UUID and",
    "//pkmode4": "never a value field. A generator emitting record_value would",
    "//pkmode5": "downgrade every live sink out of compliance.",
    "primary.key.mode": "record_key",
    "primary.key.fields": "${pk}",
    "delete.enabled": "true",
    "auto.create": "true",
    "auto.evolve": "true",

    "//restart": "connection.restart.on.errors defaults to FALSE, so MySQL closing an idle",
    "//restart2": "pooled connection (wait_timeout) or a DB restart is treated as UNRECOVERABLE:",
    "//restart3": "the task dies permanently while connector.state still reads RUNNING.",
    "//restart4": "This generator, not the template, is what register-all-sink-connectors.sh",
    "//restart5": "registers, so the flag is set HERE.",
    "connection.restart.on.errors": "true",
    "errors.retry.timeout": "-1",
    "errors.retry.delay.max.ms": "60000",
    "flush.max.retries": "10",

    "//agroal": "Survive a MySQL restart and idle-connection closes, on Agroal (Debezium 3.6.2",
    "//agroal2": "dropped c3p0 for Agroal, DBZ-8899). The four hibernate.c3p0.* keys this",
    "//agroal3": "generator used to emit are inert under 3.6.2: Hibernate parses them,",
    "//agroal4": "matches them against no active provider, and silently drops them -- same",
    "//agroal5": "failure shape connection.pool.timeout itself had under c3p0. Direct",
    "//agroal6": "equivalents: hibernate.agroal.validateOnBorrow is Agroal's checkout-time",
    "//agroal7": "liveness check (was testConnectionOnCheckout); hibernate.agroal.idleValidation_s",
    "//agroal8": "is Agroal's idle revalidation interval in seconds (was idle_test_period).",
    "//agroal9": "Agroal has no configurable test-query hook (no equivalent of",
    "//agroal10": "preferredTestQuery) -- it validates via the JDBC driver's Connection.isValid().",
    "//agroal11": "connection.pool.timeout is Debezium's own native property (not",
    "//agroal12": "provider-specific) and is kept, set directly to the value that used to",
    "//agroal13": "need the hibernate.c3p0.timeout passthrough. Same role as before: survive a",
    "//agroal14": "MySQL restart, which wait_timeout does not. The kill-45-connections",
    "//agroal15": "proof was run under c3p0/3.2.4 and has not been independently",
    "//agroal16": "re-run under Agroal/3.6.2 on this exact scenario.",
    "hibernate.agroal.validateOnBorrow": "true",
    "hibernate.agroal.idleValidation_s": "300",

    "//pool-cap": "Pool cap. The lever is max_size, NOT min_size.",
    "//pool-cap2": "min=5 with an unbounded max held 120 conns for 25 sinks. min_size=1",
    "//pool-cap3": "ALONE made it worse -- 493 conns, ceiling hit, 5 sinks FAILED --",
    "//pool-cap4": "because c3p0 then grows by acquire_increment, whose default is 32.",
    "//pool-cap5": "min=1 + max=2 + acquire_increment=1 gave a hard bound: 48 conns for",
    "//pool-cap6": "25 sinks, all RUNNING. Do NOT set min_size=0: 4 sinks then die on boot",
    "//pool-cap7": "with 'Unable to determine Dialect without JDBC metadata'. acquire_increment",
    "//pool-cap8": "is dropped (no Agroal equivalent -- Agroal has no configurable",
    "//pool-cap9": "growth-batch-size knob); max_size=2 alone remains the hard bound under",
    "//pool-cap10": "Agroal, which opens connections up to max_size on demand with no separate",
    "//pool-cap11": "increment step.",
    "connection.pool.min_size": "1",
    "connection.pool.max_size": "2",
    "connection.pool.timeout": "1800",

    "//tolerance": "NOT errors.tolerance=all. 'all' silently DROPS a failing record -- an",
    "//tolerance2": "out-of-order FK row vanishes with no park, no DLQ, no trace, defeating",
    "//tolerance3": "Set explicitly so the intent is visible.",
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

        if [ -f "${SCRIPT_DIR}/validate-sink-config.py" ]; then
            python3 "${SCRIPT_DIR}/validate-sink-config.py" "${config_file}" \
                --known-good "${CONNECTORS_DIR}/known-good.json" \
                --database-name "${DATABASE_NAME}" || exit 1
        else
            echo "  FAIL validator missing: ${SCRIPT_DIR}/validate-sink-config.py" >&2
            echo "  Refusing to emit unvalidated configs -- an absent check reads as a passing one." >&2
            exit 1
        fi

        echo "  ${connector_name}  <- ${topic}  (pk ${pk})"
        count=$((count + 1))
        total=$((total + 1))
    done < "${TABLES_CONF}"
    echo "  ${count} sink(s) for ${clinic}"
done < "${CLINICS_CONF}"

echo ""
echo "Generated ${total} sink connector configuration(s)."
echo "Register with: ./scripts/register-all-sink-connectors.sh"
