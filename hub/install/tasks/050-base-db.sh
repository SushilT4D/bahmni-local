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
[ "${DRY}" = 1 ] && { info "would: create/converge the mysql sink+debezium users and the postgres odoo_sink/clinlims_sink roles from hub/.env (postgres roles also granted schema/table/sequence/default privileges), prove each over the container network; derive dbz_odoo_owned/dbz_clinlims_owned from sync/subsystems.conf and converge the publications; read back each sink role's privileges with has_schema_privilege/has_table_privilege; apply clinic/odoo/apply-slot-heartbeat.sql to both databases; assert odoo+clinlims sequence striding (increment 10, residue 0); confirm no hub_% replication origin exists"; exit 0; }
setup_compose
[ -f "${HUB_DIR}/.env" ] || fail "${HUB_DIR}/.env not found -- run install.sh, which composes it"
# shellcheck disable=SC1091
set -a; . "${HUB_DIR}/.env"; set +a
MY="$BASE_MYSQL_CONTAINER"; PG="$BASE_PG_CONTAINER"
# ELIS/ELIS_SUPERUSER (Ruling 11): IPLIT's real hub base runs Odoo and
# OpenELIS in two separate Postgres containers with different bootstrap
# superusers (iplit-base-odoodb-1/odoo, iplit-base-openelisdb-1/clinlims);
# the mini and every clinic run one container for both. hub_compose_env
# always defaults BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER from the BASE_PG_*
# values, so the fallback here only matters for an .env composed before this
# key pair existed -- with it, every openelis-database operation below
# collapses back onto $PG/$BASE_PG_SUPERUSER exactly as before.
ELIS="${BASE_ELIS_CONTAINER:-$PG}"; ELIS_SUPERUSER="${BASE_ELIS_SUPERUSER:-$BASE_PG_SUPERUSER}"

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
# for Postgres ERROR CONTEXT lines). mask_env_secrets (hub/install/lib.sh), not
# `sed "s/${SECRET}/.../g"` -- a literal replace can't be broken by a secret
# that happens to contain a sed/regex-special character, "/" (the delimiter)
# included (Fix round 2).
mysql_root(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>&1 | mask_env_secrets REMOTE_MYSQL_PASSWORD DEBEZIUM_DB_PASSWORD; }

ver="$(printf 'select version()' | mysql_root | head -1)"
[ -n "$ver" ] || fail "could not read MySQL version from ${MY}"
ok "base mysql version ${ver}"

