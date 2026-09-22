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
#
# It runs against a temp COPY of hub/ (final review, Important 9): this test
# used to overwrite the real hub/.env in place and restore it from a backup in
# its EXIT trap, so a kill -9 between the two left a live hub configured with
# throwaway credentials. HUB_DIR is pointed at the copy BEFORE lib.sh is
# sourced, so no library function ever sees the real hub/ at all.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_HUB="$(cd "$HERE/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
export HUB_DIR="${TMP_ROOT}/hub"
mkdir -p "$HUB_DIR"
for item in docker-compose.yml tables.conf connectors scripts odoo openelis install; do
  [ -e "${REAL_HUB}/${item}" ] && cp -R "${REAL_HUB}/${item}" "${HUB_DIR}/${item}"
done
. "$HERE/../lib.sh"
export RUNTIME=docker
setup_compose   # CT/COMPOSE_CMD, so this test can use lib.sh's own container_ip
fails=0
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

docker info >/dev/null 2>&1 || { skip "docker is not available/running on this host -- test_base_db.sh needs a real docker to boot postgres+mysql"; exit 0; }

NET=hubtest-basedb-net
PG_C=hubtest-basedb-pg
MY_C=hubtest-basedb-mysql
TASK="${REPO_DIR}/hub/install/tasks/050-base-db.sh"
env_path="${HUB_DIR}/.env"
tmp_versions="${TMP_ROOT}/versions.env"
: > "$tmp_versions"   # env_put reads the file before rewriting it, so it must exist

