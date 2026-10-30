#!/usr/bin/env bash
# Starts OpenMRS's reader of OpenELIS's results (the openelis-atomfeed-client
# module's scheduled tasks), so a result validated in this node's OpenELIS
# becomes a LAB_RESULT encounter on the patient's dashboard.
#
#   clinic/scripts/start-lab-result-reader.sh [--openmrs-container NAME] [--mysql-container NAME] [--database DB]
#
# The reader's tasks are defined but not started at boot (start_on_startup 0),
# so no result reaches OpenMRS; and its bookmark into OpenELIS's patient feed
# (OpenMRS's markers table) is whatever the database last held, which on a node
# restored from a copy names another node's feed. In order:
#   1. reads the newest entry of this node's OpenELIS patient feed, as the
#      reader reads it (OpenELIS login, then the session cookie), from inside
#      the OpenMRS container with the reader's own settings;
#   2. parks the reader's bookmark there, so the results already in OpenELIS are
#      not replayed into OpenMRS;
#   3. sets exactly one "OpenElis Patient Atom Feed Task" (the lowest id; the
#      table can hold the same task twice, and two would read every result
#      twice) and the failed-event task to start at boot, any other copy not;
#   4. restarts OpenMRS and waits for its session URL (OPENMRS_RESTART_TIMEOUT_S,
#      default 1800 s);
#   5. waits until the reader task has run since the restart
#      (READER_RUN_TIMEOUT_S, default 300 s).
# Each wait that runs out fails, naming what it last saw. Results validated
# from then on reach OpenMRS when the sample's source is linked to an OpenMRS
# location (an external_reference row of type SampleSource in OpenELIS);
# a sample under an unlinked source fails in OpenMRS with "Location Uuid null".
#
# Defaults: <COMPOSE_PROJECT_NAME>-openmrs-1, <COMPOSE_PROJECT_NAME>-bahmni-mysql-1
# and database openmrs, COMPOSE_PROJECT_NAME from clinic/.env. A node whose
# containers are named otherwise passes them. RUNTIME=docker|podman overrides
# the platform's default runtime.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
OM=""; MY=""; DB=openmrs
while [ $# -gt 0 ]; do
  case "$1" in
    --openmrs-container) OM="${2:?}"; shift 2 ;;
    --mysql-container) MY="${2:?}"; shift 2 ;;
    --database) DB="${2:?}"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || fail "bad database name: $DB"
if [ -z "$OM" ] || [ -z "$MY" ]; then
  E="${CLINIC_DIR}/.env"; [ -f "$E" ] || fail "no ${E}: name the containers with --openmrs-container and --mysql-container"
  P="$(env_get "$E" COMPOSE_PROJECT_NAME)"; [ -n "$P" ] || fail "clinic/.env has no COMPOSE_PROJECT_NAME"
  [ -n "$OM" ] || OM="${P}-openmrs-1"; [ -n "$MY" ] || MY="${P}-bahmni-mysql-1"
fi
[ -n "${CT:-}" ] || setup_compose
my(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B "$1"' _ "$DB"; }
FEED="http://openelis:8052/openelis/ws/feed/patient/recent"

# 1. the newest entry of this node's OpenELIS patient feed (the reader's
# credentials stay inside the OpenMRS container, read from its own settings)
body="$(ct exec "$OM" sh -c 'F=/openmrs/data/bahmnicore.properties; U=$(sed -n "s/^openelis.user=//p" $F); P=$(sed -n "s/^openelis.password=//p" $F); [ -n "$U" ] && [ -n "$P" ] || { echo "NO-SETTINGS"; exit 0; }; S=$(curl -s -i --data-urlencode "loginName=$U" --data-urlencode "password=$P" http://openelis:8052/openelis/ValidateLogin.do | sed -n "s/^Set-Cookie: JSESSIONID=\([^;]*\).*/\1/p" | head -1); [ -n "$S" ] || { echo "NO-SESSION"; exit 0; }; curl -s -H "Cookie: JSESSIONID=$S" -w "\nHTTP %{http_code}" "$1"' _ "$FEED" < /dev/null 2>/dev/null || true)"
case "$body" in
  NO-SETTINGS*) fail "OpenMRS's /openmrs/data/bahmnicore.properties has no openelis.user or openelis.password: the reader could not log in to OpenELIS" ;;
  NO-SESSION*) fail "OpenELIS gave no session to OpenMRS's openelis.user: the reader's OpenELIS login is refused, or OpenELIS is not up" ;;
