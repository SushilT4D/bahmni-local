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
  ct exec "$MY" sh -c 'mysqladmin -uroot -p"$MYSQL_ROOT_PASSWORD" ping' >/dev/null 2>&1 && hm=1
  ct exec "$PG" pg_isready -U postgres >/dev/null 2>&1 && hp=1
  [ "$hm" = 1 ] && [ "$hp" = 1 ] && break; sleep 5
done
[ "$hm" = 1 ] && [ "$hp" = 1 ] || fail "databases not answering after 5 min: mysql=$hm postgres=$hp"
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
grep -q '^ODOO_SINK_PASSWORD=' "$E"     || NODE="${CLINIC_SLUG}" PG_CONTAINER="$PG" bash odoo/create-odoo-sink-role.sh "${CLINIC_SLUG}" >/dev/null
grep -q '^CLINLIMS_SINK_PASSWORD=' "$E" || NODE="${CLINIC_SLUG}" PG_CONTAINER="$PG" bash openelis/create-clinlims-sink-role.sh "${CLINIC_SLUG}" >/dev/null
partners="$(printf 'select count(*) from res_partner' | ct exec -i "$PG" psql -U postgres -d odoo -At)"
pubs="$(printf "select string_agg(pubname, ',') from pg_publication" | ct exec -i "$PG" psql -U postgres -d openelis -At),$(printf "select string_agg(pubname, ',') from pg_publication" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
[ "${partners:-0}" -gt 0 ] && ok "odoo restored: res_partner=${partners}" || fail "res_partner is empty after restore"
printf '%s' "$pubs" | grep -q dbz_clinlims_owned && printf '%s' "$pubs" | grep -q dbz_odoo_owned && ok "publications: ${pubs}" || fail "publications missing (got: ${pubs}); the dumps should carry dbz_clinlims_owned and dbz_odoo_owned"
