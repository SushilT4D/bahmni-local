#!/usr/bin/env bash
# After the hub adds or changes a lab test: make this clinic's applications
# show it. Run it outside clinic hours; OpenMRS is down while it runs.
#
#   clinic/scripts/refresh-lab-catalogue.sh "<concept name>"
#   clinic/scripts/refresh-lab-catalogue.sh --start-readers
#
# The test's rows reach this clinic's databases by sync, written straight into
# the tables: OpenMRS and OpenELIS do not see a row they did not write until
# they start again (OpenMRS keeps concepts in its cache and finds them through
# a search index that every start rebuilds). In order:
#   1. checks the concept is in this clinic's database by that name (its row
#      has come down); refuses, restarting nothing, when it is not;
#   2. stops odoo-connect and OpenELIS, and proves both stayed down: their
#      queued feed reads would all hit OpenMRS the moment it starts, and a
#      starting OpenMRS flooded that way can run out of memory and restart
#      again and again;
#   3. restarts OpenMRS and waits for its session URL (OPENMRS_RESTART_TIMEOUT_S,
#      default 1800 s; 302 means still starting);
#   4. searches OpenMRS for the concept by name until the search finds it
#      (CONCEPT_SEARCH_TIMEOUT_S, default 2700 s): a search goes through the
#      rebuilt index, so a hit proves a doctor can find the test;
#   5. starts OpenELIS and waits for its login page (OPENELIS_START_TIMEOUT_S,
#      default 900 s);
#   6. starts odoo-connect and checks it is still running, without a restart,
#      ODOO_CONNECT_SETTLE_S later (default 120 s).
# Each wait that runs out prints a FAIL line naming what it last saw. A failure
# in steps 3-4 leaves odoo-connect and OpenELIS stopped (starting them against
# an OpenMRS that is not up would bring the flood back): once OpenMRS answers,
# --start-readers runs steps 5 and 6 alone.
#
# REFRESH_POLL_S sets the pause between two reads of a wait (default 30 s for
# the search, 10 s for OpenELIS). Reads COMPOSE_PROJECT_NAME and the OpenMRS feed login (OPENMRS_ATOMFEED_USER,
# OPENMRS_ATOMFEED_PASSWORD) from clinic/.env; RUNTIME=docker|podman overrides
# the platform's default runtime.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
NAME=""; READERS_ONLY=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --start-readers) READERS_ONLY=1 ;;
  ''|-*) usage >&2; fail "name the concept of the test the hub added or changed, as it is written in OpenMRS: refresh-lab-catalogue.sh \"<concept name>\"" ;;
  *) NAME="$1" ;;
esac
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed clinic"
COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
[ -n "${COMPOSE_PROJECT_NAME}" ] || fail "clinic/.env has no COMPOSE_PROJECT_NAME"
OM_USER="$(env_get "$E" OPENMRS_ATOMFEED_USER)"; OM_PASS="$(env_get "$E" OPENMRS_ATOMFEED_PASSWORD)"
[ -n "${CT:-}" ] || setup_compose
P="${COMPOSE_PROJECT_NAME}"
OM="${P}-openmrs-1"; OE="${P}-openelis-1"; OC="${P}-odoo-connect-1"; MY="${P}-bahmni-mysql-1"
BASE="${PROXY_URL:-https://localhost}"
code_of(){ curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null || true; }
running(){ [ "$(ct inspect --format '{{.State.Running}}' "$1" 2>/dev/null || printf false)" = true ]; }

start_readers(){
  begin_task "start OpenELIS, then odoo-connect"
  running "$OM" || fail "OpenMRS (${OM}) is not running: start the readers only once OpenMRS answers"
  ct start "$OE" >/dev/null 2>&1 || fail "could not start OpenELIS (${OE}): ${COMPOSE_CMD:-compose} ps openelis"
  local s="${OPENELIS_START_TIMEOUT_S:-900}" t0 c=""
  t0="$(date +%s)"
  info "waiting up to $((s/60)) min for the OpenELIS login page (OPENELIS_START_TIMEOUT_S overrides)"
  while [ $(( $(date +%s) - t0 )) -lt "$s" ]; do
    c="$(code_of "${BASE}/openelis/LoginPage.do")"; [ "$c" = 200 ] && break; sleep "${REFRESH_POLL_S:-10}"
  done
  [ "$c" = 200 ] || fail "OpenELIS did not show its login page within $((s/60)) min (last HTTP code: ${c:-none}, container running: $(running "$OE" && echo yes || echo no)); odoo-connect is still stopped. ${COMPOSE_CMD:-compose} logs openelis"
  ok "OpenELIS login page answers after $(( $(date +%s) - t0 ))s"
  local r0 st w="${ODOO_CONNECT_SETTLE_S:-120}"
  r0="$(ct inspect --format '{{.RestartCount}}' "$OC" 2>/dev/null || printf 0)"
  ct start "$OC" >/dev/null 2>&1 || fail "could not start odoo-connect (${OC}): ${COMPOSE_CMD:-compose} ps odoo-connect"
  sleep "$w"
  st="$(ct inspect --format '{{.State.Running}} {{.RestartCount}}' "$OC" 2>/dev/null || printf 'false ?')"
  [ "$st" = "true ${r0}" ] || fail "odoo-connect is not running cleanly ${w}s after its start (running/restarts read '${st}', restarts before '${r0}'): ${COMPOSE_CMD:-compose} logs --tail 20 odoo-connect"
  ok "odoo-connect running, no restart in ${w}s"
}
if [ "$READERS_ONLY" = 1 ]; then start_readers; ok "readers started"; exit 0; fi

