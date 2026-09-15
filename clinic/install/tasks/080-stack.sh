#!/usr/bin/env bash
# The application stack. odoo-connect is started LAST and only after its
# atom-feed markers are parked at the head of each feed: the seed carries the
# event_records that made Rawach replay ~303k events through the hub (F-066).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "80 · stack"
[ "${DRY}" = 1 ] && { info "would: compose --profile local --profile openelis up -d; wait for OpenMRS; park odoo-connect markers; start odoo-connect"; exit 0; }
setup_compose; cd "${CLINIC_DIR}"; E="${CLINIC_DIR}/.env"; set -a; . "$E"; set +a
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local --profile openelis up -d >/dev/null )
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local stop odoo-connect >/dev/null 2>&1 || true )
url="https://localhost:${BAHMNI_PROXY_HTTPS_PORT:-9443}/openmrs/ws/rest/v1/session"
info "waiting for OpenMRS through the proxy (cold boot took 17 min on Rawach)"
wait_for_http "$url" 1500 && ok "OpenMRS answers at ${url}" || fail "OpenMRS did not answer within 25 min: ${COMPOSE_CMD} logs openmrs proxy"
OM="${COMPOSE_PROJECT_NAME}-openmrs-1"; OD="${COMPOSE_PROJECT_NAME}-odoodb-1"
feed(){ ct exec "$OM" curl -s -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "http://localhost:8080/openmrs/ws/atomfeed/$1/recent"; }
for f in patient drug lab; do
  body="$(feed "$f")"
  page="$(printf '%s' "$body" | grep -oE 'rel="via" href="[^"]+"' | grep -oE 'https?://[^"]+' | head -1 | sed 's#localhost:8080#openmrs:8080#')"
  entry="$(printf '%s' "$body" | grep -oE '<id>tag:atomfeed.ict4h.org:[^<]+' | head -1 | sed 's/<id>//')"
  if [ -z "$page" ] || [ -z "$entry" ]; then warn "feed $f has no entries yet; marker left unset"; continue; fi
  printf "insert into markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) values ('http://openmrs:8080/openmrs/ws/atomfeed/%s/recent', '%s', '%s') on conflict (feed_uri) do update set last_read_entry_id=excluded.last_read_entry_id, feed_uri_for_last_read_entry=excluded.feed_uri_for_last_read_entry\n" "$f" "$entry" "$page" \
    | ct exec -i "$OD" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d odoo -q' 2>/dev/null \
    || printf "insert into markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) select 'http://openmrs:8080/openmrs/ws/atomfeed/%s/recent', '%s', '%s' where not exists (select 1 from markers where feed_uri='http://openmrs:8080/openmrs/ws/atomfeed/%s/recent')\n" "$f" "$entry" "$page" "$f" | ct exec -i "$OD" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d odoo -q'
  ok "marker $f -> ${page##*/}"
done
( cd "${CLINIC_DIR}" && ${COMPOSE_CMD} --profile local up -d odoo-connect >/dev/null )
sleep 120
n="$(ct logs --since 2m "${COMPOSE_PROJECT_NAME}-odoo-connect-1" 2>&1 | grep -c 'Processing event' || true)"
[ "${n:-0}" -lt 50 ] && ok "odoo-connect processed ${n} events in its first two minutes (no replay)" || fail "odoo-connect is replaying: ${n} events in two minutes -- markers did not take"
