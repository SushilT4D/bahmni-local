#!/usr/bin/env bash
# The node's own proof: preflight green, and a value written that could not
# pre-exist, read back through the application (AL-011), not a row count.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "100 · exit checks"
[ "${DRY}" = 1 ] && { info "would: run clinic/scripts/preflight.sh; write a marker into res_partner and read it back over XML-RPC"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
bash scripts/preflight.sh || fail "clinic/scripts/preflight.sh reported a FAIL above"
PG="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
mark="INSTALL-PROBE-$(date -u +%Y%m%dT%H%M%SZ)"
printf "update res_partner set comment='%s' where id=(select min(id) from res_partner where active) returning id" "$mark" | ct exec -i "$PG" psql -U postgres -d odoo -At >/dev/null
got="$(python3 - "$mark" "${ODOO_ATOMFEED_USER}" "${ODOO_ATOMFEED_PASSWORD}" "${ODOO_PORT:-8069}" <<'PY'
import sys, xmlrpc.client
mark, user, pw, port = sys.argv[1:5]
url = f"http://localhost:{port}"
uid = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common").authenticate("odoo", user, pw, {})
rows = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object").execute_kw("odoo", uid, pw, "res.partner", "search_read", [[["comment", "=", mark]]], {"fields": ["comment"], "limit": 1})
print(rows[0]["comment"] if rows else "")
PY
)"
check_eq "marker read back through Odoo XML-RPC" "$got" "$mark"
