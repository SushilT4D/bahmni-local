#!/usr/bin/env bash
# Park feed bookmarks at the newest entries in this clinic's OpenMRS feeds.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
E="${CLINIC_DIR}/.env"
for k in OPENMRS_ATOMFEED_USER OPENMRS_ATOMFEED_PASSWORD; do
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
  # The feed is outside the REST API: log in for a session first, as the readers do.
  local out
  out="$(ct exec -e U="${OPENMRS_ATOMFEED_USER}" -e P="${OPENMRS_ATOMFEED_PASSWORD}" -e F="$1" "$OM" sh -c 'j=$(mktemp); curl -s -c "$j" -u "$U:$P" http://localhost:8080/openmrs/ws/rest/v1/session >/dev/null; curl -s -b "$j" -w "\n%{http_code}" "http://localhost:8080/openmrs/ws/atomfeed/$F/recent"; rm -f "$j"' 2>/dev/null || true)"
  FEED_CODE="${out##*$'\n'}"; FEED_BODY="${out%$'\n'*}"
  # OpenMRS answers 200 with an error body when it refuses: that is not an empty feed
  case "$FEED_BODY" in *"<feed"*) ;; *) FEED_CODE="${FEED_CODE:-none}, not a feed" ;; esac
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
