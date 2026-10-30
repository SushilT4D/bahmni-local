#!/usr/bin/env bash
# Parks the feed bookmarks of odoo-connect (the odoo database's markers table)
# and of OpenELIS (the openelis database's clinlims.markers) at the newest entry
# of this clinic's own OpenMRS feeds, so neither replays the events already in
# them and neither keeps a bookmark into another OpenMRS's feed.
#
#   clinic/scripts/park-feed-markers.sh
#
# The seed copies the hub's Odoo and OpenELIS databases, bookmarks included. A
# clinic restored from the seed holds the hub's OpenMRS feeds too, so those
# bookmarks name entries it has; a clinic that keeps its own OpenMRS does not,
# and a bookmark naming an entry its feed lacks stops that job for good
# ("Last Read entry not found in feed", or an error page for a page number the
# feed does not have). So each feed a bookmark is kept for is parked at its
# newest entry, and a feed with no entries has its bookmark removed: the job
# then starts at the feed's first entry when one appears.
#
# The feeds: odoo-connect's patient, encounter, lab, saleable and drug, OpenELIS's
# patient, encounter and lab, and any other feed a bookmark is already kept for.
# A feed that does not answer 200 within FEED_WAIT_S (default 600 s, while the
# atomfeed module starts) stops the script, naming it: a bookmark left as it
# was would replay or stall.
#
# odoo-connect must be stopped (it is refused while running: a running job
# writes its own bookmark back). OpenELIS, if running, is stopped for the
# parking and started again after it.
#
# Reads COMPOSE_PROJECT_NAME, OPENMRS_ATOMFEED_USER and OPENMRS_ATOMFEED_PASSWORD
# from clinic/.env; the environment overrides. RUNTIME=docker|podman overrides
# the platform's default runtime.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
E="${CLINIC_DIR}/.env"
for k in COMPOSE_PROJECT_NAME OPENMRS_ATOMFEED_USER OPENMRS_ATOMFEED_PASSWORD; do
  [ -n "${!k:-}" ] || { [ -f "$E" ] && v="$(env_get "$E" "$k")" && [ -n "$v" ] && printf -v "$k" '%s' "$v"; } || fail "${k} is not set and not in ${E}"
done
[ -n "${CT:-}" ] || setup_compose
OM="${COMPOSE_PROJECT_NAME}-openmrs-1"; PGC="${COMPOSE_PROJECT_NAME}-bahmni-postgres-1"
OC="${COMPOSE_PROJECT_NAME}-odoo-connect-1"; EL="${COMPOSE_PROJECT_NAME}-openelis-1"

running(){ [ "$(ct inspect --format '{{.State.Running}}' "$1" 2>/dev/null || printf false)" = true ]; }
running "$OC" && fail "odoo-connect is running; stop it first (a running job writes its own bookmark back over a parked one)"
el_was_up=0; el_back=0
# a stop part-way leaves OpenELIS down, its bookmarks not all parked: say so
trap '[ "$el_was_up" = 1 ] && [ "$el_back" = 0 ] && printf "  OpenELIS is left stopped; start it once the bookmarks are parked: run this script again\n" >&2' EXIT
if running "$EL"; then el_was_up=1; ensure_stopped "$EL" || fail "OpenELIS would not stay stopped; nothing was parked"; fi

