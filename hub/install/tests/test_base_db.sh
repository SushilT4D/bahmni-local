#!/usr/bin/env bash
# Local smoke test: does hub/install/tasks/050-base-db.sh actually converge a
# base stack's databases end to end, on THIS machine, against throwaway
# postgres/mysql containers standing in for the real base stack -- no hub
# compose project, no real cloud/clinic base stack, nothing but the two
# databases 050-base-db.sh touches. Distinct from test_lib.sh (mysql_user_sql's
# pure text generation only, no docker) and from test_broker_boot.sh (the
# hub's OWN Kafka broker, a completely different pair of containers).
#
# RUNTIME=docker is forced (not left to detect_runtime's macOS-default
# podman, which is not installed on every dev machine, this one included):
# both this script's own container/network setup AND the 050-base-db.sh
# subprocess it launches must agree on the same runtime, or the subprocess's
# `ct exec` would look for these containers under the wrong tool and find
# nothing.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../lib.sh"
export RUNTIME=docker
fails=0
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

docker info >/dev/null 2>&1 || { skip "docker is not available/running on this host -- test_base_db.sh needs a real docker to boot postgres+mysql"; exit 0; }

NET=hubtest-basedb-net
PG_C=hubtest-basedb-pg
MY_C=hubtest-basedb-mysql
TASK="${REPO_DIR}/hub/install/tasks/050-base-db.sh"
env_path="${HUB_DIR}/.env"
env_backup=""
tmp_versions="$(mktemp "${HUB_DIR}/.versions.XXXXXX")"

if [ -f "$env_path" ]; then
  env_backup="$(mktemp "${HUB_DIR}/.env-backup.XXXXXX")"
  cp -p "$env_path" "$env_backup"
fi

cleanup(){
  docker rm -f "$PG_C" "$MY_C" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  if [ -n "$env_backup" ]; then cp -p "$env_backup" "$env_path"; rm -f "$env_backup"; else rm -f "$env_path"; fi
  rm -f "$tmp_versions"
}
trap cleanup EXIT

# Images: sync/versions.env if it names them (its values carry inline "#
# comment" text that only versions_put strips -- a raw env_get here would
# hand docker an image tag with a comment glued on), else the fleet's pins.
versions_put "$tmp_versions" || bad "versions_put failed to copy sync/versions.env"
PG_IMAGE="$(env_get "$tmp_versions" POSTGRES_IMAGE)"; PG_IMAGE="${PG_IMAGE:-postgres:16}"
MY_IMAGE="$(env_get "$tmp_versions" MYSQL_IMAGE)"; MY_IMAGE="${MY_IMAGE:-mysql:8.0.39}"
ok "images: postgres=${PG_IMAGE} mysql=${MY_IMAGE}"

docker network create "$NET" >/dev/null 2>&1 && ok "throwaway network ${NET} created" || { bad "could not create network ${NET}"; exit 1; }

# --- throwaway postgres: wal_level=logical via the container command -------
docker run -d --name "$PG_C" --network "$NET" -e POSTGRES_PASSWORD=throwaway \
  "$PG_IMAGE" -c wal_level=logical >/dev/null \
  && ok "postgres container ${PG_C} (${PG_IMAGE}) started" || { bad "postgres container failed to start"; exit 1; }

ready=0
for i in $(seq 1 30); do docker exec "$PG_C" pg_isready -U postgres >/dev/null 2>&1 && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "postgres answers pg_isready" || { bad "postgres never answered pg_isready"; exit 1; }

# Seed: roles odoo/clinlims (LOGIN REPLICATION, matching the real base
# stack's own application roles) and the two databases. A FEW conf tables in
# odoo (not all twelve) on purpose -- it exercises build_publication's
# skip-what's-missing path, not just its happy path. All four conf tables in
# openelis's clinlims schema, id columns with NO default (OpenELIS/Hibernate
# assigns ids, matching production) and a hand-created <table>_seq per table,
# since there is no serial column to hang a default sequence off of. Some
# sequences are left never-nextval'd (pg_sequences.last_value NULL, the
# "never used" pass case); others get a real value at residue 0 (multiple of
# 10) via setval, the "used correctly" pass case -- both are asserted OK by
# 050-base-db.sh's striding check.
docker exec -i "$PG_C" psql -U postgres -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null
CREATE ROLE odoo LOGIN REPLICATION PASSWORD 'seedpw';
CREATE ROLE clinlims LOGIN REPLICATION PASSWORD 'seedpw';
CREATE DATABASE odoo OWNER odoo;
CREATE DATABASE openelis OWNER clinlims;
SQL
seed_rc=$?
if [ "$seed_rc" = 0 ]; then
  docker exec -i "$PG_C" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null
