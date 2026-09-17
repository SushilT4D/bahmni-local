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
[ "${DRY}" = 1 ] && { info "would: compose up -d kafka-connect kafka-ui; wait for localhost:8083/connector-plugins; count the MySql/Postgres/JdbcSink connector plugin classes (want 3); wait for kafka-ui's login page on 127.0.0.1:8080 (HTTP 200); prove /api/clusters refuses an unauthenticated call (401/403 or a 302 to /login); log in as KAFKA_UI_USER and read the cluster back via /api/clusters"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a

compose up -d kafka-connect kafka-ui >/dev/null

for i in $(seq 1 60); do curl -sf --max-time 5 localhost:8083/connector-plugins >/dev/null 2>&1 && break; sleep 5; done
plugins="$(curl -s localhost:8083/connector-plugins | jq -r '.[].class' | grep -cE 'MySqlConnector|PostgresConnector|JdbcSinkConnector' || true)"
[ "$plugins" = 3 ] && ok "connect plugins: MySql, Postgres, JdbcSink" || fail "connect plugins missing (${plugins:-0}/3) -- are the jars mounted as files?"

# kafka-ui: the login page answers -- `-L` follows LOGIN_FORM's redirect from
# "/" to "/login", so a 200 here proves the app is actually serving, not just
# that the container is Up.
answered=0
for i in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 5 http://127.0.0.1:8080/ 2>/dev/null)"
  [ "$code" = 200 ] && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "kafka-ui login page answers on 127.0.0.1:8080 (HTTP 200)" \
  || fail "kafka-ui never answered HTTP 200 on 127.0.0.1:8080/ (or its login redirect) within 300s (last HTTP ${code:-<none>})"

# kafka-ui: a negative proof auth is ON -- an unauthenticated call to a real
# API route must never be answered with data. Kafbat's actual LOGIN_FORM
# behavior (confirmed live, 2026-09-18): every unauthenticated request --
# API paths included -- is redirected to /login (302), rather than a bare
# 401/403; that redirect is accepted here alongside 401/403 (whichever a
# future Spring Security build ships), but the redirect target must actually
# BE the login page, not "/" or the data itself.
api_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 http://127.0.0.1:8080/api/clusters 2>/dev/null || true)"
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

# kafka-ui: a POSITIVE proof the configured credentials actually work -- log
# in through Spring Security's own form-login endpoint (POST /login,
# username=/password= form-urlencoded) and use the session cookie it sets to
# read /api/clusters back, expecting this hub's own cluster name. The
# password never touches a command line or this task's own argv: the
# url-encoded form body is written by python3 straight to a mode-600 temp
# file (removed by a trap on every exit path from here on), and curl sends
# it with `-d @file`, never as a literal argument. A wrong-credentials
# attempt (proven live) redirects to /login?error, never to "/" -- so
# checking the success redirect does NOT carry "login" is a reliable signal,
# without needing to hardcode the exact success target.
ui_login_body="$(mktemp "${HUB_DIR}/.kafka-ui-login.XXXXXX")"
ui_cookie_jar="$(mktemp "${HUB_DIR}/.kafka-ui-cookies.XXXXXX")"
chmod 600 "$ui_login_body" "$ui_cookie_jar"
trap 'rm -f "$ui_login_body" "$ui_cookie_jar"' EXIT
python3 -c '
import sys, urllib.parse
user, pw = sys.argv[1], sys.argv[2]
sys.stdout.write("username=%s&password=%s" % (urllib.parse.quote_plus(user), urllib.parse.quote_plus(pw)))
' "${KAFKA_UI_USER:?}" "${KAFKA_UI_PASSWORD:?}" > "$ui_login_body"
login_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 -c "$ui_cookie_jar" -d @"$ui_login_body" http://127.0.0.1:8080/login 2>/dev/null || true)"
login_code="${login_result%% *}"; login_redirect="${login_result#* }"
case "$login_code" in
  302)
    case "$login_redirect" in
      *login*) fail "kafka-ui login with KAFKA_UI_USER/KAFKA_UI_PASSWORD from hub/.env failed (redirected to ${login_redirect})" ;;
      *) ok "kafka-ui login succeeded (HTTP 302 -> ${login_redirect})" ;;
    esac ;;
  *) fail "kafka-ui login POST answered HTTP ${login_code:-<none>}, expected a 302 redirect" ;;
esac
clusters_body="$(curl -s --max-time 10 -b "$ui_cookie_jar" http://127.0.0.1:8080/api/clusters 2>/dev/null || true)"
printf '%s' "$clusters_body" | grep -qF '"name":"hub"' \
  && ok "kafka-ui authenticated session reads back cluster \"hub\" via /api/clusters" \
  || fail "kafka-ui authenticated /api/clusters did not carry cluster \"hub\" (got: $(printf '%s' "$clusters_body" | head -c 200))"