# The update and insert of one bookmark (markers has no unique key on feed_uri,
# so ON CONFLICT cannot work), and the removal of one. Only the three columns
# every odoo-connect and OpenELIS table has.
PARK_SQL="$(cat <<'SQL'
UPDATE markers SET last_read_entry_id=:'e', feed_uri_for_last_read_entry=:'p' WHERE feed_uri=:'f';
INSERT INTO markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) SELECT :'f', :'e', :'p' WHERE NOT EXISTS (SELECT 1 FROM markers WHERE feed_uri=:'f');
SQL
)"
CLEAR_SQL="$(cat <<'SQL'
DELETE FROM markers WHERE feed_uri=:'f';
SQL
)"
# mk DB SCHEMA [FEED ENTRY PAGE] : psql on bahmni-postgres with the values as
# psql variables (never interpolated into SQL text), the markers table found
# through the search path
mk(){
  local db="$1" sch="$2"; shift 2
  { printf 'SET search_path=%s;\n' "$sch"; cat; } \
    | ct exec -i "$PGC" sh -c 'psql -U postgres -d "$1" -v ON_ERROR_STOP=1 -q -At -v f="$2" -v e="$3" -v p="$4"' _ "$db" "${1:-}" "${2:-}" "${3:-}"
}
feed(){ # NAME : sets FEED_CODE and FEED_BODY from this clinic's OpenMRS
  local out
  out="$(ct exec "$OM" curl -s -w '\n%{http_code}' -u "${OPENMRS_ATOMFEED_USER}:${OPENMRS_ATOMFEED_PASSWORD}" "http://localhost:8080/openmrs/ws/atomfeed/$1/recent" 2>/dev/null || true)"
  FEED_CODE="${out##*$'\n'}"; FEED_BODY="${out%$'\n'*}"
}
WAITED=0
head_of(){ # NAME : sets PAGE and ENTRY (both empty for a feed with no entries)
  local t0; t0="$(date +%s)"
  while :; do
    feed "$1"; [ "${FEED_CODE:-}" = 200 ] && break
    # only the first feed waits for the atomfeed module; once one answered, a
    # feed that does not is a wrong name or credential, not a slow start
    if [ "$WAITED" = 1 ] || [ $(( $(date +%s) - t0 )) -ge "${FEED_WAIT_S:-600}" ]; then
      fail "feed $1 answered HTTP ${FEED_CODE:-none} after $(( $(date +%s) - t0 ))s (FEED_WAIT_S ${FEED_WAIT_S:-600}) for OPENMRS_ATOMFEED_USER=${OPENMRS_ATOMFEED_USER}: wrong credentials, or the atomfeed module is not up. No bookmark of $1 was changed"
    fi
    sleep 15
  done
  WAITED=1
  # the via link carries type= between rel= and href=; entries are oldest
  # first, so the last id is the newest
  PAGE="$(printf '%s' "$FEED_BODY" | grep -oE 'rel="via"[^>]*href="[^"]+"' | grep -oE 'https?://[^"]+' | head -1 | sed 's#localhost:8080#openmrs:8080#' || true)"
  ENTRY="$(printf '%s' "$FEED_BODY" | grep -oE '<id>tag:atomfeed.ict4h.org:[^<]+' | tail -1 | sed 's/<id>//' || true)"
  [ -n "$PAGE" ] && [ -n "$ENTRY" ] || { PAGE=""; ENTRY=""; }
}

park(){ # WHO DB SCHEMA DEFAULT-FEEDS
  local who="$1" db="$2" sch="$3" feeds="$4" present f uri got
  [ "$(printf "select count(*) from information_schema.tables where table_schema='%s' and table_name='markers'" "$sch" | mk "$db" "$sch")" = 1 ] \
    || fail "no ${sch}.markers table in the ${db} database: ${who} keeps its feed positions there"
  present="$(printf 'select feed_uri from markers' | mk "$db" "$sch" | sed -nE 's#.*/atomfeed/([a-z]+)/recent$#\1#p' | tr '\n' ' ')"
  for f in $(printf '%s %s\n' "$feeds" "$present" | tr ' ' '\n' | grep -v '^$' | sort -u); do
    head_of "$f"; uri="http://openmrs:8080/openmrs/ws/atomfeed/${f}/recent"
    if [ -z "$ENTRY" ]; then
      printf '%s\n' "$CLEAR_SQL" | mk "$db" "$sch" "$uri" >/dev/null
      got="$(printf "select count(*) from markers where feed_uri=:'f'" | mk "$db" "$sch" "$uri")"
      [ "$got" = 0 ] && ok "${who} ${f}: this clinic's feed is empty, bookmark removed" || fail "${who} ${f}: the bookmark of an empty feed is still there (${got} rows)"
      continue
    fi
    printf '%s\n' "$PARK_SQL" | mk "$db" "$sch" "$uri" "$ENTRY" "$PAGE" >/dev/null
    got="$(printf "select last_read_entry_id from markers where feed_uri=:'f'" | mk "$db" "$sch" "$uri")"
    [ "$got" = "$ENTRY" ] && ok "${who} ${f} -> page ${PAGE##*/}, entry ${ENTRY##*:}" || fail "${who} ${f}: the bookmark did not take (the table holds '${got}', wanted '${ENTRY}')"
  done
}
park odoo-connect odoo public "patient encounter lab saleable drug"
park OpenELIS openelis clinlims "patient encounter lab"
if [ "$el_was_up" = 1 ]; then ct start "$EL" >/dev/null && el_back=1 && ok "OpenELIS started again" || fail "OpenELIS did not start again after the parking"; fi
