#!/usr/bin/env bash
# Live smoke test: does hub/install/install.sh actually install a hub, end to
# end, on THIS machine -- every task from 000 to 100, run as the real scripts,
# against a real hub Kafka broker/Schema Registry/Connect/kafka-ui and
# throwaway MySQL 8.0.39 + Postgres 16 containers standing in for the base
# stack. Then again, to prove the whole run is idempotent.
#
# WHAT CHANGED, AND WHY (final review, Important 3b + Important 9)
#
#   1. It runs the INSTALLER, not a hand-picked pair of tasks. This test used
#      to invoke 050, 080 and 090 directly -- so tasks 000, 020, 030, 040, 060,
#      070 and 100 had never once been executed as scripts, anywhere, by
#      anything. Everything known about them came from reading them. Now
#      install.sh itself is what runs, with the task-selection logic, the
#      hub/.env composition and the whole task loop included.
#
#   2. It never touches the real hub/. Previously it overwrote hub/.env and
#      hub/kafka_server_jaas.conf in place and restored them from a backup in
#      its EXIT trap -- so a kill -9 (or a crash between the two) left a live
#      hub configured with throwaway credentials. It now copies hub/ into a
#      mktemp directory and points HUB_DIR at the copy: the installer writes
#      its .env, its JAAS file, its rendered connector configs and its scratch
#      files THERE. The compose file inside the copy is the one compose is
#      given, so hub/docker-compose.yml's relative bind mounts
#      (./kafka_server_jaas.conf, ./connectors) resolve inside the copy too.
#      The real hub/.env's checksum is asserted unchanged at the end.
#
# HOW IT RUNS BESIDE A REAL STACK. hub/docker-compose.yml pins fixed
# container_names (kafka, kafka-controller, schema-registry, kafka-connect,
# kafka-ui) and this host already runs a real bahmni-local clinic stack under
# exactly those names, on 127.0.0.1:9092/8082/8083/8086. boot-override.yml +
# source-override.yml rename every one of them to hubtest-* and republish their
# ports (19092/18082/18083/18080); the overrides reach the task scripts through
# COMPOSE_FILE, which lib.sh's own compose() helper honours without knowing
# anything about them. The tasks address the renamed containers and ports
# through the documented ambient overrides -- KAFKA_CONTAINER,
# HUB_CONNECT_URL_OVERRIDE, HUB_SCHEMA_REGISTRY_URL_OVERRIDE,
# HUB_KAFKA_UI_URL_OVERRIDE, SASL_LISTENER_PORT, HUB_MIN_DISK_GB,
# HUB_EXIT_CHECKS_SKIP_GIT -- so this is the real, unmodified production code
# path, just addressed by different names. It never touches the real
# containers.
#
# Distinct from test_broker_boot.sh (the two boot services alone, asserted
# against directly, no task script involved) and test_base_db.sh (Postgres +
# MySQL only, no Kafka at all).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_HUB="$(cd "$HERE/../.." && pwd)"

# --- the temp copy of hub/ (Important 9) ------------------------------------
# Created BEFORE lib.sh is sourced, so HUB_DIR (and with it CLINIC_DIR, which
# lib.sh derives from it at source time) is the copy from the very first line
# of library code onwards -- never the real hub/ for even one function call.
# install/ is copied too: it is what the copy's own compose file mounts
# nothing of, but a copy that is missing it would not be a copy of hub/.
TMP_ROOT="$(mktemp -d)"
HUB_COPY="${TMP_ROOT}/hub"
mkdir -p "$HUB_COPY"
for item in docker-compose.yml .env.example README.md tables.conf clinics.conf connectors scripts odoo openelis install; do
  [ -e "${REAL_HUB}/${item}" ] && cp -R "${REAL_HUB}/${item}" "${HUB_COPY}/${item}"
done
export HUB_DIR="$HUB_COPY"
. "$HERE/../lib.sh"
export RUNTIME=docker
fails=0
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

