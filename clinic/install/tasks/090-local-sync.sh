#!/usr/bin/env bash
# The clinic's own sync layer, in the order the repo scripts expect. Judged on
# TASK state, never connector state (F-027).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "90 · local sync"
[ "${DRY}" = 1 ] && { info "would: debezium profile up; generate+register source, retention, heartbeat, odoo/clinlims connectors, local sinks; setup-mirrormaker; mirrormaker-connect up"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
# kafka-ui is NOT in this first up: it is gated on kafka-connect's health, and
# compose gives up on a slow Connect long before Connect does (manpur, 1 vCPU:
# "dependency failed to start: container kafka-connect is unhealthy"). The wait
# for Connect is ours, on a named budget; the UI follows and is never fatal.
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-controller kafka schema-registry kafka-connect >/dev/null )
connect_s="${CONNECT_BOOT_TIMEOUT_S:-1800}"
info "waiting up to $((connect_s/60)) min for Kafka Connect's REST port (it scans every plugin first; CONNECT_BOOT_TIMEOUT_S overrides)"
up=0; for i in $(seq 1 $((connect_s/5))); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && { up=1; break; }; sleep 5; done
[ "$up" = 1 ] || fail "Kafka Connect's REST port did not answer within $((connect_s/60)) min: ${COMPOSE_CMD} logs kafka-connect"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d kafka-ui >/dev/null 2>&1 ) || warn "kafka-ui did not start (a convenience, not part of the sync path): ${COMPOSE_CMD} --profile debezium up -d kafka-ui"
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
# Judged on TASK state (F-027), polled: a small host needs more than the old
# fixed 30 s to start fourteen connectors. A connector with no task at all is
# NOT running (any() over an empty list is false and used to pass). A FAILED
# task never heals by waiting, so it ends the wait at once.
JQ_NOT_RUNNING='to_entries[] | select((.value.status.tasks | length) == 0 or (.value.status.tasks | any(.state != "RUNNING"))) | .key'
JQ_FAILED='to_entries[] | select(.value.status.tasks | any(.state == "FAILED")) | .key'
tasks_s="${CONNECT_TASKS_TIMEOUT_S:-600}"; bad=""
for i in $(seq 1 $((tasks_s/15))); do
  sleep 15
  st="$(curl -s --max-time 10 'localhost:8083/connectors?expand=status' || true)"
  [ -n "$st" ] && [ "$st" != "{}" ] || { bad="(Connect's REST gave no connector status)"; continue; }
  bad="$(printf '%s' "$st" | jq -r "$JQ_NOT_RUNNING" 2>/dev/null | tr '\n' ' ' || printf 'unreadable ')"
  [ -z "$bad" ] && break
  failed="$(printf '%s' "$st" | jq -r "$JQ_FAILED" 2>/dev/null | tr '\n' ' ' || true)"
  [ -n "$failed" ] && { bad="$failed(FAILED)"; break; }
done
[ -z "$bad" ] && ok "every connector task RUNNING ($(curl -s localhost:8083/connectors | jq length))" || fail "tasks not RUNNING: ${bad}"
ret="$(ct exec kafka kafka-configs --bootstrap-server localhost:9092 --entity-type topics --entity-name "schema-changes.${MYSQL_SERVER_NAME}" --describe 2>/dev/null | grep -oE 'retention.ms=-1' | head -1)"
[ "$ret" = "retention.ms=-1" ] && ok "schema-changes.${MYSQL_SERVER_NAME} retention -1" || fail "schema-changes topic retention is not -1 (F-045)"
bash scripts/setup-mirrormaker.sh >/dev/null
grep -qE "^clusters *= *${LOCAL_CLUSTER_ALIAS}, *remote" config/mirrormaker/mm2.properties && ok "mm2.properties: clusters = ${LOCAL_CLUSTER_ALIAS}, remote" || fail "mm2.properties does not carry this node's alias"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile debezium up -d mirrormaker-connect >/dev/null )
sleep 120
exp="$(ct logs mirrormaker-connect 2>&1 | grep -c Expiring || true)"
[ "${exp:-0}" = 0 ] && ok "mirrormaker: 0 expiring records after two minutes" || fail "mirrormaker is expiring records (${exp}) -- the hub is not reachable at ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
