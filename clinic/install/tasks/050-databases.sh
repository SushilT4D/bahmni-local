#!/usr/bin/env bash
# Starts MySQL and Postgres, loads each database from the seed unless it is already there, records the id floors, then creates the sync users and publications.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "50 · databases"
[ "${DRY}" = 1 ] && { info "would: up bahmni-mysql bahmni-postgres; restore from ${SEED_DIR:-?} each database that is not there yet; record the obs and orders floors in .install-state (kept if already recorded); create sync users, roles and publications"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
compose up -d bahmni-mysql bahmni-postgres >/dev/null

hm=0
hp=0
for i in $(seq 1 60); do
  mysql_ready "$MY" && hm=1   # authenticated, over TCP: a ping passes against the image's temporary init server
  ct exec "$PG" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 && hp=1   # over TCP: the postgres image's init server listens on the socket only
  [ "$hm" = 1 ] && [ "$hp" = 1 ] && break; sleep 5
done

[ "$hm" = 1 ] && [ "$hp" = 1 ] || fail "databases not answering after 5 min: mysql=$hm postgres=$hp (mysql=0 means no authenticated answer over TCP yet: docker logs ${MY} | tail)"
ok "bahmni-mysql and bahmni-postgres answer"

want_mb="$(sed -nE 's/^innodb_buffer_pool_size *= *([0-9]+)M$/\1/p' "${CLINIC_DIR}/config/mysql/sync-tuning.cnf" 2>/dev/null || true)"
got_b="$(ct exec "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h127.0.0.1 -uroot -N -e "select @@innodb_buffer_pool_size"' 2>/dev/null || echo 0)"
[ -n "$want_mb" ] && [ "$(( ${got_b:-0} / 1048576 ))" -ge "$want_mb" ] && ok "mysql innodb_buffer_pool_size ${want_mb} MB in force (read back from the server)" \
  || fail "mysql buffer pool is $(( ${got_b:-0} / 1048576 )) MB, config/mysql/sync-tuning.cnf says ${want_mb:-?} MB: the conf.d mount is not in force (compose up -d --force-recreate bahmni-mysql)"

ct inspect "$MY" --format '{{.Config.Cmd}}' | grep -q -- "--auto-increment-offset=${RESIDUE}" && ok "mysql runs with --auto-increment-offset=${RESIDUE}" || fail "mysql Config.Cmd lacks --auto-increment-offset=${RESIDUE}"

mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }
psql_pg(){ ct exec -i "$PG" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

# restore-rules:begin

restore_pool_mb(){ mysql_pool_mb "$1"; }   # the node's standing size (lib.sh); the restore adds the redo log and relaxed flush
restore_tune_sql(){ # POOL_MB -- SET GLOBAL only: gone at the next restart, never written to the data directory
  printf 'SET GLOBAL innodb_redo_log_capacity=2147483648; SET GLOBAL innodb_buffer_pool_size=%s; SET GLOBAL innodb_flush_log_at_trx_commit=2; SET GLOBAL sync_binlog=0;\n' "$(( $1 * 1048576 ))"
}

restore_revert_sql(){ # POOL_BYTES REDO_BYTES FLUSH SYNC_BINLOG, as read before tuning
  printf 'SET GLOBAL innodb_flush_log_at_trx_commit=%s; SET GLOBAL sync_binlog=%s; SET GLOBAL innodb_buffer_pool_size=%s; SET GLOBAL innodb_redo_log_capacity=%s;\n' "$3" "$4" "$1" "$2"
}

restore_state(){ # PERSON_EXISTS(0|1) DONE_MARKER(0|1) DB_TABLES DUMP_TABLES -> restore | skip | adopt | interrupted
  if [ "$1" != 1 ]; then echo restore
  elif [ "$2" = 1 ]; then echo skip
  elif [ "${4:-0}" -gt 0 ] && [ "${3:-0}" -ge "$4" ]; then echo adopt
  else echo interrupted; fi
}

definer_sql(){
  { grep -oE 'DEFINER=`[^`]+`@`[^`]+`' || true; } | sort -u \
    | sed -E "s/DEFINER=\`([^\`]+)\`@\`([^\`]+)\`/CREATE USER IF NOT EXISTS '\1'@'\2' ACCOUNT LOCK; GRANT ALL ON openmrs.* TO '\1'@'\2';/"
}

# restore-rules:end
D="${SEED_DIR}"
. "${INSTALL_DIR}/state.sh"

DONE="${CLINIC_DIR}/.openmrs-restore.done"
has_person="$(printf 'select count(*) from information_schema.tables where table_schema="openmrs" and table_name="person"' | mysql_root)"
has_done=0; [ -f "$DONE" ] && has_done=1
db_tables=0
dump_tables=0
if [ "$has_person" = 1 ] && [ "$has_done" = 0 ]; then
  info "openmrs exists with no completion marker; counting the dump's tables to tell a finished restore from an interrupted one (a minute or two)"
  db_tables="$(printf 'select count(*) from information_schema.tables where table_schema="openmrs" and table_type="BASE TABLE"' | mysql_root)"
  dump_tables="$(gunzip -c "${D}/openmrs.sql.gz" | grep -c '^CREATE TABLE ' || true)"
fi

case "$(restore_state "$has_person" "$has_done" "$db_tables" "$dump_tables")" in
  skip) skip "openmrs schema already restored" ;;
  adopt) date -u +%Y-%m-%dT%H:%M:%SZ > "$DONE"; skip "openmrs schema already restored (${db_tables} of ${dump_tables} tables; marker written)" ;;
  interrupted)
    fail "openmrs holds ${db_tables} of the dump's ${dump_tables} tables and has no completion marker: an earlier restore was interrupted. A half-restored database is not dropped automatically. If this node holds nothing you need, drop it yourself and resume: ${CT} exec -i ${MY} sh -c 'mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"drop database openmrs\"'  then --from 050" ;;
  restore)
    mem_mb="$(ct exec "$MY" awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
    pool_mb="$(restore_pool_mb "$mem_mb")"
    before="$(printf 'select concat_ws(" ", @@innodb_buffer_pool_size, @@innodb_redo_log_capacity, @@innodb_flush_log_at_trx_commit, @@sync_binlog)' | mysql_root)"

    # shellcheck disable=SC2086
    revert(){ [ -n "${before:-}" ] && restore_revert_sql $before | mysql_root >/dev/null 2>&1 || true; [ -n "${hb:-}" ] && kill "$hb" 2>/dev/null || true; }
    trap revert EXIT
    restore_tune_sql "$pool_mb" | mysql_root >/dev/null && info "restore settings: buffer pool ${pool_mb} MB (server sees ${mem_mb} MB), redo log 2 GB, relaxed flush -- SET GLOBAL only, put back when the restore ends" \
      || info "could not raise the restore settings (older MySQL?); restoring on the server's own"
    n_def="$(gunzip -c "${D}/openmrs.sql.gz" | definer_sql | tee "${CLINIC_DIR}/.openmrs-definers.sql" | grep -c 'CREATE USER' || true)"
    if [ "${n_def:-0}" -gt 0 ]; then
      { printf 'SET sql_log_bin=0;\n'; cat "${CLINIC_DIR}/.openmrs-definers.sql"; } | mysql_root
      ok "definer accounts the dump names: ${n_def} (locked; they own its triggers and views)"
    fi

    rm -f "${CLINIC_DIR}/.openmrs-definers.sql"
    info "restoring openmrs (this is the slow one: 10 min on an SSD laptop, an hour or more on a small cloud disk)"
    ( while sleep 300; do
        mb="$(printf 'select round(sum(data_length+index_length)/1048576) from information_schema.tables where table_schema="openmrs"' | mysql_root 2>/dev/null || true)"
        printf '  still restoring openmrs: %s MB loaded (%s)\n' "${mb:-?}" "$(date -u +%H:%M:%SZ)"
      done ) &
    hb=$!
    ( printf 'SET sql_log_bin=0;\nCREATE DATABASE IF NOT EXISTS openmrs;\nUSE openmrs;\n'; gunzip -c "${D}/openmrs.sql.gz" ) | ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
    revert; trap - EXIT; hb=""
    date -u +%Y-%m-%dT%H:%M:%SZ > "$DONE"
    ;;
