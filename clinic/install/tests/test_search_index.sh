#!/usr/bin/env bash
# A restored OpenMRS database must be searchable: task 050 clears
# search.indexVersion after the restore (both phases) so OpenMRS rebuilds its
# index on the next start, and task 080 does not finish a seed until patient
# search finds a restored patient.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T50="${HERE}/../tasks/050-databases.sh"; T80="${HERE}/../tasks/080-stack.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
line(){ grep -n -- "$2" "$1" | head -1 | cut -d: -f1; }

clear="$(line "$T50" "property='search.indexVersion'")"
restored="$(line "$T50" 'openmrs restored: person=')"
# top-level if/case blocks open before the clear (0 = it runs in every phase)
depth="$(awk -v n="${clear:-0}" 'NR>=n{exit} /^(if|case) /{d++} /^(fi|esac)/{d--} END{print d+0}' "$T50")"
[ -n "$clear" ] && ok_ "050 clears search.indexVersion" || bad "050 does not clear search.indexVersion"
[ -n "$clear" ] && [ -n "$restored" ] && [ "$clear" -gt "$restored" ] && ok_ "after the restore" || bad "the clear is not after the restore"
[ -n "$clear" ] && [ "$depth" = 0 ] && ok_ "in both phases, not inside a phase block" || bad "the clear sits inside a top-level block (depth ${depth})"
grep -q "sql_log_bin=0; UPDATE openmrs.global_property SET property_value='' WHERE property='search.indexVersion'" "$T50" \
  && ok_ "the clear is kept out of the binlog" || bad "the clear is not wrapped in sql_log_bin=0"
grep -q 'could not clear openmrs search.indexVersion' "$T50" && ok_ "050 reads the value back" || bad "050 does not read the cleared value back"

wait80="$(line "$T80" 'SEARCH_INDEX_TIMEOUT_S')"
early="$(line "$T80" 'if \[ "${PHASE:-install}" = install \]; then')"
[ -n "$wait80" ] && ok_ "080 waits for patient search on a named budget" || bad "080 has no SEARCH_INDEX_TIMEOUT_S wait"
[ -n "$wait80" ] && [ -n "$early" ] && [ "$wait80" -gt "$early" ] && ok_ "only in the seed phase" || bad "the search wait is not after the install-phase exit"
grep -q 'ws/rest/v1/patient?identifier=' "$T80" && ok_ "080 searches by identifier, as staff do" || bad "080 does not search by identifier"
grep -q 'Resume with --from 080' "$T80" && ok_ "a timeout names the resume" || bad "the timeout does not say how to resume"
exit $((fails > 0))
