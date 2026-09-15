#!/usr/bin/env bash
# L-008 before the first application write: MySQL striding (server flags are
# set; this moves the captured tables' AUTO_INCREMENT above their floors),
# Postgres sequences at the residue (mandatory even though the dumps carry
# INCREMENT BY 10 -- the restored last_value sits in Rawach's residue), and the
# replication origins the customizer jar needs (L-009).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · striding + replication origins (residue ${RESIDUE})"
[ "${DRY}" = 1 ] && { info "would: configure-pk-offsets.sh; stride clinlims + odoo sequences; apply-replication-origin.sql on odoo and openelis"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"; PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }

CLINICS_FILE="${LEDGER}" MYSQL_SERVICE=bahmni-mysql bash scripts/configure-pk-offsets.sh >/dev/null
inc_off="$(printf 'select @@auto_increment_increment, @@auto_increment_offset' | mysql_root | tr '\t' ' ')"
check_eq "mysql increment/offset" "$inc_off" "10 ${RESIDUE}"

ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
DECLARE r record; lv bigint; ns bigint; res int := ${RESIDUE}; n int := 0;
BEGIN
  FOR r IN SELECT schemaname s, sequencename q FROM pg_sequences WHERE schemaname='clinlims' LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO lv;
    ns := ((COALESCE(lv,0) / 10) + 1) * 10 + res;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q, ns);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'strided % clinlims sequences', n;
END \$\$;
SQL
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${RESIDUE}" -q -f /dev/stdin < odoo/apply-odoo-sequence-striding.sql
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${RESIDUE}" -q -f /dev/stdin < odoo/apply-master-sequence-striding.sql
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where (schemaname='clinlims') and (increment_by<>10 or last_value %% 10 <> ${RESIDUE}) limit 3" | ct exec -i "$PG" psql -U postgres -d openelis -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "clinlims sequences: increment 10, residue ${RESIDUE}" || fail "clinlims sequences off-residue: ${bad}"
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where sequencename in ('res_partner_id_seq','sale_order_id_seq','product_product_id_seq') and (increment_by<>10 or last_value %% 10 <> ${RESIDUE})" | ct exec -i "$PG" psql -U postgres -d odoo -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "odoo sequences: increment 10, residue ${RESIDUE}" || fail "odoo sequences off-residue: ${bad}"

for db in odoo openelis; do ct exec -i "$PG" psql -U postgres -d "$db" -q -f /dev/stdin < odoo/apply-replication-origin.sql >/dev/null; done
origins="$(printf "select count(*) from pg_replication_origin where roname like 'hub_%%'" | ct exec -i "$PG" psql -U postgres -At)"
[ "${origins:-0}" -ge 8 ] && ok "replication origins hub_1.. (${origins})" || fail "replication origins missing (${origins})"
