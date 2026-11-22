#!/usr/bin/env bash
# Checks Odoo end to end on this node: inserts a partner into Odoo's database, checks its id is on this
# node's residue, then reads it back through Odoo's XML-RPC API as ODOO_ATOMFEED_USER.
# Writes one res_partner row ("Odoo round-trip check <slug>") per run; it is this node's own row and syncs to the hub.
# Usage: scripts/check-odoo-roundtrip.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
CT="${CONTAINER_TOOL:-podman}"

ok(){   printf '  ok   %s\n' "$*"; }
fail(){ printf '  FAIL %s\n' "$*" >&2; exit 1; }

env_get(){ # KEY -> its value in ENV_FILE, quotes removed
  local v
  v="$({ grep -E "^$1=" "${ENV_FILE}" || true; } | head -1 | cut -d= -f2-)"
  case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
  printf '%s' "$v"
}

[ -f "${ENV_FILE}" ] || fail "no ${ENV_FILE}"
SLUG="$(env_get BHS_LOCATION)"
BHS_SITE_NUMBER="$(env_get BHS_SITE_NUMBER)"
USER_="$(env_get ODOO_ATOMFEED_USER)"
PW="$(env_get ODOO_ATOMFEED_PASSWORD)"
PORT="$(env_get ODOO_PORT)"; PORT="${PORT:-8069}"
PG=bahmni-bahmni-postgres-1
for k in SLUG BHS_SITE_NUMBER USER_ PW; do [ -n "${!k}" ] || fail "${k%_} is not set in ${ENV_FILE}"; done

mark="ODOO-ROUNDTRIP-${SLUG}-$(date -u +%Y%m%dT%H%M%SZ)"
id="$(printf "insert into res_partner (name, active, comment, create_date, write_date) values ('Odoo round-trip check %s', true, '%s', now(), now()) returning id" "$SLUG" "$mark" \
  | "$CT" exec -i "$PG" psql -U postgres -d odoo -At 2>/dev/null | head -1 || true)"
case "$id" in ''|*[!0-9]*) fail "could not insert the check row into res_partner in ${PG} (got '${id:-nothing}')" ;; esac
[ $(( id % 10 )) -eq "$BHS_SITE_NUMBER" ] && ok "row ${id} is on this node's residue ${BHS_SITE_NUMBER}" \
  || fail "row ${id} is not on residue ${BHS_SITE_NUMBER}: res_partner_id_seq is not strided for this node"

# res.partner.comment is an HTML field in Odoo 16: "=" compares against the sanitised form (<p>...</p>), so the
# search uses "like"; the value read back is compared exactly.
got="$(python3 - "$mark" "$USER_" "$PW" "$PORT" <<'PY'
import sys, xmlrpc.client
mark, user, pw, port = sys.argv[1:5]
url = f"http://localhost:{port}"
try:
    uid = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common").authenticate("odoo", user, pw, {})
    if not uid:
        sys.stderr.write(f"Odoo refuses the login {user}\n"); sys.exit(1)
    rows = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object").execute_kw("odoo", uid, pw, "res.partner", "search_read", [[["comment", "like", mark]]], {"fields": ["comment"], "limit": 1})
    print(rows[0]["comment"] if rows else "")
except Exception as e:
    sys.stderr.write("odoo xml-rpc: %s: %s\n" % (type(e).__name__, str(e)[:200])); sys.exit(1)
PY
)" || fail "Odoo XML-RPC on :${PORT} did not answer (reason above)"

case "$got" in *"$mark"*) ok "read back through Odoo XML-RPC as ${USER_}: ${mark}" ;;
  *) fail "Odoo XML-RPC returned '${got}', not ${mark}" ;; esac
