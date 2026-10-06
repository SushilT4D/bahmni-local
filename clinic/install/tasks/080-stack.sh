#!/usr/bin/env bash
# phase: both
# The application stack. odoo-connect is started LAST and only after its
# atom-feed markers are parked at the head of each feed: the seed carries the
# event_records that made Rawach replay ~303k events through the hub.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · stack"
[ "${DRY}" = 1 ] && { info "would: seed-odoo-conf.sh; fix-mount-ownership.sh; compose --profile local --profile openelis up -d; wait for OpenMRS; park odoo-connect markers; start odoo-connect; on seed, wait until patient search finds a restored patient"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"
# BEFORE sourcing .env: compose gives an exported shell variable precedence over
# the file, so a stale export here would hide the repaired value from `up`.
ensure_openmrs_jvm_opts "$E"
set -a; . "$E"; set +a
OM="${COMPOSE_PROJECT_NAME}-openmrs-1"; OD="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"; OC="${COMPOSE_PROJECT_NAME}-odoo-connect-1"
# The clinic mounts CONTAINER_DATA_PATH/config/odoo read-write at /etc/odoo;
# task 030 creates it empty, which hides the odoo image's OWN odoo.conf (no
# db_name, no addons_path -- /web/login 303s to /web/database/selector rather
# than answering 200, fix-round-1 review vs. staging). Seed it BEFORE the
# ownership sweep below, so the file this creates gets chowned along with the
# rest of config/odoo rather than needing its own pass.
bash "${CLINIC_DIR}/scripts/seed-odoo-conf.sh" || fail "seed-odoo-conf.sh reported a FAIL above"
# Odoo answered HTTP 500 on every request on manpur: its image
# runs as uid 101, task 030 makes this node's bind-mount data dirs with a
# plain mkdir -p (owned by the login user), and uid 101 could not write
# /var/lib/odoo/.local. Kafka/kafka-connect/mirrormaker-connect are the same
# class of defect (a non-1000 image uid), so they are swept here too, once,
# before anything in this profile set is started -- images are present since
# task 040, and every directory this sweeps already exists since task 030, so
# one call here also covers what 090 starts later (kafka,
# kafka-connect, mirrormaker-connect: no separate call there).
bash "${CLINIC_DIR}/scripts/fix-mount-ownership.sh" || fail "fix-mount-ownership.sh reported a FAIL above"
# forms-guard:begin
# OpenMRS mounts the forms folder (FORMS_DIR, FORMS_MOUNT_MODE; forms.sh). A
# missing source would be created empty by the runtime and every form would
# fail to open, so the stack does not start until task 075 has set it up, and
# a node with a forms repo runs only from that repo's clone, read-only. At
# seed, every published form row in the restored database must find its file.
. "${INSTALL_DIR}/forms.sh"
fdir="${FORMS_DIR:-${FORMS_FROZEN_DIR}}"; fmode="${FORMS_MOUNT_MODE:-rw}"
case "$fmode" in ro|rw) ;; *) fail "clinic/.env FORMS_MOUNT_MODE is '${fmode}'; it is ro or rw (task 075 sets it)" ;; esac
if [ -n "${FORMS_REPO_URL:-}" ] && { [ "$fdir" != "$(forms_folder_for "${FORMS_REPO_URL}")" ] || [ "$fmode" != ro ]; }; then
  fail "clinic/.env names a forms repo, but the forms mount is ${fdir} (${fmode}), not its clone's $(forms_folder_for "${FORMS_REPO_URL}") (ro): task 075 sets both, run it again (resume --from 075)"
fi
v="$(forms_folder_verdict "$fdir")" || fail "$v"
ok "forms: ${v#ok } (mounted ${fmode})"
if [ "${PHASE:-install}" = seed ]; then
  strict=0; [ -n "${FORMS_REPO_URL:-}" ] && strict=1
  forms_rowfile_gate "$fdir" "$strict"
fi
# forms-guard:end
# initializer-guard:begin
# The Initializer must not write rows the hub owns here: the domain list
# docker-compose.yml hands OpenMRS is checked against the module's domains and
# the extracted config tree before anything starts (initializer.sh).
. "${INSTALL_DIR}/initializer.sh"
v="$(initializer_domains_verdict "${OPENMRS_INITIALIZER_DOMAINS:-${INITIALIZER_DOMAINS_DEFAULT}}" "${BAHMNI_CONFIG_DIR:-${CLINIC_DIR}/extracted/bahmni_config}")" || fail "$v"
ok "initializer domains: ${v#ok }"
# initializer-guard:end
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local --profile openelis up -d >/dev/null )
ensure_stopped "$OC" && ok "odoo-connect parked until its markers are set" || fail "odoo-connect will not stay stopped: ${COMPOSE_CMD} ps odoo-connect"
url="https://localhost/openmrs/ws/rest/v1/session"
# The FIRST boot is the long one: the Initializer loads the masterdata CSVs into
# the seeded database once (checksums persist under CONTAINER_DATA_PATH, later
# boots skip them). Measured: 17 min on Rawach, 36 min on manpur's 1-vCPU VM --
# which a fixed 25 min budget cut off while OpenMRS was still starting.
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
if [ "${PHASE:-install}" = install ]; then
  ok "baseline stack up; odoo-connect stays stopped until the seed (its feed users are the hub's)"
  exit 0
