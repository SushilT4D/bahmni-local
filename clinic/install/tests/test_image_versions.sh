#!/usr/bin/env bash
# The person installing a clinic may run other versions of the application
# images (lib.sh IMAGE_KEYS): --versions <file> or the prompt. Pure functions
# only: no runtime, no network.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }

export CLINIC_DIR="$TMP/clinic"; mkdir -p "$CLINIC_DIR"
export DRY=1
export VERSIONS_FILE="$TMP/versions.env"
cat > "$VERSIONS_FILE" <<'EOF'
# pins
KAFKA_IMAGE=confluentinc/cp-kafka:8.3.2          # sync layer
OPENMRS_IMAGE_NAME=infoiplitin/openmrs:iplit-1.2.0-1200-03   # app
ODOO_IMAGE_NAME=bahmni/odoo-16:1.0.0
ODOO_CONNECT_IMAGE_TAG=1.0.0
OPENELIS_IMAGE_TAG=1.1.0-111                     # app
BAHMNI_WEB_IMAGE=infoiplitin/bahmni-iplit-web:bhs-0.0.30
BAHMNI_CONFIG_IMAGE=infoiplitin/clinic-config-indiadistro:bhs-0.0.20
IMPLEMENTER_INTERFACE_IMAGE_TAG=1.1.0-74
PATIENT_DOCUMENTS_TAG=1.1.0-32
ATOMFEED_CONSOLE_IMAGE_TAG=1.0.0-23
EOF
# shellcheck source=../lib.sh
. "${HERE}/../lib.sh"

# every key the installer offers has a default in the real pin file
REAL="$(cd "$HERE/../../.." && pwd)/sync/versions.env"
for k in $IMAGE_KEYS; do
  v="$(VERSIONS_FILE="$REAL" pin_get "$k")"; [ -n "$v" ] && printf '  ok   sync/versions.env has a default for %s\n' "$k" || { printf '  FAIL sync/versions.env has no default for %s\n' "$k"; fails=$((fails+1)); }
done
case " $IMAGE_KEYS " in *" KAFKA_IMAGE "*|*" DEBEZIUM_CONNECT_IMAGE "*|*" MM2_IMAGE "*) printf '  FAIL the sync layer is offered as a per-node choice\n'; fails=$((fails+1)) ;; *) printf '  ok   the sync layer is not a per-node choice\n' ;; esac

# pin_get strips the inline comment
assert_eq "pin_get strips the comment" "$(pin_get OPENELIS_IMAGE_TAG)" "1.1.0-111"

# image_value
assert_eq "a tag key takes a tag" "$(image_value OPENELIS_IMAGE_TAG 1.0.0-99)" "1.0.0-99"
assert_eq "a bare tag keeps the image name" "$(image_value BAHMNI_WEB_IMAGE bhs-0.0.34)" "infoiplitin/bahmni-iplit-web:bhs-0.0.34"
assert_eq "a full reference is kept" "$(image_value BAHMNI_WEB_IMAGE acme/web:2)" "acme/web:2"
d="sha256:$(printf '%064d' 0)"
assert_eq "a digest reference is kept" "$(image_value OPENMRS_IMAGE_NAME "infoiplitin/openmrs@${d}")" "infoiplitin/openmrs@${d}"
( image_value KAFKA_IMAGE confluentinc/cp-kafka:7 ) >/dev/null 2>&1; assert_rc "a sync-layer key is refused" $? 1
( image_value OPENELIS_IMAGE_TAG 'x y' ) >/dev/null 2>&1; assert_rc "a tag with a space is refused" $? 1
( image_value OPENELIS_IMAGE_TAG 'a/b:1' ) >/dev/null 2>&1; assert_rc "a reference where a tag belongs is refused" $? 1
( image_value BAHMNI_WEB_IMAGE 'Acme/Web:1' ) >/dev/null 2>&1; assert_rc "an upper-case repository is refused" $? 1
( image_value BAHMNI_WEB_IMAGE '$(id)' ) >/dev/null 2>&1; assert_rc "shell text is refused" $? 1
( image_value BAHMNI_WEB_IMAGE '' ) >/dev/null 2>&1; assert_rc "an empty value is refused" $? 1

# image_choices_load: a --versions file
f="$TMP/choices.env"
printf '# chosen for this node\nBAHMNI_WEB_IMAGE=bhs-0.0.34\n  OPENELIS_IMAGE_TAG="1.0.0-99"   # trailing comment\n\n' > "$f"
( set -a; . "$VERSIONS_FILE"; set +a; image_choices_load "$f"; printf '%s %s %s\n' "$BAHMNI_WEB_IMAGE" "$OPENELIS_IMAGE_TAG" "$PATIENT_DOCUMENTS_TAG" ) > "$TMP/out" 2>&1
assert_eq "a --versions file sets what it names and nothing else" "$(cat "$TMP/out")" "infoiplitin/bahmni-iplit-web:bhs-0.0.34 1.0.0-99 1.1.0-32"
printf 'KAFKA_IMAGE=confluentinc/cp-kafka:7.6.0\n' > "$TMP/bad1.env"
( image_choices_load "$TMP/bad1.env" ) >/dev/null 2>&1; assert_rc "a --versions file naming the sync layer is refused" $? 1
printf 'BAHMNI_WEB_IMAGE\n' > "$TMP/bad2.env"
( image_choices_load "$TMP/bad2.env" ) >/dev/null 2>&1; assert_rc "a line that is not KEY=value is refused" $? 1
( image_choices_load "$TMP/none.env" ) >/dev/null 2>&1; assert_rc "a missing --versions file is refused" $? 1

