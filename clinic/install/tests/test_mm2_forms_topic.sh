#!/usr/bin/env bash
# The clinic's MirrorMaker pulls the cloud's form files topic, and never sends one up.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SM="${HERE}/../../scripts/setup-mirrormaker.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

fn="$(sed -n '/^build_topic_pattern() {/,/^}/p' "$SM")"
[ -n "$fn" ] || { bad "setup-mirrormaker.sh has no build_topic_pattern"; exit 1; }
CONF="${HERE}/../../../sync/tables/openmrs.conf"
pattern(){ PROJECT_DIR="${HERE}/../.." bash -c '. "${PROJECT_DIR}/../sync/tables/tables.sh"
'"$fn"'
build_topic_pattern "$1" "$2" "$3"' _ "$1" "$CONF" "$2"; }

down="$(pattern bahmni-cloud down)" || bad "the down list could not be built"
[ "$(printf '%s' "$down" | grep -o 'bahmni-cloud\\.forms\\.files' | wc -l | tr -d ' ')" = 1 ] \
  && ok_ "down: the forms topic is pulled, once" || bad "down list has no forms topic (or has it twice): ${down}"
printf '%s' "$down" | grep -q 'bahmni-cloud\\.openmrs\\.all' && ok_ "down: the rows' topic is still pulled" || bad "down list lost openmrs.all: ${down}"
up="$(pattern bahmni-ghated up)" || bad "the up list could not be built"
printf '%s' "$up" | grep -q 'bahmni-ghated\\.openmrs\\.all' || bad "the up list is not the real one: ${up}"
printf '%s' "$up" | grep -q 'forms' && bad "up list carries a forms topic: ${up}" || ok_ "up: no forms topic leaves the clinic"
exit "$fails"