begin_task "refresh the lab test catalogue: ${NAME}"
# 1. the concept has come down
esc="$(printf '%s' "$NAME" | sed -e 's/\\/\\\\/g' -e "s/'/''/g")"
n="$(printf "SELECT COUNT(*) FROM openmrs.concept_name WHERE name = '%s' AND voided = 0;\n" "$esc" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B' 2>/dev/null)" \
  || fail "could not read this clinic's concept names in ${MY}: is MySQL running? Nothing was restarted"
[ "${n:-0}" -gt 0 ] 2>/dev/null || fail "no concept named '${NAME}' in this clinic's database: its row has not come down from the hub yet (check the concept sinks: bash scripts/check-sink-tasks.sh), or the name is spelled differently. Nothing was restarted"
ok "the concept '${NAME}' is in this clinic's database (${n} name row(s))"
# 2. the feed readers down, and proven down
ensure_stopped "$OC" || fail "odoo-connect (${OC}) will not stay stopped: ${COMPOSE_CMD:-compose} ps odoo-connect. Nothing else was touched"
ensure_stopped "$OE" || fail "OpenELIS (${OE}) will not stay stopped: ${COMPOSE_CMD:-compose} ps openelis. odoo-connect is stopped; start it again with: bash scripts/refresh-lab-catalogue.sh --start-readers"
ok "odoo-connect and OpenELIS stopped"
# 3. OpenMRS
ct restart "$OM" >/dev/null 2>&1 || fail "could not restart OpenMRS (${OM}); odoo-connect and OpenELIS are stopped: once OpenMRS answers, bash scripts/refresh-lab-catalogue.sh --start-readers"
s="${OPENMRS_RESTART_TIMEOUT_S:-1800}"
info "waiting up to $((s/60)) min for OpenMRS (OPENMRS_RESTART_TIMEOUT_S overrides)"
rc=0; wait_for_http_or_restart "${BASE}/openmrs/ws/rest/v1/session" "$s" "$OM" || rc=$?
case "$rc" in
  0) ok "OpenMRS answers" ;;
  2) fail "OpenMRS is restarting again and again (its log lines are above); odoo-connect and OpenELIS stay stopped. ${COMPOSE_CMD:-compose} logs openmrs" ;;
  *) last="$(code_of "${BASE}/openmrs/ws/rest/v1/session")"
     fail "OpenMRS did not answer within $((s/60)) min (last HTTP code: ${last:-none}$( [ "$last" = 302 ] && printf ', its startup page: still starting')); odoo-connect and OpenELIS stay stopped. Once it answers: bash scripts/refresh-lab-catalogue.sh --start-readers" ;;
esac
# 4. the concept, found by a search
q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$NAME")"
s="${CONCEPT_SEARCH_TIMEOUT_S:-2700}"; t0="$(date +%s)"; seen=""
info "waiting up to $((s/60)) min for OpenMRS's search to find '${NAME}' (the start rebuilds the search index; CONCEPT_SEARCH_TIMEOUT_S overrides)"
found=0
while [ $(( $(date +%s) - t0 )) -lt "$s" ]; do
  reply="$(curl -sk --max-time 30 -u "${OM_USER}:${OM_PASS}" -w '\n%{http_code}' "${BASE}/openmrs/ws/rest/v1/concept?q=${q}&v=custom:(uuid,display)" 2>/dev/null || true)"
  seen="$(printf '%s' "$reply" | python3 -c '
import json, sys
raw = sys.stdin.read(); body, _, code = raw.rpartition("\n")
want = sys.argv[1].casefold()
try:
    res = json.loads(body).get("results", [])
except Exception:
    print("HTTP %s, not a search answer" % (code or "none")); sys.exit(1)
hit = [r for r in res if want in str(r.get("display", "")).casefold()]
print("HTTP %s, %d result(s), %d naming it" % (code, len(res), len(hit)))
sys.exit(0 if hit else 1)' "$NAME")" && { found=1; break; }
  sleep "${REFRESH_POLL_S:-30}"
done
[ "$found" = 1 ] || fail "OpenMRS's search has not found '${NAME}' after $((s/60)) min (last answer: ${seen:-none}); the index may still be rebuilding (${COMPOSE_CMD:-compose} logs openmrs | grep -i index). odoo-connect and OpenELIS are stopped: once the search finds it, bash scripts/refresh-lab-catalogue.sh --start-readers"
ok "OpenMRS's search finds '${NAME}' after $(( $(date +%s) - t0 ))s (${seen})"
# 5-6. the readers
start_readers
ok "lab test catalogue refreshed: '${NAME}' can be ordered, and the lab and billing read their feeds again"
