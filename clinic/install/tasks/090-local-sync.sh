#!/usr/bin/env bash
# The clinic's own sync layer, in the order the repo scripts expect. Judged on
# TASK state, never connector state (F-027).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "90 · local sync"
[ "${DRY}" = 1 ] && { info "would: debezium profile up; generate+register source, retention, heartbeat, odoo/clinlims connectors, local sinks; setup-mirrormaker; mirrormaker-connect up"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-controller kafka schema-registry kafka-connect kafka-ui >/dev/null )
for i in $(seq 1 60); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && break; sleep 5; done
plugins="$(curl -s localhost:8083/connector-plugins | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector')"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins}/3) -- are the jars mounted as files?"
til="$(bash scripts/generate-table-config.sh local | grep -E '^TABLE_INCLUDE_LIST=' | cut -d= -f2-)"
[ -n "$til" ] && env_put "$E" TABLE_INCLUDE_LIST "$til"
bash scripts/generate-connectors.sh >/dev/null
bash scripts/register-source-connector.sh >/dev/null
bash scripts/set-schema-history-retention.sh "${CT}" >/dev/null
NODE="${CLINIC_SLUG}" bash connectors/register-odoo.sh odoo-source-connector clinlims-source-connector odoo-clinic-sink-all clinlims-clinic-sink-all >/dev/null
# after register-odoo.sh, not before: the heartbeat script patches the two PG
# source connectors' configs (GET then PUT), so they must exist, and it takes
# BOTH source names (first live clinic, manpur: it was called with one name
# and one line too early -- "$5: unbound variable"). Its DB half (heartbeat
# table + publication membership) is idempotent; the seed already carries both.
bash scripts/apply-slot-heartbeat.sh "${CT}" "${COMPOSE_PROJECT_NAME}-bahmni-postgres-1" postgres odoo-source-connector clinlims-source-connector >/dev/null
bash scripts/generate-local-sink-connectors.sh >/dev/null
bash scripts/register-local-sink-connectors.sh >/dev/null
sleep 30
bad="$(curl -s 'localhost:8083/connectors?expand=status' | jq -r 'to_entries[] | select(.value.status.tasks | any(.state != "RUNNING")) | .key' | tr '\n' ' ')"
[ -z "$bad" ] && ok "every connector task RUNNING ($(curl -s localhost:8083/connectors | jq length))" || fail "tasks not RUNNING: ${bad}"
ret="$(ct exec kafka kafka-configs --bootstrap-server localhost:9092 --entity-type topics --entity-name "schema-changes.${MYSQL_SERVER_NAME}" --describe 2>/dev/null | grep -oE 'retention.ms=-1' | head -1)"
[ "$ret" = "retention.ms=-1" ] && ok "schema-changes.${MYSQL_SERVER_NAME} retention -1" || fail "schema-changes topic retention is not -1 (F-045)"
bash scripts/setup-mirrormaker.sh >/dev/null
grep -qE "^clusters *= *${LOCAL_CLUSTER_ALIAS}, *remote" config/mirrormaker/mm2.properties && ok "mm2.properties: clusters = ${LOCAL_CLUSTER_ALIAS}, remote" || fail "mm2.properties does not carry this node's alias"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d mirrormaker-connect >/dev/null )
sleep 120
exp="$(ct logs mirrormaker-connect 2>&1 | grep -c Expiring || true)"
[ "${exp:-0}" = 0 ] && ok "mirrormaker: 0 expiring records after two minutes" || fail "mirrormaker is expiring records (${exp}) -- the hub is not reachable at ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
