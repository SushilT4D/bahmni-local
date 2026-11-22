#!/usr/bin/env bash
# Final checks: every page answers and the counters are in range.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "100 · exit checks"
[ "${DRY}" = 1 ] && { info "would: fetch the OpenMRS, OpenELIS and Odoo login pages through ${LAN_NAME}; at seed also run preflight.sh"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a

N="${LAN_NAME}"
O="odoo.${N}"
lan_get(){ # HOST PATH -> body, fetched by name with the name pinned to this machine
  curl -sk -L --max-time 30 --resolve "$1:443:127.0.0.1" "https://$1$2" 2>/dev/null || true
}

lan_code(){ curl -sk -o /dev/null -w '%{http_code}' --max-time 30 --resolve "$1:443:127.0.0.1" "https://$1$2" 2>/dev/null || true; }
lan_get "$N" /openmrs/ws/rest/v1/session | grep -q '"authenticated"' && ok "https://${N}/openmrs answers as OpenMRS" \
  || fail "https://${N}/openmrs does not answer as OpenMRS: ${COMPOSE_CMD} logs proxy openmrs"

elis_boot_s="${OPENELIS_BOOT_TIMEOUT_S:-300}"
elis_up=0
elis_code=""
for i in $(seq 1 $((elis_boot_s / 10))); do
  elis_out="$(curl -sk -L --max-time 30 --resolve "$N:443:127.0.0.1" -w '\n%{http_code}' "https://$N/openelis/" 2>/dev/null || true)"
  elis_code="${elis_out##*$'\n'}"
  elis_body="${elis_out%$'\n'*}"
  if elis_page_ok "$elis_code" "$elis_body"; then elis_up=1; break; fi
  sleep 10
done

if [ "$elis_up" = 1 ]; then ok "https://${N}/openelis answers as OpenELIS"
else
  fail "https://${N}/openelis does not answer as OpenELIS within ${elis_boot_s}s (OPENELIS_BOOT_TIMEOUT_S), last code ${elis_code:-none}: ${COMPOSE_CMD} logs openelis"
fi

odoo_boot_s="${ODOO_BOOT_TIMEOUT_S:-120}"
odoo_up=0
odoo_last_code=""
for i in $(seq 1 $((odoo_boot_s / 10))); do
  odoo_last_code="$(lan_code "$O" /web/login)"; [ "$odoo_last_code" = 200 ] && { odoo_up=1; break; }; sleep 10
done

[ "$odoo_up" = 1 ] || fail "https://${O}/web/login did not answer 200 within ${odoo_boot_s}s (ODOO_BOOT_TIMEOUT_S), last code ${odoo_last_code:-none} -- a 303 to /web/database/selector means config/odoo/odoo.conf is missing or its dbfilter matches more than one database: run scripts/seed-odoo-conf.sh. Otherwise: ${COMPOSE_CMD} logs odoo proxy"
ok "https://${O}/web/login answers 200"

css_path="$(lan_get "$O" /web/login | grep -oE 'href="[^"]*assets_frontend[^"]*\.css"' | head -1 | sed -E 's/href="([^"]*)"/\1/' || true)"
css_code="$(lan_code "$O" "${css_path}")"
[ -n "$css_path" ] && [ "$css_code" = 200 ] && ok "Odoo CSS bundle answers 200 (${css_path})" \
  || fail "Odoo CSS bundle does not answer 200 (path '${css_path:-none found}', code ${css_code:-none}): the login page renders unstyled -- ${COMPOSE_CMD} logs odoo | grep -i asset"
bash scripts/preflight.sh || fail "clinic/scripts/preflight.sh reported a FAIL above"
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
# counter-check:begin
# id counters at or above the seed's floors, read now that the applications
. "${INSTALL_DIR}/state.sh"
ai_of(){ printf "set session information_schema_stats_expiry=0; select auto_increment from information_schema.tables where table_schema='openmrs' and table_name='%s'" "$1" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 || true; }
v="$(counter_floor_verdicts "${REPO_DIR}/sync/tables/openmrs.conf" "${BHS_SITE_NUMBER}" ai_of)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF

# counter-check:end
v="$(capture_filter_check)" || fail "$v"
while IFS= read -r l; do if [ -n "$l" ]; then ok "${l#ok }"; fi; done <<EOF
$v
EOF
v="$(signal_capture_check)" || fail "$v"
ok "${v#ok }"

v="$(clinlims_down_sink_check)" || fail "$v"
ok "${v#ok }"

. "${INSTALL_DIR}/state.sh"

seed_now="$(printf "select property_value from openmrs.global_property where property='order.nextOrderNumberSeed'" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 || true)"
v="$(order_seed_verdict "$seed_now" "${BHS_SITE_NUMBER}")" || fail "$v"
ok "${v#ok }"

# Patient search index: started last, in the background, only when search finds no patient yet.
omrs_api(){ curl -sk --max-time 60 -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "$@"; }
probe="$(printf "select identifier from openmrs.patient_identifier where voided=0 order by patient_identifier_id limit 1" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N' 2>/dev/null || true)"
if [ -n "$probe" ] && has_text "$(omrs_api "https://localhost/openmrs/ws/rest/v1/patient?identifier=${probe}&v=custom:(uuid)" 2>/dev/null || true)" '"uuid"'; then
  skip "OpenMRS search index already finds ${probe}"
else
  code="$(omrs_api -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"async":true}' https://localhost/openmrs/ws/rest/v1/searchindexupdate 2>/dev/null || true)"
  case "$code" in
    2*) ok "OpenMRS search index rebuild started in the background: patient search fills in as it runs (${COMPOSE_CMD} logs openmrs | grep -i index)" ;;
    *)  warn "OpenMRS search index rebuild not started (HTTP ${code:-none}): start it in OpenMRS Administration > Search Index" ;;
  esac
fi
