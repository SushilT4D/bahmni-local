#!/usr/bin/env bash
# Per-row ownership before the first application write: MySQL striding (server flags are
# set; this moves the captured tables' AUTO_INCREMENT above their floors),
# Postgres sequences at the residue (mandatory even though the dumps carry
# INCREMENT BY 10 -- the restored last_value sits in Rawach's residue), and the
# replication origins the customizer jar needs.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · striding + replication origins (residue ${RESIDUE})"
[ "${DRY}" = 1 ] && { info "would: configure-pk-offsets.sh; stride clinlims + odoo sequences; apply-replication-origin.sql on odoo and openelis"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"; PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }

CLINICS_FILE="${LEDGER}" MYSQL_CONTAINER="$MY" bash scripts/configure-pk-offsets.sh >/dev/null
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
# Same table list the publication and MirrorMaker whitelist use (sync/subsystems.conf's
# odoo: rows, the :all aggregate row excluded, trimmed and validated by subsystem_tables)
# -- one source of truth, passed to the SQL as a comma-separated psql variable rather
# than duplicated as a second hard-coded array.
ODOO_TABLES="$(subsystem_tables odoo | tr '\n' ',' | sed 's/,$//')"
[ -n "${ODOO_TABLES}" ] || fail "no odoo: rows found in ${REPO_DIR}/sync/subsystems.conf"
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${RESIDUE}" -v tables="${ODOO_TABLES}" -q -f /dev/stdin < odoo/apply-odoo-sequence-striding.sql
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${RESIDUE}" -q -f /dev/stdin < odoo/apply-master-sequence-striding.sql
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where (schemaname='clinlims') and (increment_by<>10 or last_value %% 10 <> ${RESIDUE}) limit 3" | ct exec -i "$PG" psql -U postgres -d openelis -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "clinlims sequences: increment 10, residue ${RESIDUE}" || fail "clinlims sequences off-residue: ${bad}"
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where sequencename in ('res_partner_id_seq','sale_order_id_seq','product_product_id_seq') and (increment_by<>10 or last_value %% 10 <> ${RESIDUE})" | ct exec -i "$PG" psql -U postgres -d odoo -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "odoo sequences: increment 10, residue ${RESIDUE}" || fail "odoo sequences off-residue: ${bad}"

# The four address and attribute id sequences (village_village, state_district,
# district_subdistrict, res_partner_attributes) get RESTART WITH'd by the SQL
# above but, on a fresh clinic, are never nextval()'d before this task runs --
# so pg_sequences.last_value reads NULL (is_called=false) even though the
# RESTART value IS set. So the check reads last_value and is_called from the
# sequence itself (a direct select does not consume nextval).
# increment_by is safe to read from pg_sequences either way; the
# residue has to come from the sequence object itself, which reports the
# internal counter regardless of is_called.
address_seq_bad=""
for seq in village_village_id_seq state_district_id_seq district_subdistrict_id_seq res_partner_attributes_id_seq; do
  inc="$(printf "select increment_by from pg_sequences where sequencename='%s'" "$seq" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
  [ "$inc" = 10 ] || { address_seq_bad="${address_seq_bad} ${seq}(increment_by=${inc:-missing})"; continue; }
  lv="$(printf 'select last_value from public.%s' "$seq" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
  [ -n "$lv" ] && [ $((lv % 10)) -eq "${RESIDUE}" ] || address_seq_bad="${address_seq_bad} ${seq}(last_value=${lv:-NULL})"
done
[ -z "$address_seq_bad" ] && ok "address odoo sequences: increment 10, residue ${RESIDUE}" || fail "address odoo sequences off-residue:${address_seq_bad}"

for db in odoo openelis; do ct exec -i "$PG" psql -U postgres -d "$db" -q -f /dev/stdin < odoo/apply-replication-origin.sql >/dev/null; done
origins="$(printf "select count(*) from pg_replication_origin where roname like 'hub_%%'" | ct exec -i "$PG" psql -U postgres -At)"
[ "${origins:-0}" -ge 8 ] && ok "replication origins hub_1.. (${origins})" || fail "replication origins missing (${origins})"
