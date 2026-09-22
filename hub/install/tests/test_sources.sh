#!/usr/bin/env bash
# Live smoke test: does hub/install/install.sh actually install a hub, end to
# end, on THIS machine -- every task from 000 to 100, run as the real scripts,
# against a real hub Kafka broker/Schema Registry/Connect/kafka-ui and a
# throwaway MySQL 8.0.39 + TWO Postgres 16 containers standing in for the base
# stack. Then again, to prove the whole run is idempotent.
#
# TWO POSTGRES INSTANCES, NOT ONE. The base is shaped like the
# rebuilt Azure hub's real one: Odoo and OpenELIS on separate Postgres
# containers, ASYMMETRIC on purpose (hubtest-src-pg: POSTGRES_USER=odoo,
# POSTGRES_DB=odoo -- odoo IS its own bootstrap superuser, databases
# odoo+postgres, no role named "postgres"; hubtest-src-elis: a STOCK
# postgres:16 substitute, POSTGRES_USER=postgres, POSTGRES_DB=openelis --
# databases openelis+postgres, no DATABASE named clinlims, and clinlims is
# created separately as a plain LOGIN role, database/schema OWNER, WITHOUT
# REPLICATION and WITHOUT SUPERUSER). A one-container smoke (superuser
# postgres for both databases) could never have caught two real defects this
# shape did: stop 2 -- task 000's psql reads had no -d, so libpq defaulted the
# database to the ROLE name, which exists for postgres/odoo but not for
# clinlims (037d284 fixed it with -d postgres; hub/install/tests/test_lint.sh
# now pins that fix so it cannot silently regress) -- and stop 6 --
# clinlims-cloud-source's replication slot never went active ("permission
# denied to start WAL sender") because a non-superuser owner role has no
# REPLICATION attribute by default, only fixed once 050 grants it explicitly
# and reads back rolreplication=t. A superuser clinlims (IPLIT's own
# openelis-db image is genuinely shaped that way) would make both of these a
# no-op that passes for the wrong reason, which is why this base does not
# model that shape even though the installer supports it too.
#
# HOW THIS SMOKE IS SHAPED, AND WHY
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

# --- the temp copy of hub/ --------------------------------------------------
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
ELIS_C=hubtest-src-elis
# The two instances' own bootstrap superusers -- asymmetric ON PURPOSE
# (Azure rehearsal stops 2 and 6): PG_C boots AS odoo's own instance
# (POSTGRES_USER=odoo -- odoo IS the bootstrap superuser, matching bahmni's
# own odoo-16-db image); ELIS_C boots as a STOCK postgres:16 substitute
# (POSTGRES_USER=postgres), the shape the rebuilt Azure hub's OpenELIS
# instance actually turned out to be -- clinlims there is merely the
# DATABASE/schema OWNER, created LOGIN, WITHOUT REPLICATION and WITHOUT
# SUPERUSER, exactly like stop 6 found it (clinlims-cloud-source's task
# failed with "permission denied to start WAL sender" until 050 grants
# REPLICATION explicitly). Testing this shape -- not "IPLIT's own openelis-db
# image", where clinlims would itself be superuser -- is deliberate: a
# superuser clinlims would make every ownership/grant check below a no-op
# that passes whether or not the code under test does anything at all.
# README's Azure command sets BASE_PG_SUPERUSER/BASE_ELIS_SUPERUSER
# explicitly for exactly this asymmetric shape.
PG_SUPERUSER=odoo
ELIS_SUPERUSER=postgres
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
# the end. This is the direct assertion -- not "we restored a
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
    for c in "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C" "$MY_C" "$PG_C" "$ELIS_C"; do
      printf '\n  --- docker logs --tail 60 %s ---\n' "$c" >&2
      ct logs --tail 60 "$c" 2>&1 | mask_env_secrets $HUB_KEYS | sed 's/^/    /' >&2
    done
  fi
  [ -f "$env_path" ] && dc down -v >/dev/null 2>&1 || true
  for c in "$MY_C" "$PG_C" "$ELIS_C" "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C"; do ct rm -f -v "$c" >/dev/null 2>&1 || true; done
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
for c in "$MY_C" "$PG_C" "$ELIS_C" "$CTRL_C" "$KAFKA_C" "$SR_C" "$CONNECT_C" "$UI_C"; do ct rm -f -v "$c" >/dev/null 2>&1 || true; done
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
EOF
  # No POSTGRES_USER/POSTGRES_PASSWORD here (two-instance base):
  # a two-container base has no single shared superuser or password for those
  # keys to name -- BASE_PG_SUPERUSER/BASE_ELIS_SUPERUSER come from the
  # install command's own environment below instead (put_coord: the
  # environment wins unconditionally, every run), exactly like hub/README.md's
  # documented Azure command. hub_compose_env's own base-.env fallback for
  # BASE_PG_SUPERUSER (env_get "$base" POSTGRES_USER) is what a ONE-container
  # base's own .env would carry; this base is never that.
  printf 'REMOTE_KAFKA_PASSWORD=%s\n' "$(gen_secret)" > "$tmp_secrets"
  # kafka.hubtest.internal, never kafka.example: hub/install/tasks/020-env.sh
  # (Azure rehearsal stop 4) now refuses any HUB_KEYS value that looks like a
  # sample placeholder, and placeholder_value (hub/install/lib.sh) matches a
  # bare "*.example" suffix -- REMOTE_KAFKA_HOST is derived from this file's
  # own REMOTE_KAFKA_BOOTSTRAP_SERVERS host part, so "kafka.example:9092"
  # would make 020 fail this smoke on a placeholder it wrote itself.
  printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.hubtest.internal:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$tmp_hubenv" )
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
# is exported below, and it is what the tasks themselves use. The four
# BASE_PG_*/BASE_ELIS_* coordinates are exported here too (README's Azure
# command sets all seven the same way): hub_compose_env's put_coord/
# put_derived make the install command's own environment win unconditionally,
# every run, over both hub/.env's stored value and the base .env's
# POSTGRES_USER -- exactly what a two-instance base with no single shared
# superuser needs.
export BASE_MYSQL_CONTAINER="$MY_C" BASE_PG_CONTAINER="$PG_C" BASE_PG_SUPERUSER="$PG_SUPERUSER" \
       BASE_ELIS_CONTAINER="$ELIS_C" BASE_ELIS_SUPERUSER="$ELIS_SUPERUSER" KAFKA_BASE_NETWORK="$NET"
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