esac

persons="$(printf 'select count(*) from openmrs.person' | mysql_root)"
obs="$(printf 'select count(*) from openmrs.obs' | mysql_root)"
[ "${persons:-0}" -gt 0 ] && ok "openmrs restored: person=${persons} obs=${obs}" || fail "openmrs.person is empty after restore"

# seed-floors:begin
max_id(){ printf 'select ifnull(max(`%s`), 0) from openmrs.`%s`' "$2" "$1" | mysql_root 2>/dev/null | tail -1; }
v="$(record_seed_floors "${REPO_DIR}/sync/tables/openmrs.conf" max_id)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF

# seed-floors:end

printf 'SET sql_log_bin=0; ALTER TABLE openmrs.liquibasechangelog MODIFY ID VARCHAR(255) NOT NULL;\n' | mysql_root
[ "$(printf 'select character_maximum_length from information_schema.columns where table_schema="openmrs" and table_name="liquibasechangelog" and column_name="ID"' | mysql_root)" = 255 ] \
  && ok "openmrs liquibasechangelog.ID is varchar(255)" || fail "could not widen openmrs.liquibasechangelog.ID"

printf "SET sql_log_bin=0; UPDATE openmrs.global_property SET property_value='' WHERE property='search.indexVersion';\n" | mysql_root
[ -z "$(printf "select property_value from openmrs.global_property where property='search.indexVersion'" | mysql_root)" ] \
  && ok "openmrs search index set to rebuild on its next start" || fail "could not clear openmrs search.indexVersion"
