#!/usr/bin/env bash
# Sets this clinic's id ranges (striding) in MySQL, Odoo and OpenELIS so no two nodes create the same id.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "60 · striding + replication origins (residue ${BHS_SITE_NUMBER})"
if [ "${DRY}" = 1 ]; then
  . "${INSTALL_DIR}/state.sh"
  ft="$(clinlims_floor_tables 2>&1)" || ft="<the down list could not be read: ${ft}>"
  info "would: configure-pk-offsets.sh; lift the obs and orders id counters above the floors recorded in .install-state; set order.nextOrderNumberSeed in this clinic's range; record $(for t in $ft; do printf '%s ' "$(clinlims_floor_key "$t")"; done)in .install-state from each sequence's last value before the stride (kept if already recorded); stride clinlims sequences above their rows (scripts/sql/openelis/apply-sequence-striding.sql) and odoo sequences; apply-replication-origin.sql on odoo and openelis"
  exit 0
fi

setup_compose; cd "${CLINIC_DIR}"
E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
mysql_root(){ ct exec -i "$MY" sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N'; }

. "${INSTALL_DIR}/state.sh"
CLINICS_JSON="${CLINICS_JSON}" MYSQL_CONTAINER="$MY" SEED_MANIFEST="${STATE_FILE}" bash scripts/configure-pk-offsets.sh >/dev/null
inc_off="$(printf 'select @@auto_increment_increment, @@auto_increment_offset' | mysql_root | tr '\t' ' ')"
check_eq "mysql increment/offset" "$inc_off" "10 ${BHS_SITE_NUMBER}"

# seed-counters:begin
. "${INSTALL_DIR}/state.sh"
sc_ai(){ printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1" | mysql_root 2>/dev/null | tail -1 || true; }
for t in ${SEED_COUNTER_TABLES}; do
  fl="$(stamp_get "$(floor_key "$t")")"
  [ -n "$fl" ] || fail "no ${t} floor is recorded on this machine, so its id counter cannot be set above the hub's rows. Rerun the databases step (install.sh ... --from 050) or call the operator."

  # floor-residue:begin
  v="$(seed_floor_residue_verdict "$t" "$fl" "$(seed_floor_residue_sql "$t" "$fl" | mysql_root 2>/dev/null | tail -1 || true)")" || fail "$v"
  ok "${v#ok }"

  # floor-residue:end
  plan="$(seed_counter_plan "$t" "$(sc_ai "$t")" "$fl" "${BHS_SITE_NUMBER}")" || fail "$plan"
  if [ "$plan" != keep ]; then printf 'ALTER TABLE openmrs.`%s` AUTO_INCREMENT = %s;\n' "$t" "${plan#set }" | mysql_root >/dev/null || fail "could not set the ${t} id counter to ${plan#set }: the database did not take the change. Rerun the striding step (install.sh ... --from 060) or call the operator."; fi
  v="$(counter_floor_verdict "$t" "$(sc_ai "$t")" "$fl" "${BHS_SITE_NUMBER}")" || fail "$v"
  if [ "$plan" = keep ]; then ok "${v#ok } (counter already there, unchanged)"; else ok "${v#ok } (counter set to ${plan#set })"; fi
done

# seed-counters:end
# counter-check:begin
. "${INSTALL_DIR}/state.sh"
ai_of(){ printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1" | mysql_root 2>/dev/null | tail -1 || true; }
v="$(counter_floor_verdicts "${REPO_DIR}/sync/tables/openmrs.conf" "${BHS_SITE_NUMBER}" ai_of)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF

# counter-check:end
# order-seed:begin
gp_sql="select concat('v=', coalesce(max(property_value), '')) from openmrs.global_property where property='order.nextOrderNumberSeed'"
gp_read(){ printf '%s' "$gp_sql" | mysql_root 2>/dev/null | tail -1 || true; }
seed_now="$(gp_read)"
case "$seed_now" in v=*) ;; *) fail "could not read order.nextOrderNumberSeed: the database is not answering. Wait a minute and run the same command again; if it persists, call the operator." ;; esac
plan="$(order_seed_plan "${seed_now#v=}" "${BHS_SITE_NUMBER}")" || fail "$plan"
if [ "$plan" != keep ]; then { printf 'use openmrs;\n'; order_seed_sql "${plan#set }"; } | mysql_root; fi
seed_now="$(gp_read)"
v="$(order_seed_verdict "${seed_now#v=}" "${BHS_SITE_NUMBER}")" || fail "$v"
ok "${v#ok }"

# order-seed:end

# clinlims-floors:begin
elis_seq(){ clinlims_seq_sql "$1" | ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -At; }
v="$(record_clinlims_floors elis_seq)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF

# clinlims-floors:end
o="$(ct exec -i "$PG" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -v residue="${BHS_SITE_NUMBER}" -qAt -f /dev/stdin < scripts/sql/openelis/apply-sequence-striding.sql 2>&1)" \
  || fail "the OpenELIS sequences could not be strided above their rows: $(printf '%s\n' "$o" | sed -n 's/^.*ERROR: *//p' | head -1)"
ok "$(printf '%s\n' "$o" | grep '^clinlims sequences step 10' | tail -1)"

ODOO_TABLES="$(subsystem_tables odoo | tr '\n' ',' | sed 's/,$//')"
[ -n "${ODOO_TABLES}" ] || fail "no tables in the [up] section of ${REPO_DIR}/sync/tables/odoo.conf"
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${BHS_SITE_NUMBER}" -v tables="${ODOO_TABLES}" -q -f /dev/stdin < scripts/sql/odoo/apply-odoo-sequence-striding.sql
ct exec -i "$PG" psql -U postgres -d odoo -v residue="${BHS_SITE_NUMBER}" -q -f /dev/stdin < scripts/sql/odoo/apply-master-sequence-striding.sql
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where (schemaname='clinlims') and (increment_by<>10 or last_value %% 10 <> ${BHS_SITE_NUMBER}) limit 3" | ct exec -i "$PG" psql -U postgres -d openelis -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "clinlims sequences: increment 10, residue ${BHS_SITE_NUMBER}" || fail "clinlims sequences off-residue: ${bad}"
bad="$(printf "select sequencename||':'||increment_by||':'||(last_value %% 10) from pg_sequences where sequencename in ('res_partner_id_seq','sale_order_id_seq','product_product_id_seq') and (increment_by<>10 or last_value %% 10 <> ${BHS_SITE_NUMBER})" | ct exec -i "$PG" psql -U postgres -d odoo -At | tr '\n' ' ')"
[ -z "$bad" ] && ok "odoo sequences: increment 10, residue ${BHS_SITE_NUMBER}" || fail "odoo sequences off-residue: ${bad}"

address_seq_bad=""
for seq in village_village_id_seq state_district_id_seq district_subdistrict_id_seq res_partner_attributes_id_seq; do
  inc="$(printf "select increment_by from pg_sequences where sequencename='%s'" "$seq" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
  [ "$inc" = 10 ] || { address_seq_bad="${address_seq_bad} ${seq}(increment_by=${inc:-missing})"; continue; }
  lv="$(printf 'select last_value from public.%s' "$seq" | ct exec -i "$PG" psql -U postgres -d odoo -At)"
  [ -n "$lv" ] && [ $((lv % 10)) -eq "${BHS_SITE_NUMBER}" ] || address_seq_bad="${address_seq_bad} ${seq}(last_value=${lv:-NULL})"
done

[ -z "$address_seq_bad" ] && ok "address odoo sequences: increment 10, residue ${BHS_SITE_NUMBER}" || fail "address odoo sequences off-residue:${address_seq_bad}"

for db in odoo openelis; do ct exec -i "$PG" psql -U postgres -d "$db" -q -f /dev/stdin < scripts/sql/apply-replication-origin.sql >/dev/null; done
origins="$(printf "select count(*) from pg_replication_origin where roname in ('cloud_odoo','cloud_openelis')" | ct exec -i "$PG" psql -U postgres -At)"
[ "${origins:-0}" -eq 2 ] && ok "replication origins cloud_odoo and cloud_openelis" || fail "replication origins missing: ${origins:-0} of cloud_odoo, cloud_openelis"