docker info >/dev/null 2>&1 || { skip "docker is not available/running on this host -- test_sources.sh needs a real docker to boot kafka+connect+mysql+postgres"; rm -rf "$TMP_ROOT"; exit 0; }
ok "hub/ copied to a throwaway tree (${HUB_COPY}); the real ${REAL_HUB}/.env is never written by this run"

NET=hubtest-src-net
MY_C=hubtest-src-mysql
PG_C=hubtest-src-pg
CTRL_C=hubtest-kafka-controller
KAFKA_C=hubtest-kafka
SR_C=hubtest-schema-registry
CONNECT_C=hubtest-kafka-connect
UI_C=hubtest-kafka-ui
PROJ=hubtest-src
COMPOSE_F="${HUB_DIR}/docker-compose.yml"
OVERRIDE_F="${HERE}/boot-override.yml"
SRC_OVERRIDE_F="${HERE}/source-override.yml"
env_path="${HUB_DIR}/.env"
jaas_path="${HUB_DIR}/kafka_server_jaas.conf"
tmp_base="${TMP_ROOT}/base.env"
tmp_secrets="${TMP_ROOT}/secrets.env"
tmp_hubenv="${TMP_ROOT}/hub.env"

# The real hub/.env and JAAS, if this host has them: hashed now, compared at
# the end. This is the direct assertion for Important 9 -- not "we restored a
# backup correctly", but "we never wrote them at all".
real_env_sig(){ for f in "${REAL_HUB}/.env" "${REAL_HUB}/kafka_server_jaas.conf"; do
    if [ -f "$f" ]; then printf '%s %s\n' "$(shasum -a 256 < "$f" | cut -d' ' -f1)" "$f"; else printf 'absent %s\n' "$f"; fi
  done; }
real_sig_before="$(real_env_sig)"