esac
code="${body##*HTTP }"; [ "$code" = 200 ] || fail "OpenELIS's patient feed answered HTTP ${code:-none} to the reader's login; nothing was changed"
page="$(printf '%s' "$body" | grep -oE 'rel="via"[^>]*href="[^"]+"' | grep -oE 'https?://[^"]+' | head -1 || true)"
entry="$(printf '%s' "$body" | grep -oE '<id>tag:atomfeed.ict4h.org:[^<]+' | tail -1 | sed 's/<id>//' || true)"

# the two values go into SQL: they must look like a feed page and an atomfeed id
[ -z "$page" ] || printf '%s' "$page" | grep -qE '^http://openelis:8052/openelis/ws/feed/patient/[0-9]+$' || fail "OpenELIS's feed names an unexpected page: ${page}"
[ -z "$entry" ] || printf '%s' "$entry" | grep -qE '^tag:atomfeed\.ict4h\.org:[0-9a-f-]+$' || fail "OpenELIS's feed names an unexpected entry: ${entry}"
# 2 and 3. the bookmark and the start-at-boot flags, in one transaction
task="$(printf "select min(task_config_id) from scheduler_task_config where name = 'OpenElis Patient Atom Feed Task';\n" | my)"
case "$task" in ''|NULL|*[!0-9]*) fail "no 'OpenElis Patient Atom Feed Task' in ${DB}.scheduler_task_config: is the openelis-atomfeed-client module installed?" ;; esac
{
  printf 'START TRANSACTION;\n'
  if [ -n "$page" ] && [ -n "$entry" ]; then
    printf "UPDATE markers SET last_read_entry_id = '%s', feed_uri_for_last_read_entry = '%s' WHERE feed_uri = '%s';\n" "$entry" "$page" "$FEED"
    printf "INSERT INTO markers (feed_uri, last_read_entry_id, feed_uri_for_last_read_entry) SELECT '%s', '%s', '%s' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM markers WHERE feed_uri = '%s');\n" "$FEED" "$entry" "$page" "$FEED"
  else
    printf "DELETE FROM markers WHERE feed_uri = '%s';\n" "$FEED"
  fi
  printf "UPDATE scheduler_task_config SET start_on_startup = (task_config_id = %s) WHERE name = 'OpenElis Patient Atom Feed Task';\n" "$task"
  printf "UPDATE scheduler_task_config SET start_on_startup = 1 WHERE schedulable_class LIKE '%%OpenElisPatientFeedFailedEventsTask%%';\n"
  printf 'COMMIT;\n'
} | my >/dev/null || fail "the reader's bookmark and start flags could not be written in ${DB}"
if [ -n "$page" ] && [ -n "$entry" ]; then ok "lab-result reader bookmark -> page ${page##*/}, entry ${entry##*:}"
else ok "lab-result reader bookmark removed: this node's OpenELIS patient feed is empty"; fi
on="$(printf "select group_concat(task_config_id order by task_config_id) from scheduler_task_config where start_on_startup = 1 and (name = 'OpenElis Patient Atom Feed Task' or schedulable_class like '%%OpenElisPatientFeedFailedEventsTask%%');\n" | my)"
ok "starting at boot: reader task ${task} and the failed-event task (ids ${on})"

# 4 and 5. restart OpenMRS, then see the reader run
t0="$(printf 'select now();\n' | my)"
ct restart "$OM" >/dev/null || fail "OpenMRS did not restart"
budget="${OPENMRS_RESTART_TIMEOUT_S:-1800}"; s="$(date +%s)"; c=""
while [ $(( $(date +%s) - s )) -lt "$budget" ]; do
  c="$(ct exec "$OM" curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/openmrs/ws/rest/v1/session < /dev/null 2>/dev/null || true)"
  [ "$c" = 200 ] && break; sleep 15
done
[ "$c" = 200 ] || fail "OpenMRS's session URL answered ${c:-nothing} after ${budget}s (OPENMRS_RESTART_TIMEOUT_S); the reader is set to start once OpenMRS is up"
budget="${READER_RUN_TIMEOUT_S:-300}"; s="$(date +%s)"; ran=""
while [ $(( $(date +%s) - s )) -lt "$budget" ]; do
  ran="$(printf "select coalesce(last_execution_time, '') >= '%s' from scheduler_task_config where task_config_id = %s;\n" "$t0" "$task" | my)"
  [ "$ran" = 1 ] && break; sleep 10
done
[ "$ran" = 1 ] || fail "reader task ${task} has not run in ${budget}s after the restart (READER_RUN_TIMEOUT_S); OpenMRS is up"
ok "lab-result reader task ${task} ran after the restart"
