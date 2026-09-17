#!/usr/bin/env bash
# The base stack's databases made fit to be the sync hub: MySQL and Postgres
# accounts the Debezium/JDBC connectors log in as, the two ownership
# publications (derived from sync/subsystems.conf, the one place that says
# which tables are synced), a heartbeat table in each database so an idle
# slot still confirms WAL, and a striding assertion (never a stride -- the
# hub is residue 0 and this task does not touch a sequence's value).
#
# Publications here are UNFILTERED FOR TABLE lists, unlike a clinic's own
# row-filtered publication (id % 10 = residue). That is not an oversight: a
# spoke publishes only the rows it owns so it never re-publishes what it
# received (L-008), but the hub's whole job is to relay everything every
# spoke sent it onward to every other spoke -- per-table filtering would
# silently drop the very rows this layer exists to move (see
# hub/openelis/enable-hub-relay.sql's header for the incident that happens
# when a hub publication IS row-filtered). Replication origins are the same
# story the other way around: a spoke needs one so its own customizer jar can
# tell a replayed write from a local one (L-009), but an origin on the hub
# would make it start filtering its own relay -- so this task creates none
# and asserts none exist.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "50 · base database prerequisites"
[ "${DRY}" = 1 ] && { info "would: create/converge the mysql sink+debezium users and the postgres odoo_sink/clinlims_sink roles from hub/.env, prove each over the container network; derive dbz_odoo_owned/dbz_clinlims_owned from sync/subsystems.conf and converge the publications; apply clinic/odoo/apply-slot-heartbeat.sql to both databases; assert odoo+clinlims sequence striding (increment 10, residue 0); confirm no hub_% replication origin exists"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a
MY="$BASE_MYSQL_CONTAINER"; PG="$BASE_PG_CONTAINER"

# container_ip CONTAINER : its address on whichever docker/podman network(s)
# it is attached to. Used to dial MySQL/Postgres from inside their OWN
# container by IP rather than by "localhost" -- the postgres image's
# pg_hba.conf special-cases 127.0.0.1/::1 as trust regardless of
# POSTGRES_HOST_AUTH_METHOD, so a localhost round-trip would "succeed"
# without ever checking the password we just set. The container's real
# address falls through to the catch-all host line instead, so only that
# path actually exercises the password.
container_ip(){ ct inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" | awk '{print $1}'; }

# --- MySQL: sink + debezium accounts ---------------------------------------
# MYSQL_PWD is expanded by the sh INSIDE the container, from that container's
# own environment -- never by us, so the root password never appears on a
# command line or in this script's own argv. REMOTE_MYSQL_PASSWORD and
# DEBEZIUM_DB_PASSWORD are masked in anything mysql_root prints back: a
# syntax error near a password clause otherwise echoes the clause, secret
# included (the same failure mode create-odoo-sink-role.sh's header records
# for Postgres ERROR CONTEXT lines).
mysql_root(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>&1 | sed "s/${REMOTE_MYSQL_PASSWORD}/<hidden>/g; s/${DEBEZIUM_DB_PASSWORD}/<hidden>/g"; }

ver="$(printf 'select version()' | mysql_root | head -1)"
[ -n "$ver" ] || fail "could not read MySQL version from ${MY}"
ok "base mysql version ${ver}"

{
  mysql_user_sql "$ver" "$REMOTE_MYSQL_USER" "$REMOTE_MYSQL_PASSWORD" "$REMOTE_MYSQL_DATABASE"
  printf "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES, INDEX, ALTER ON %s.* TO '%s'@'%%';\n" "$REMOTE_MYSQL_DATABASE" "$REMOTE_MYSQL_USER"
} | mysql_root >/dev/null
ok "mysql user ${REMOTE_MYSQL_USER} present, granted on ${REMOTE_MYSQL_DATABASE}.*"

{
  mysql_user_sql "$ver" "$DEBEZIUM_DB_USER" "$DEBEZIUM_DB_PASSWORD" '*'
  printf "GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '%s'@'%%';\n" "$DEBEZIUM_DB_USER"
} | mysql_root >/dev/null
ok "mysql user ${DEBEZIUM_DB_USER} present, granted on *.*"

# mysql_login_ok HOST USER PASSWORD : proves USER/PASSWORD authenticate over
# a real TCP round-trip to HOST -- the password travels on this exec's stdin
# (read once inside the container), never as a command-line argument, so it
# never reaches this host's own process list either.
mysql_login_ok(){
  printf '%s\n' "$3" | ct exec -i -e MLHOST="$1" -e MLUSER="$2" "$MY" sh -c \
    'IFS= read -r pw && MYSQL_PWD="$pw" mysql -h "$MLHOST" -u "$MLUSER" -N -e "select 1"' >/dev/null 2>&1
}
my_ip="$(container_ip "$MY")"
[ -n "$my_ip" ] || fail "could not read ${MY}'s network address via ct inspect"
mysql_login_ok "$my_ip" "$REMOTE_MYSQL_USER" "$REMOTE_MYSQL_PASSWORD" \
  && ok "mysql ${REMOTE_MYSQL_USER}@${my_ip} authenticates over the network" \
  || fail "mysql ${REMOTE_MYSQL_USER}@${my_ip} did not authenticate"
mysql_login_ok "$my_ip" "$DEBEZIUM_DB_USER" "$DEBEZIUM_DB_PASSWORD" \
  && ok "mysql ${DEBEZIUM_DB_USER}@${my_ip} authenticates over the network" \
  || fail "mysql ${DEBEZIUM_DB_USER}@${my_ip} did not authenticate"

# --- Postgres: sink roles ---------------------------------------------------
# pg_admin DB ARGS... : psql as the base Postgres superuser, script on stdin,
# no masking -- reserved for SQL that carries no secret.
pg_admin(){ local db="$1"; shift; ct exec -i "$PG" psql -U "$BASE_PG_SUPERUSER" -d "$db" -v ON_ERROR_STOP=1 -q "$@"; }
# pg_admin_pw DB : like pg_admin, for SQL (on stdin) that carries
# ODOO_SINK_PASSWORD/CLINLIMS_SINK_PASSWORD -- masked the same way mysql_root
# masks the MySQL secrets above.
pg_admin_pw(){
  ct exec -i "$PG" psql -U "$BASE_PG_SUPERUSER" -d "$1" -v ON_ERROR_STOP=1 -q 2>&1 \
    | sed "s/${ODOO_SINK_PASSWORD}/<hidden>/g; s/${CLINLIMS_SINK_PASSWORD}/<hidden>/g"
}
create_pg_sink_role(){ # ROLE PASSWORD DB
  local role="$1" pw="$2" db="$3"
  printf "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') THEN CREATE ROLE %s LOGIN; END IF; END \$\$;\nALTER ROLE %s WITH LOGIN PASSWORD '%s';\n" \
    "$role" "$role" "$role" "$pw" | pg_admin_pw "$db" >/dev/null
  ok "postgres role ${role} present, password converged"
}
create_pg_sink_role odoo_sink "$ODOO_SINK_PASSWORD" odoo
create_pg_sink_role clinlims_sink "$CLINLIMS_SINK_PASSWORD" openelis

# pg_login_ok HOST DB USER PASSWORD : same proof as mysql_login_ok, over psql.
pg_login_ok(){
  printf '%s\n' "$4" | ct exec -i -e PLHOST="$1" -e PLDB="$2" -e PLUSER="$3" "$PG" sh -c \
    'IFS= read -r pw && PGPASSWORD="$pw" psql -h "$PLHOST" -U "$PLUSER" -d "$PLDB" -Atc "select 1"' >/dev/null 2>&1
}
pg_ip="$(container_ip "$PG")"
[ -n "$pg_ip" ] || fail "could not read ${PG}'s network address via ct inspect"
pg_login_ok "$pg_ip" odoo odoo_sink "$ODOO_SINK_PASSWORD" \
  && ok "postgres odoo_sink@${pg_ip}/odoo authenticates over the network" \
  || fail "postgres odoo_sink@${pg_ip}/odoo did not authenticate"
pg_login_ok "$pg_ip" openelis clinlims_sink "$CLINLIMS_SINK_PASSWORD" \
  && ok "postgres clinlims_sink@${pg_ip}/openelis authenticates over the network" \
  || fail "postgres clinlims_sink@${pg_ip}/openelis did not authenticate"

# --- Publications: derived from sync/subsystems.conf, not hand-copied ------
SUBSYSTEMS="${REPO_DIR}/sync/subsystems.conf"
[ -f "$SUBSYSTEMS" ] || fail "sync/subsystems.conf not found at ${SUBSYSTEMS}"
# subsystem_tables PREFIX : the <prefix>:<table> rows, :all (a topic, not a
# table) excluded -- same filter clinic/install/tasks/050-databases.sh and
# 060-striding.sh apply to the same file, so there is exactly one place that
# says which tables are synced.
subsystem_tables(){ grep -E "^$1:" "$SUBSYSTEMS" | grep -v ':all$' | cut -d: -f2; }

EXISTING_ODOO_TABLES=""; EXISTING_CLINLIMS_TABLES=""
# build_publication DB PREFIX SCHEMA PUBNAME : the publication's FOR TABLE
# list is the configured tables that actually exist in DB today
# (to_regclass) -- a table not yet created (an Odoo 16 rename still pending
# on this base stack, say) is skipped with a WARN, never a hard failure,
# because the base stack's own schema is not this task's to fix; only an
# EMPTY result (nothing configured exists) is. Sets
# EXISTING_ODOO_TABLES/EXISTING_CLINLIMS_TABLES (space-separated, existing
# tables only) as a side effect, so the striding check below asks "does this
# table exist" once, not twice.
build_publication(){
  local db="$1" prefix="$2" schema="$3" pub="$4" t exists parts="" list=""
  for t in $(subsystem_tables "$prefix"); do
    exists="$(printf "select (to_regclass('%s.%s') is not null)" "$schema" "$t" | pg_admin "$db" -At)"
    if [ "$exists" = t ]; then
      parts="${parts}${parts:+, }${schema}.${t}"; list="${list}${list:+ }${t}"
    else
      warn "publication ${pub}: ${schema}.${t} does not exist in ${db} -- skipped"
    fi
  done
  [ -n "$parts" ] || fail "publication ${pub}: none of the configured ${prefix}: tables exist in ${db}"
  printf "DO \$\$\nBEGIN\n  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '%s') THEN\n    EXECUTE 'ALTER PUBLICATION %s SET TABLE %s';\n  ELSE\n    EXECUTE 'CREATE PUBLICATION %s FOR TABLE %s';\n  END IF;\nEND \$\$;\n" \
    "$pub" "$pub" "$parts" "$pub" "$parts" | pg_admin "$db" >/dev/null
  got="$(printf "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = '%s'" "$pub" | pg_admin "$db" -At)"
  ok "publication ${pub} carries: ${got}"
  case "$pub" in
    dbz_odoo_owned)     EXISTING_ODOO_TABLES="$list" ;;
    dbz_clinlims_owned) EXISTING_CLINLIMS_TABLES="$list" ;;
  esac
}
build_publication odoo odoo public dbz_odoo_owned
build_publication openelis clinlims clinlims dbz_clinlims_owned

