#!/usr/bin/env bash
# The node's own proof: preflight green, and a value written that could not
# pre-exist, read back through the application, not a row count.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "100 · exit checks"
[ "${DRY}" = 1 ] && { info "would: run clinic/scripts/preflight.sh; write a marker into res_partner and read it back over XML-RPC"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
bash scripts/preflight.sh || fail "clinic/scripts/preflight.sh reported a FAIL above"
# odoo-connect and the XML-RPC marker below can both look fine against a dead
# Odoo (manpur, 2026-09-21: /var/lib/odoo owned by the wrong uid -- HTTP 500 on
# every request, including XML-RPC, which curl-retries into looking like a
# slow start rather than a permanent failure) -- so prove the login PAGE
# itself answers first. Odoo 16 builds its asset bundle on the first hit, so
# this is retried, not a single probe. ODOO_BOOT_TIMEOUT_S (default 120,
# probed every 10s) names the wait so its own message never drifts from what
# actually ran.
odoo_port="${BAHMNI_ODOO_HTTPS_PORT:-9444}"
odoo_boot_s="${ODOO_BOOT_TIMEOUT_S:-120}"
odoo_up=0; odoo_last_code=""
for i in $(seq 1 $((odoo_boot_s / 10))); do
  odoo_last_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://localhost:${odoo_port}/web/login" 2>/dev/null || true)"
  [ "$odoo_last_code" = 200 ] && { odoo_up=1; break; }
  sleep 10
done
if [ "$odoo_up" = 1 ]; then
  ok "Odoo login page answers 200 on :${odoo_port}"
  # a 200 page with a broken stylesheet looks the same to curl: read the CSS
  # bundle the page names back through the proxy (a seed's bundle rows point
  # at files this node does not have; task 050 drops them)
  css_path="$(curl -sk --max-time 10 "https://localhost:${odoo_port}/web/login" 2>/dev/null | grep -oE 'href="[^"]*assets_frontend[^"]*\.css"' | head -1 | sed -E 's/href="([^"]*)"/\1/')"
  css_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "https://localhost:${odoo_port}${css_path}" 2>/dev/null || true)"
  [ -n "$css_path" ] && [ "$css_code" = 200 ] && ok "Odoo CSS bundle answers 200 (${css_path})" \
    || fail "Odoo CSS bundle does not answer 200 (path '${css_path:-none found}', code ${css_code:-none}): the login page renders unstyled -- ${COMPOSE_CMD} logs odoo | grep -i asset"
else
  # a 303 to /web/database/selector (instead of 200) means config/odoo/odoo.conf
  # is missing, or its dbfilter matches more than one database.
  fail "Odoo login page did not answer 200 on :${odoo_port} within ${odoo_boot_s}s (ODOO_BOOT_TIMEOUT_S), last code ${odoo_last_code:-none} -- a 303 to /web/database/selector means config/odoo/odoo.conf is missing or its dbfilter matches more than one database: run scripts/seed-odoo-conf.sh. Otherwise: ${COMPOSE_CMD} logs odoo"
fi
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
# probe-row:begin
# The probe is a row this node OWNS: an insert takes the next id from the
# strided sequence, so it lands on this node's residue and no other node can
# write the same hub row. An update of the oldest row would touch a legacy
# id every clinic shares, so each clinic's probe would overwrite the last
# one's on the hub. The marker carries the slug so the hub can look for this
# clinic's marker and no other's.
mark="INSTALL-PROBE-${CLINIC_SLUG}-$(date -u +%Y%m%dT%H%M%SZ)"
probe_id="$(printf "insert into res_partner (name, active, comment, create_date, write_date) values ('Install probe %s', true, '%s', now(), now()) returning id" "${CLINIC_SLUG}" "$mark" | ct exec -i "$PG" psql -U postgres -d odoo -At 2>/dev/null | head -1)"
case "$probe_id" in ''|*[!0-9]*) fail "could not insert the install probe into res_partner (got '${probe_id:-nothing}')" ;; esac
[ $(( probe_id % 10 )) -eq "${RESIDUE}" ] && ok "install probe row ${probe_id} on this node's residue ${RESIDUE}" || fail "install probe row ${probe_id} is not on residue ${RESIDUE}: res_partner_id_seq is not strided for this node"
# probe-row:end
# Wrapped so a dead Odoo (HTTP 500, refused connection, auth failure, ...)
# never dumps a 20-line xmlrpc.client.ProtocolError traceback into the log --
# lib.sh's ERR trap already dumped the whole heredoc TWICE the first time
# this broke. Any exception becomes exactly one line on stderr, caught below
# and turned into a single named fail().
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