# --- throwaway postgres x2: shaped like the rebuilt Azure hub's real base --
# hubtest-src-pg boots AS the odoo instance itself (POSTGRES_USER=odoo,
# POSTGRES_DB=odoo -- databases odoo+postgres, no role named "postgres");
# hubtest-src-elis boots as a STOCK postgres:16 substitute (POSTGRES_USER=
# postgres, POSTGRES_DB=openelis) -- clinlims is created separately below as
# a plain LOGIN role, database/schema OWNER, WITHOUT REPLICATION and WITHOUT
# SUPERUSER (Azure rehearsal stop 6). This asymmetry is deliberate, not an
# oversight: the ELIS instance's OWN maintenance database is still "postgres"
# either way (stop 2's fix), but only the stock-postgres shape actually
# exercises 050's ensure_source_replication grant and apply-slot-
# heartbeat.sql's explicit GRANT to clinlims -- both are no-ops when clinlims
# is itself the superuser/creator. Every table each source's
# table.include.list needs comes from subsystem_tables, never hand-copied,
# so this cannot drift from what 080 actually registers.
ct run -d --name "$PG_C" --network "$NET" -e POSTGRES_USER=odoo -e POSTGRES_PASSWORD=odoopw -e POSTGRES_DB=odoo "$PG_IMAGE" -c wal_level=logical -c shared_buffers=32MB >/dev/null \
  && ok "postgres container ${PG_C} (${PG_IMAGE}, bootstrap superuser odoo, trimmed footprint) started" || { bad "postgres container ${PG_C} failed to start"; printf '%s\n' "$fails failure(s)"; exit 1; }
ct run -d --name "$ELIS_C" --network "$NET" -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=throwaway -e POSTGRES_DB=openelis "$PG_IMAGE" -c wal_level=logical -c max_replication_slots=8 -c max_wal_senders=8 -c shared_buffers=32MB >/dev/null \
  && ok "postgres container ${ELIS_C} (${PG_IMAGE}, bootstrap superuser postgres -- stock image, clinlims is a granted role -- trimmed footprint) started" || { bad "postgres container ${ELIS_C} failed to start"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 60); do ct logs "$PG_C" 2>&1 | grep -q "PostgreSQL init process complete" && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] || { bad "postgres ${PG_C} never logged the temp-to-real handoff (init process complete)"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 60); do ct logs "$ELIS_C" 2>&1 | grep -q "PostgreSQL init process complete" && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] || { bad "postgres ${ELIS_C} never logged the temp-to-real handoff (init process complete)"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 30); do ct exec "$PG_C" pg_isready -U "$PG_SUPERUSER" >/dev/null 2>&1 && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "postgres ${PG_C} answers pg_isready as ${PG_SUPERUSER} (past the init-server handoff)" || { bad "postgres ${PG_C} never answered pg_isready after the handoff"; printf '%s\n' "$fails failure(s)"; exit 1; }
