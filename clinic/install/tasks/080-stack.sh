#!/usr/bin/env bash
# Starts the applications (OpenMRS, Odoo, OpenELIS, proxy), checks the hub logins, then starts odoo-connect last.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · stack"
[ "${DRY}" = 1 ] && { info "would: seed-odoo-conf.sh; fix-mount-ownership.sh; compose --profile local --profile openelis up -d; wait for OpenMRS; park the odoo-connect and OpenELIS feed bookmarks; start OpenMRS's lab-result reader; start odoo-connect"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"

ensure_openmrs_jvm_opts "$E"
set -a; . "$E"; set +a
OM="${COMPOSE_PROJECT_NAME}-openmrs-1"
OD="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
OC="${COMPOSE_PROJECT_NAME}-odoo-connect-1"

bash "${CLINIC_DIR}/scripts/seed-odoo-conf.sh" || fail "seed-odoo-conf.sh reported a FAIL above"

bash "${CLINIC_DIR}/scripts/fix-mount-ownership.sh" || fail "fix-mount-ownership.sh reported a FAIL above"

# forms-guard:begin
. "${INSTALL_DIR}/forms.sh"
v="$(forms_mount_verdict "${FORMS_DIR:-${FORMS_FROZEN_DIR}}" "${FORMS_READ_ONLY:-false}" "${FORMS_REPO_URL:-}")" || fail "$v"
ok "forms: ${v#ok }"
fdir="${FORMS_DIR:-${FORMS_FROZEN_DIR}}"
strict=0; [ -n "${FORMS_REPO_URL:-}" ] && strict=1
forms_rowfile_gate "$fdir" "$strict"

# forms-guard:end
# initializer-guard:begin
. "${INSTALL_DIR}/initializer.sh"
v="$(initializer_domains_verdict "${OPENMRS_INITIALIZER_DOMAINS:-${INITIALIZER_DOMAINS_DEFAULT}}" "${BAHMNI_CONFIG_DIR:-${CLINIC_DIR}/extracted/bahmni_config}")" || fail "$v"
ok "initializer domains: ${v#ok }"

# initializer-guard:end
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local --profile openelis up -d >/dev/null )
ensure_stopped "$OC" && ok "odoo-connect parked until its markers are set" || fail "odoo-connect will not stay stopped: ${COMPOSE_CMD} ps odoo-connect"
url="https://localhost/openmrs/ws/rest/v1/session"

boot_s="${OPENMRS_BOOT_TIMEOUT_S:-3600}"
info "waiting up to $((boot_s/60)) min for OpenMRS through the proxy (first boot: 17 min on Rawach, 36 min on a 1-vCPU VM; OPENMRS_BOOT_TIMEOUT_S overrides)"
rc=0; wait_for_http_or_restart "$url" "$boot_s" "$OM" || rc=$?
case "$rc" in
  0) ok "OpenMRS answers at ${url}" ;;
  2) fail "OpenMRS is crash-looping (its log lines are above): ${COMPOSE_CMD} logs openmrs" ;;
  *) last="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
     if [ "$last" = 302 ]; then
       fail "OpenMRS is still starting after $((boot_s/60)) min (the proxy answers 302, its startup page) -- not a crash. Let it finish, then resume --from 080; a larger OPENMRS_BOOT_TIMEOUT_S waits longer"
     else
       fail "OpenMRS did not answer within $((boot_s/60)) min (last HTTP code: ${last:-none}): ${COMPOSE_CMD} logs openmrs proxy"
     fi ;;
esac

omrs_login(){ # USER PASS -> 0 if OpenMRS authenticates them
  local reply
  reply="$(curl -sk --max-time 20 -u "$1:$2" "$url" 2>/dev/null)" || reply=""
  has_text "$reply" '"authenticated":true'
}

omrs_login "${OPENMRS_ATOMFEED_USER}" "${OPENMRS_ATOMFEED_PASSWORD}" && ok "OpenMRS accepts OPENMRS_ATOMFEED_USER" \
  || fail "OpenMRS refuses the OpenMRS feed user's password in clinic/.env: the hub's credential changed after install. Call the operator (they update OPENMRS_ATOMFEED_PASSWORD in clinic/.env; then run install.sh again)"

odoo_login_ok(){
  python3 - "${ODOO_ATOMFEED_USER}" "${ODOO_ATOMFEED_PASSWORD}" "${ODOO_PORT:-8069}" <<'PY2' 2>/dev/null
import sys, xmlrpc.client
u, p, port = sys.argv[1:4]
try:
    sys.exit(0 if xmlrpc.client.ServerProxy(f"http://localhost:{port}/xmlrpc/2/common").authenticate("odoo", u, p, {}) else 1)
except Exception:
    sys.exit(1)
PY2
}

bash scripts/park-feed-markers.sh || fail "the feed bookmarks were not parked (reason above); odoo-connect is not started"