CREATE TABLE res_partner (id serial PRIMARY KEY, name text);
CREATE TABLE product_template (id serial PRIMARY KEY, name text);
CREATE TABLE sale_order (id serial PRIMARY KEY, name text);
ALTER SEQUENCE res_partner_id_seq INCREMENT BY 10;
ALTER SEQUENCE product_template_id_seq INCREMENT BY 10;
ALTER SEQUENCE sale_order_id_seq INCREMENT BY 10;
SELECT setval('sale_order_id_seq', 10, true);
SQL
  seed_rc=$?
fi
if [ "$seed_rc" = 0 ]; then
  docker exec -i "$PG_C" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q <<'SQL' >/dev/null
CREATE SCHEMA clinlims;
CREATE TABLE clinlims.sample (id integer PRIMARY KEY, name text);
CREATE TABLE clinlims.sample_item (id integer PRIMARY KEY, name text);
CREATE TABLE clinlims.analysis (id integer PRIMARY KEY, name text);
CREATE TABLE clinlims.result (id integer PRIMARY KEY, name text);
CREATE SEQUENCE clinlims.sample_seq INCREMENT BY 10;
CREATE SEQUENCE clinlims.sample_item_seq INCREMENT BY 10;
CREATE SEQUENCE clinlims.analysis_seq INCREMENT BY 10;
CREATE SEQUENCE clinlims.result_seq INCREMENT BY 10;
SELECT setval('clinlims.sample_seq', 20, true);
SELECT setval('clinlims.analysis_seq', 30, true);
SQL
  seed_rc=$?
fi
[ "$seed_rc" = 0 ] && ok "postgres seeded: roles odoo/clinlims, 3 odoo tables, 4 clinlims tables+sequences" || { bad "postgres seed failed (rc=${seed_rc})"; exit 1; }

# --- throwaway mysql ---------------------------------------------------------
docker run -d --name "$MY_C" --network "$NET" -e MYSQL_ROOT_PASSWORD=throwaway \
  "$MY_IMAGE" >/dev/null \
  && ok "mysql container ${MY_C} (${MY_IMAGE}) started" || { bad "mysql container failed to start"; exit 1; }


# The official mysql image runs a TEMPORARY, socket-only server to execute
# its own init scripts, shuts it down, then execs the real one -- a single
# successful ping can land in that temporary instance's window, moments
# before it goes down for the handoff (reproduced live: ping succeeded,
# then the very next query attempt got "Can't connect ... through socket",
# then the one after that succeeded for good). Debounce: only trust it after
# two CONSECUTIVE successful pings, which reliably lands after the handoff.
ready=0; consec=0
for i in $(seq 1 60); do
  if docker exec "$MY_C" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqladmin -uroot ping' >/dev/null 2>&1; then
    consec=$((consec+1))
    [ "$consec" -ge 2 ] && { ready=1; break; }
  else
    consec=0
  fi
  sleep 2
done
[ "$ready" = 1 ] && ok "mysql answers mysqladmin ping (debounced past the init-server handoff)" || { bad "mysql never answered ping"; exit 1; }

# --- hub/.env for the task under test ---------------------------------------
REMOTE_MYSQL_PW="$(gen_secret)"; DEBEZIUM_PW="$(gen_secret)"; ODOO_SINK_PW="$(gen_secret)"; CLINLIMS_SINK_PW="$(gen_secret)"
( umask 077
cat > "$env_path" <<EOF
BASE_MYSQL_CONTAINER=${MY_C}
BASE_PG_CONTAINER=${PG_C}
BASE_PG_SUPERUSER=postgres
REMOTE_MYSQL_USER=sink
REMOTE_MYSQL_PASSWORD=${REMOTE_MYSQL_PW}
REMOTE_MYSQL_DATABASE=openmrs
DEBEZIUM_DB_USER=debezium
DEBEZIUM_DB_PASSWORD=${DEBEZIUM_PW}
ODOO_SINK_PASSWORD=${ODOO_SINK_PW}
CLINLIMS_SINK_PASSWORD=${CLINLIMS_SINK_PW}
KAFKA_BASE_NETWORK=${NET}
EOF
)
chmod 600 "$env_path"
ok "temp hub/.env written (restored on exit)"