# --- Heartbeat: idle-slot WAL confirmation, both databases -----------------
# clinic/odoo/apply-slot-heartbeat.sql stays where it is (shared with the
# clinic installer); this task references it by path. It adds dbz_heartbeat
# to the publication itself (ALTER PUBLICATION ... ADD TABLE, idempotent) --
# run AFTER build_publication above so that ADD lands on the converged list,
# not one this task's own SET TABLE would immediately strip back out. Its
# own last statement is the read-back proof: "<pub> now carries: ...".
HEARTBEAT_SQL="${REPO_DIR}/clinic/odoo/apply-slot-heartbeat.sql"
[ -f "$HEARTBEAT_SQL" ] || fail "clinic/odoo/apply-slot-heartbeat.sql not found at ${HEARTBEAT_SQL}"
pg_admin odoo     -v s=public    -v r=odoo     -v p=dbz_odoo_owned     -f /dev/stdin < "$HEARTBEAT_SQL"
pg_admin openelis -v s=clinlims  -v r=clinlims -v p=dbz_clinlims_owned -f /dev/stdin < "$HEARTBEAT_SQL"

# --- Striding: assert only, never stride ------------------------------------
# The hub is residue 0: every synced sequence must already carry increment
# 10 and a last_value that is a multiple of 10 (or NULL -- never used, which
# is a pass, not a violation). This task does not fix a violation, because
# striding an already-written hub is a data-moving operation (F-061's
# business), not a prerequisite-check's.
SEQ_REPORT=""; SEQ_BAD=""
check_sequences(){ # DB SCHEMA MODE TABLES...
  local db="$1" schema="$2" mode="$3"; shift 3
  local t seqname row inc last
  for t in "$@"; do
    if [ "$mode" = odoo ]; then
      # Odoo ids carry a nextval() default; pg_get_serial_sequence resolves
      # the real owning sequence (not always <table>_id_seq -- inherited or
      # renamed tables differ). NULL means no serial default at all.
      seqname="$(printf "select pg_get_serial_sequence('%s.%s','id')" "$schema" "$t" | pg_admin "$db" -At)"
      if [ -z "$seqname" ]; then SEQ_BAD="${SEQ_BAD} ${schema}.${t}(no serial sequence on id)"; continue; fi
      seqname="${seqname##*.}"
    else
      # OpenELIS assigns ids in Hibernate: the id columns have no default, so
      # there is no serial sequence to resolve -- the sequence is the named
      # <table>_seq Module 28's striding SQL created directly.
      seqname="${t}_seq"
    fi
    row="$(printf "select increment_by || '|' || coalesce(last_value::text,'NULL') from pg_sequences where schemaname = '%s' and sequencename = '%s'" "$schema" "$seqname" | pg_admin "$db" -At)"
    if [ -z "$row" ]; then SEQ_BAD="${SEQ_BAD} ${schema}.${seqname}(missing)"; continue; fi
    inc="${row%%|*}"; last="${row#*|}"
    [ "$inc" = 10 ] || SEQ_BAD="${SEQ_BAD} ${schema}.${seqname}(increment_by=${inc})"
    if [ "$last" != NULL ] && [ $((last % 10)) -ne 0 ]; then SEQ_BAD="${SEQ_BAD} ${schema}.${seqname}(last_value=${last})"; fi
    SEQ_REPORT="${SEQ_REPORT}${SEQ_REPORT:+, }${schema}.${seqname}:incr=${inc}/last=${last}"
  done
}
check_sequences odoo public odoo $EXISTING_ODOO_TABLES
check_sequences openelis clinlims clinlims $EXISTING_CLINLIMS_TABLES
[ -z "$SEQ_BAD" ] && ok "sequence striding (residue 0): ${SEQ_REPORT}" || fail "sequence striding violations:${SEQ_BAD}"

# --- Replication origins: none, on purpose ----------------------------------
origins="$(printf "select count(*) from pg_replication_origin where roname like 'hub_%%'" | pg_admin odoo -At)"
[ "${origins:-0}" = 0 ] && ok "origins: none (hub relays)" || fail "hub_% replication origin(s) exist on the hub (${origins}) -- an origin here would switch the relay off"

ok "base databases carry the sync identities, publications, heartbeats; striding at residue 0"
