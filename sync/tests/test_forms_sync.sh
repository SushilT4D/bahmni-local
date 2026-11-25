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
req="${SRC}/requirements.txt"
[ "$(grep -cE '^(kafka-python|PyMySQL)==[0-9.]+$' "$req")" = 2 ] && [ "$(grep -c . "$req")" = 2 ] \
  && ok_ "requirements: both libraries pinned to one version" || bad "requirements.txt does not pin exactly kafka-python and PyMySQL"
grep -nE '(say|log|print)\(.*FORMS_DB_PASSWORD' "${SRC}/forms_sync.py" >/dev/null \
  && bad "forms_sync.py prints the database password setting" || ok_ "the database password is never printed"
grep -q 'cleanup.policy": "compact"' "${SRC}/forms_sync.py" && ok_ "the forms topic is created to keep the latest message per file" \
  || bad "forms_sync.py does not create the topic as compact"
[ -x "${SRC}/build.sh" ] && ok_ "build.sh is executable" || bad "build.sh is not executable"
exit "$fails"
