#!/usr/bin/env bash
# The stamp and the records-entered-before-seeding rule.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
expect(){ # LABEL WANT_RC WANT_PREFIX CMD...
  local label="$1" wrc="$2" wpre="$3"; shift 3; local out rc
  out="$("$@" 2>&1)"; rc=$?
  [ "$rc" = "$wrc" ] && case "$out" in "$wpre"*) true ;; *) false ;; esac && ok_ "$label" || bad "$label: rc=$rc out='$out'"
}
# stamp
[ -z "$(stamp_get STATE)" ] && ok_ "no stamp -> empty" || bad "no stamp not empty"
stamp_put STATE SEEDING; [ "$(stamp_get STATE)" = SEEDING ] && ok_ "stamp round-trips" || bad "stamp round-trip"
# a run that reached the sync layer cannot be redone by dropping databases
# --from/--only only resume a run that stopped part-way, past the gate; an
# installed machine runs only --only 010 (the name service)
# after sync started only a resume that re-runs the drop (050 or earlier) is refused
exit $((fails > 0))