# image_choices_write: only what differs from the default is recorded
a="$TMP/answers.env"; : > "$a"
( set -a; . "$VERSIONS_FILE"; set +a; image_choices_load "$f"; image_choices_write "$a" )
assert_eq "the answers file records the chosen web image" "$(env_get "$a" BAHMNI_WEB_IMAGE)" "infoiplitin/bahmni-iplit-web:bhs-0.0.34"
assert_eq "the answers file records the chosen OpenELIS tag" "$(env_get "$a" OPENELIS_IMAGE_TAG)" "1.0.0-99"
assert_eq "an unchanged image is not recorded" "$(grep -c '^PATIENT_DOCUMENTS_TAG=' "$a")" "0"

# image_keys_from: a node's .env wins over the defaults loaded before it, for the
# application images only
n="$TMP/node.env"; printf 'BAHMNI_WEB_IMAGE=acme/web:9\nKAFKA_IMAGE=confluentinc/cp-kafka:7.6.0\n' > "$n"
( set -a; . "$VERSIONS_FILE"; set +a; image_keys_from "$n"; printf '%s %s\n' "$BAHMNI_WEB_IMAGE" "$KAFKA_IMAGE" ) > "$TMP/out"
assert_eq "the node's application image wins; its sync-layer value does not" "$(cat "$TMP/out")" "acme/web:9 confluentinc/cp-kafka:8.3.2"

# versions_put writes the defaults, then the chosen application images
e="$TMP/rendered.env"; printf 'X=1\n' > "$e"
( set -a; . "$VERSIONS_FILE"; set +a; image_choices_load "$f"; versions_put "$e" )
assert_eq "rendered env: chosen web image" "$(env_get "$e" BAHMNI_WEB_IMAGE)" "infoiplitin/bahmni-iplit-web:bhs-0.0.34"
assert_eq "rendered env: default for what was not chosen" "$(env_get "$e" PATIENT_DOCUMENTS_TAG)" "1.1.0-32"
assert_eq "rendered env: sync layer from the pin file" "$(env_get "$e" KAFKA_IMAGE)" "confluentinc/cp-kafka:8.3.2"

# image_choices_report: names what differs; warns only for a schema-changing app
( set -a; . "$VERSIONS_FILE"; set +a; BAHMNI_WEB_IMAGE=acme/web:2; image_choices_report ) > "$TMP/r1" 2>&1
grep -q 'image BAHMNI_WEB_IMAGE=acme/web:2 (default infoiplitin/bahmni-iplit-web:bhs-0.0.30)' "$TMP/r1" && printf '  ok   report names the changed UI image\n' || { printf '  FAIL report: %s\n' "$(cat "$TMP/r1")"; fails=$((fails+1)); }
grep -q WARN "$TMP/r1" && { printf '  FAIL a UI image change warns about lockstep\n'; fails=$((fails+1)); } || printf '  ok   a UI image change does not warn\n'
( set -a; . "$VERSIONS_FILE"; set +a; OPENMRS_IMAGE_NAME=infoiplitin/openmrs:other; image_choices_report ) > "$TMP/r2" 2>&1
grep -q 'WARN OPENMRS_IMAGE_NAME: .*the hub must run the same version' "$TMP/r2" && printf '  ok   an OpenMRS change warns about lockstep\n' || { printf '  FAIL no lockstep warning: %s\n' "$(cat "$TMP/r2")"; fails=$((fails+1)); }
( set -a; . "$VERSIONS_FILE"; set +a; image_choices_report ) > "$TMP/r3" 2>&1
grep -q 'the defaults in sync/versions.env' "$TMP/r3" && printf '  ok   report says when nothing differs\n' || { printf '  FAIL report: %s\n' "$(cat "$TMP/r3")"; fails=$((fails+1)); }

# image_choose on a terminal: "n", then a bare tag for the web image, Enter for the rest
( set -a; . "$VERSIONS_FILE"; set +a; export INSTALL_INTERACTIVE=1
  printf 'n\n\n\n\n\n%s\n\n\n\n\n' bhs-0.0.34 | { image_choose 2>/dev/null; printf '%s %s\n' "$BAHMNI_WEB_IMAGE" "$OPENMRS_IMAGE_NAME"; } ) > "$TMP/out"
assert_eq "prompt: a bare tag changes one image, Enter keeps the others" "$(cat "$TMP/out")" "infoiplitin/bahmni-iplit-web:bhs-0.0.34 infoiplitin/openmrs:iplit-1.2.0-1200-03"
( set -a; . "$VERSIONS_FILE"; set +a; export INSTALL_INTERACTIVE=1
  printf '\n' | { image_choose 2>/dev/null; printf '%s\n' "$BAHMNI_WEB_IMAGE"; } ) > "$TMP/out"
assert_eq "prompt: Enter at the first question keeps every default" "$(cat "$TMP/out")" "infoiplitin/bahmni-iplit-web:bhs-0.0.30"

printf '%s failure(s)\n' "$fails"; exit $((fails>0))