setup_compose
# dc: the COPY's compose file plus both renaming overrides, a dedicated project
# name and an explicit --env-file -- used by this script for teardown and for
# the pre-run cleanup. The TASKS get the same three files through COMPOSE_FILE
# (exported below), which is how lib.sh's own compose() -- which knows nothing
# about override files -- ends up running exactly this stack.
dc(){ docker compose -p "$PROJ" -f "$COMPOSE_F" -f "$OVERRIDE_F" -f "$SRC_OVERRIDE_F" --env-file "$env_path" "$@"; }
cleanup(){
  # On a failed run the container logs are the whole point -- and `dc down -v`
  # below deletes them for good. Dumped BEFORE teardown, one container at a
  # time, masked through mask_env_secrets with every HUB_KEYS name (unset ones
  # are skipped, per its own contract) so a secret that reached a container's
  # own log never reaches this test's output unredacted. The throwaway .env is
  # re-sourced first so mask_env_secrets has something to mask against.
  if [ "${fails:-0}" -gt 0 ]; then
    printf '\n  -- run failed (%s failure(s)): last 60 log lines per hubtest container, before teardown --\n' "$fails" >&2
    if [ -f "$env_path" ]; then set -a; . "$env_path" 2>/dev/null; set +a; fi
    for c in "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C" "$MY_C" "$PG_C"; do
      printf '\n  --- docker logs --tail 60 %s ---\n' "$c" >&2
      ct logs --tail 60 "$c" 2>&1 | mask_env_secrets $HUB_KEYS | sed 's/^/    /' >&2
    done
  fi
  [ -f "$env_path" ] && dc down -v >/dev/null 2>&1 || true
  for c in "$MY_C" "$PG_C" "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C"; do ct rm -f "$c" >/dev/null 2>&1 || true; done
  ct network rm "$NET" >/dev/null 2>&1 || true
  # The whole throwaway tree, secrets and rendered configs included. Nothing
  # under the real hub/ was ever written, so there is nothing to restore.
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# --- Pre-run cleanup: leftover state from an earlier, non-trapped run -------
# A run killed outright (not a normal exit or a signal the EXIT trap catches)
# can leave hubtest-* containers and the network behind; clear them before
# creating anything new so a stale run never collides with this one. Temp
# FILES need no such sweep any more: every one this run creates lives under
# $TMP_ROOT, which nothing else shares.
for c in "$MY_C" "$PG_C" "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C"; do ct rm -f "$c" >/dev/null 2>&1 || true; done
ct network rm "$NET" >/dev/null 2>&1 || true
docker volume rm -f "${PROJ}_kafka-data" "${PROJ}_kafka-controller-data" "${PROJ}_connect-data" >/dev/null 2>&1 || true
ok "pre-run cleanup: no leftover hubtest-* containers, network or volumes"

ct network create "$NET" >/dev/null 2>&1 && ok "throwaway network ${NET} created" || { bad "could not create network ${NET}"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- the three input files install.sh is given ------------------------------
# A throwaway base .env (what a base stack's own .env would carry), a throwaway
# secrets file (the fleet SASL password) and a throwaway sync/hub.env (the
# fleet endpoint pointer, via the HUB_ENV override). install.sh composes
# hub/.env from exactly these three, through the real hub_compose_env.
( umask 077
  cat > "$tmp_base" <<'EOF'
MYSQL_ROOT_PASSWORD=throwaway
OPENMRS_DB_NAME=openmrs
ODOO_DB_PASSWORD=odoopw
OPENELIS_DB_PASSWORD=clinlimspw
POSTGRES_USER=postgres
POSTGRES_PASSWORD=throwaway
EOF
  printf 'REMOTE_KAFKA_PASSWORD=%s\n' "$(gen_secret)" > "$tmp_secrets"
  printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$tmp_hubenv" )
ok "throwaway base .env, secrets file and sync/hub.env written under ${TMP_ROOT}"

# --- throwaway mysql: binlog enabled + strided at residue 0 -----------------
# --auto-increment-increment/offset=10 because that IS the base contract task
# 000 asserts (the hub is residue 0), so a throwaway that skipped it would
# make 000 fail for a reason that says nothing about the installer.
MY_IMAGE="$(env_get "${REPO_DIR}/sync/versions.env" MYSQL_IMAGE)"; MY_IMAGE="${MY_IMAGE%%[[:space:]]*}"; MY_IMAGE="${MY_IMAGE:-mysql:8.0.39}"
PG_IMAGE="$(env_get "${REPO_DIR}/sync/versions.env" POSTGRES_IMAGE)"; PG_IMAGE="${PG_IMAGE%%[[:space:]]*}"; PG_IMAGE="${PG_IMAGE:-postgres:16}"
ct run -d --name "$MY_C" --network "$NET" -e MYSQL_ROOT_PASSWORD=throwaway "$MY_IMAGE" \
  --server-id=1 --log-bin=mysql-bin --binlog-format=ROW --binlog-row-image=FULL \
  --auto-increment-increment=10 --auto-increment-offset=10 \
  --performance-schema=OFF --innodb-buffer-pool-size=64M >/dev/null \
  && ok "mysql container ${MY_C} (${MY_IMAGE}, binlog ROW/FULL, strided 10/10, trimmed footprint) started" || { bad "mysql container failed to start"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 60); do ct logs "$MY_C" 2>&1 | grep -q 'ready for connections.*port: 3306' && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "mysql real server ready on port 3306 (past the init-server handoff)" || { bad "mysql never logged the final server's ready-for-connections line"; printf '%s\n' "$fails failure(s)"; exit 1; }

# mysql_root (hub/install/lib.sh) is the one definition -- BASE_MYSQL_CONTAINER
# is exported below, and it is what the tasks themselves use.
export BASE_MYSQL_CONTAINER="$MY_C" BASE_PG_CONTAINER="$PG_C" KAFKA_BASE_NETWORK="$NET"
seed_rc=0
mysql_root <<'SQL' >/dev/null || seed_rc=$?
CREATE DATABASE IF NOT EXISTS openmrs;
USE openmrs;
CREATE TABLE users (user_id INT PRIMARY KEY, username VARCHAR(64));
CREATE TABLE user_property (user_id INT, property VARCHAR(64), value VARCHAR(64), PRIMARY KEY (user_id, property));
CREATE TABLE user_role (user_id INT, role VARCHAR(64), PRIMARY KEY (user_id, role));
CREATE TABLE role (role VARCHAR(64) PRIMARY KEY);
CREATE TABLE role_privilege (role VARCHAR(64), privilege VARCHAR(64), PRIMARY KEY (role, privilege));
CREATE TABLE role_role (parent_role VARCHAR(64), child_role VARCHAR(64), PRIMARY KEY (parent_role, child_role));
CREATE TABLE provider (provider_id INT PRIMARY KEY, name VARCHAR(64));
CREATE TABLE event_records (uuid VARCHAR(38) PRIMARY KEY, category VARCHAR(255));
SQL
[ "$seed_rc" = 0 ] && ok "mysql seeded: openmrs + hub/tables.conf's 7 unmarked (cloud-owned) tables + event_records (090's informational read)" || { bad "mysql seed failed (rc=${seed_rc})"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- throwaway postgres: wal_level=logical, odoo/clinlims roles+dbs, every
# table each source's table.include.list needs (subsystem_tables, never
# hand-copied, so this cannot drift from what 080 actually registers)
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
  odoo_tables="$(subsystem_tables odoo)" || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  { for t in $odoo_tables; do
      printf 'CREATE TABLE %s (id serial PRIMARY KEY, name text);\n' "$t"
      printf 'ALTER SEQUENCE %s_id_seq INCREMENT BY 10;\n' "$t"
    done
    # The SOURCE roles' DML rights, granted up front -- including for tables
    # that do not exist yet. 050 creates dbz_heartbeat as the superuser later,
    # and the heartbeat ACTION QUERY is real INSERT/UPDATE SQL the source
    # connector issues AS ITSELF (odoo/clinlims), not something the
    # replication protocol grants for free: caught live as "Could not execute
    # heartbeat action ... permission denied". A real Odoo/OpenELIS
    # deployment's own source role owns its schema and so already has this;
    # this throwaway seed created everything as postgres, hence the explicit
    # grant plus the matching ALTER DEFAULT PRIVILEGES for anything postgres
    # creates from here on.
    printf 'GRANT USAGE ON SCHEMA public TO odoo;\n'
    printf 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO odoo;\n'
    printf 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO odoo;\n'
  } | ct exec -i "$PG_C" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  clinlims_tables="$(subsystem_tables clinlims)" || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  { printf 'CREATE SCHEMA clinlims;\n'
    for t in $clinlims_tables; do
      printf 'CREATE TABLE clinlims.%s (id integer PRIMARY KEY, name text);\n' "$t"
      printf 'CREATE SEQUENCE clinlims.%s_seq INCREMENT BY 10;\n' "$t"
    done
    printf 'GRANT USAGE ON SCHEMA clinlims TO clinlims;\n'
    printf 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA clinlims TO clinlims;\n'
    printf 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA clinlims GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO clinlims;\n'
  } | ct exec -i "$PG_C" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
fi
[ "$seed_rc" = 0 ] && ok "postgres seeded: roles odoo/clinlims (+DML and default privileges), all $(printf '%s\n' "$odoo_tables" | wc -l | tr -d ' ') odoo tables, all $(printf '%s\n' "$clinlims_tables" | wc -l | tr -d ' ') clinlims tables (subsystem_tables, striding-compliant)" \
  || { bad "postgres seed failed (rc=${seed_rc})"; printf '%s\n' "$fails failure(s)"; exit 1; }

# --- the ambient overrides the installer runs under -------------------------
# COMPOSE_FILE is what carries the two rename overrides into every task's own
# compose() call; COMPOSE_PROJECT_NAME keeps this stack's volumes and network
# aliases out of any other project's way. Everything else is a documented
# per-task override (each named in the task that reads it).
export COMPOSE_FILE="${COMPOSE_F}:${OVERRIDE_F}:${SRC_OVERRIDE_F}"
export COMPOSE_PROJECT_NAME="$PROJ"
export HUB_ENV="$tmp_hubenv"
export KAFKA_CONTAINER="$KAFKA_C"
export HUB_CONNECT_URL_OVERRIDE="http://127.0.0.1:18083"
export HUB_SCHEMA_REGISTRY_URL_OVERRIDE="http://127.0.0.1:18082"
export HUB_KAFKA_UI_URL_OVERRIDE="http://127.0.0.1:18080"
export SASL_LISTENER_PORT=19092
export KAFKA_SASL_BIND=127.0.0.1
export HUB_MIN_DISK_GB=1
export HUB_EXIT_CHECKS_SKIP_GIT=1
ok "overrides exported: COMPOSE_FILE(3 files), project ${PROJ}, KAFKA_CONTAINER=${KAFKA_C}, connect 18083, registry 18082, kafka-ui 18080, SASL 19092, KAFKA_SASL_BIND=127.0.0.1, HUB_MIN_DISK_GB=1"

INSTALL="${REPO_DIR}/hub/install/install.sh"
run_installer(){ # LABEL -> prints the run's output, sets RC
  printf '\n  == %s: %s --hub hubtest --base-env <tmp> --secrets <tmp> ==\n' "$1" "${INSTALL#${REPO_DIR}/}"
}

# --- RUN 1: the whole installer, every task -------------------------------
run_installer "run 1"
out1="$(bash "$INSTALL" --hub hubtest --base-env "$tmp_base" --secrets "$tmp_secrets" 2>&1)"; rc1=$?
printf '%s\n' "$out1" | sed 's/^/    /'
[ "$rc1" = 0 ] && ok "install.sh run 1 exits 0" || bad "install.sh run 1 exited ${rc1}"

assert_line(){ if printf '%s\n' "$out1" | grep -qF "$2"; then printf '  ok   %s\n' "$1"; else bad "$1 -- expected output to contain: $2"; fi; }
# every task actually ran, in order, and reached its own read-back
assert_line "task 000 ran"                                 "0 · preflight"
assert_line "000 checked the base network"                 "base network ${NET} exists"
assert_line "000 read base mysql fitness"                  "base mysql fit: binlog_format=ROW"
assert_line "000 named the pg role it connected as"        "accepts role postgres"
assert_line "000 gated the postgres major version"         "(>=10: pgoutput and pg_sequences)"
assert_line "000 read disk free inside the base container" "disk free on the docker storage pool"
assert_line "task 020 ran"                                 "20 · hub/.env"
assert_line "020 proved every key round-trips"             "round-trips through sourcing hub/.env"
assert_line "020 ended with the key count and mode"        "hub/.env complete ("
assert_line "task 030 ran"                                 "30 · JAAS + directories"
assert_line "030 wrote the JAAS file mode 600"             "JAAS written for admin and mirrormaker (mode 600)"
assert_line "task 040 ran"                                 "40 · images"
assert_line "040 confirmed every image present"            "every image present"
assert_line "task 050 ran"                                 "50 · base database prerequisites"
assert_line "050 converged the odoo publication"           "publication dbz_odoo_owned carries:"
assert_line "050 converged the clinlims publication"       "publication dbz_clinlims_owned carries:"
assert_line "050 asserted striding at residue 0"           "sequence striding (residue 0)"
assert_line "task 060 ran"                                 "60 · kafka"
assert_line "060 matched the cluster id"                   "cluster id ="
assert_line "060 read the published 9092 binding back"     "clinic-facing 9092 published on 127.0.0.1:19092"
assert_line "060 proved SASL on the published port"        "SASL listener answers on the published 19092 as mirrormaker"
assert_line "060 proved schema registry serves"            "schema registry answers on http://127.0.0.1:18082/subjects"
assert_line "task 070 ran"                                 "70 · kafka connect"
assert_line "070 resolved all three plugin classes"        "connect plugins: MySql, Postgres, JdbcSink"
assert_line "070 proved kafka-ui's login page answers"     "kafka-ui login page answers on http://127.0.0.1:18080"
assert_line "070 proved kafka-ui refuses anonymous API"    "kafka-ui /api/clusters refuses an unauthenticated call"
assert_line "070 logged in to kafka-ui for real"           "kafka-ui login succeeded and reads back cluster"
assert_line "task 080 ran"                                 "80 · sources"
assert_line "080 mysql version gate passed"                "fit for Debezium 3.6.2"
assert_line "080 rendered the source config mode 600"      "gitignored, mode 600"
assert_line "080 registered the mysql source"              "mysql-cloud-source-connector registered (HTTP"
assert_line "080 registered both postgres sources"         "odoo-cloud-source, clinlims-cloud-source registered via connectors/register-odoo.sh NODE=cloud"
assert_line "080 set schema-changes retention -1"          "retention -1"
assert_line "080 saw mysql-cloud-source-connector RUNNING" "mysql-cloud-source-connector: connector RUNNING"
assert_line "080 saw odoo-cloud-source RUNNING"            "odoo-cloud-source: connector RUNNING"
assert_line "080 saw clinlims-cloud-source RUNNING"        "clinlims-cloud-source: connector RUNNING"
assert_line "080 saw dbz_odoo_down slot active"            "replication slot dbz_odoo_down active"
assert_line "080 saw dbz_clinlims_down slot active"        "replication slot dbz_clinlims_down active"
assert_line "080 asserted the odoo heartbeat keys"         "odoo-cloud-source: table.include.list carries public.dbz_heartbeat"
assert_line "080 asserted the clinlims heartbeat keys"     "clinlims-cloud-source: table.include.list carries clinlims.dbz_heartbeat"
assert_line "080 reached its final summary line"           "hub sources registered and proven:"
assert_line "task 090 ran"                                 "90 · exit checks"
assert_line "090 read the published 9092 binding back"     "clinic-facing 9092 published on 127.0.0.1:19092"
assert_line "090 printed the event_records line"           "base openmrs event_records:"
assert_line "090 reported all green"                       "exit checks: all green"
assert_line "task 100 ran"                                 "100 · join hand-off"
assert_line "100 printed the operator join command"        "skills/install-clinic.sh join <slug>"
printf '%s\n' "$out1" | grep -qx "done" && ok "installer reached its own final 'done' line" || bad "install.sh never printed its final 'done' line"
# the loopback warning C2 requires when the declared bind is not public
assert_line "the loopback bind warned loudly"              "clinics cannot dial this hub directly"

# --- Ruling 11: the clinlims source's database.hostname placeholder actually
# resolves to BASE_ELIS_CONTAINER (this one-container test never sets it, so
# hub_compose_env defaults it from BASE_PG_CONTAINER) -----------------------
elis_container="$(env_get "$env_path" BASE_ELIS_CONTAINER)"
rendered_host="$(curl -s "${HUB_CONNECT_URL_OVERRIDE}/connectors/clinlims-cloud-source/config" | jq -r '.["database.hostname"] // empty')"
if [ -n "$elis_container" ] && [ "$rendered_host" = "$elis_container" ]; then
  ok "clinlims-cloud-source database.hostname resolves to BASE_ELIS_CONTAINER (${elis_container})"
else
  bad "clinlims-cloud-source database.hostname (${rendered_host:-<empty>}) does not equal BASE_ELIS_CONTAINER (${elis_container:-<empty>})"
fi

# --- Important 8: the rendered config carrying DEBEZIUM_DB_PASSWORD is 600 --
gen_cfg="${HUB_DIR}/connectors/mysql-cloud-source-connector.json"
if [ -f "$gen_cfg" ]; then
  gen_mode="$(stat -c %a "$gen_cfg" 2>/dev/null || stat -f %Lp "$gen_cfg")"
  [ "$gen_mode" = 600 ] && ok "the rendered mysql source config is mode 600 on disk" || bad "the rendered mysql source config is mode ${gen_mode}, want 600"
else
  bad "no rendered mysql source config at ${gen_cfg}"
fi
jaas_mode="$(stat -c %a "$jaas_path" 2>/dev/null || stat -f %Lp "$jaas_path" 2>/dev/null || true)"
[ "$jaas_mode" = 600 ] && ok "the generated JAAS file is mode 600 on disk" || bad "the generated JAAS file is mode ${jaas_mode:-<missing>}, want 600"

# --- no password value in the installer's own output ------------------------
for secret in "$(env_get "$env_path" DEBEZIUM_DB_PASSWORD)" "$(env_get "$env_path" ODOO_DB_PASSWORD)" "$(env_get "$env_path" CLINLIMS_SOURCE_PASSWORD)" "$(env_get "$env_path" KAFKA_UI_PASSWORD)" "$(env_get "$env_path" REMOTE_KAFKA_PASSWORD)"; do
  [ -n "$secret" ] || continue
  printf '%s\n' "$out1" | grep -qF "$secret" && bad "a secret value leaked into install.sh's own output" || true
done
ok "no secret value found in install.sh's output"

# --- Ruling 7 (F-073): no rendered connector config in a fixed /tmp path ----
[ -e /tmp/.reg.out ] && bad "register-odoo.sh left /tmp/.reg.out behind (F-073)" || ok "no /tmp/.reg.out left behind after registration (F-073)"

# --- RUN 2: the whole installer again, unchanged inputs (idempotency) ------
run_installer "run 2 (idempotency)"
out2="$(bash "$INSTALL" --hub hubtest --base-env "$tmp_base" --secrets "$tmp_secrets" 2>&1)"; rc2=$?
printf '%s\n' "$out2" | sed 's/^/    /'
[ "$rc2" = 0 ] && ok "install.sh run 2 exits 0" || bad "install.sh run 2 exited ${rc2}"
line1="$(printf '%s\n' "$out1" | grep 'hub sources registered and proven:')"
line2="$(printf '%s\n' "$out2" | grep 'hub sources registered and proven:')"
[ -n "$line1" ] && [ "$line1" = "$line2" ] && ok "run 2 reaches the identical 080 summary line (idempotent)" || bad "080's final line changed between runs: [${line1}] vs [${line2}]"
printf '%s\n' "$out2" | grep -qF "exit checks: all green" && ok "run 2's exit checks are all green too" || bad "run 2 did not reach 'exit checks: all green'"

# --- Ruling 14: the two Postgres sources still do not collide on JMX names --
connect_logs="$(ct logs "$CONNECT_C" 2>&1)"
if printf '%s\n' "$connect_logs" | grep -q "InstanceAlreadyExists"; then
  bad "Connect log carries an InstanceAlreadyExists line -- the two Postgres sources' JMX names still collide"
else
  ok "no InstanceAlreadyExists in the Connect log (custom.metric.tags disambiguates the two Postgres sources)"
fi

# --- Important 9: the real hub/ was never written ---------------------------
real_sig_after="$(real_env_sig)"
[ "$real_sig_before" = "$real_sig_after" ] \
  && ok "the real ${REAL_HUB}/.env and kafka_server_jaas.conf are byte-identical to before this run (never written, never restored)" \
  || bad "the real hub/.env or JAAS changed during this run: [${real_sig_before}] -> [${real_sig_after}]"
stray="$(ls -1a "$REAL_HUB" 2>/dev/null | grep -E '^\.(src-|task080\.|sasl-check\.|kafka-ui-|env-backup\.|jaas-backup\.|broker-boot-)' || true)"
[ -z "$stray" ] && ok "no scratch file left under the real hub/ (${REAL_HUB})" || bad "scratch files left under the real hub/: $(printf '%s ' $stray)"

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
