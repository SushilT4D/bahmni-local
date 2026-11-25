#!/usr/bin/env bash
# forms-sync: which form files travel from the cloud, and how a clinic writes them.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${HERE}/../forms-sync"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

out="$(cd "$SRC" && python3 -m unittest -q test_formslogic 2>&1)" && ok_ "unit tests: $(printf '%s\n' "$out" | grep -E '^Ran ')" \
  || { bad "unit tests"; printf '%s\n' "$out" | tail -25; }
exit "$fails"
