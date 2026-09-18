#!/usr/bin/env bash
# Databases up, seeds restored, sync users created. Roles BEFORE restore so the
# dumps' OWNER TO / GRANT lines resolve; sql_log_bin=0 so the restore is not
# replayed to Kafka (the source connector starts later with snapshot no_data).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "50 · databases + seed"
[ "${DRY}" = 1 ] && { info "would: up bahmni-mysql bahmni-postgres; create roles; restore ${SEED_DIR}/{openmrs,odoo,openelis}.sql.gz; create debezium+sink MySQL users"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"; PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
compose up -d bahmni-mysql bahmni-postgres >/dev/null
# bahmni-mysql has no compose healthcheck; ask each server directly
hm=0; hp=0
for i in $(seq 1 60); do
  mysql_ready "$MY" && hm=1   # authenticated, over TCP: a ping passes against the image's temporary init server
  ct exec "$PG" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 && hp=1   # over TCP: the postgres image's init server listens on the socket only
  [ "$hm" = 1 ] && [ "$hp" = 1 ] && break; sleep 5
done
[ "$hm" = 1 ] && [ "$hp" = 1 ] || fail "databases not answering after 5 min: mysql=$hm postgres=$hp (mysql=0 means no authenticated answer over TCP yet: docker logs ${MY} | tail)"
ok "bahmni-mysql and bahmni-postgres answer"
# the flags must be in Config.Cmd, not only in the compose file (F-007)
ct inspect "$MY" --format '{{.Config.Cmd}}' | grep -q -- "--auto-increment-offset=${RESIDUE}" && ok "mysql runs with --auto-increment-offset=${RESIDUE}" || fail "mysql Config.Cmd lacks --auto-increment-offset=${RESIDUE}"

mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }
psql_pg(){ ct exec -i "$PG" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

# --- MySQL: openmrs
if [ "$(printf 'select count(*) from information_schema.tables where table_schema="openmrs" and table_name="person"' | mysql_root)" = 1 ]; then skip "openmrs schema already restored"; else
  info "restoring openmrs (this is the slow one)"
  ( printf 'SET sql_log_bin=0;\n'; gunzip -c "${SEED_DIR}/openmrs.sql.gz" ) | ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
fi
persons="$(printf 'select count(*) from openmrs.person' | mysql_root)"; obs="$(printf 'select count(*) from openmrs.obs' | mysql_root)"
[ "${persons:-0}" -gt 0 ] && ok "openmrs restored: person=${persons} obs=${obs}" || fail "openmrs.person is empty after restore"
mysql_root <<SQL
CREATE USER IF NOT EXISTS 'debezium'@'%' IDENTIFIED BY '${DEBEZIUM_DB_PASSWORD}';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
CREATE USER IF NOT EXISTS 'sink'@'%' IDENTIFIED BY '${LOCAL_MYSQL_PASSWORD}';
GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.users TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.user_property TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.user_role TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.role TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.role_privilege TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.role_role TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.provider TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.person TO 'sink'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE ON openmrs.person_name TO 'sink'@'%';
FLUSH PRIVILEGES;
SQL
[ "$(printf "select count(*) from mysql.user where user in ('debezium','sink')" | mysql_root)" = 2 ] && ok "mysql users debezium, sink" || fail "mysql users not created"

# --- PostgreSQL: roles, sink roles, databases, restores
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
    gunzip -c "${SEED_DIR}/${db}.sql.gz" | ct exec -i "$PG" psql -U postgres -d "$db" -q 2>&1 | grep -E '^ERROR' | sort | uniq -c | sed 's/^/    restore error: /' || true
  fi
done
# sink roles AFTER the databases exist and are restored: they connect with
# `psql -d odoo` / `-d openelis` and GRANT ON ALL TABLES, so the DBs and their
# tables must exist first (first live clinic, manpur: they ran before createdb).
# Always call these -- they are idempotent (reuse the .env password, CREATE-or-
# ALTER the role). The old `grep .env ||` guard skipped them when the password was
# present, which stranded a node whose earlier run appended the password but failed
# before creating the role (exactly what the create-before-DB bug above caused).
NODE="${CLINIC_SLUG}" PG_CONTAINER="$PG" bash odoo/create-odoo-sink-role.sh "${CLINIC_SLUG}"
NODE="${CLINIC_SLUG}" PG_CONTAINER="$PG" bash openelis/create-clinlims-sink-role.sh "${CLINIC_SLUG}"
partners="$(printf 'select count(*) from res_partner' | ct exec -i "$PG" psql -U postgres -d odoo -At)"
[ "${partners:-0}" -gt 0 ] && ok "odoo restored: res_partner=${partners}" || fail "res_partner is empty after restore"

# Publications are created by the installer, not expected inside the dump (sync-core
# Task 4, 2026-09-17): a dump seeded from the hub (the future seed source) carries no
# publication at all -- staging has 0. The table list is derived at run time from
# sync/subsystems.conf's odoo:/clinlims: rows, the same file the striding SQL (task 060)
# and the MirrorMaker whitelist read, so there is exactly one place that says which
# tables are synced. dbz_heartbeat is deliberately left OUT of this list: task 080 runs
# scripts/apply-slot-heartbeat.sh once Connect is up, and that script creates the
# heartbeat table and ALTER PUBLICATION ... ADD TABLE's it in itself (idempotent, checks
# NOT EXISTS first) -- adding it here too would just mean this ALTER strips it back out
# on the next re-run of this task, only for the heartbeat script to re-add it. One owner
# per piece of the publication.
sync_publication(){ # db  subsystems-prefix  pg-schema  pubname
  local db="$1" prefix="$2" schema="$3" pub="$4" tables t parts=""
  tables="$(subsystem_tables "${prefix}")"
  [ -n "${tables}" ] || fail "no ${prefix}: rows found in ${REPO_DIR}/sync/subsystems.conf"
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