ready=0
for i in $(seq 1 30); do ct exec "$ELIS_C" pg_isready -U "$ELIS_SUPERUSER" >/dev/null 2>&1 && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "postgres ${ELIS_C} answers pg_isready as ${ELIS_SUPERUSER} (past the init-server handoff)" || { bad "postgres ${ELIS_C} never answered pg_isready after the handoff"; printf '%s\n' "$fails failure(s)"; exit 1; }

seed_rc=0
odoo_tables="$(subsystem_tables odoo)" || seed_rc=$?
if [ "$seed_rc" = 0 ]; then
  { for t in $odoo_tables; do
      printf 'CREATE TABLE %s (id serial PRIMARY KEY, name text);\n' "$t"
      printf 'ALTER SEQUENCE %s_id_seq INCREMENT BY 10;\n' "$t"
    done
  } | ct exec -i "$PG_C" psql -U "$PG_SUPERUSER" -d odoo -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  # clinlims itself: a plain LOGIN role, database+schema OWNER, WITHOUT
  # REPLICATION and WITHOUT SUPERUSER (Azure rehearsal stop 6) -- database
  # ownership carries CREATE on it implicitly, which is what lets the next
  # step connect AS clinlims and create its own schema.
  { printf "CREATE ROLE clinlims LOGIN PASSWORD 'clinlimspw';\n"
    printf 'ALTER DATABASE openelis OWNER TO clinlims;\n'
  } | ct exec -i "$ELIS_C" psql -U "$ELIS_SUPERUSER" -d postgres -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  clinlims_tables="$(subsystem_tables clinlims)" || seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  # Connected AS clinlims (not the postgres superuser): the schema and every
  # table/sequence inside it are owned by clinlims itself, by construction,
  # the same way a real Odoo/OpenELIS deployment's own source role owns its
  # schema. dbz_heartbeat is the one table clinlims does NOT create (050's
  # apply-slot-heartbeat.sql adds it later, as the superuser, which is
  # exactly why that file's own GRANT SELECT/INSERT/UPDATE to :r matters here
  # and is not a no-op the way it would be on a superuser clinlims.
  { printf 'CREATE SCHEMA clinlims AUTHORIZATION clinlims;\n'
    for t in $clinlims_tables; do
      printf 'CREATE TABLE clinlims.%s (id integer PRIMARY KEY, name text);\n' "$t"
      printf 'CREATE SEQUENCE clinlims.%s_seq INCREMENT BY 10;\n' "$t"
    done
  } | ct exec -i "$ELIS_C" psql -U clinlims -d openelis -v ON_ERROR_STOP=1 -q >/dev/null || seed_rc=$?
fi
[ "$seed_rc" = 0 ] && ok "postgres seeded: ${PG_SUPERUSER}@${PG_C} owns all $(printf '%s\n' "$odoo_tables" | wc -l | tr -d ' ') odoo tables; clinlims@${ELIS_C} (a plain role, not the ${ELIS_SUPERUSER} superuser) owns all $(printf '%s\n' "$clinlims_tables" | wc -l | tr -d ' ') clinlims tables (subsystem_tables, striding-compliant)" \
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
# HUB_MIN_IMAGE_DISK_GB (Azure rehearsal stop 3): the image-store floor beside
# HUB_MIN_DISK_GB's volume-pool floor -- same test-only-override contract,
# relaxed here for the same reason (this dev host's real free space is not
# what either check is proving).
export HUB_MIN_IMAGE_DISK_GB=1
export HUB_EXIT_CHECKS_SKIP_GIT=1
ok "overrides exported: COMPOSE_FILE(3 files), project ${PROJ}, KAFKA_CONTAINER=${KAFKA_C}, connect 18083, registry 18082, kafka-ui 18080, SASL 19092, KAFKA_SASL_BIND=127.0.0.1, HUB_MIN_DISK_GB=1, HUB_MIN_IMAGE_DISK_GB=1"

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
assert_line "000 named the pg role it connected as (rolsuper proven)"   "accepts role ${PG_SUPERUSER}"
assert_line "000 gated the postgres major version"         "(>=10: pgoutput and pg_sequences)"
# --- the ELIS block: BASE_ELIS_CONTAINER != BASE_PG_CONTAINER on
# this two-instance base, so 000's whole 3b block runs for real for the first
# time -- previously a no-op on every smoke, since the one-container base
# always collapsed ELIS back onto PG.
assert_line "000 checked the base elis container running"              "base elis container ${ELIS_C} running"
assert_line "000 named the elis role it connected as (rolsuper proven)" "accepts role ${ELIS_SUPERUSER}"
assert_line "000 gated the elis postgres major version"                "elis pg major"
assert_line "000 read elis wal_level"                                  "elis wal_level=logical"
assert_line "000 read elis max_replication_slots"                      "elis max_replication_slots="
assert_line "000 read elis max_wal_senders"                            "elis max_wal_senders="
# --- disk: two floors, two filesystems (Azure rehearsal stop 3) -- prefix
# only, never the GB numbers themselves, which are real and host-dependent.
assert_line "000 read disk free on the volume pool"        "disk free on the volume pool ("
assert_line "000 read disk free on the image store"        "disk free on the image store ("
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
# ensure_source_replication (Azure rehearsal stop 6): on the stock-postgres
# ELIS instance, clinlims is a plain owner role, not the superuser -- without
# this explicit grant, clinlims-cloud-source's slot would never go active
# ("permission denied to start WAL sender"), exactly as stop 6 hit live. The
# odoo instance already has REPLICATION for free (odoo IS its own superuser),
# so this line for odoo proves the grant is idempotent/harmless there too.
assert_line "050 granted odoo replication (WAL sender)"      "source role odoo in odoo may start a WAL sender (rolreplication=t)"
assert_line "050 granted clinlims replication (WAL sender)"  "source role clinlims in openelis may start a WAL sender (rolreplication=t)"

