#!/usr/bin/env bash
# Live smoke test: does hub/install/tasks/080-sources.sh actually register and
# prove the hub's three Debezium sources end to end -- against a REAL hub
# Kafka broker + Connect and throwaway MySQL 8.0.39 / Postgres 16 standing in
# for the base stack, seeded with every table each source's table.include.list
# names (Debezium's initial/no_data snapshot needs each listed table to
# actually exist, so a minimal 1-2 table seed would make the connectors
# themselves fail to reach RUNNING -- table.include.list is derived the same
# way 080 derives it: hub/tables.conf's unmarked rows for MySQL,
# subsystem_tables for both Postgres sources, never hand-copied, so this test
# can't silently drift from what 080 actually registers).
#
# Fix round 1: this test used to fail fast on a genuine, unavoidable
# collision -- hub/docker-compose.yml pins fixed container_names (kafka,
# kafka-controller, schema-registry, kafka-connect), and this host already
# runs a real bahmni-local clinic stack under exactly those names, so the
# real, unmodified task scripts (which hardcode `exec kafka`, matching
# production) couldn't be exercised without stopping that other stack. Fixed
# by making the container/URL indirection first-class: hub/install/lib.sh's
# KAFKA_CONTAINER (bare "kafka" in production; nothing about a real
# deployment ever needs it to differ) and 080-sources.sh's CONNECT_URL are
# both env-overridable, and clinic/scripts/set-schema-history-retention.sh
# (shared with the clinic; untouched otherwise) takes the same KAFKA_CONTAINER
# override. This test renames its own throwaway containers (hubtest-kafka /
# hubtest-kafka-controller / hubtest-kafka-connect, via boot-override.yml +
# this directory's source-override.yml layered on top -- schema-registry is
# skipped entirely, since every converter in play here is JsonConverter) and
# exports the overrides before invoking the real 050 and 080 task scripts, so
# this is still the real, unmodified production code path, just addressed by
# different names -- never the real Rawach containers, which this test never
# touches.
#
# Distinct from test_broker_boot.sh (asserts directly against its own renamed
# containers; never invokes a real task script) and test_base_db.sh
# (Postgres+MySQL only, no Kafka at all).
#
# Fix round 2: the slot-active wait (080-sources.sh's wait_slot) is bounded
# at 15 minutes now instead of round 1's 600s, because the actual root cause
# of that wait -- the two Postgres sources colliding on Debezium's JMX MBean
# names, since both share topic.prefix=bahmni-cloud -- is fixed directly
# (custom.metric.tags on each connector JSON), asserted here by grepping the
# full Connect log for the collision warning across both runs. This test's
# own throwaway containers (mysql/postgres flags, and KAFKA_HEAP_OPTS in
# boot-override.yml/source-override.yml) are also trimmed so the whole smoke
# fits beside another real stack's containers on a shared, resource-
# constrained Mac, and a pre-run cleanup step clears any hubtest-src-*
# container/network or hub/.src-*/.task080.* temp file a prior, non-trapped
# (e.g. killed) run left behind.
#
# Task 7 (Ruling 9): the run now continues past 080 into 090-exit-checks.sh
# for real too -- against this same throwaway stack, with SASL_LISTENER_PORT
# pointed at the throwaway broker's own republished SASL port (source-
# override.yml's kafka: 19092, never the real 9092) and
# HUB_EXIT_CHECKS_SKIP_GIT=1 (090's own documented escape hatch: this smoke
# runs beside another session's in-flight edits to this same checkout, which
# git status --porcelain would otherwise -- correctly, just not usefully here
# -- report as dirty). A throwaway kafka-ui (hubtest-kafka-ui, republished on
# 18080) is also brought up and proven the same way task 070 proves the real
# one (login page, negative auth check, and the positive login + read-back
# proof, Ruling R3a) -- the only real, live proof that Ruling 3's login/auth
# actually work, not just that the compose file parses.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib.sh"
export RUNTIME=docker
fails=0
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

docker info >/dev/null 2>&1 || { skip "docker is not available/running on this host -- test_sources.sh needs a real docker to boot kafka+connect+mysql+postgres"; exit 0; }

