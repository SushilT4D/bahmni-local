#!/bin/bash
# Generate the hub's UP-direction JDBC sink configs, one per clinic per table.
#
# Usage: generate-sink-connectors.sh [clinic ...]     (default: every clinic)
#
# WHY THIS WAS REWRITTEN (2026-09-14). The previous version could serve exactly
# one clinic: it named every connector mysql-sink-${table} with no clinic
# component, so a second clinic's run overwrote the first clinic's files and,
# on registration, PUT over its live connectors. Clinic 2's twelve sinks were
# therefore created by hand as mysql-sink-ghated-* and existed in no file in any
# repo -- only in Kafka Connect's internal config topic.
#
# It also could not serve clinic 1 any more: the L-008 guard below refused any
# table listed in this directory's tables.conf, and person/person_name were
# added there on 2026-09-14, so the loop exited 1 on person.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

# These sinks apply UP-direction data: they consume <clinic>.<server>.openmrs.*
# topics and write clinic-authored rows into the cloud. So the table list is the
# CLINIC's (debezium/local/tables.conf), NOT this directory's tables.conf --
# which lists the tables that flow the other way.
#
# Until 2026-08-27 this defaulted to ${PROJECT_DIR}/tables.conf and generated
# up-direction sinks for users/role/role_privilege/role_role/user_property/
# user_role/provider, all subscribed to topics the clinic never publishes. Those
# seven measured 0 messages while person/patient/visit carried 122k/122k/478k:
# inert, but they reported RUNNING and inflated any "all sinks green" check.
TABLES_CONF="${TABLES_CONF:-${PROJECT_DIR}/../debezium/local/tables.conf}"
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

        # L-008, NOT L-001. A table appearing in BOTH directions is legitimate:
        # L-008 is per-ROW ownership and explicitly permits more than one node to
        # write a table provided no two nodes write the same row, which the
        # strided PK guarantees. This check used to `exit 1` here, which encoded
        # the SUPERSEDED per-table rule L-001 and, once person/person_name were
        # added to the down list on 2026-09-14, stopped the generator dead on
        # clinic 1. It warns now, because a bidirectional table is still worth a
        # human glance -- it is only safe ABOVE that table's base_id floor
        # (architecture 4; rows below it occupy all ten residues, F-067/BL-067).
        if [ -f "${DOWN_TABLES_CONF}" ] && grep -qE "^[[:space:]]*${table}:" "${DOWN_TABLES_CONF}"; then
            echo "  NOTE ${table}: bidirectional (also in ${DOWN_TABLES_CONF##*/}). Safe under L-008 only above its base_id floor." >&2
        fi

        connector_name="${name_prefix}${table}"
        topic="${mm_prefix}.${server_name}.${DATABASE_NAME}.${table}"
        config_file="${CONNECTORS_DIR}/${connector_name}.json"

        # SHAPE IS AUTHORITATIVE: connectors/known-good.json is the committed
        # record of a sink that actually works, and the validator diffs against
        # it. Both were refreshed 2026-09-14 from the LIVE hub.
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

    "//L-010": "record_key, NOT record_value. L-010 requires the sync key to be",
    "//L-010b": "collision-free by construction: under v1 that is the STRIDED",
    "//L-010c": "INTEGER PK carried in the Kafka record key, never the UUID and",
    "//L-010d": "never a value field. This generator emitted record_value until",
    "//L-010e": "2026-09-14 while all 24 live sinks ran record_key -- so running it",
    "//L-010f": "would have downgraded every one of them out of compliance.",
    "primary.key.mode": "record_key",
    "primary.key.fields": "${pk}",
    "delete.enabled": "true",
    "auto.create": "true",
    "auto.evolve": "true",

    "//BL-039": "connection.restart.on.errors defaults to FALSE, so MySQL closing an idle",
    "//BL-039b": "pooled connection (wait_timeout) or a DB restart is treated as UNRECOVERABLE:",
    "//BL-039c": "the task dies permanently while connector.state still reads RUNNING.",
    "//BL-039d": "Added to the sink TEMPLATE on 2026-08-20 but not here -- and this",
    "//BL-039e": "generator, not the template, is what register-all-sink-connectors.sh",
    "//BL-039f": "registers. Six cloud sinks were found FAILED on 2026-08-27 as a result.",
    "connection.restart.on.errors": "true",
    "errors.retry.timeout": "-1",
    "errors.retry.delay.max.ms": "60000",
    "flush.max.retries": "10",

    "//c3p0": "F-007 REAL FIX, 2026-09-02. connection.pool.timeout is INERT --",
    "//c3p02": "confirmed from the debezium-connector-jdbc 3.2.4 bytecode: min_size,",
    "//c3p03": "max_size and acquire_increment each have a matching hibernate.c3p0.*",
    "//c3p04": "literal, connection.pool.timeout has NONE, so it is silently dropped.",
    "//c3p05": "The four below DO reach c3p0 and are the only client-side defence;",
    "//c3p06": "they survive a MySQL restart, which wait_timeout does not.",
    "//c3p07": "PROVEN 2026-09-02: killed all 45 sink connections server-side and the",
    "//c3p08": "next write landed in 5s, every task RUNNING. Control sink FAILED.",
    "hibernate.c3p0.timeout": "1800",
    "hibernate.c3p0.idle_test_period": "300",
    "hibernate.c3p0.preferredTestQuery": "SELECT 1",
    "hibernate.c3p0.testConnectionOnCheckout": "true",

    "//pool-cap": "F-013 REAL FIX, 2026-09-02. The lever is max_size, NOT min_size.",
    "//pool-cap2": "min=5 with an unbounded max held 120 conns for 25 sinks. min_size=1",
    "//pool-cap3": "ALONE made it worse -- 493 conns, ceiling hit, 5 sinks FAILED --",
    "//pool-cap4": "because c3p0 then grows by acquire_increment, whose default is 32.",
    "//pool-cap5": "min=1 + max=2 + acquire_increment=1 gives a hard bound: 48 conns for",
    "//pool-cap6": "25 sinks, all RUNNING. Do NOT set min_size=0: 4 sinks then die on boot",
    "//pool-cap7": "with 'Unable to determine Dialect without JDBC metadata'.",
    "connection.pool.min_size": "1",
    "connection.pool.max_size": "2",
    "connection.pool.acquire_increment": "1",
    "connection.pool.timeout": "300",

    "//BL-005": "NOT errors.tolerance=all. 'all' silently DROPS a failing record -- an",
    "//BL-005b": "out-of-order FK row vanishes with no park, no DLQ, no trace, defeating",
    "//BL-005c": "L-004 and L-010. Set explicitly so the intent is visible.",
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