# sink-grants:begin
grants="$(sink_grant_sql)" || fail "could not build the sink user's grants from sync/tables/openmrs.conf [down]"
mysql_root <<SQL
CREATE USER IF NOT EXISTS 'debezium'@'%' IDENTIFIED BY '${DEBEZIUM_DB_PASSWORD}';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
CREATE USER IF NOT EXISTS 'sink'@'%' IDENTIFIED BY '${LOCAL_MYSQL_PASSWORD}';
GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO 'sink'@'%';
${grants}
FLUSH PRIVILEGES;
SQL
[ "$(printf "select count(*) from mysql.user where user in ('debezium','sink')" | mysql_root)" = 2 ] && ok "mysql users debezium, sink" || fail "mysql users not created"
missing="$(printf '%s\n' "${SINK_GRANTS_READ_SQL}" | mysql_root | sink_grants_missing)" || fail "could not read back the sink user's grants"
[ -z "$missing" ] && ok "sink user granted on every down table: $(down_tables | tr '\n' ' ')" \
  || fail "the sink user lacks SELECT, INSERT, UPDATE or DELETE on: $(printf '%s' "$missing" | tr '\n' ' ')"

# sink-grants:end
# signal-table:begin
printf '%s;\n%s;\nFLUSH PRIVILEGES;\n' "$(signal_table_ddl)" "$(signal_table_grant)" | mysql_root >/dev/null || fail "could not create $(signal_table_db).debezium_signal or grant the debezium user on it"
v="$(signal_table_read_sql | mysql_root | signal_table_verdict)" || fail "$v"
ok "${v#ok }"

# signal-table:end

