#!/usr/bin/env bash
# Recreate the openmrs service on a running clinic node, after the checks
# installer task 080 runs before it starts OpenMRS. Use it whenever OpenMRS
# must take a new config tree, forms mount or domain list: after
# extract-ui-config.sh takes a new config image, after update-forms.sh points
# the forms mount at the forms repo's clone, after an edit of clinic/.env.
#
#   clinic/scripts/recreate-openmrs.sh [--check]
#
#   1. clinic/.env's OpenMRS JVM options: the heap cap is pinned, and a
#      -Dinitializer.domains left in OMRS_JAVA_SERVER_OPTS is taken out
#      (docker-compose.yml passes the property once, from
#      OPENMRS_INITIALIZER_DOMAINS);
#   2. the forms mount (FORMS_DIR, FORMS_READ_ONLY): it exists, holds forms and
#      translations/, and with a forms repo configured it is that repo's
#      clone, read-only;
#   3. the Initializer domain list against the config tree OpenMRS mounts
#      (BAHMNI_CONFIG_DIR): nothing would load rows the hub owns;
#   4. recreates openmrs alone (up -d --no-deps --force-recreate openmrs), with
#      the node's compose setup: from clinic/, clinic/.env's COMPOSE_FILE and
#      the fleet's profiles, through docker compose, or docker-compose over the
#      podman socket on a podman node.
#
# A refused check stops before anything is recreated; the running OpenMRS is
# left as it is. --check runs the checks only: it changes neither clinic/.env
# nor the stack.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
. "${HERE}/../install/lib.sh"
. "${INSTALL_DIR}/forms.sh"
. "${INSTALL_DIR}/initializer.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
begin_task "recreate openmrs$( [ "$CHECK" = 1 ] && printf ' (checks only: nothing changes)')"
setup_compose
# BEFORE sourcing .env: compose gives an exported shell variable precedence
# over the file, so a stale export would hide the repaired value from `up`.
if [ "$CHECK" = 1 ]; then
  case " $(env_get "$E" OMRS_JAVA_SERVER_OPTS)" in
    *" -Dinitializer.domains="*) warn "OMRS_JAVA_SERVER_OPTS carries -Dinitializer.domains; a run without --check takes it out" ;;
  esac
else
  ensure_openmrs_jvm_opts "$E"
fi
set -a; . "$E"; set +a
v="$(forms_mount_verdict "${FORMS_DIR:-${FORMS_FROZEN_DIR}}" "${FORMS_READ_ONLY:-false}" "${FORMS_REPO_URL:-}")" || fail "$v"
ok "forms: ${v#ok }"
v="$(initializer_domains_verdict "${OPENMRS_INITIALIZER_DOMAINS:-${INITIALIZER_DOMAINS_DEFAULT}}" "${BAHMNI_CONFIG_DIR:-${CLINIC_DIR}/extracted/bahmni_config}")" || fail "$v"
ok "initializer domains: ${v#ok }"
if [ "$CHECK" = 1 ]; then log "checks only: openmrs was not recreated."; exit 0; fi
compose up -d --no-deps --force-recreate openmrs >/dev/null || fail "compose could not recreate openmrs: ${COMPOSE_CMD} ps openmrs; ${COMPOSE_CMD} logs openmrs"
ok "openmrs recreated; it answers at https://localhost/openmrs once started (a new config tree makes the first start long). Follow it with: cd ${CLINIC_DIR} && ${COMPOSE_CMD} logs -f openmrs"
