#!/usr/bin/env bash
# Brings up Kafka Connect and confirms its plugin path actually resolved the
# three classes the sync layer depends on: Debezium's MySQL and Postgres
# source connectors, and its BUNDLED JDBC sink
# (io.debezium.connector.jdbc.JdbcSinkConnector, already inside
# DEBEZIUM_CONNECT_IMAGE -- there is no separate Confluent JDBC plugin to
# install). Also brings up kafka-ui (Ruling 3) alongside it and proves its
# login is actually on: the login page answers, an unauthenticated API call
# is refused (401/403, or kafbat's own 302-to-/login), and -- the positive
# half -- KAFKA_UI_USER/KAFKA_UI_PASSWORD from hub/.env actually log in and
# read the cluster back, not just that AUTH_TYPE=LOGIN_FORM is configured.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "70 · kafka connect"
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka-connect kafka-ui; wait for \${KAFKA_CONNECT_URL}/connector-plugins; count the MySql/Postgres/JdbcSink connector plugin classes (want 3); wait for kafka-ui's login page on 127.0.0.1:8080 (HTTP 200); prove /api/clusters refuses an unauthenticated call (401/403 or a 302 to /login); log in as KAFKA_UI_USER and read the cluster back via /api/clusters"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

# Two ambient overrides, the same class as KAFKA_CONTAINER/SASL_LISTENER_PORT
# and with the same one legitimate user -- the live smoke, which runs this task
# for real against its own renamed, differently-published Connect and kafka-ui
# (final review, Important 3b). HUB_CONNECT_URL_OVERRIDE is the name
# 080-sources.sh and 090-exit-checks.sh already use, in the same precedence
# order: an explicit override, then hub/.env's own KAFKA_CONNECT_URL (an
# operator's real customization, which this task used to ignore entirely),
# then the bare default.
CONNECT_URL="${HUB_CONNECT_URL_OVERRIDE:-${KAFKA_CONNECT_URL:-http://localhost:8083}}"
UI_URL="${HUB_KAFKA_UI_URL_OVERRIDE:-http://127.0.0.1:8080}"

compose up -d kafka-connect kafka-ui >/dev/null

for i in $(seq 1 60); do curl -sf --max-time 5 "${CONNECT_URL}/connector-plugins" >/dev/null 2>&1 && break; sleep 5; done
plugins="$(curl -s "${CONNECT_URL}/connector-plugins" | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector' || true)"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins:-0}/3) -- are the jars mounted as files?"

# kafka-ui: the login page answers -- `-L` follows LOGIN_FORM's redirect from
# "/" to "/login", so a 200 here proves the app is actually serving, not just
# that the container is Up.
answered=0
for i in $(seq 1 60); do
  # `|| true` OUTSIDE the substitution (final review, Important 3): this task
  # runs under `set -euo pipefail` with lib.sh's ERR trap armed, so the very
  # first poll -- which curl is expected to fail while kafka-ui is still
  # starting -- used to abort the whole task instead of sleeping and retrying.
  # A wait loop that cannot survive its own first failure is not a wait loop.
  code="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 5 "${UI_URL}/" 2>/dev/null)" || true
  [ "$code" = 200 ] && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "kafka-ui login page answers on ${UI_URL} (HTTP 200)" \
  || fail "kafka-ui never answered HTTP 200 on ${UI_URL}/ (or its login redirect) within 300s (last HTTP ${code:-<none>})"

# kafka-ui: a negative proof auth is ON -- an unauthenticated call to a real
# API route must never be answered with data. Kafbat's actual LOGIN_FORM
# behavior (confirmed live, 2026-09-18): every unauthenticated request --
# API paths included -- is redirected to /login (302), rather than a bare
# 401/403; that redirect is accepted here alongside 401/403 (whichever a
# future Spring Security build ships), but the redirect target must actually
# BE the login page, not "/" or the data itself.
api_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 "${UI_URL}/api/clusters" 2>/dev/null || true)"
api_code="${api_result%% *}"; api_redirect="${api_result#* }"
case "$api_code" in
  401|403) ok "kafka-ui /api/clusters refuses an unauthenticated call (HTTP ${api_code})" ;;
  302)
    case "$api_redirect" in
      */login) ok "kafka-ui /api/clusters refuses an unauthenticated call (HTTP 302 -> ${api_redirect})" ;;
      *) fail "kafka-ui /api/clusters redirected unauthenticated to '${api_redirect:-<none>}', not a login path" ;;
    esac ;;
  *) fail "kafka-ui /api/clusters answered HTTP ${api_code:-<none>} unauthenticated (want 401/403, or a 302 to the login page)" ;;
esac

# kafka-ui: a POSITIVE proof the configured credentials actually work --
# kafka_ui_login_ok (hub/install/lib.sh), hoisted out of this task (code
# review fold-in, Fix round 1, Critical 1): it reads KAFKA_UI_USER/
# KAFKA_UI_PASSWORD from this task's own already-exported environment
# (never as its own arguments), logs in through Spring Security's own
# form-login endpoint, and reads /api/clusters back with the resulting
# session. Shared with the live smoke so the two never drift into two
# near-verbatim copies again.
reason="$(kafka_ui_login_ok "$UI_URL")" \
  && ok "kafka-ui login succeeded and reads back cluster \"hub\" via /api/clusters" \
  || fail "$reason"
