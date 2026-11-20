#!/usr/bin/env bash
# Final checks: every page answers, the counters are in range, and a test value round-trips through the apps.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "100 · exit checks"
[ "${DRY}" = 1 ] && { info "would: fetch the OpenMRS, OpenELIS and Odoo login pages through ${LAN_NAME}; at seed also run preflight.sh and a marker round-trip"; exit 0; }
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
v="$(counter_floor_verdicts "${REPO_DIR}/sync/tables/openmrs.conf" "${RESIDUE}" ai_of)" || fail "$v"
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
fk_rows="$(clinic_fk_rows "$MY")" || fail "could not read this clinic's foreign keys from MySQL; the database is not answering"
v="$(provenance_fk_verdict "${PROVENANCE_COPY}" "$fk_rows")" || fail "$v"
ok "${v#ok }"

seed_now="$(printf "select property_value from openmrs.global_property where property='order.nextOrderNumberSeed'" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N' 2>/dev/null | tail -1 || true)"
v="$(order_seed_verdict "$seed_now" "${RESIDUE}")" || fail "$v"
ok "${v#ok }"
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"

# probe-row:begin
mark="INSTALL-PROBE-${CLINIC_SLUG}-$(date -u +%Y%m%dT%H%M%SZ)"
probe_id="$(printf "insert into res_partner (name, active, comment, create_date, write_date) values ('Install probe %s', true, '%s', now(), now()) returning id" "${CLINIC_SLUG}" "$mark" | ct exec -i "$PG" psql -U postgres -d odoo -At 2>/dev/null | head -1)"
case "$probe_id" in ''|*[!0-9]*) fail "could not insert the install probe into res_partner (got '${probe_id:-nothing}')" ;; esac
[ $(( probe_id % 10 )) -eq "${RESIDUE}" ] && ok "install probe row ${probe_id} on this node's residue ${RESIDUE}" || fail "install probe row ${probe_id} is not on residue ${RESIDUE}: res_partner_id_seq is not strided for this node"

# probe-row:end
xmlrpc_err="$(mktemp)"
if got="$(python3 - "$mark" "${ODOO_ATOMFEED_USER}" "${ODOO_ATOMFEED_PASSWORD}" "${ODOO_PORT:-8069}" 2>"$xmlrpc_err" <<'PY'
# xmlrpc-marker:begin
# res.partner.comment is an HTML field in Odoo 16: "=" is compared against the
# sanitised form (<p>...</p>) and never matches a value written as plain text,
# so the search uses "like"; the value read back is still compared exactly.
import sys, xmlrpc.client
mark, user, pw, port = sys.argv[1:5]
url = f"http://localhost:{port}"
try:
    uid = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common").authenticate("odoo", user, pw, {})
    rows = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object").execute_kw("odoo", uid, pw, "res.partner", "search_read", [[["comment", "like", mark]]], {"fields": ["comment"], "limit": 1})
    sys.stdout.write((rows[0]["comment"] if rows else "") + "\n")
except Exception as e:
    sys.stderr.write("odoo xml-rpc: %s: %s\n" % (type(e).__name__, str(e)[:200]))
    sys.exit(1)
# xmlrpc-marker:end
PY
)"; then
  rm -f "$xmlrpc_err"
else
  xmlrpc_line="$(cat "$xmlrpc_err")"; rm -f "$xmlrpc_err"
  fail "Odoo XML-RPC did not answer: ${xmlrpc_line:-no output} -- ${COMPOSE_CMD} logs odoo"
fi

check_eq "marker read back through Odoo XML-RPC" "$got" "$mark"