NET=hubtest-src-net
MY_C=hubtest-src-mysql
PG_C=hubtest-src-pg
CTRL_C=hubtest-kafka-controller
KAFKA_C=hubtest-kafka
CONNECT_C=hubtest-kafka-connect
UI_C=hubtest-kafka-ui
PROJ=hubtest-src
COMPOSE_F="${HUB_DIR}/docker-compose.yml"
OVERRIDE_F="${HERE}/boot-override.yml"
SRC_OVERRIDE_F="${HERE}/source-override.yml"
env_path="${HUB_DIR}/.env"
env_backup=""
jaas_path="${HUB_DIR}/kafka_server_jaas.conf"
jaas_backup=""
tmp_base="$(mktemp "${HUB_DIR}/.src-base.XXXXXX")"
tmp_secrets="$(mktemp "${HUB_DIR}/.src-secrets.XXXXXX")"
tmp_hubenv="$(mktemp "${HUB_DIR}/.src-hubenv.XXXXXX")"

if [ -f "$env_path" ]; then env_backup="$(mktemp "${HUB_DIR}/.env-backup.XXXXXX")"; cp -p "$env_path" "$env_backup"; fi
if [ -f "$jaas_path" ]; then jaas_backup="$(mktemp "${HUB_DIR}/.jaas-backup.XXXXXX")"; cp -p "$jaas_path" "$jaas_backup"; fi

