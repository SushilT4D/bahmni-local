#!/usr/bin/env bash
# Every service the installer starts carries a restart policy, in the base
# file or the override, so the runtime brings it back after a reboot.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"
B="$C/docker-compose.yml"; O="$C/docker-compose.override.yml"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
names(){ [ -f "$1" ] && awk '/^services:/{s=1;next} /^[^ #]/{s=0} s&&/^  [a-z][a-z0-9_-]*:[ ]*$/{sub(/:.*/,"");print $1}' "$1"; }
svc(){ [ -f "$1" ] && awk -v s="  $2:" '$0==s{p=1;next} p&&/^  [a-z]/{p=0} p' "$1"; }
for n in $( { names "$B"; names "$O"; } | sort -u ); do
  body="$(svc "$B" "$n"; svc "$O" "$n")"
  printf '%s\n' "$body" | grep -E '^[[:space:]]+profiles:' | grep -qE 'local|debezium|openelis' || continue
  printf '%s\n' "$body" | grep -qE '^[[:space:]]+restart:' && ok_ "$n" || bad "$n has no restart policy"
done
exit $((fails > 0))