# Both MySQL accounts are host-unscoped (@'%'), not pinned to the hub's own
# address: the same convention clinic/install/tasks/050-databases.sh already
# uses for 'debezium'@'%'/'sink'@'%', carried forward rather than tightened
# here.
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
# pg_admin (hub/install/lib.sh) dispatches its CONTAINER/SUPERUSER on the DB
# name it's given -- "openelis" routes to BASE_ELIS_CONTAINER/
# BASE_ELIS_SUPERUSER (Ruling 11: IPLIT's base runs it as a separate Postgres
# container from "odoo"), everything else (odoo, and the bare "postgres"
# maintenance db used nowhere in this file) stays on BASE_PG_CONTAINER/
# BASE_PG_SUPERUSER. Every call site below already passes "odoo" or
# "openelis" as its db argument, so dispatching there routes
# create_pg_sink_role/build_publication/check_sink_privileges/check_sequences
# and the heartbeat calls correctly without touching any of them. Hoisted to
# lib.sh (code review fold-in, Task 6/7 review) so this task and
# 080-sources.sh share one contract instead of each defining a same-named
# function with a different argument shape.
#
# pg_admin_pw DB : like pg_admin, for SQL (on stdin) that carries
# ODOO_SINK_PASSWORD/CLINLIMS_SINK_PASSWORD -- masked the same way mysql_root
# masks the MySQL secrets above (mask_env_secrets, Fix round 2).
pg_admin_pw(){
  pg_admin "$@" 2>&1 | mask_env_secrets ODOO_SINK_PASSWORD CLINLIMS_SINK_PASSWORD
}
# create_pg_sink_role ROLE PASSWORD DB SCHEMA : role create-when-absent +
# password convergence, then the same schema/table/sequence/default-privilege
# grants hub/odoo/create-odoo-sink-role.sh and
# clinic/openelis/create-clinlims-sink-role.sh already give this exact role
# (lines 67-71 and 74-78 respectively) -- the fleet's one convention for a
# sink role, not a hub-specific invention. ALL TABLES/ALL SEQUENCES cover
# what exists today; ALTER DEFAULT PRIVILEGES covers a table added to the
# schema later, so a subsystems.conf addition does not also need a grants
# re-run here. All four GRANTs are idempotent (re-granting an already-held
# privilege is a no-op), so a rerun converges, never errors. PASSWORD is
# escaped (pg_lit_escape) before it is interpolated into the ALTER ROLE
# literal, not used raw (Fix round 2) -- interpolating it raw would let an
# operator-typed password containing "'" break out of the literal.
create_pg_sink_role(){
  local role="$1" pw db="$3" schema="$4"
  pw="$(pg_lit_escape "$2")"
  pg_admin_pw "$db" <<SQL >/dev/null
DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${role}') THEN CREATE ROLE ${role} LOGIN; END IF; END \$\$;
ALTER ROLE ${role} WITH LOGIN PASSWORD '${pw}';
GRANT USAGE ON SCHEMA ${schema} TO ${role};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ${schema} TO ${role};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ${schema} TO ${role};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${schema} GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${role};
SQL
  ok "postgres role ${role} present, password converged, granted on schema ${schema}"
}
create_pg_sink_role odoo_sink "$ODOO_SINK_PASSWORD" odoo public
create_pg_sink_role clinlims_sink "$CLINLIMS_SINK_PASSWORD" openelis clinlims

# pg_login_ok HOST DB USER PASSWORD : same proof as mysql_login_ok, over psql
# -- runs the psql CLIENT from inside the container that actually hosts DB
# (PG for odoo, ELIS for openelis), same dispatch as pg_admin/pg_admin_pw
# above, since in a two-container base the ELIS container is where
# clinlims_sink's role and network path actually live.
pg_login_ok(){
  local ct_name="$PG"
  [ "$2" = openelis ] && ct_name="$ELIS"
  printf '%s\n' "$4" | ct exec -i -e PLHOST="$1" -e PLDB="$2" -e PLUSER="$3" "$ct_name" sh -c \
    'IFS= read -r pw && PGPASSWORD="$pw" psql -h "$PLHOST" -U "$PLUSER" -d "$PLDB" -Atc "select 1"' >/dev/null 2>&1
}
pg_ip="$(container_ip "$PG")"
[ -n "$pg_ip" ] || fail "could not read ${PG}'s network address via ct inspect"
elis_ip="$(container_ip "$ELIS")"
[ -n "$elis_ip" ] || fail "could not read ${ELIS}'s network address via ct inspect"
pg_login_ok "$pg_ip" odoo odoo_sink "$ODOO_SINK_PASSWORD" \
  && ok "postgres odoo_sink@${pg_ip}/odoo authenticates over the network" \
  || fail "postgres odoo_sink@${pg_ip}/odoo did not authenticate"
pg_login_ok "$elis_ip" openelis clinlims_sink "$CLINLIMS_SINK_PASSWORD" \
  && ok "postgres clinlims_sink@${elis_ip}/openelis authenticates over the network" \
  || fail "postgres clinlims_sink@${elis_ip}/openelis did not authenticate"