psql_pg <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='odoo')     THEN CREATE ROLE odoo     SUPERUSER LOGIN REPLICATION PASSWORD '${ODOO_DB_PASSWORD}'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='clinlims') THEN CREATE ROLE clinlims LOGIN REPLICATION PASSWORD '${OPENELIS_DB_PASSWORD}'; END IF;
  -- The seed dumps carry GRANTs to these sink roles, so they must exist BEFORE the
  -- restore (bare here; the sink-role scripts below set passwords + table grants).
  -- poc_sink appears in the OpenELIS dump but the fleet has no script for it -- a
  -- bare role satisfies the grant. (first live clinic, manpur)
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='odoo_sink')     THEN CREATE ROLE odoo_sink     LOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='clinlims_sink') THEN CREATE ROLE clinlims_sink LOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='poc_sink')      THEN CREATE ROLE poc_sink      LOGIN; END IF;
END \$\$;
ALTER ROLE odoo WITH PASSWORD '${ODOO_DB_PASSWORD}';
ALTER ROLE clinlims WITH PASSWORD '${OPENELIS_DB_PASSWORD}';
SQL
for db in odoo openelis; do
  if [ "$(printf "select count(*) from pg_database where datname='$db'" | ct exec -i "$PG" psql -U postgres -At)" = 1 ]; then skip "database $db exists"; else
    printf 'CREATE DATABASE %s OWNER odoo\n' "$db" | ct exec -i "$PG" psql -U postgres -q
    [ "$db" = openelis ] && printf 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";\n' | ct exec -i "$PG" psql -U postgres -d openelis -q
    gunzip -c "${D}/${db}.sql.gz" | ct exec -i "$PG" psql -U postgres -d "$db" -q 2>&1 | grep -E '^ERROR' | sort | uniq -c | sed 's/^/    restore error: /' || true
  fi
done

# odoo-assets:begin
n="$(printf '%s\n' "delete from ir_attachment where res_model='ir.ui.view' and name like '%assets%'" | ct exec -i "$PG" psql -U postgres -d odoo -At 2>/dev/null | sed -nE 's/^DELETE ([0-9]+)$/\1/p')"
ok "odoo: dropped ${n:-0} asset-bundle attachment row(s) from the seed; Odoo rebuilds them on first request"

# odoo-assets:end
PG_CONTAINER="$PG" bash scripts/create-odoo-sink-role.sh
PG_CONTAINER="$PG" bash scripts/create-clinlims-sink-role.sh

partners="$(printf 'select count(*) from res_partner' | ct exec -i "$PG" psql -U postgres -d odoo -At)"
[ "${partners:-0}" -gt 0 ] && ok "odoo restored: res_partner=${partners}" || fail "res_partner is empty after restore"

sync_publication(){ # db  subsystems-prefix  pg-schema  pubname
  local db="$1" prefix="$2" schema="$3" pub="$4" tables t parts=""
  tables="$(subsystem_tables "${prefix}")"
  [ -n "${tables}" ] || fail "no ${prefix} tables in the [up] section of ${REPO_DIR}/sync/tables/ (odoo.conf or openelis.conf)"
  for t in ${tables}; do parts="${parts}${parts:+, }${schema}.${t}"; done
  ct exec -i "$PG" psql -U postgres -d "${db}" -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '${pub}') THEN
    EXECUTE 'ALTER PUBLICATION ${pub} SET TABLE ${parts}';
  ELSE
    EXECUTE 'CREATE PUBLICATION ${pub} FOR TABLE ${parts}';
  END IF;
END \$\$;
SQL
}

sync_publication odoo odoo public dbz_odoo_owned
sync_publication openelis clinlims clinlims dbz_clinlims_owned

want_odoo="$(subsystem_tables odoo | wc -l | tr -d ' ')"
want_clinlims="$(subsystem_tables clinlims | wc -l | tr -d ' ')"
got_odoo="$(printf "select count(*) from pg_publication_tables where pubname='dbz_odoo_owned'" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
got_clinlims="$(printf "select count(*) from pg_publication_tables where pubname='dbz_clinlims_owned'" | ct exec -i "$PG" psql -U postgres -d openelis -At)"
[ "${got_odoo:-0}" = "${want_odoo}" ] && ok "publication dbz_odoo_owned: ${got_odoo} tables" || fail "publication dbz_odoo_owned: ${got_odoo:-0} tables, want ${want_odoo}"
[ "${got_clinlims:-0}" = "${want_clinlims}" ] && ok "publication dbz_clinlims_owned: ${got_clinlims} tables" || fail "publication dbz_clinlims_owned: ${got_clinlims:-0} tables, want ${want_clinlims}"
