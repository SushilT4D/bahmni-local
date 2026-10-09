#!/usr/bin/env bash
# Every dot-file the installer keeps directly under clinic/ (named as
# ${CLINIC_DIR}/.<name> in the installer's scripts) is ignored by git. The node
# preflight fails on any untracked path, so a state file the installer writes
# and git does not ignore stops the exit checks of every install that writes it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${HERE}/../../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
names="$(cd "$R" && cat clinic/install/*.sh clinic/install/tasks/*.sh \
  | grep -oE '\$\{CLINIC_DIR\}/\.[A-Za-z][A-Za-z0-9_.-]*' | sed 's#.*}/##' | sort -u)"
[ -n "$names" ] || bad "found no \${CLINIC_DIR}/.<name> path in the installer (the pattern no longer matches)"
for n in $names; do
  [ "$n" = .env ] && continue   # matched by the repo-wide .env rule, checked below with the rest
  (cd "$R" && git ls-files --error-unmatch "clinic/$n" >/dev/null 2>&1) && continue   # a tracked template it reads
  if (cd "$R" && git check-ignore -q "clinic/$n"); then ok_ "clinic/$n is ignored"; else bad "clinic/$n is written by the installer but not ignored by git"; fi
done
(cd "$R" && git check-ignore -q clinic/.env) && ok_ "clinic/.env is ignored" || bad "clinic/.env is not ignored"
exit $((fails > 0))