cleanup(){
  docker rm -f -v "$PG_C" "$MY_C" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  # The throwaway hub tree, .env included. Nothing under the real hub/ was
  # written, so there is nothing to restore.
  rm -rf "$TMP_ROOT"
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

# The official postgres image has the SAME two-phase startup as mysql's: a
# temporary server (on the Unix socket only) runs the entrypoint's own setup
# (password, encoding), gets stopped, then the real, long-running one starts
# -- reproduced live: pg_isready succeeded once, and the very next `psql`
# (the seed script below) got "connection ... failed: No such file or
# directory" because the temp instance had just gone down for the handoff.
# "PostgreSQL init process complete; ready for start up." is logged exactly
# once, right at that handoff, so wait for it before trusting pg_isready.
ready=0
for i in $(seq 1 60); do
  docker logs "$PG_C" 2>&1 | grep -q "PostgreSQL init process complete" && { ready=1; break; }
  sleep 2
done
[ "$ready" = 1 ] || { bad "postgres never logged the temp-to-real handoff (init process complete)"; exit 1; }
ready=0
for i in $(seq 1 30); do docker exec "$PG_C" pg_isready -U postgres >/dev/null 2>&1 && { ready=1; break; }; sleep 2; done
[ "$ready" = 1 ] && ok "postgres real server answers pg_isready (past the init-server handoff)" || { bad "postgres never answered pg_isready after the handoff"; exit 1; }

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

# The official mysql image runs a TEMPORARY, socket-only server (logged
# "ready for connections ... port: 0") to execute its own init scripts, shuts
# it down, then execs the real, network-enabled one ("port: 3306"). A single
# successful `mysqladmin ping` -- even two CONSECUTIVE ones a couple of
# seconds apart -- can still land entirely inside the temporary instance's
# window if it stays up that long (reproduced live both ways: a lone ping
# succeeding right before the handoff, and two in a row both hitting the
# temp instance before it went down). The unambiguous signal is the log
# line itself: wait for "ready for connections" together with "port: 3306",
# which only the final server ever prints.
ready=0
for i in $(seq 1 60); do
  docker logs "$MY_C" 2>&1 | grep -q 'ready for connections.*port: 3306' && { ready=1; break; }
  sleep 2
done
[ "$ready" = 1 ] && ok "mysql real server ready for connections on port 3306 (past the init-server handoff)" || { bad "mysql never logged the final server's ready-for-connections line"; exit 1; }

# --- hub/.env for the task under test ---------------------------------------
# Fix round 2: these four passwords deliberately carry a "'" and a "\" each --
# an operator could type either into hub/.env, and 050-base-db.sh's SQL
# literals (mysql_user_sql, create_pg_sink_role) must survive it, which the
# network login proofs and the write-proof below prove end to end. printf
# '%q' quotes each value for THIS FILE itself, not just the SQL later: a
# naive unquoted heredoc interpolation would drop an unmatched "'" straight
# into hub/.env, and `. hub/.env` sourcing it back would either error out or
# -- worse -- treat everything up to the NEXT "'" anywhere later in the file
# as one string, silently corrupting every key after it.
weird_secret(){ printf '%s%s%s%s' "$(gen_secret)" "'" '\' "$(gen_secret)"; }
REMOTE_MYSQL_PW="$(weird_secret)"; DEBEZIUM_PW="$(weird_secret)"; ODOO_SINK_PW="$(weird_secret)"; CLINLIMS_SINK_PW="$(weird_secret)"
( umask 077
cat > "$env_path" <<EOF
BASE_MYSQL_CONTAINER=${MY_C}
BASE_PG_CONTAINER=${PG_C}
BASE_PG_SUPERUSER=postgres
REMOTE_MYSQL_USER=sink
REMOTE_MYSQL_PASSWORD=$(printf '%q' "$REMOTE_MYSQL_PW")
REMOTE_MYSQL_DATABASE=openmrs
DEBEZIUM_DB_USER=debezium
DEBEZIUM_DB_PASSWORD=$(printf '%q' "$DEBEZIUM_PW")
ODOO_SINK_PASSWORD=$(printf '%q' "$ODOO_SINK_PW")
CLINLIMS_SINK_PASSWORD=$(printf '%q' "$CLINLIMS_SINK_PW")
KAFKA_BASE_NETWORK=${NET}
EOF
)
chmod 600 "$env_path"
ok "temp hub/.env written (restored on exit), sink+debezium+mysql passwords each carry a ' and a \\"

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

# The odoo: tables NOT seeded (everything configured minus the 3 seeded here)
# must be WARNed as skipped, never silently dropped or hard-failed. Derived
# from subsystem_tables' live count, not a hardcoded 9 -- sync/subsystems.conf
# is another session's in-flight work (never edited by this task) and its
# odoo: row count has already moved once during this fix round. subsystem_tables
# itself comes from clinic/install/lib.sh (sourced transitively via
# hub/install/lib.sh above), the same parser 050-base-db.sh now calls, so this
# count can never drift from what the task under test actually iterates over.
#
# Captured on its own line, not `subsystem_tables odoo | wc -l | tr -d ' '`
# (Fix round 2, same class as 050-base-db.sh's for-loop fix): without
# `pipefail` a fail() from subsystem_tables deep in that pipe would be
# invisible -- wc/tr would just count whatever partial output leaked through
# before the pipe closed and report a silently-wrong total. Capturing the
# generator's own output first means its exit status can be checked honestly.
odoo_tables="$(subsystem_tables odoo)"; odoo_tables_rc=$?
[ "$odoo_tables_rc" = 0 ] || bad "subsystem_tables odoo failed (rc=${odoo_tables_rc}): ${odoo_tables}"
total_odoo="$(printf '%s\n' "$odoo_tables" | wc -l | tr -d ' ')"
expected_warns=$((total_odoo - 3))
warn_count="$(printf '%s\n' "$out1" | grep -c 'WARN.*does not exist in odoo')"
[ "${warn_count:-0}" = "$expected_warns" ] \
  && ok "${expected_warns} unseeded odoo tables (of ${total_odoo} configured, 3 seeded) warned as skipped, not failed" \
  || bad "expected ${expected_warns} 'does not exist in odoo' warnings (of ${total_odoo} configured), got ${warn_count:-0}"

# Independent check (not just trusting the task's own claim): the MySQL
# accounts exist with the grants this task asked for.
test_mysql_root(){ docker exec -i "$MY_C" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N'; }
grants_sink="$(printf "SHOW GRANTS FOR 'sink'@'%%'" | test_mysql_root)"
grants_dbz="$(printf "SHOW GRANTS FOR 'debezium'@'%%'" | test_mysql_root)"
case "$grants_sink" in *REFERENCES*ALTER*|*ALTER*REFERENCES*) ok "mysql sink grants include CREATE/REFERENCES/INDEX/ALTER" ;; *) bad "mysql sink grants missing expected privileges: ${grants_sink}" ;; esac
case "$grants_dbz" in *"REPLICATION SLAVE"*"REPLICATION CLIENT"*) ok "mysql debezium grants include REPLICATION SLAVE/CLIENT" ;; *) bad "mysql debezium grants missing expected privileges: ${grants_dbz}" ;; esac

