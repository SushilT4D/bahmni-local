#!/usr/bin/env bash
# The hub keeps MirrorMaker's read position per alias; a reinstalled node's
# topics start at 0, so its first events fall below that position and are
# skipped. Task 090 drops the hub's position for a fresh node once the twin
# guard has proven the alias quiet, and keeps it on a rerun of a node that
# has already mirrored.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
eq(){ [ "$2" = "$3" ] && ok_ "$1" || bad "$1: got '$2', want '$3'"; }
T90="${HERE}/../tasks/090-local-sync.sh"
blk="$(sed -n '/# mm2-reset:begin/,/# mm2-reset:end/p' "$T90")"
[ -n "$blk" ] || { bad "090 has no mm2-reset block"; exit 1; }
d(){ bash -c "$blk"$'\n''mm2_reset_needed "$@"' _ "$@"; }
eq "fresh node, quiet alias, hub remembers -> reset"        "$(d 1 0 1)"  yes
eq "rerun: this node already mirrored -> keep"              "$(d 1 12 1)" no
eq "first node under the alias (hub has nothing) -> no-op"  "$(d 1 0 0)"  no
eq "twin check not proven quiet -> never reset"             "$(d 0 0 1)"  no
eq "unreadable local count -> never reset"                  "$(d 1 '' 1)" no
code="$(grep -vE '^[[:space:]]*#' "$T90")"
printf '%s' "$code" | grep -q -- '--delete --topic "$offsets_topic"' && ok_ "090 deletes the hub's offsets topic on a reset" || bad "090 has no delete of the offsets topic"
printf '%s' "$code" | grep -q 'MM2_OFFSET_RESET_SKIP' && ok_ "the reset has a conscious override" || bad "no MM2_OFFSET_RESET_SKIP override"
# ordering: the render (setup-mirrormaker) comes before the twin guard, the reset before topic creation, the properties file is removed after the reset
r=$(grep -n 'bash scripts/setup-mirrormaker.sh' "$T90" | head -1 | cut -d: -f1); g=$(grep -n 'TWIN_GUARD_SKIP:-0' "$T90" | head -1 | cut -d: -f1)
s=$(grep -n '# mm2-reset:begin' "$T90" | cut -d: -f1); c=$(grep -n -- '--create --if-not-exists' "$T90" | head -1 | cut -d: -f1)
rm_=$(grep -n 'rm -f /tmp/twin-guard.properties' "$T90" | head -1 | cut -d: -f1); del=$(grep -n -- '--delete --topic "$offsets_topic"' "$T90" | cut -d: -f1)
[ "$r" -lt "$g" ] && ok_ "mm2.properties is rendered before the twin guard (the reset needs the topic list)" || bad "render after the guard"
[ "$s" -lt "$c" ] && ok_ "the reset runs before the up topics are created" || bad "reset after topic creation"
[ "$del" -lt "$rm_" ] && ok_ "the hub client properties outlive the reset" || bad "the properties file is removed before the reset uses it"
exit "$fails"