fi
# The four hub credentials were written at install; the hub may have rotated
# one since. Check each against the data just restored before any feed runs.
omrs_login(){ # USER PASS -> 0 if OpenMRS authenticates them
  local reply
  reply="$(curl -sk --max-time 20 -u "$1:$2" "$url" 2>/dev/null)" || reply=""
  has_text "$reply" '"authenticated":true'
}
omrs_login "${OPENMRS_ATOMFEED_USER}" "${OPENMRS_ATOMFEED_PASSWORD}" && ok "OpenMRS accepts OPENMRS_ATOMFEED_USER" \
  || fail "OpenMRS refuses the OpenMRS feed user's password in clinic/.env: the hub's credential changed after install. Call the operator (they update OPENMRS_ATOMFEED_PASSWORD in clinic/.env; then run seed.sh again)"
# OPENELIS_ATOMFEED_* is an OpenELIS account (OpenMRS and odoo-connect log in
# to OpenELIS with it to read its feeds); OpenELIS offers no plain login check,
# so it is proven when those feeds run, not here.
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
# the markers are only safe to park while odoo-connect is down
[ "$(ct inspect --format '{{.State.Running}}' "$OC" 2>/dev/null || printf false)" = false ] || fail "odoo-connect is running before its markers are parked (it would replay every past event)"
feed(){ # NAME : sets FEED_CODE (HTTP status) and FEED_BODY
  local out
  out="$(ct exec "$OM" curl -s -w '\n%{http_code}' -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "http://localhost:8080/openmrs/ws/atomfeed/$1/recent" 2>/dev/null || true)"
  FEED_CODE="${out##*$'\n'}"; FEED_BODY="${out%$'\n'*}"
}
# odoo-connect keeps its feed positions in the odoo database itself (staging,
# five feeds), now colocated on the shared bahmni-postgres instance --
# the Odoo app's own tables live in that same database, not a separate odoodb.
# mk runs psql there, using the same postgres superuser role tasks 050/060 use
# (not a container-env POSTGRES_USER, which bahmni-postgres does not set for
# this role), with the feed/entry/page as psql variables so no value is ever
# interpolated into SQL text.
mk(){ ct exec -i "$OD" sh -c 'psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q -At -v f="$1" -v e="$2" -v p="$3"' _ "${1:-}" "${2:-}" "${3:-}"; }
[ "$(printf "select count(*) from information_schema.tables where table_name='markers'" | mk)" = 1 ] || fail "no markers table in bahmni-postgres's odoo database; odoo-connect 1.0.0 keeps its feed positions there on every lab node, so this Postgres image is not the fleet's"
# Every feed odoo-connect reads: the five each lab node's table carries, plus any
# other row already in this node's table -- a stale row for a feed we did not
# list is exactly as dangerous as a stale patient row.
present="$(printf 'select feed_uri from markers' | mk | sed -nE 's#.*/atomfeed/([a-z]+)/recent$#\1#p' | tr '\n' ' ')"
for f in $(printf 'patient encounter lab saleable drug %s\n' "$present" | tr ' ' '\n' | grep -v '^$' | sort -u); do
  # /session answering does not prove every module is up: give the atomfeed
  # module up to 10 more minutes before calling the credentials wrong. A feed
  # that never reads is a STOP, not a skip: an unparked marker replays every
  # past event (a bare grep in the $(...) below once aborted the task before
  # the empty-feed guard could even run).
  for i in $(seq 1 40); do feed "$f"; [ "${FEED_CODE:-}" = 200 ] && break; sleep 15; done
  [ "${FEED_CODE:-}" = 200 ] || fail "feed $f answered HTTP ${FEED_CODE:-none} for OPENMRS_ATOMFEED_USER=${OPENMRS_ATOMFEED_USER}: wrong atomfeed credentials, or the atomfeed module never came up (${COMPOSE_CMD} logs openmrs). The markers must be parked before odoo-connect starts."
  # the via link carries type= between rel= and href= (manpur: the old regex never matched);
  # entries are oldest-first, so the LAST id is the head (verified against Rawach's live marker)
  page="$(printf '%s' "$FEED_BODY" | grep -oE 'rel="via"[^>]*href="[^"]+"' | grep -oE 'https?://[^"]+' | head -1 | sed 's#localhost:8080#openmrs:8080#' || true)"
  entry="$(printf '%s' "$FEED_BODY" | grep -oE '<id>tag:atomfeed.ict4h.org:[^<]+' | tail -1 | sed 's/<id>//' || true)"
  if [ -z "$page" ] || [ -z "$entry" ]; then warn "feed $f is empty (HTTP 200, no entries); marker left unset"; continue; fi
  uri="http://openmrs:8080/openmrs/ws/atomfeed/${f}/recent"
  # markers has no unique key on feed_uri (Rawach's DDL), so ON CONFLICT cannot
  # work there: update the row if present, insert it if not, then read it back.
  # Only the three columns every odoo-connect table has: the Odoo 16 table (its
  # own liquibase DDL) carries no create_date/write_date, the Odoo 10 one did.
  mk "$uri" "$entry" "$page" <<'SQL'
UPDATE markers SET last_read_entry_id=:'e', feed_uri_for_last_read_entry=:'p' WHERE feed_uri=:'f';
INSERT INTO markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) SELECT :'f', :'e', :'p' WHERE NOT EXISTS (SELECT 1 FROM markers WHERE feed_uri=:'f');
SQL
  got="$(printf "select last_read_entry_id from markers where feed_uri=:'f'" | mk "$uri")"
  [ "$got" = "$entry" ] && ok "marker $f -> page ${page##*/}, entry ${entry##*:}" || fail "marker $f did not take: the table holds '${got}', wanted '${entry}'"
