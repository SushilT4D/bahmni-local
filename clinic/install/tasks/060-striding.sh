#!/usr/bin/env bash
# phase: seed
# Per-row ownership before the first application write: MySQL striding (server flags are
# set; this moves the captured tables' AUTO_INCREMENT above their floors, and the
# obs and orders counters above the seed's floors whether or not they are
# captured yet), the order-number counter in this clinic's own range,
# Postgres sequences at the residue (mandatory even though the dumps carry
# INCREMENT BY 10 -- the restored last_value sits in Rawach's residue), and the
# replication origins the customizer jar needs.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · striding + replication origins (residue ${RESIDUE})"
[ "${DRY}" = 1 ] && { info "would: configure-pk-offsets.sh; lift the obs and orders id counters above the seed's floors; set order.nextOrderNumberSeed in this clinic's range; stride clinlims + odoo sequences; apply-replication-origin.sql on odoo and openelis"; exit 0; }
setup_compose; mk_podman_shim; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"; PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }

CLINICS_FILE="${LEDGER}" MYSQL_CONTAINER="$MY" SEED_MANIFEST="${SEED_DIR}/manifest.env" bash scripts/configure-pk-offsets.sh >/dev/null
inc_off="$(printf 'select @@auto_increment_increment, @@auto_increment_offset' | mysql_root | tr '\t' ' ')"
check_eq "mysql increment/offset" "$inc_off" "10 ${RESIDUE}"
# seed-counters:begin
# obs and orders: a clinic writes both from its first consultation, whether or
# not sync/local/tables.conf lists them yet, and an id below the seed's floor
# is one the hub's own rows use. Each counter moves to the first id on this
# clinic's residue at or above the floor the seed gate recorded from the
# manifest, and is read back. A manifest without the floor leaves the counter
# as the seed restored it, and says so.
. "${INSTALL_DIR}/state.sh"
sc_ai(){ printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1" | mysql_root 2>/dev/null | tail -1 || true; }
for t in ${SEED_COUNTER_TABLES}; do
  fl="$(stamp_get "$(floor_key "$t")")"
  if [ -z "$fl" ]; then ok "${t} id counter left as the seed restored it: the seed gave no ${t} floor ($(floor_key "$t") is not in its manifest.env)"; continue; fi
  plan="$(seed_counter_plan "$t" "$(sc_ai "$t")" "$fl" "${RESIDUE}")" || fail "$plan"
  if [ "$plan" != keep ]; then printf 'ALTER TABLE openmrs.`%s` AUTO_INCREMENT = %s;\n' "$t" "${plan#set }" | mysql_root >/dev/null || fail "could not set the ${t} id counter to ${plan#set }: the database did not take the change. Rerun the striding step (seed.sh --seed <folder> --from 060) or call the operator."; fi
  v="$(counter_floor_verdict "$t" "$(sc_ai "$t")" "$fl" "${RESIDUE}")" || fail "$v"
  if [ "$plan" = keep ]; then ok "${v#ok } (counter already there, unchanged)"; else ok "${v#ok } (counter set to ${plan#set })"; fi
done
# seed-counters:end
# counter-check:begin
# Read each seed-floored table's counter back rather than trusting the ALTER:
# the next id it issues must be at or above floor + residue. A table list that
# cannot be read fails here rather than checking no table.
. "${INSTALL_DIR}/state.sh"
ai_of(){ printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1" | mysql_root 2>/dev/null | tail -1 || true; }
v="$(counter_floor_verdicts "${REPO_DIR}/sync/local/tables.conf" "${RESIDUE}" ai_of)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF
# counter-check:end
# order-seed:begin
# order numbers: this clinic's own range, set before OpenMRS first starts and
# read back rather than trusting the write
# (the row's value, or empty when the seed lacks the row; no answer at all is a
# database that is not answering, never taken as "absent")
gp_sql="select concat('v=', coalesce(max(property_value), '')) from openmrs.global_property where property='order.nextOrderNumberSeed'"
gp_read(){ printf '%s' "$gp_sql" | mysql_root 2>/dev/null | tail -1 || true; }
seed_now="$(gp_read)"
case "$seed_now" in v=*) ;; *) fail "could not read order.nextOrderNumberSeed: the database is not answering. Wait a minute and run the same command again; if it persists, call the operator." ;; esac
plan="$(order_seed_plan "${seed_now#v=}" "${RESIDUE}")" || fail "$plan"
if [ "$plan" != keep ]; then { printf 'use openmrs;\n'; order_seed_sql "${plan#set }"; } | mysql_root; fi
seed_now="$(gp_read)"
v="$(order_seed_verdict "${seed_now#v=}" "${RESIDUE}")" || fail "$v"
ok "${v#ok }"
# order-seed:end

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
