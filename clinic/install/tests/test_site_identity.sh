#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: output lacks %q\n' "$1" "$3"; fails=$((fails+1)); fi; }
mkdir -p "$TMP/clinic/bahmni_config/openmrs/apps/registration"
printf '{"id":"bahmni.registration","config":{"defaultIdentifierPrefix":"ABC"}}\n' > "$TMP/clinic/bahmni_config/openmrs/apps/registration/app.json"
. "${HERE}/../tasks/070-site-identity.sh" --lib-only
set +e +u
assert_eq "appjson_prefix reads the value" "$(appjson_prefix "$TMP/clinic/bahmni_config/openmrs/apps/registration/app.json")" "ABC"
out="$(env -i PATH="$PATH" HOME="$HOME" DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" PLATFORM=linux RUNTIME=docker MRN_PREFIX=AZR SITE_NUMBER=7 RESIDUE=7 COMPOSE_PROJECT_NAME=bahmni-azure bash "${HERE}/../tasks/070-site-identity.sh" 2>&1)"
assert_contains "dry run warns about app.json prefix" "$out" "defaultIdentifierPrefix"
assert_contains "dry run prints the jq command" "$out" "jq"
assert_contains "dry run prints the idgen hand-step" "$out" "identifierSource"
# node-local tree (task 045): a missing app.json is a STOP in a real run, a plain "would" in a dry run
mkdir -p "$TMP/c2"; printf 'BAHMNI_CONFIG_DIR=%s\n' "$TMP/c2/extracted/bahmni_config" > "$TMP/c2/.env"
run2(){ env -i PATH="$PATH" HOME="$HOME" DRY="$1" INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/c2" REPO_DIR="$TMP" PLATFORM=linux RUNTIME=docker MRN_PREFIX=AZR SITE_NUMBER=7 RESIDUE=7 COMPOSE_PROJECT_NAME=bahmni-azure bash "${HERE}/../tasks/070-site-identity.sh" 2>&1; }
out="$(run2 1)"; printf '%s' "$out" | grep -q 'tracked fleet file' && { printf '  FAIL dry run on a node-local tree still says "tracked fleet file"\n'; fails=$((fails+1)); } || printf '  ok   dry run on a node-local tree does not blame a tracked file\n'
if out="$(trap - ERR; run2 0)"; then rc=0; else rc=$?; fi   # an expected failure: keep lib.sh's ERR trap quiet
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q -- '--from 045'; then printf '  ok   real run without the extraction stops and names task 045\n'; else printf '  FAIL real run without the extraction: rc=%s out=%s\n' "$rc" "$out"; fails=$((fails+1)); fi
mkdir -p "$TMP/c2/extracted/bahmni_config/openmrs/apps/registration"; printf '{"config":{"defaultIdentifierPrefix":"GAN"}}\n' > "$TMP/c2/extracted/bahmni_config/openmrs/apps/registration/app.json"
out="$(run2 1)"; printf '%s' "$out" | grep -q 'GAN -> AZR' && printf '  ok   dry run names the prefix change on the node-local tree\n' || { printf '  FAIL dry run did not name GAN -> AZR: %s\n' "$out"; fails=$((fails+1)); }
exit "$fails"