setup_compose
# dc: the hub compose file plus BOTH renaming overrides, a dedicated project
# name, and an explicit --env-file (compose's own auto-.env-detection depends
# on cwd, which this script never changes) -- never the shared compose()
# helper from lib.sh, which knows nothing about either override file.
dc(){ docker compose -p "$PROJ" -f "$COMPOSE_F" -f "$OVERRIDE_F" -f "$SRC_OVERRIDE_F" --env-file "$env_path" "$@"; }
cleanup(){
  # Ruling 6(e), code review fold-in (Task 6 review): on a failed run, the
  # container logs are the whole point -- and `dc down -v` below deletes them
  # for good. Dumped BEFORE teardown, one container at a time, masked through
  # mask_env_secrets with every HUB_KEYS name (unset/empty ones are skipped,
  # per its own contract) so a real secret value that ended up in a
  # container's own log (a startup banner, a rejected connection) never
  # reaches this test's output unredacted. $env_path is re-sourced first
  # (the throwaway hub/.env still exists at this point, values included) so
  # mask_env_secrets actually has something to mask against -- this script's
  # own process never otherwise exports them.
  if [ "${fails:-0}" -gt 0 ]; then
    printf '\n  -- run failed (%s failure(s)): last 60 log lines per hubtest container, before teardown --\n' "$fails" >&2
    if [ -f "$env_path" ]; then set -a; . "$env_path" 2>/dev/null; set +a; fi
    for c in "$CTRL_C" "$KAFKA_C" "$CONNECT_C" "$UI_C" "$MY_C" "$PG_C"; do
      printf '\n  --- docker logs --tail 60 %s ---\n' "$c" >&2
      ct logs --tail 60 "$c" 2>&1 | mask_env_secrets $HUB_KEYS | sed 's/^/    /' >&2
    done
  fi
  dc down -v >/dev/null 2>&1 || true
  ct rm -f "$MY_C" "$PG_C" >/dev/null 2>&1 || true
  ct network rm "$NET" >/dev/null 2>&1 || true
  if [ -n "$env_backup" ]; then cp -p "$env_backup" "$env_path"; rm -f "$env_backup"; else rm -f "$env_path"; fi
  if [ -n "$jaas_backup" ]; then cp -p "$jaas_backup" "$jaas_path"; rm -f "$jaas_backup"; else rm -f "$jaas_path"; fi
  rm -f "$tmp_base" "$tmp_secrets" "$tmp_hubenv"
  # kafka-ui login probe temp files (carry KAFKA_UI_PASSWORD briefly) -- a
  # glob backstop, same style as the pre-run cleanup below, in case a crash
  # between their mktemp and their own explicit rm -f skipped that cleanup.
  rm -f "${HUB_DIR}"/.kafka-ui-login-test.* "${HUB_DIR}"/.kafka-ui-cookies-test.* >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Pre-run cleanup: leftover state from an earlier, non-trapped run -------
# (Ruling 15) A run killed outright (not a normal exit or a signal the EXIT
# trap above catches) can leave hubtest-* containers/network and
# hub/.src-*/.task080.* temp files behind; clear them before creating
# anything new so a stale run never collides with this one. `rm -f`/`-rf` on
# a glob that matches nothing just tries (and silently tolerates failing on)
# the literal pattern as a filename, so no nullglob dance is needed here.
for c in "$MY_C" "$PG_C" "$CTRL_C" "$KAFKA_C" "$CONNECT_C" "$UI_C"; do ct rm -f "$c" >/dev/null 2>&1 || true; done
ct network rm "$NET" >/dev/null 2>&1 || true
rm -f "${HUB_DIR}"/.src-base.* "${HUB_DIR}"/.src-secrets.* "${HUB_DIR}"/.src-hubenv.* "${HUB_DIR}"/.kafka-ui-login-test.* "${HUB_DIR}"/.kafka-ui-cookies-test.* >/dev/null 2>&1 || true
rm -rf "${HUB_DIR}"/.task080.* >/dev/null 2>&1 || true
ok "pre-run cleanup: no leftover hubtest-src-* containers/network or hub/.src-*/.task080.* temp files"

ct network create "$NET" >/dev/null 2>&1 && ok "throwaway network ${NET} created" || { bad "could not create network ${NET}"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- hub/.env: composed through the real hub_compose_env, not hand-written --
# Fidelity matters here more than in test_base_db.sh's hand-written .env: this
# test exercises every one of task 080's key reads (CLOUD_MYSQL_HOST/PORT/
# DATABASE included), so it should get them the same way a real install does
# -- defaulted by hub_compose_env -- not a bespoke copy that could silently
# diverge from what that function actually produces.
export BASE_MYSQL_CONTAINER="$MY_C" BASE_PG_CONTAINER="$PG_C" KAFKA_BASE_NETWORK="$NET"
cat > "$tmp_base" <<'EOF'
MYSQL_ROOT_PASSWORD=throwaway
OPENMRS_DB_NAME=openmrs
ODOO_DB_PASSWORD=odoopw
OPENELIS_DB_PASSWORD=clinlimspw
POSTGRES_USER=postgres
POSTGRES_PASSWORD=throwaway
EOF
printf 'REMOTE_KAFKA_PASSWORD=%s\n' "$(gen_secret)" > "$tmp_secrets"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$tmp_hubenv"
HUB_ENV="$tmp_hubenv" hub_compose_env "$tmp_base" "$tmp_secrets" "$env_path"
ok "hub/.env composed via hub_compose_env (throwaway base/secrets/hub.env)"
write_jaas "$jaas_path" "$(env_get "$env_path" KAFKA_ADMIN_PASSWORD)" "$(env_get "$env_path" REMOTE_KAFKA_PASSWORD)"
ok "temp JAAS written at hub/kafka_server_jaas.conf (restored on exit)"

# --- throwaway mysql: binlog enabled, openmrs + hub/tables.conf's 7 cloud-owned tables
MY_IMAGE="$(env_get "$env_path" MYSQL_IMAGE)"; MY_IMAGE="${MY_IMAGE:-mysql:8.0.39}"
ct run -d --name "$MY_C" --network "$NET" -e MYSQL_ROOT_PASSWORD=throwaway "$MY_IMAGE" \
  --server-id=1 --log-bin=mysql-bin --binlog-format=ROW --binlog-row-image=FULL \
  --performance-schema=OFF --innodb-buffer-pool-size=64M >/dev/null \
  && ok "mysql container ${MY_C} (${MY_IMAGE}, binlog ROW/FULL, trimmed footprint) started" || { bad "mysql container failed to start"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 60); do ct logs "$MY_C" 2>&1 | grep -q 'ready for connections.*port: 3306' && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "mysql real server ready on port 3306 (past the init-server handoff)" || { bad "mysql never logged the final server's ready-for-connections line"; printf '%s\n' "$fails failure(s)"; exit 1; }

mysql_root_seed(){ ct exec -i "$MY_C" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }
seed_rc=0
mysql_root_seed <<'SQL' >/dev/null || seed_rc=$?
CREATE DATABASE IF NOT EXISTS openmrs;
USE openmrs;
CREATE TABLE users (user_id INT PRIMARY KEY, username VARCHAR(64));
CREATE TABLE user_property (user_id INT, property VARCHAR(64), value VARCHAR(64), PRIMARY KEY (user_id, property));
CREATE TABLE user_role (user_id INT, role VARCHAR(64), PRIMARY KEY (user_id, role));
CREATE TABLE role (role VARCHAR(64) PRIMARY KEY);
CREATE TABLE role_privilege (role VARCHAR(64), privilege VARCHAR(64), PRIMARY KEY (role, privilege));
CREATE TABLE role_role (parent_role VARCHAR(64), child_role VARCHAR(64), PRIMARY KEY (parent_role, child_role));
CREATE TABLE provider (provider_id INT PRIMARY KEY, name VARCHAR(64));
SQL
[ "$seed_rc" = 0 ] && ok "mysql seeded: openmrs + hub/tables.conf's 7 unmarked (cloud-owned) tables" || { bad "mysql seed failed (rc=${seed_rc})"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- throwaway postgres: wal_level=logical, odoo/clinlims roles+dbs, every table
# each source's table.include.list needs (subsystem_tables -- never hand-copied)
PG_IMAGE="$(env_get "$env_path" POSTGRES_IMAGE)"; PG_IMAGE="${PG_IMAGE:-postgres:16}"
ct run -d --name "$PG_C" --network "$NET" -e POSTGRES_PASSWORD=throwaway "$PG_IMAGE" -c wal_level=logical -c shared_buffers=32MB >/dev/null \
  && ok "postgres container ${PG_C} (${PG_IMAGE}, trimmed footprint) started" || { bad "postgres container failed to start"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 60); do ct logs "$PG_C" 2>&1 | grep -q "PostgreSQL init process complete" && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] || { bad "postgres never logged the temp-to-real handoff (init process complete)"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 30); do ct exec "$PG_C" pg_isready -U postgres >/dev/null 2>&1 && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "postgres real server answers pg_isready (past the init-server handoff)" || { bad "postgres never answered pg_isready after the handoff"; printf '%s\n' "$fails failure(s)"; exit 1; }

seed_rc=0
ct exec -i "$PG_C" psql -U postgres -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null || seed_rc=$?
CREATE ROLE odoo LOGIN REPLICATION PASSWORD 'odoopw';
CREATE ROLE clinlims LOGIN REPLICATION PASSWORD 'clinlimspw';
CREATE DATABASE odoo OWNER odoo;
CREATE DATABASE openelis OWNER clinlims;
SQL
if [ "$seed_rc" = 0 ]; then
  odoo_tables="$(subsystem_tables odoo)"; odoo_tables_rc=$?
  if [ "$odoo_tables_rc" = 0 ]; then
    { for t in $odoo_tables; do
        printf 'CREATE TABLE %s (id serial PRIMARY KEY, name text);\n' "$t"
        printf 'ALTER SEQUENCE %s_id_seq INCREMENT BY 10;\n' "$t"
      done
    } | ct exec -i "$PG_C" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
  else
    seed_rc=1
  fi
fi
if [ "$seed_rc" = 0 ]; then
  clinlims_tables="$(subsystem_tables clinlims)"; clinlims_tables_rc=$?
  if [ "$clinlims_tables_rc" = 0 ]; then
    { printf 'CREATE SCHEMA clinlims;\n'
      for t in $clinlims_tables; do
        printf 'CREATE TABLE clinlims.%s (id integer PRIMARY KEY, name text);\n' "$t"
        printf 'CREATE SEQUENCE clinlims.%s_seq INCREMENT BY 10;\n' "$t"
      done
    } | ct exec -i "$PG_C" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
  else
    seed_rc=1
  fi
fi
[ "$seed_rc" = 0 ] && ok "postgres seeded: roles odoo/clinlims, all $(printf '%s\n' "$odoo_tables" | wc -l | tr -d ' ') odoo tables, all $(printf '%s\n' "$clinlims_tables" | wc -l | tr -d ' ') clinlims tables (subsystem_tables, striding-compliant)" \
  || { bad "postgres seed failed (rc=${seed_rc})"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- the hub compose stack, renamed: kafka-controller, kafka, kafka-connect,
# kafka-ui -- schema-registry is never brought up -- source-override.yml
# drops kafka-connect's dependency on it, and nothing here uses anything but
# JsonConverter. kafka-ui is included (Ruling 9) so Ruling 3's login/auth can
# be proven live, the same two ways task 070 proves the real one.
dc up -d kafka-controller kafka kafka-connect kafka-ui >/dev/null \
  && ok "hub compose up -d kafka-controller kafka kafka-connect kafka-ui (renamed ${CTRL_C}/${KAFKA_C}/${CONNECT_C}/${UI_C}; schema-registry skipped)" \
  || { bad "hub compose up failed"; printf '%s\n' "$fails failure(s)"; exit 1; }
answered=0
for i in $(seq 1 60); do ct exec "$KAFKA_C" kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { answered=1; break; }; sleep 5; done
[ "$answered" = 1 ] && ok "hub kafka (${KAFKA_C}) answers on kafka:29092" || { bad "hub kafka did not answer within 300s"; printf '%s\n' "$fails failure(s)"; exit 1; }
answered=0
for i in $(seq 1 60); do curl -sf --max-time 5 127.0.0.1:18083/connector-plugins >/dev/null 2>&1 && { answered=1; break; }; sleep 5; done
[ "$answered" = 1 ] && ok "hub kafka-connect (${CONNECT_C}) answers on 127.0.0.1:18083" || { bad "hub kafka-connect did not answer within 300s"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- kafka-ui (Ruling 9, the only real proof of Ruling 3): the login page
# answers, an unauthenticated API call is refused, and the configured
# credentials actually log in and read the cluster back -- the exact checks
# task 070 itself performs against the real service, here against the
# throwaway one on 127.0.0.1:18080. Ruling R3a (found live on the first
# smoke run): kafbat's actual LOGIN_FORM behavior redirects an unauthenticated
# API call to /login (302), not a bare 401/403, so the negative check accepts
# either; the positive login proof is what actually confirms auth works.
answered=0
for i in $(seq 1 60); do
  ui_code="$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 5 http://127.0.0.1:18080/ 2>/dev/null)"
  [ "$ui_code" = 200 ] && { answered=1; break; }
  sleep 5
done
[ "$answered" = 1 ] && ok "hub kafka-ui (${UI_C}) login page answers on 127.0.0.1:18080 (HTTP 200)" || { bad "hub kafka-ui did not answer HTTP 200 on 127.0.0.1:18080/ within 300s (last HTTP ${ui_code:-<none>})"; printf '%s\n' "$fails failure(s)"; exit 1; }
ui_api_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 http://127.0.0.1:18080/api/clusters 2>/dev/null || true)"
ui_api_code="${ui_api_result%% *}"; ui_api_redirect="${ui_api_result#* }"
case "$ui_api_code" in
  401|403) ok "hub kafka-ui /api/clusters refuses an unauthenticated call (HTTP ${ui_api_code})" ;;
  302) case "$ui_api_redirect" in
    */login) ok "hub kafka-ui /api/clusters refuses an unauthenticated call (HTTP 302 -> ${ui_api_redirect})" ;;
    *) bad "hub kafka-ui /api/clusters redirected unauthenticated to '${ui_api_redirect:-<none>}', not a login path" ;;
  esac ;;
  *) bad "hub kafka-ui /api/clusters answered HTTP ${ui_api_code:-<none>} unauthenticated (want 401/403, or a 302 to the login page)" ;;