# --- Publications: derived from sync/subsystems.conf, not hand-copied ------
# subsystem_tables (clinic/install/lib.sh, sourced transitively) is the one
# parser for sync/subsystems.conf's <prefix>:<table> rows -- trims each row,
# strips a trailing comment, skips :all (a topic, not a table), and fails
# naming the row if what is left is not a bare lowercase identifier. This
# task supplies the other half: whether a syntactically-good name actually
# exists as a table in the database today (to_regclass), which is knowledge
# the shared parser has no business having.
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
  local db="$1" prefix="$2" schema="$3" pub="$4" t exists parts="" list="" tables
  # Captured into a variable FIRST, not `for t in $(subsystem_tables "$prefix")`
  # directly (Fix round 2, code review): subsystem_tables runs in the
  # command substitution's OWN subshell, so its fail() (a bad row name) only
  # ends that subshell -- the for-list's word-splitting is not a context
  # `set -e` checks, so the loop would silently run on whatever rows were
  # printed before the bad one and this task would reach its final ok line
  # anyway. A plain assignment's exit status IS what `set -e` checks, so a
  # capture-then-loop propagates the failure correctly.
  tables="$(subsystem_tables "$prefix")"
  for t in $tables; do
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

# --- Privilege read-back: a positive assertion, not a silent GRANT (AL-008) -
# The GRANT statements in create_pg_sink_role succeed even against a role
# that ends up with no matching privilege (a schema typo, the wrong
# search_path) -- GRANT itself never fails that way. Ask Postgres directly,
# per table that actually exists (EXISTING_ODOO_TABLES/EXISTING_CLINLIMS_TABLES,
# the same filtered lists build_publication just computed), and fail naming
# the first table found lacking a privilege rather than the whole set.
check_sink_privileges(){ # ROLE DB SCHEMA TABLES...
  local role="$1" db="$2" schema="$3"; shift 3
  local t schema_ok priv_ok checked="" bad=""
  schema_ok="$(printf "select has_schema_privilege('%s', '%s', 'USAGE')" "$role" "$schema" | pg_admin "$db" -At)"
  [ "$schema_ok" = t ] || fail "${role} lacks USAGE on schema ${schema}"
  for t in "$@"; do
    priv_ok="$(printf "select has_table_privilege('%s', '%s.%s', 'SELECT,INSERT,UPDATE,DELETE')" "$role" "$schema" "$t" | pg_admin "$db" -At)"
    if [ "$priv_ok" = t ]; then
      checked="${checked}${checked:+,}${t}"
    else
      bad="$t"; break
    fi
  done
  [ -z "$bad" ] || fail "${role} lacks SELECT/INSERT/UPDATE/DELETE on ${schema}.${bad}"
  ok "${role} may SELECT/INSERT/UPDATE/DELETE: ${checked}"
}
check_sink_privileges odoo_sink odoo public $EXISTING_ODOO_TABLES
check_sink_privileges clinlims_sink openelis clinlims $EXISTING_CLINLIMS_TABLES

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
# pg_replication_origin is per Postgres INSTANCE, not shared across two
# separate servers -- queried through odoo's own instance (PG) below, and,
# when Ruling 11's two-container base differs (IPLIT's real hub: OpenELIS
# lives on its own Postgres instance, ELIS), through openelis's instance too.
# A single-instance check would silently miss an origin created on the other
# one; the mini and every clinic collapse ELIS back onto PG, so this is a
# no-op there (already proven fit by the one check).
check_no_hub_origins(){ # DB
  local db="$1" origins
  origins="$(printf "select count(*) from pg_replication_origin where roname like 'hub_%%'" | pg_admin "$db" -At)"
  [ "${origins:-0}" = 0 ] && ok "origins: none (hub relays), db=${db}" || fail "hub_% replication origin(s) exist on ${db} (${origins}) -- an origin here would switch the relay off"
}
check_no_hub_origins odoo
[ "$ELIS" != "$PG" ] && check_no_hub_origins openelis

ok "base databases carry the sync identities, publications, heartbeats; striding at residue 0"
