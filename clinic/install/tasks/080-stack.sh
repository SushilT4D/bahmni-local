#!/usr/bin/env bash
# The application stack. odoo-connect is started LAST and only after its
# atom-feed markers are parked at the head of each feed: the seed carries the
# event_records that made Rawach replay ~303k events through the hub (F-066).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · stack"
[ "${DRY}" = 1 ] && { info "would: compose --profile local --profile openelis up -d; wait for OpenMRS; park odoo-connect markers; start odoo-connect"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"
# BEFORE sourcing .env: compose gives an exported shell variable precedence over
# the file, so a stale export here would hide the repaired value from `up`.
ensure_openmrs_jvm_opts "$E"
set -a; . "$E"; set +a
OM="${COMPOSE_PROJECT_NAME}-openmrs-1"; OD="${COMPOSE_PROJECT_NAME}-odoodb-1"; OC="${COMPOSE_PROJECT_NAME}-odoo-connect-1"
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local --profile openelis up -d >/dev/null )
ensure_stopped "$OC" && ok "odoo-connect parked until its markers are set" || fail "odoo-connect will not stay stopped: ${COMPOSE_CMD} ps odoo-connect"
url="https://localhost:${BAHMNI_PROXY_HTTPS_PORT:-9443}/openmrs/ws/rest/v1/session"
info "waiting for OpenMRS through the proxy (cold boot took 17 min on Rawach)"
rc=0; wait_for_http_or_restart "$url" 1500 "$OM" || rc=$?
case "$rc" in
  0) ok "OpenMRS answers at ${url}" ;;
  2) fail "OpenMRS is crash-looping (its log lines are above): ${COMPOSE_CMD} logs openmrs" ;;
  *) fail "OpenMRS did not answer within 25 min: ${COMPOSE_CMD} logs openmrs proxy" ;;
esac
# the markers are only safe to park while odoo-connect is down (F-066)
[ "$(ct inspect --format '{{.State.Running}}' "$OC" 2>/dev/null || printf false)" = false ] || fail "odoo-connect is running before its markers are parked (F-066 replay risk)"
feed(){ # NAME : sets FEED_CODE (HTTP status) and FEED_BODY
  local out
  out="$(ct exec "$OM" curl -s -w '\n%{http_code}' -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "http://localhost:8080/openmrs/ws/atomfeed/$1/recent" 2>/dev/null || true)"
  FEED_CODE="${out##*$'\n'}"; FEED_BODY="${out%$'\n'*}"
}
for f in patient drug lab; do
  # /session answering does not prove every module is up: give the atomfeed
  # module up to 10 more minutes before calling the credentials wrong. A feed
  # that never reads is a STOP, not a skip: an unparked marker is the F-066
  # replay (first live clinic, manpur: a bare grep in the $(...) below aborted
  # the task before the empty-feed guard could even run).
  for i in $(seq 1 40); do feed "$f"; [ "${FEED_CODE:-}" = 200 ] && break; sleep 15; done
  [ "${FEED_CODE:-}" = 200 ] || fail "feed $f answered HTTP ${FEED_CODE:-none} for OPENMRS_ATOMFEED_USER=${OPENMRS_ATOMFEED_USER}: wrong atomfeed credentials, or the atomfeed module never came up (${COMPOSE_CMD} logs openmrs). The markers must be parked before odoo-connect starts (F-066)."
  page="$(printf '%s' "$FEED_BODY" | grep -oE 'rel="via" href="[^"]+"' | grep -oE 'https?://[^"]+' | head -1 | sed 's#localhost:8080#openmrs:8080#' || true)"
  entry="$(printf '%s' "$FEED_BODY" | grep -oE '<id>tag:atomfeed.ict4h.org:[^<]+' | head -1 | sed 's/<id>//' || true)"
  if [ -z "$page" ] || [ -z "$entry" ]; then warn "feed $f is empty (HTTP 200, no entries); marker left unset"; continue; fi
  printf "insert into markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) values ('http://openmrs:8080/openmrs/ws/atomfeed/%s/recent', '%s', '%s') on conflict (feed_uri) do update set last_read_entry_id=excluded.last_read_entry_id, feed_uri_for_last_read_entry=excluded.feed_uri_for_last_read_entry\n" "$f" "$entry" "$page" \
    | ct exec -i "$OD" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d odoo -q' 2>/dev/null \
    || printf "insert into markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) select 'http://openmrs:8080/openmrs/ws/atomfeed/%s/recent', '%s', '%s' where not exists (select 1 from markers where feed_uri='http://openmrs:8080/openmrs/ws/atomfeed/%s/recent')\n" "$f" "$entry" "$page" "$f" | ct exec -i "$OD" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d odoo -q'
  ok "marker $f -> ${page##*/}"
done
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local up -d odoo-connect >/dev/null )
r0="$(ct inspect --format '{{.RestartCount}}' "$OC" 2>/dev/null || printf 0)"
sleep 120
# a dead odoo-connect would pass the replay check below with 0 events (AL-008): prove it is up and has not restarted
state="$(ct inspect --format '{{.State.Running}} {{.RestartCount}}' "$OC" 2>/dev/null || printf 'false 0')"
[ "$state" = "true ${r0}" ] || { ct logs --tail 10 "$OC" 2>&1 | sed 's/^/    /' >&2; fail "odoo-connect is not running cleanly two minutes after start (running/restarts: ${state}; its log lines are above)"; }
n="$(ct logs --since 2m "$OC" 2>&1 | grep -c 'Processing event' || true)"
[ "${n:-0}" -lt 50 ] && ok "odoo-connect processed ${n} events in its first two minutes (no replay)" || fail "odoo-connect is replaying: ${n} events in two minutes -- markers did not take"