esac
ui_login_body="$(mktemp "${HUB_DIR}/.kafka-ui-login-test.XXXXXX")"
ui_cookie_jar="$(mktemp "${HUB_DIR}/.kafka-ui-cookies-test.XXXXXX")"
chmod 600 "$ui_login_body" "$ui_cookie_jar"
python3 -c '
import sys, urllib.parse
user, pw = sys.argv[1], sys.argv[2]
sys.stdout.write("username=%s&password=%s" % (urllib.parse.quote_plus(user), urllib.parse.quote_plus(pw)))
' "$(env_get "$env_path" KAFKA_UI_USER)" "$(env_get "$env_path" KAFKA_UI_PASSWORD)" > "$ui_login_body"
ui_login_result="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 -c "$ui_cookie_jar" -d @"$ui_login_body" http://127.0.0.1:18080/login 2>/dev/null || true)"
ui_login_code="${ui_login_result%% *}"; ui_login_redirect="${ui_login_result#* }"
case "$ui_login_code" in
  302) case "$ui_login_redirect" in
    *login*) bad "hub kafka-ui login with KAFKA_UI_USER/KAFKA_UI_PASSWORD failed (redirected to ${ui_login_redirect})" ;;
    *) ok "hub kafka-ui login succeeded (HTTP 302 -> ${ui_login_redirect})" ;;
  esac ;;
  *) bad "hub kafka-ui login POST answered HTTP ${ui_login_code:-<none>}, expected a 302 redirect" ;;
