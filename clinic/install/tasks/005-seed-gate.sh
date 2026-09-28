#!/usr/bin/env bash
# phase: seed
# Everything that can refuse the seed refuses here, before a database is touched.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/state.sh"
. "${INSTALL_DIR}/dns.sh"
begin_task "05 · seed gate"
refuse(){ printf '\n  >>> %s\n\n' "$1" >&2; fail "$1"; }
st="$(stamp_get STATE)"
v="$(stamp_gate_verdict "$st" "$(stamp_get SYNC_STARTED)")" || refuse "$v"
ok "machine state ${st}"
v="$(seed_manifest_verdict "${SEED_DIR}" "$(date +%s)" "${SEED_MAX_AGE_DAYS:-6}")" || refuse "$v"
taken="${v#ok }"
ok "seed taken ${taken} (limit ${SEED_MAX_AGE_DAYS:-6} days); three dumps match their checksums"
v="$(seed_shape_verdict "${SEED_DIR}")" || refuse "$v"
ok "${v#ok }"
name="${LAN_NAME:-bahmni.clinic}"; ip="$(lan_ip)"
v="$(lan_name_verdict "$(lan_resolve "$name")" "$ip" "$name")" || refuse "$v"
ok "${name} resolves to this machine (${ip})"
setup_compose; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"; PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
if [ "$st" = INSTALLED ]; then
  # rows created after install, above the marks install recorded; a missing
  # mark or a database that does not answer yields no number, and the verdict
  # then refuses rather than reading it as zero
  no="$(printf 'select count(*) from openmrs.person where person_id > %s' "$(stamp_get HWM_OPENMRS_PERSON)" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null || true)"
  nd="$(printf 'select count(*) from res_partner where id > %s' "$(stamp_get HWM_ODOO_PARTNER)" | ct exec -i "$PG" psql -U postgres -d odoo -At 2>/dev/null || true)"
  ne="$(printf 'select count(*) from clinlims.sample where id > %s' "$(stamp_get HWM_OPENELIS_SAMPLE)" | ct exec -i "$PG" psql -U postgres -d openelis -At 2>/dev/null || true)"
  v="$(early_data_verdict "$no" "$nd" "$ne" "${DISCARD:-0}")" || refuse "$v"
  case "$v" in discard*) warn "discarding what was entered before seeding: ${v#discard }" ;; *) ok "nothing was entered before seeding" ;; esac
else
  ok "an earlier seed stopped part-way; it is redone from the start"
fi
[ "${DRY}" = 1 ] && { info "would: mark this machine SEEDING"; exit 0; }
stamp_put STATE SEEDING; stamp_put SEEDING_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; stamp_put SEED_TAKEN_AT "$taken"
ok "machine state SEEDING"
