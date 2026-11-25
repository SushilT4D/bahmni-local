#!/usr/bin/env bash
# The installer starts forms-sync, and refuses when MirrorMaker would never bring it a form file.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T90="${HERE}/../tasks/090-local-sync.sh"; ROOT="${HERE}/../../.."
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
INSTALL_DIR="${HERE}/.."; CLINIC_DIR="${HERE}/../.."
. "${HERE}/../forms.sh"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
printf 'ghated->cloud.topics = (bahmni-ghated\\.openmrs\\.all)\ncloud->ghated.topics = (bahmni-cloud\\.openmrs\\.all|bahmni-cloud\\.forms\\.files)\n' > "$W/with"
printf 'ghated->cloud.topics = (bahmni-ghated\\.forms\\.files)\ncloud->ghated.topics = (bahmni-cloud\\.openmrs\\.all)\n' > "$W/without"
if type forms_topic_listed >/dev/null 2>&1; then
  forms_topic_listed "$W/with" ghated && ok_ "a down list with the forms topic is accepted" || bad "a down list with the forms topic was refused"
  forms_topic_listed "$W/without" ghated && bad "a down list without the forms topic was accepted" || ok_ "a down list without the forms topic is refused, whatever the up list holds"
  forms_topic_listed "$W/absent" ghated 2>/dev/null && bad "a missing mm2.properties was accepted" || ok_ "a missing mm2.properties is refused"
else
  bad "forms.sh has no forms_topic_listed"
fi

code="$(grep -vE '^[[:space:]]*#' "$T90")"
printf '%s\n' "$code" | grep -q 'forms_topic_listed config/mirrormaker/mm2.properties' \
  && ok_ "task 090 checks the list MirrorMaker will use" || bad "task 090 does not check that MirrorMaker pulls the forms topic"
mm="$(printf '%s\n' "$code" | grep -n 'up -d mirrormaker-connect' | head -1 | cut -d: -f1)"
fs="$(printf '%s\n' "$code" | grep -n 'up -d forms-sync' | head -1 | cut -d: -f1)"
[ -n "$fs" ] && [ -n "$mm" ] && [ "$fs" -gt "$mm" ] && ok_ "task 090 starts forms-sync, after MirrorMaker" || bad "task 090 does not start forms-sync after MirrorMaker"

git -C "$ROOT" check-ignore -q clinic/forms/x && ok_ "a forms clone left on an upgraded clinic stays ignored" || bad "clinic/forms/ is not ignored: a left-over private clone would show as untracked"
git -C "$ROOT" check-ignore -q clinic/bahmni_home/clinical_forms/x.json && ok_ "form files left in the old folder stay ignored" || bad "clinic/bahmni_home/clinical_forms/ is not ignored"
exit "$fails"
