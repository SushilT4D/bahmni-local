#!/usr/bin/env bash
# Brings up Kafka Connect and confirms its plugin path actually resolved the
# three classes the sync layer depends on: Debezium's MySQL and Postgres
# source connectors, and its BUNDLED JDBC sink
# (io.debezium.connector.jdbc.JdbcSinkConnector, already inside
# DEBEZIUM_CONNECT_IMAGE -- there is no separate Confluent JDBC plugin to
# install). hub/docker-compose.yml defines no kafka-ui service (unlike the
# clinic's), so only kafka-connect comes up here.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "70 · kafka connect"
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka-connect; wait for localhost:8083/connector-plugins; count the MySql/Postgres/JdbcSink connector plugin classes (want 3)"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"

compose up -d kafka-connect >/dev/null

for i in $(seq 1 60); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && break; sleep 5; done
plugins="$(curl -s localhost:8083/connector-plugins | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector' || true)"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins:-0}/3) -- are the jars mounted as files?"
