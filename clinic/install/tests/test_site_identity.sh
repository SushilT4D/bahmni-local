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
exit "$fails"