# --- Ruling (two-instance base): 050's clinlims half actually LANDS in
# hubtest-src-elis -- read independently from the database itself, not just
# trusted from 050's own ok line -- and the odoo instance carries none of it.
# A dispatch bug in pg_admin (hub/install/lib.sh) that ignored the db
# argument and always used BASE_PG_CONTAINER would have this task register
# clinlims_sink and dbz_clinlims_owned on the ODOO instance instead -- silent
# on the one-container base (same cluster either way), loud here only if
# checked explicitly, since pg_admin would otherwise simply fail to connect
# (no "openelis" database on the odoo instance) rather than mis-register.
clinlims_pub_elis="$(ct exec "$ELIS_C" psql -U "$ELIS_SUPERUSER" -d openelis -Atc "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'dbz_clinlims_owned'")"
case ",${clinlims_pub_elis}," in
  *,sample,*) ok "dbz_clinlims_owned publication independently confirmed in ${ELIS_C} (the OpenELIS instance): ${clinlims_pub_elis}" ;;
  *) bad "dbz_clinlims_owned publication not found (or incomplete) in ${ELIS_C}: ${clinlims_pub_elis:-<empty>}" ;;
esac
clinlims_sink_role_elis="$(ct exec "$ELIS_C" psql -U "$ELIS_SUPERUSER" -d openelis -Atc "select rolname from pg_roles where rolname = 'clinlims_sink'")"
[ "$clinlims_sink_role_elis" = clinlims_sink ] && ok "role clinlims_sink independently confirmed in ${ELIS_C} (the OpenELIS instance)" || bad "role clinlims_sink not found in ${ELIS_C}"
clinlims_schema_on_pg="$(ct exec "$PG_C" psql -U "$PG_SUPERUSER" -d odoo -Atc "select count(*) from pg_namespace where nspname = 'clinlims'")"
clinlims_sink_on_pg="$(ct exec "$PG_C" psql -U "$PG_SUPERUSER" -d odoo -Atc "select count(*) from pg_roles where rolname = 'clinlims_sink'")"
if [ "$clinlims_schema_on_pg" = 0 ] && [ "$clinlims_sink_on_pg" = 0 ]; then
  ok "the odoo instance (${PG_C}) holds no clinlims schema and no clinlims_sink role"
else
  bad "the odoo instance (${PG_C}) unexpectedly carries clinlims objects (schema count=${clinlims_schema_on_pg}, clinlims_sink role count=${clinlims_sink_on_pg})"
fi

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
assert_line "090 named the odoo instance in slot retention" "slot dbz_odoo_down (${PG_C}) retains"
assert_line "090 named the elis instance in slot retention" "slot dbz_clinlims_down (${ELIS_C}) retains"
assert_line "090 printed the event_records line"           "base openmrs event_records:"
assert_line "090 reported all green"                       "exit checks: all green"
assert_line "task 100 ran"                                 "100 · join hand-off"
assert_line "100 printed the operator join command"        "skills/install-clinic.sh join <slug>"
printf '%s\n' "$out1" | grep -qx "done" && ok "installer reached its own final 'done' line" || bad "install.sh never printed its final 'done' line"
# the loopback warning C2 requires when the declared bind is not public
assert_line "the loopback bind warned loudly"              "clinics cannot dial this hub directly"

