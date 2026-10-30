#!/usr/bin/env bash
# scripts/start-lab-result-reader.sh starts OpenMRS's reader of OpenELIS's
# results: it parks the reader's bookmark at this node's OpenELIS feed and sets
# exactly one copy of the reader task (the table can hold it twice) and the
# failed-event task to start at boot, then restarts OpenMRS and waits to see
# the reader run. Task 080 runs it after the feed bookmarks are parked and
# before odoo-connect starts. The live proof is a node; this guards the rules.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/start-lab-result-reader.sh"; T80="${HERE}/../tasks/080-stack.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
bash -n "$S" && ok_ "the script parses" || bad "the script does not parse"
grep -q "select min(task_config_id) from scheduler_task_config where name = 'OpenElis Patient Atom Feed Task'" "$S" \
  && grep -q "SET start_on_startup = (task_config_id = %s) WHERE name = 'OpenElis Patient Atom Feed Task'" "$S" \
  && ok_ "exactly one copy of the reader task starts at boot (the lowest id), any other copy not" || bad "the one-copy rule for the reader task is missing"
grep -q "OpenElisPatientFeedFailedEventsTask" "$S" && ok_ "the failed-event task starts at boot too" || bad "the failed-event task is not set to start"
grep -q 'START TRANSACTION' "$S" && grep -q 'COMMIT' "$S" && ok_ "the bookmark and the start flags are written in one transaction" || bad "no transaction around the bookmark and the start flags"
# the values read from OpenELIS's feed go into SQL only in the expected shapes
re_page='^http://openelis:8052/openelis/ws/feed/patient/[0-9]+$'; re_entry='^tag:atomfeed\.ict4h\.org:[0-9a-f-]+$'
grep -qF "$re_page" "$S" && grep -qF "$re_entry" "$S" && ok_ "the feed page and entry are checked before they are written" || bad "the feed values are not checked"
for v in "http://openelis:8052/openelis/ws/feed/patient/4" "tag:atomfeed.ict4h.org:956d9876-118a-44ba-9ad2-c8e0e7b48eeb"; do
  printf '%s' "$v" | grep -qE "$re_page|$re_entry" || bad "a well-formed value is refused: $v"
done
for v in "http://openelis:8052/openelis/ws/feed/patient/4'; DROP TABLE markers; --" "tag:atomfeed.ict4h.org:abc' OR '1'='1"; do
  printf '%s' "$v" | grep -qE "$re_page|$re_entry" && bad "an unexpected value passes: $v"
done
ok_ "a well-formed page and entry pass, anything carrying a quote does not"
grep -q 'READER_RUN_TIMEOUT_S' "$S" && grep -q 'OPENMRS_RESTART_TIMEOUT_S' "$S" && ok_ "both waits have a named budget" || bad "a wait without a named budget"
np="$(grep -n 'bash scripts/park-feed-markers.sh' "$T80" | head -1 | cut -d: -f1)"; nr="$(grep -n 'bash scripts/start-lab-result-reader.sh' "$T80" | head -1 | cut -d: -f1)"
no="$(grep -n 'up -d odoo-connect' "$T80" | head -1 | cut -d: -f1)"
[ -n "$np" ] && [ -n "$nr" ] && [ -n "$no" ] && [ "$np" -lt "$nr" ] && [ "$nr" -lt "$no" ] \
  && ok_ "080 starts the reader after parking the bookmarks and before odoo-connect" || bad "080 order: park ${np:-none}, reader ${nr:-none}, odoo-connect ${no:-none}"
exit $((fails > 0))
