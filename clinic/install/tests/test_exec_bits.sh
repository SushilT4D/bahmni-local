#!/usr/bin/env bash
# The commands staff and operators type are executable in the checkout they
# clone: a script committed without its x bit answers "Permission denied".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
for f in clinic/install/install.sh clinic/install/seed.sh clinic/install/tasks/*.sh clinic/scripts/extract-baseline.sh; do
  ( cd "$REPO" && [ -e "$f" ] ) || continue
  mode="$(cd "$REPO" && git ls-files -s -- "$f" 2>/dev/null | cut -d' ' -f1)"
  [ -z "$mode" ] && continue   # not tracked (a working copy outside git): nothing to check
  [ "$mode" = 100755 ] && ok_ "$f executable" || bad "$f is committed as $mode, not 100755"
done
exit $((fails > 0))