# --- the clinlims source's database.hostname placeholder actually
# resolves to BASE_ELIS_CONTAINER -- this two-instance base sets it explicitly
# (hubtest-src-elis, distinct from BASE_PG_CONTAINER), so this is no longer
# the defaulted-from-BASE_PG_CONTAINER no-op it was on the one-container base.
# -----------------------------------------------------------------------
elis_container="$(env_get "$env_path" BASE_ELIS_CONTAINER)"
rendered_host="$(curl -s "${HUB_CONNECT_URL_OVERRIDE}/connectors/clinlims-cloud-source/config" | jq -r '.["database.hostname"] // empty')"
if [ -n "$elis_container" ] && [ "$rendered_host" = "$elis_container" ]; then
  ok "clinlims-cloud-source database.hostname resolves to BASE_ELIS_CONTAINER (${elis_container})"
else
  bad "clinlims-cloud-source database.hostname (${rendered_host:-<empty>}) does not equal BASE_ELIS_CONTAINER (${elis_container:-<empty>})"
fi
# Independent check (not just 080's own "replication slot ... active" claim):
# read pg_replication_slots directly from the ELIS instance itself.
slot_active_elis="$(ct exec "$ELIS_C" psql -U "$ELIS_SUPERUSER" -d openelis -Atc "select active from pg_replication_slots where slot_name = 'dbz_clinlims_down'")"
[ "$slot_active_elis" = t ] && ok "replication slot dbz_clinlims_down independently confirmed active in ${ELIS_C}" || bad "replication slot dbz_clinlims_down not active in ${ELIS_C} (read: ${slot_active_elis:-<empty>})"

# --- the rendered config carrying DEBEZIUM_DB_PASSWORD is 600 ---------------
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

# --- no rendered connector config in a fixed /tmp path ----------------------
[ -e /tmp/.reg.out ] && bad "register-odoo.sh left /tmp/.reg.out behind" || ok "no /tmp/.reg.out left behind after registration"

# --- RUN 2: the whole installer again, unchanged inputs (idempotency) ------
run_installer "run 2 (idempotency)"
out2="$(bash "$INSTALL" --hub hubtest --base-env "$tmp_base" --secrets "$tmp_secrets" 2>&1)"; rc2=$?
printf '%s\n' "$out2" | sed 's/^/    /'
[ "$rc2" = 0 ] && ok "install.sh run 2 exits 0" || bad "install.sh run 2 exited ${rc2}"
line1="$(printf '%s\n' "$out1" | grep 'hub sources registered and proven:')"
line2="$(printf '%s\n' "$out2" | grep 'hub sources registered and proven:')"
[ -n "$line1" ] && [ "$line1" = "$line2" ] && ok "run 2 reaches the identical 080 summary line (idempotent)" || bad "080's final line changed between runs: [${line1}] vs [${line2}]"
printf '%s\n' "$out2" | grep -qF "exit checks: all green" && ok "run 2's exit checks are all green too" || bad "run 2 did not reach 'exit checks: all green'"

# --- the two Postgres sources still do not collide on JMX names -------------
connect_logs="$(ct logs "$CONNECT_C" 2>&1)"
if printf '%s\n' "$connect_logs" | grep -q "InstanceAlreadyExists"; then
  bad "Connect log carries an InstanceAlreadyExists line -- the two Postgres sources' JMX names still collide"
else
  ok "no InstanceAlreadyExists in the Connect log (custom.metric.tags disambiguates the two Postgres sources)"
fi

# --- the real hub/ was never written -----------------------------------------
real_sig_after="$(real_env_sig)"
[ "$real_sig_before" = "$real_sig_after" ] \
  && ok "the real ${REAL_HUB}/.env and kafka_server_jaas.conf are byte-identical to before this run (never written, never restored)" \
  || bad "the real hub/.env or JAAS changed during this run: [${real_sig_before}] -> [${real_sig_after}]"
stray="$(ls -1a "$REAL_HUB" 2>/dev/null | grep -E '^\.(src-|task080\.|sasl-check\.|kafka-ui-|env-backup\.|jaas-backup\.|broker-boot-)' || true)"
[ -z "$stray" ] && ok "no scratch file left under the real hub/ (${REAL_HUB})" || bad "scratch files left under the real hub/: $(printf '%s ' $stray)"

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