done
ok_odoo=0; for i in $(seq 1 12); do odoo_login_ok && { ok_odoo=1; break; }; sleep 10; done
[ "$ok_odoo" = 1 ] && ok "Odoo accepts ODOO_ATOMFEED_USER" \
  || fail "Odoo refuses the Odoo feed user's password in clinic/.env (or Odoo is not answering on :${ODOO_PORT:-8069}): the hub's credential may have changed after install. Call the operator"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local up -d odoo-connect >/dev/null )
r0="$(ct inspect --format '{{.RestartCount}}' "$OC" 2>/dev/null || printf 0)"
sleep 120
# a dead odoo-connect would pass the replay check below with 0 events: prove it is up and has not restarted
state="$(ct inspect --format '{{.State.Running}} {{.RestartCount}}' "$OC" 2>/dev/null || printf 'false 0')"
[ "$state" = "true ${r0}" ] || { ct logs --tail 10 "$OC" 2>&1 | sed 's/^/    /' >&2; fail "odoo-connect is not running cleanly two minutes after start (running/restarts: ${state}; its log lines are above)"; }
n="$(ct logs --since 2m "$OC" 2>&1 | grep -c 'Processing event' || true)"
[ "${n:-0}" -lt 50 ] && ok "odoo-connect processed ${n} events in its first two minutes (no replay)" || fail "odoo-connect is replaying: ${n} events in two minutes -- markers did not take"
# OpenMRS rebuilds its search index in the background after this restore
# (task 050 cleared search.indexVersion). Until it finishes, no patient can be
# found by identifier or name, so the seed is not done until one can.
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
probe="$(printf "select identifier from openmrs.patient_identifier where voided=0 order by patient_identifier_id limit 1" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N' 2>/dev/null || true)"
[ -n "$probe" ] || fail "no patient identifier in openmrs to test patient search with"
search_s="${SEARCH_INDEX_TIMEOUT_S:-2700}"
info "waiting up to $((search_s/60)) min for OpenMRS to index the restored patients (SEARCH_INDEX_TIMEOUT_S overrides)"
t0="$(date +%s)"; found=0
while [ $(( $(date +%s) - t0 )) -lt "$search_s" ]; do
  reply="$(curl -sk --max-time 30 -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "https://localhost/openmrs/ws/rest/v1/patient?identifier=${probe}&v=custom:(uuid)" 2>/dev/null || true)"
  has_text "$reply" '"uuid"' && { found=1; break; }
  sleep 30
done
[ "$found" = 1 ] && ok "patient search finds ${probe} after $(( $(date +%s) - t0 ))s" \
  || fail "patient search still finds nothing for ${probe} after $((search_s/60)) min: OpenMRS has not finished indexing (${COMPOSE_CMD} logs openmrs | grep -i index). Resume with --from 080 once it has"
