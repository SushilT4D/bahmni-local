#!/usr/bin/env bash
# Every task declares the phase it runs in, and the runner's phase rule holds.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HERE}/../lib.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
for t in "${HERE}"/../tasks/[0-9]*-*.sh; do
  p="$(sed -n '2p' "$t")"
  case "$p" in "# phase: install"|"# phase: seed"|"# phase: both") ok_ "$(basename "$t"): ${p#\# phase: }" ;; *) bad "$(basename "$t") line 2 is '$p', not a phase header" ;; esac
done
check(){ phase_runs "$1" "$2"; r=$?; [ "$r" = "$3" ] && ok_ "phase_runs $1 $2 -> $r" || bad "phase_runs $1 $2 -> $r, want $3"; }
check install install 0; check install both 0; check install seed 1
check seed seed 0;       check seed both 0;    check seed install 1
tmp="$(mktemp)"; printf '#!/usr/bin/env bash\necho hi\n' > "$tmp"
[ "$(task_phase "$tmp")" = both ] && ok_ "no header -> both" || bad "no header -> $(task_phase "$tmp")"; rm -f "$tmp"
exit $((fails > 0))
