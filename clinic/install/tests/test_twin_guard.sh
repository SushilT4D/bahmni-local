#!/usr/bin/env bash
# Two nodes installed under one clinic slug are exact twins: same residue, same
# topic prefix, same MirrorMaker alias. Both would mint the same ids and both
# would mirror into the hub's topics for that clinic. Nothing in the ledger can
# see a second live host, but the hub can: a live node's MirrorMaker heartbeat
# topic <alias>.heartbeats on the hub advances about once a second. Task 090
# reads its end offset twice before starting this node's MirrorMaker and
# refuses if it moved.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
eq(){ [ "$2" = "$3" ] && ok_ "$1" || bad "$1: got '$2', want '$3'"; }
T90="${HERE}/../tasks/090-local-sync.sh"
blk="$(sed -n '/# twin-guard:begin/,/# twin-guard:end/p' "$T90")"
[ -n "$blk" ] || { bad "090 has no twin-guard block"; exit 1; }
call(){ env -i PATH="$PATH" bash -c "${blk}"$'\n''"$@"' _ "$@" 2>&1; }
eq "twin_state: offset moved -> alive"          "$(call twin_state 55557 55599)" alive
eq "twin_state: offset still -> quiet"          "$(call twin_state 100 100)" quiet
eq "twin_state: topic absent (0,0) -> quiet"    "$(call twin_state 0 0)" quiet
eq "twin_state: unreadable -> unknown"          "$(call twin_state '' '')" unknown
eq "twin_state: unreadable second read -> unknown" "$(call twin_state 5 '')" unknown
eq "twin_offset: parses kafka-get-offsets output" "$(printf 'x\nmanpur.heartbeats:0:55599\n' | env -i PATH="$PATH" bash -c "${blk}"$'\n''twin_offset manpur.heartbeats')" 55599
eq "twin_offset: a missing topic reads as 0"    "$(printf 'Error occurred: Could not match any topic-partitions with the specified filters\n' | env -i PATH="$PATH" bash -c "${blk}"$'\n''twin_offset manpur.heartbeats')" 0
eq "twin_offset: junk reads as empty"           "$(printf 'Timed out waiting for a node assignment\n' | env -i PATH="$PATH" bash -c "${blk}"$'\n''twin_offset manpur.heartbeats')" ""
code="$(grep -vE '^[[:space:]]*#' "$T90")"
g="$(printf '%s\n' "$code" | grep -n 'twin_state ' | head -1 | cut -d: -f1)"
m="$(printf '%s\n' "$code" | grep -n 'up -d mirrormaker-connect' | head -1 | cut -d: -f1)"
[ -n "$g" ] && [ -n "$m" ] && [ "$g" -lt "$m" ] && ok_ "the guard runs before MirrorMaker starts" || bad "guard at $g, MirrorMaker start at $m"
printf '%s' "$code" | grep -q 'TWIN_GUARD_SKIP' && ok_ "an operator can skip the guard consciously (TWIN_GUARD_SKIP=1)" || bad "no conscious skip"
printf '%s' "$code" | grep -qi 'another node' && ok_ "the FAIL names a second live node" || bad "the FAIL does not say what was found"
exit "$fails"
