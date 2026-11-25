#!/usr/bin/env bash
# forms-sync runs as its own service: sending on the cloud, receiving at a clinic.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD="${HERE}/../../cloud/docker-compose.yml"; CLINIC="${HERE}/../../clinic/docker-compose.yml"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
# The service's block: from its "  forms-sync:" line to the next line at the same or a shallower indent.
block(){ awk '/^  forms-sync:[[:space:]]*$/{on=1; print; next} on && /^ {0,2}[^ #]/{exit} on{print}' "$1"; }
has(){ printf '%s\n' "$1" | grep -qF -- "$2"; }
check(){ if has "$1" "$2"; then ok_ "$3"; else bad "$3"; fi; }

c="$(block "$CLOUD")"
[ -n "$c" ] && ok_ "cloud: a forms-sync service" || bad "cloud: no forms-sync service"
check "$c" 'image: bahmni-local/forms-sync:1.0' "cloud: runs the forms-sync image"
check "$c" 'command: ["send"]' "cloud: send mode"
check "$c" 'FORMS_TOPIC: bahmni-cloud.forms.files' "cloud: writes the forms topic"
check "$c" 'CHANGE_TOPIC: bahmni-cloud.openmrs.all' "cloud: listens to the change stream the form rows travel in"
check "$c" 'cloud-forms:/forms:ro' "cloud: the forms folder is mounted read-only"
check "$c" 'restart: always' "cloud: restarted like the other services"
check "$c" 'FORMS_DB_USER: ${DEBEZIUM_DB_USER}' "cloud: reads with the capture login"
grep -A3 -E '^  cloud-forms:' "$CLOUD" | grep -q 'external: true' && grep -A3 -E '^  cloud-forms:' "$CLOUD" | grep -qF 'name: ${CLOUD_FORMS_VOLUME:-' \
  && ok_ "cloud: the forms volume is the base stack's own, named by CLOUD_FORMS_VOLUME" || bad "cloud: cloud-forms is not an external volume named by CLOUD_FORMS_VOLUME"
grep -vE '^[[:space:]]*#' "$CLOUD" | grep -qF 'CLOUD_FORMS_VOLUME:?' && bad "cloud: CLOUD_FORMS_VOLUME is required, so a hub without it cannot run any compose command" \
  || ok_ "cloud: a hub without CLOUD_FORMS_VOLUME can still run its other services"
grep -q 'sync/forms-sync/build.sh' "${HERE}/../../cloud/SETUP.md" && ok_ "cloud: the setup steps build the image" || bad "cloud/SETUP.md does not say how the forms-sync image is built"

k="$(block "$CLINIC")"
[ -n "$k" ] && ok_ "clinic: a forms-sync service" || bad "clinic: no forms-sync service"
check "$k" 'image: bahmni-local/forms-sync:1.0' "clinic: runs the forms-sync image"
check "$k" 'profiles: ["debezium"]' "clinic: starts with Kafka and MirrorMaker"
check "$k" 'command: ["receive"]' "clinic: receive mode"
check "$k" 'FORMS_TOPIC: cloud.bahmni-cloud.forms.files' "clinic: reads MirrorMaker's copy of the forms topic"
check "$k" '${FORMS_DIR:?' "clinic: the forms folder must be set, there is no default"
check "$k" 'restart: ${RESTART_POLICY}' "clinic: restarted like the other services"
check "$k" 'FORMS_DB_USER: ${OPENMRS_DB_USERNAME}' "clinic: reads with the OpenMRS login"

for b in "$c" "$k"; do
  printf '%s\n' "$b" | grep -E 'FORMS_DB_PASSWORD:' | grep -vqE 'FORMS_DB_PASSWORD: *"?\$\{[A-Z_]+(:\?[^}]*)?\}"? *$' && bad "a database password is written into a compose file" || true
done
[ "$fails" = 0 ] && ok_ "no password literal in either service"
grep -vE '^[[:space:]]*#' "${HERE}/../../clinic/install/tasks/040-images.sh" | grep -q 'sync/forms-sync/build.sh' \
  && ok_ "clinic installer builds the forms-sync image" || bad "clinic installer does not build the forms-sync image the compose file names"
exit "$fails"
