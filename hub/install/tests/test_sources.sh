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
# KAFKA_CONTAINER/CONNECT_CONTAINER (bare "kafka"/"kafka-connect" in
# production; nothing about a real deployment ever needs them to differ) and
# 080-sources.sh's CONNECT_URL are all env-overridable, and
# clinic/scripts/set-schema-history-retention.sh (shared with the clinic;
# untouched otherwise) takes the same KAFKA_CONTAINER override. This test
# renames its own throwaway containers (hubtest-kafka / hubtest-kafka-
# controller / hubtest-kafka-connect, via boot-override.yml + this
# directory's source-override.yml layered on top -- schema-registry is
# skipped entirely, since every converter in play here is JsonConverter) and
# exports the three overrides before invoking the real 050 and 080 task
# scripts, so this is still the real, unmodified production code path, just
# addressed by different names -- never the real Rawach containers, which
# this test never touches.
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
  dc down -v >/dev/null 2>&1 || true
  ct rm -f "$MY_C" "$PG_C" >/dev/null 2>&1 || true
  ct network rm "$NET" >/dev/null 2>&1 || true
  if [ -n "$env_backup" ]; then cp -p "$env_backup" "$env_path"; rm -f "$env_backup"; else rm -f "$env_path"; fi
  if [ -n "$jaas_backup" ]; then cp -p "$jaas_backup" "$jaas_path"; rm -f "$jaas_backup"; else rm -f "$jaas_path"; fi
  rm -f "$tmp_base" "$tmp_secrets" "$tmp_hubenv"
}
trap cleanup EXIT

# --- Pre-run cleanup: leftover state from an earlier, non-trapped run -------
# (Ruling 15) A run killed outright (not a normal exit or a signal the EXIT
# trap above catches) can leave hubtest-* containers/network and
# hub/.src-*/.task080.* temp files behind; clear them before creating
# anything new so a stale run never collides with this one. `rm -f`/`-rf` on
# a glob that matches nothing just tries (and silently tolerates failing on)
# the literal pattern as a filename, so no nullglob dance is needed here.
for c in "$MY_C" "$PG_C" "$CTRL_C" "$KAFKA_C" "$CONNECT_C"; do ct rm -f "$c" >/dev/null 2>&1 || true; done
ct network rm "$NET" >/dev/null 2>&1 || true
rm -f "${HUB_DIR}"/.src-base.* "${HUB_DIR}"/.src-secrets.* "${HUB_DIR}"/.src-hubenv.* >/dev/null 2>&1 || true
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

# --- the hub compose stack, renamed: kafka-controller, kafka, kafka-connect -
# schema-registry is never brought up -- source-override.yml drops kafka-
# connect's dependency on it, and nothing here uses anything but JsonConverter.
dc up -d kafka-controller kafka kafka-connect >/dev/null \
  && ok "hub compose up -d kafka-controller kafka kafka-connect (renamed ${CTRL_C}/${KAFKA_C}/${CONNECT_C}; schema-registry skipped)" \
  || { bad "hub compose up failed"; printf '%s\n' "$fails failure(s)"; exit 1; }
answered=0
for i in $(seq 1 60); do ct exec "$KAFKA_C" kafka-broker-api-versions --bootstrap-server kafka:29092 >/dev/null 2>&1 && { answered=1; break; }; sleep 5; done
[ "$answered" = 1 ] && ok "hub kafka (${KAFKA_C}) answers on kafka:29092" || { bad "hub kafka did not answer within 300s"; printf '%s\n' "$fails failure(s)"; exit 1; }
answered=0
for i in $(seq 1 60); do curl -sf --max-time 5 127.0.0.1:18083/connector-plugins >/dev/null 2>&1 && { answered=1; break; }; sleep 5; done
[ "$answered" = 1 ] && ok "hub kafka-connect (${CONNECT_C}) answers on 127.0.0.1:18083" || { bad "hub kafka-connect did not answer within 300s"; printf '%s\n' "$fails failure(s)"; exit 1; }

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
# KAFKA_CONTAINER/CONNECT_CONTAINER/CONNECT_URL exported here, once, flow
# through to 080's own `ct exec "$KAFKA_CONTAINER"` calls and (inherited by
# the subprocess) clinic/scripts/set-schema-history-retention.sh's own
# `exec "$KAFKA_CONTAINER"` -- the one and only reason this run can address
# hubtest-kafka/hubtest-kafka-connect instead of the real bare names.
export KAFKA_CONTAINER="$KAFKA_C" CONNECT_CONTAINER="$CONNECT_C" CONNECT_URL="http://127.0.0.1:18083"
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

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