# --- run 050-base-db.sh for real, twice (idempotency) -----------------------
out1="$(bash "$TASK" 2>&1)"; rc1=$?
printf '%s\n' "$out1" | sed 's/^/    /'
[ "$rc1" = 0 ] && ok "first run of 050-base-db.sh exits 0" || bad "first run of 050-base-db.sh exited ${rc1}"

assert_line(){ # LABEL PATTERN
  if printf '%s\n' "$out1" | grep -qF "$2"; then printf '  ok   %s\n' "$1"; else bad "$1 -- expected output to contain: $2"; fi
}
assert_line "publication dbz_odoo_owned converged from the seeded tables"          "publication dbz_odoo_owned carries: product_template,res_partner,sale_order"
assert_line "publication dbz_clinlims_owned converged from the seeded tables"      "publication dbz_clinlims_owned carries: analysis,result,sample,sample_item"
assert_line "heartbeat added dbz_heartbeat to dbz_odoo_owned"                      "dbz_heartbeat"
assert_line "mysql sink user authenticates over the network"                      "mysql sink@"
assert_line "mysql debezium user authenticates over the network"                  "mysql debezium@"
assert_line "postgres odoo_sink authenticates over the network"                   "postgres odoo_sink@"
assert_line "postgres clinlims_sink authenticates over the network"               "postgres clinlims_sink@"
assert_line "sequence striding read-back printed"                                 "sequence striding (residue 0):"
assert_line "no replication origins on the hub"                                   "origins: none (hub relays)"
assert_line "task reaches its final summary line"                                 "base databases carry the sync identities, publications, heartbeats; striding at residue 0"

# The odoo:/clinlims: tables NOT seeded (9 of odoo's 12, none of clinlims's 4)
# must be WARNed as skipped, never silently dropped or hard-failed.
warn_count="$(printf '%s\n' "$out1" | grep -c 'WARN.*does not exist in odoo')"
[ "${warn_count:-0}" = 9 ] && ok "9 unseeded odoo tables warned as skipped, not failed" || bad "expected 9 'does not exist in odoo' warnings, got ${warn_count:-0}"

# Independent check (not just trusting the task's own claim): the MySQL
# accounts exist with the grants this task asked for.
test_mysql_root(){ docker exec -i "$MY_C" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }
grants_sink="$(printf "SHOW GRANTS FOR 'sink'@'%%'" | test_mysql_root)"
grants_dbz="$(printf "SHOW GRANTS FOR 'debezium'@'%%'" | test_mysql_root)"
case "$grants_sink" in *REFERENCES*ALTER*|*ALTER*REFERENCES*) ok "mysql sink grants include CREATE/REFERENCES/INDEX/ALTER" ;; *) bad "mysql sink grants missing expected privileges: ${grants_sink}" ;; esac
case "$grants_dbz" in *"REPLICATION SLAVE"*"REPLICATION CLIENT"*) ok "mysql debezium grants include REPLICATION SLAVE/CLIENT" ;; *) bad "mysql debezium grants missing expected privileges: ${grants_dbz}" ;; esac

# --- idempotency: run again, expect the same read-back facts ---------------
out2="$(bash "$TASK" 2>&1)"; rc2=$?
printf '%s\n' "$out2" | sed 's/^/    /'
[ "$rc2" = 0 ] && ok "second run of 050-base-db.sh exits 0" || bad "second run of 050-base-db.sh exited ${rc2}"

line1="$(printf '%s\n' "$out1" | grep 'base databases carry the sync identities')"
line2="$(printf '%s\n' "$out2" | grep 'base databases carry the sync identities')"
[ -n "$line1" ] && [ "$line1" = "$line2" ] && ok "second run reaches the identical final line" || bad "final line changed between runs: [${line1}] vs [${line2}]"

pub1="$(printf '%s\n' "$out1" | grep 'publication dbz_odoo_owned carries:')"
pub2="$(printf '%s\n' "$out2" | grep 'publication dbz_odoo_owned carries:')"
[ -n "$pub1" ] && [ "$pub1" = "$pub2" ] && ok "dbz_odoo_owned publication unchanged on rerun" || bad "dbz_odoo_owned publication changed between runs: [${pub1}] vs [${pub2}]"

seq1="$(printf '%s\n' "$out1" | grep 'sequence striding (residue 0):')"
seq2="$(printf '%s\n' "$out2" | grep 'sequence striding (residue 0):')"
[ -n "$seq1" ] && [ "$seq1" = "$seq2" ] && ok "sequence striding read-back unchanged on rerun (never strides)" || bad "sequence striding line changed between runs: [${seq1}] vs [${seq2}]"

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