# The seed carries the hub's password for OpenELIS's feed login; login_user is node-local, so it is set to this node's
# OPENELIS_ATOMFEED_PASSWORD, encrypted by OpenELIS's own phl.util.Crypto (the value its login compares against).
OE="${COMPOSE_PROJECT_NAME}-openelis-1"; oe_user="${OPENELIS_ATOMFEED_USER:-atomfeed}"
enc="$(ct exec -e PW="${OPENELIS_ATOMFEED_PASSWORD}" "$OE" sh -c 'jrunscript -cp /run/bahmni-lab/bahmni-lab/WEB-INF/lib/crypto.jar -e "print(new Packages.phl.util.Crypto().getEncrypt(java.lang.System.getenv(\"PW\")))"' < /dev/null 2>/dev/null | tr -d '\r\n' || true)"
case "$enc" in ''|*[!A-Za-z0-9+/=]*) fail "OpenELIS's phl.util.Crypto in ${OE} did not encrypt OPENELIS_ATOMFEED_PASSWORD (got '${enc}')" ;; esac
have="$(ct exec "$OD" psql -U postgres -d openelis -Atc "select password from clinlims.login_user where login_name = '${oe_user}'" < /dev/null)"
[ -n "$have" ] || fail "OpenELIS has no login_user '${oe_user}' (OPENELIS_ATOMFEED_USER): the seed's openelis database lacks the feed login"
if [ "$have" = "$enc" ]; then skip "OpenELIS login ${oe_user} already has OPENELIS_ATOMFEED_PASSWORD"
else
  ct exec "$OD" psql -U postgres -d openelis -v ON_ERROR_STOP=1 -qc "update clinlims.login_user set password = '${enc}' where login_name = '${oe_user}'" < /dev/null \
    || fail "could not set OpenELIS login ${oe_user}'s password"
  ok "OpenELIS login ${oe_user} set to OPENELIS_ATOMFEED_PASSWORD (the seed held the hub's)"
fi

bash scripts/start-lab-result-reader.sh || fail "OpenMRS's lab-result reader was not started (reason above); odoo-connect is not started"

# res_users is node-local (sync/unsynced-allowlist.conf), so the feed login's password is set to this node's
# ODOO_ATOMFEED_PASSWORD, hashed by Odoo's own passlib context.
ODC="${COMPOSE_PROJECT_NAME}-odoo-1"
up=0; for i in $(seq 1 12); do curl -s --max-time 5 -o /dev/null "http://localhost:${ODOO_PORT:-8069}/web/webclient/version_info" -H 'Content-Type: application/json' -d '{}' && { up=1; break; }; sleep 10; done
[ "$up" = 1 ] || fail "Odoo is not answering on :${ODOO_PORT:-8069}: ${COMPOSE_CMD} logs odoo"
n_user="$(ct exec "$OD" psql -U postgres -d odoo -Atc "select count(*) from res_users where login = '${ODOO_ATOMFEED_USER}' and active" < /dev/null)"
[ "$n_user" = 1 ] || fail "Odoo has no active login '${ODOO_ATOMFEED_USER}' (ODOO_ATOMFEED_USER in clinic/.env)"
if odoo_login_ok; then skip "Odoo login ${ODOO_ATOMFEED_USER} already has ODOO_ATOMFEED_PASSWORD"
else
  hash="$(ct exec -e PW="${ODOO_ATOMFEED_PASSWORD}" "$ODC" python3 -c 'import os; from passlib.context import CryptContext; print(CryptContext(["pbkdf2_sha512"]).hash(os.environ["PW"]))' < /dev/null 2>/dev/null | tr -d '\r\n' || true)"
  case "$hash" in '$pbkdf2-sha512$'*) ;; *) fail "passlib in ${ODC} did not hash ODOO_ATOMFEED_PASSWORD" ;; esac
  ct exec "$OD" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -qc "update res_users set password = '${hash}' where login = '${ODOO_ATOMFEED_USER}'" < /dev/null \
    || fail "could not set Odoo login ${ODOO_ATOMFEED_USER}'s password"
  ok "Odoo login ${ODOO_ATOMFEED_USER} set to ODOO_ATOMFEED_PASSWORD (the seed held the hub's)"
fi
ok_odoo=0; for i in $(seq 1 12); do odoo_login_ok && { ok_odoo=1; break; }; sleep 10; done
[ "$ok_odoo" = 1 ] && ok "Odoo accepts ODOO_ATOMFEED_USER" \
  || fail "Odoo refuses the Odoo feed user's password in clinic/.env (or Odoo is not answering on :${ODOO_PORT:-8069}): the hub's credential may have changed after install. Call the operator"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local up -d odoo-connect >/dev/null )
r0="$(ct inspect --format '{{.RestartCount}}' "$OC" 2>/dev/null || printf 0)"
sleep 120

state="$(ct inspect --format '{{.State.Running}} {{.RestartCount}}' "$OC" 2>/dev/null || printf 'false 0')"
[ "$state" = "true ${r0}" ] || { ct logs --tail 10 "$OC" 2>&1 | sed 's/^/    /' >&2; fail "odoo-connect is not running cleanly two minutes after start (running/restarts: ${state}; its log lines are above)"; }
n="$(ct logs --since 2m "$OC" 2>&1 | grep -c 'Processing event' || true)"
[ "${n:-0}" -lt 50 ] && ok "odoo-connect processed ${n} events in its first two minutes (no replay)" || fail "odoo-connect is replaying: ${n} events in two minutes -- markers did not take"