# 050's own privilege read-back: the ok line must name every seeded
# table -- order is whatever sync/subsystems.conf lists them in, not
# alphabetical, so check comma-delimited membership (a plain grep for e.g.
# "sample" would also match inside "sample_item") with a case pattern rather
# than lean on a word-boundary regex extension that varies by grep flavor.
has_csv(){ case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; } # HAYSTACK NEEDLE
priv_line_odoo="$(printf '%s\n' "$out1" | grep 'odoo_sink may SELECT/INSERT/UPDATE/DELETE:')"
csv_odoo="${priv_line_odoo#*DELETE: }"
if [ -n "$priv_line_odoo" ] \
  && has_csv "$csv_odoo" res_partner \
  && has_csv "$csv_odoo" product_template \
  && has_csv "$csv_odoo" sale_order; then
  ok "odoo_sink privilege read-back names all 3 seeded tables"
else
  bad "odoo_sink privilege read-back missing or incomplete: ${priv_line_odoo}"
fi
priv_line_clinlims="$(printf '%s\n' "$out1" | grep 'clinlims_sink may SELECT/INSERT/UPDATE/DELETE:')"
csv_clinlims="${priv_line_clinlims#*DELETE: }"
if [ -n "$priv_line_clinlims" ] \
  && has_csv "$csv_clinlims" sample \
  && has_csv "$csv_clinlims" sample_item \
  && has_csv "$csv_clinlims" analysis \
  && has_csv "$csv_clinlims" result; then
  ok "clinlims_sink privilege read-back names all 4 seeded tables"
else
  bad "clinlims_sink privilege read-back missing or incomplete: ${priv_line_clinlims}"
fi

# --- write-proof: prove it as the sink connector would, not just SELECT ----
# has_table_privilege can be true and a write can still fail for reasons the
# privilege check cannot see (search_path, a column-level default owned by
# another role) -- so also actually write. A value that could not be there
# otherwise (memory: presence-is-not-proof-of-sync), inserted then deleted
# over the same network path the login-proof used, as the sink role itself,
# never the superuser. The id is explicit on BOTH tables, res_partner
# included, even though its id is `serial` -- an INSERT that omits id would
# call nextval() on res_partner_id_seq and advance it from NULL to 1, which
# is not a multiple of 10 and would fail the very next run's striding
# assertion (caught live: it did, on the first draft of this test). Naming
# id explicitly bypasses the default entirely, so the sequence this task
# only ever asserts against is never touched by proving the grant.
# container_ip: hub/install/lib.sh's (final review, Minor 20) -- this test
# used to carry a third copy of it, through a bare `docker` rather than `ct`.
pg_write_ok(){ # HOST DB USER PASSWORD SQL
  printf '%s\n' "$4" | docker exec -i -e PWHOST="$1" -e PWDB="$2" -e PWUSER="$3" -e PWSQL="$5" "$PG_C" sh -c \
    'IFS= read -r pw && PGPASSWORD="$pw" psql -h "$PWHOST" -U "$PWUSER" -d "$PWDB" -v ON_ERROR_STOP=1 -q -c "$PWSQL"' 2>&1
}
pg_ip="$(container_ip "$PG_C")"
MARKER="sinkproof-$(gen_secret)"

wout="$(pg_write_ok "$pg_ip" odoo odoo_sink "$ODOO_SINK_PW" \
  "INSERT INTO res_partner (id, name) VALUES (999001, '${MARKER}'); DELETE FROM res_partner WHERE id = 999001;")"
wrc=$?
[ "$wrc" = 0 ] && ok "odoo_sink inserted and deleted a marker row in res_partner over the network" \
  || bad "odoo_sink could not insert+delete a marker row in res_partner: ${wout}"

wout="$(pg_write_ok "$pg_ip" openelis clinlims_sink "$CLINLIMS_SINK_PW" \
  "INSERT INTO clinlims.sample (id, name) VALUES (999001, '${MARKER}'); DELETE FROM clinlims.sample WHERE id = 999001;")"
wrc=$?
[ "$wrc" = 0 ] && ok "clinlims_sink inserted and deleted a marker row in clinlims.sample over the network" \
  || bad "clinlims_sink could not insert+delete a marker row in clinlims.sample: ${wout}"

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
