#!/usr/bin/env bash
# Starts the applications (OpenMRS, Odoo, OpenELIS, proxy), checks the hub logins, then starts odoo-connect last.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · stack"
[ "${DRY}" = 1 ] && { info "would: seed-odoo-conf.sh; fix-mount-ownership.sh; compose --profile local --profile openelis up -d; wait for OpenMRS; park the odoo-connect and OpenELIS feed bookmarks; start OpenMRS's lab-result reader; start odoo-connect; on seed, wait until patient search finds a restored patient"; exit 0; }
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

bash scripts/start-lab-result-reader.sh || fail "OpenMRS's lab-result reader was not started (reason above); odoo-connect is not started"
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

MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
probe="$(printf "select identifier from openmrs.patient_identifier where voided=0 order by patient_identifier_id limit 1" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N' 2>/dev/null || true)"
[ -n "$probe" ] || fail "no patient identifier in openmrs to test patient search with"
search_s="${SEARCH_INDEX_TIMEOUT_S:-2700}"
info "waiting up to $((search_s/60)) min for OpenMRS to index the restored patients (SEARCH_INDEX_TIMEOUT_S overrides)"
t0="$(date +%s)"
found=0
while [ $(( $(date +%s) - t0 )) -lt "$search_s" ]; do
  reply="$(curl -sk --max-time 30 -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "https://localhost/openmrs/ws/rest/v1/patient?identifier=${probe}&v=custom:(uuid)" 2>/dev/null || true)"
  has_text "$reply" '"uuid"' && { found=1; break; }
  sleep 30
done

[ "$found" = 1 ] && ok "patient search finds ${probe} after $(( $(date +%s) - t0 ))s" \
  || fail "patient search still finds nothing for ${probe} after $((search_s/60)) min: OpenMRS has not finished indexing (${COMPOSE_CMD} logs openmrs | grep -i index). Resume with --from 080 once it has"