esac
ui_clusters_body="$(curl -s --max-time 10 -b "$ui_cookie_jar" http://127.0.0.1:18080/api/clusters 2>/dev/null || true)"
printf '%s' "$ui_clusters_body" | grep -qF '"name":"hub"' \
  && ok "hub kafka-ui authenticated session reads back cluster \"hub\" via /api/clusters" \
  || bad "hub kafka-ui authenticated /api/clusters did not carry cluster \"hub\" (got: $(printf '%s' "$ui_clusters_body" | head -c 200))"
rm -f "$ui_login_body" "$ui_cookie_jar"

# --- run 050-base-db.sh for real (080 depends on its publications+heartbeats)
# No container/URL overrides needed -- 050 never touches Kafka/Connect.
TASK050="${REPO_DIR}/hub/install/tasks/050-base-db.sh"
out050="$(bash "$TASK050" 2>&1)"; rc050=$?
printf '%s\n' "$out050" | sed 's/^/    /'
[ "$rc050" = 0 ] && ok "050-base-db.sh exits 0 (prerequisite for 080)" || { bad "050-base-db.sh exited ${rc050}"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- source-role DML grants, after 050 (which is what creates dbz_heartbeat)
# 050 grants odoo_sink/clinlims_sink (the JDBC SINK roles); it has no reason
# to touch odoo/clinlims (the SOURCE roles the Postgres source connectors log
# in as) -- those are this test's own seed, not 050's job. A real OpenELIS/
# Odoo deployment's own source role already owns its schema and so already
# has these rights; this throwaway seed created every table as postgres, so
# odoo/clinlims (LOGIN REPLICATION only, no DML) cannot run the heartbeat
# ACTION QUERY, which is real INSERT/UPDATE SQL the source connector issues
# as itself, not something the replication protocol grants for free -- caught
# live: odoo-cloud-source logged "Could not execute heartbeat action ...
# permission denied for schema clinlims" until this grant was added.
seed_rc=0
ct exec -i "$PG_C" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null || seed_rc=$?
GRANT USAGE ON SCHEMA public TO odoo;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO odoo;
SQL
ct exec -i "$PG_C" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null || seed_rc=$?
GRANT USAGE ON SCHEMA clinlims TO clinlims;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA clinlims TO clinlims;
SQL
[ "$seed_rc" = 0 ] && ok "source roles odoo/clinlims granted DML (dbz_heartbeat included) after 050 created it" \
  || { bad "granting odoo/clinlims DML failed (rc=${seed_rc})"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- run 080-sources.sh for real, twice (idempotency) -----------------------
# KAFKA_CONTAINER/CONNECT_URL exported here, once, flow through to 080's own
# `ct exec "$KAFKA_CONTAINER"` calls and (inherited by the subprocess)
# clinic/scripts/set-schema-history-retention.sh's own `exec
# "$KAFKA_CONTAINER"` -- the one and only reason this run can address
# hubtest-kafka/hubtest-kafka-connect instead of the real bare names. Also
# exported here (not just at the 090 call site below) so every subprocess
# from this point on -- 080 included -- shares one consistent environment.
export KAFKA_CONTAINER="$KAFKA_C" CONNECT_URL="http://127.0.0.1:18083"
TASK080="${REPO_DIR}/hub/install/tasks/080-sources.sh"
out1="$(bash "$TASK080" 2>&1)"; rc1=$?
printf '%s\n' "$out1" | sed 's/^/    /'
[ "$rc1" = 0 ] && ok "first run of 080-sources.sh exits 0" || bad "first run of 080-sources.sh exited ${rc1}"

assert_line(){ if printf '%s\n' "$out1" | grep -qF "$2"; then printf '  ok   %s\n' "$1"; else bad "$1 -- expected output to contain: $2"; fi; }
assert_line "mysql version gate passed"                    "fit for Debezium 3.6.2"
assert_line "mysql-cloud-source-connector registered"      "mysql-cloud-source-connector registered (HTTP"
assert_line "odoo/clinlims sources registered"             "odoo-cloud-source, clinlims-cloud-source registered via connectors/register-odoo.sh NODE=cloud"
assert_line "schema-changes retention -1"                  "retention -1"
assert_line "mysql-cloud-source-connector RUNNING"         "mysql-cloud-source-connector: connector RUNNING"
assert_line "odoo-cloud-source RUNNING"                    "odoo-cloud-source: connector RUNNING"
assert_line "clinlims-cloud-source RUNNING"                "clinlims-cloud-source: connector RUNNING"
assert_line "dbz_odoo_down slot active"                    "replication slot dbz_odoo_down active"
assert_line "dbz_clinlims_down slot active"                "replication slot dbz_clinlims_down active"
assert_line "schema-changes topic exists"                  "topic schema-changes"
assert_line "odoo heartbeat in table.include.list"         "odoo-cloud-source: table.include.list carries public.dbz_heartbeat"
assert_line "clinlims heartbeat in table.include.list"     "clinlims-cloud-source: table.include.list carries clinlims.dbz_heartbeat"
assert_line "odoo heartbeat.interval.ms present"           "odoo-cloud-source: heartbeat.interval.ms="
assert_line "clinlims heartbeat.interval.ms present"       "clinlims-cloud-source: heartbeat.interval.ms="
assert_line "task reaches its final summary line"          "hub sources registered and proven:"

# --- Ruling 11: the clinlims source's database.hostname placeholder is
# actually substituted to BASE_ELIS_CONTAINER, not just present in the
# template. This one-container test never sets BASE_ELIS_CONTAINER, so
# hub_compose_env defaults it to BASE_PG_CONTAINER's value ($PG_C) -- proving
# the placeholder resolves at all, even though it resolves to the same
# container clinlims lives on here. Read back from Connect's own /config
# (database.hostname is not a secret field, unlike database.password).
elis_container="$(env_get "$env_path" BASE_ELIS_CONTAINER)"
rendered_host="$(curl -s "${CONNECT_URL}/connectors/clinlims-cloud-source/config" | jq -r '.["database.hostname"] // empty')"
if [ -n "$elis_container" ] && [ "$rendered_host" = "$elis_container" ]; then
  ok "clinlims-cloud-source database.hostname resolves to BASE_ELIS_CONTAINER (${elis_container})"
else
  bad "clinlims-cloud-source database.hostname (${rendered_host:-<empty>}) does not equal BASE_ELIS_CONTAINER (${elis_container:-<empty>})"
fi

# No password value ever appears in the task's own stdout/stderr.
for secret in "$(env_get "$env_path" DEBEZIUM_DB_PASSWORD)" "$(env_get "$env_path" ODOO_DB_PASSWORD)" "$(env_get "$env_path" CLINLIMS_SOURCE_PASSWORD)"; do
  [ -n "$secret" ] || continue
  printf '%s\n' "$out1" | grep -qF "$secret" && bad "a secret value leaked into 080-sources.sh's own output" || true
done
ok "no secret value found in 080-sources.sh's output"

# --- idempotency: run again, expect the same final line --------------------
out2="$(bash "$TASK080" 2>&1)"; rc2=$?
printf '%s\n' "$out2" | sed 's/^/    /'
[ "$rc2" = 0 ] && ok "second run of 080-sources.sh exits 0" || bad "second run of 080-sources.sh exited ${rc2}"
line1="$(printf '%s\n' "$out1" | grep 'hub sources registered and proven:')"
line2="$(printf '%s\n' "$out2" | grep 'hub sources registered and proven:')"
[ -n "$line1" ] && [ "$line1" = "$line2" ] && ok "second run reaches the identical final line (idempotent)" || bad "final line changed between runs: [${line1}] vs [${line2}]"

# --- Ruling 14: the two Postgres sources no longer collide on JMX bean names.
# custom.metric.tags (database=odoo / database=clinlims, both connector JSONs)
# disambiguates Debezium's MBean ObjectNames, which otherwise collide because
# both sources share topic.prefix=bahmni-cloud -- the exact mechanism Fix
# round 1 traced as the reason the slot-active wait exceeded even a 600s
# bound (ChangeEventSourceCoordinator stalls behind the retry loop this
# produces before it reaches START_REPLICATION). Checked over the FULL
# Connect log across both runs above, not just the first -- a real collision
# would log on every registration, not only the first.
connect_logs="$(ct logs "$CONNECT_C" 2>&1)"
if printf '%s\n' "$connect_logs" | grep -q "InstanceAlreadyExists"; then
  bad "Connect log carries an InstanceAlreadyExists line -- the two Postgres sources' JMX names still collide"
else
  ok "no InstanceAlreadyExists in the Connect log (custom.metric.tags disambiguates the two Postgres sources)"
fi

# --- Ruling 7 (F-073): register-odoo.sh (hub copy) never leaves a rendered
# connector config -- with its plaintext password -- sitting in a fixed,
# world-readable /tmp path. Checked once here, after both real registration
# runs above (each of the two 080 runs registers odoo-cloud-source and
# clinlims-cloud-source via connectors/register-odoo.sh, so four registration
# calls have happened by this point).
[ -e /tmp/.reg.out ] && bad "register-odoo.sh left /tmp/.reg.out behind (F-073)" || ok "no /tmp/.reg.out left behind after registration (F-073)"

# --- run 090-exit-checks.sh for real, against this same throwaway stack -----
# (Ruling 9). SASL_LISTENER_PORT points sasl_listener_ok (lib.sh, shared with
# task 060) at the throwaway broker's own republished SASL port
# (source-override.yml's kafka: 19092, never the real 9092).
# HUB_EXIT_CHECKS_SKIP_GIT is 090's own documented escape hatch for exactly
# this situation: this smoke runs beside another session's in-flight edits to
# this same checkout, which a real `git status --porcelain` would report as
# dirty for reasons that have nothing to do with whether 080/090 themselves
# work. HUB_MIN_DISK_GB=1 lowers the disk-free threshold from its production
# default of 20 -- never loosened there -- so the assertion is about the
# CHECK running and reporting a real number, not about how much space this
# particular dev host happens to have free right now. Ruling R1b: the
# disk-free check itself reads free space under the broker's OWN data volume
# via `ct exec "$KAFKA_CONTAINER" df -Pk /var/lib/kafka/data` (never a
# host-level df on DockerRootDir, which Docker Desktop for macOS cannot
# resolve at all -- found live on this exact host, fixed in 090 itself, not
# worked around here), so it is exercised for real and expected to pass
# cleanly on any host, this one included.
export SASL_LISTENER_PORT=19092 HUB_EXIT_CHECKS_SKIP_GIT=1 HUB_MIN_DISK_GB=1
TASK090="${REPO_DIR}/hub/install/tasks/090-exit-checks.sh"
out090="$(bash "$TASK090" 2>&1)"; rc090=$?
printf '%s\n' "$out090" | sed 's/^/    /'
[ "$rc090" = 0 ] && ok "090-exit-checks.sh exits 0 against the throwaway stack" || bad "090-exit-checks.sh exited ${rc090}"
printf '%s\n' "$out090" | grep -qF "exit checks: all green" && ok "090 reaches its summary line (exit checks: all green)" || bad "090 did not reach its summary line -- see its output above"

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
