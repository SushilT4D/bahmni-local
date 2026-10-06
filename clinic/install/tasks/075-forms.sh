#!/usr/bin/env bash
# phase: both
# The forms OpenMRS loads when task 080 starts it: clinic/forms, mounted
# read-only over the config tree's bahmniforms. With a forms repo
# (FORMS_REPO_URL, FORMS_REPO_KEY in the answers), a clone of it, fast-forwarded
# on every run; without one, a copy of the config image's own forms. At seed,
# the incoming forms are checked against the restored database's concepts
# before they are put in place: a form whose concepts the node lacks opens
# with fields that save nothing. Safe to re-run.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/forms.sh"
begin_task "75 · forms"
E="${CLINIC_DIR}/.env"
FORMS_REPO_URL="${FORMS_REPO_URL:-}"; FORMS_REPO_KEY="${FORMS_REPO_KEY:-}"
if [ "${DRY}" = 1 ]; then
  if [ -n "${FORMS_REPO_URL}" ]; then info "would: clone or fast-forward the forms repo ${FORMS_REPO_URL} into ${FORMS_DIR}$( [ "${PHASE:-install}" = seed ] && printf ', check its concepts against this node'"'"'s OpenMRS first')"
  else info "would: copy the config image's forms into ${FORMS_DIR}/bahmniforms (no forms repo configured)"; fi
  exit 0
fi
[ -f "$E" ] || fail "no ${E}; task 020 renders it"
# The answers name the forms repo at install; clinic/.env keeps it for the seed
# sitting and for scripts/update-forms.sh, which read nothing else.
if [ "${PHASE:-install}" = install ]; then
  env_put "$E" FORMS_REPO_URL "${FORMS_REPO_URL}"; env_put "$E" FORMS_REPO_KEY "${FORMS_REPO_KEY}"
fi
export FORMS_REPO_URL FORMS_REPO_KEY
# The concept check needs the database the clinic will run on: the seed's.
# The baseline is replaced at seed, so install does not check against it.
check=0
if [ "${PHASE:-install}" = seed ] && [ -n "${FORMS_REPO_URL}" ]; then
  check=1
else
  [ -z "${FORMS_REPO_URL}" ] || info "the concept check runs at seed, against the hub's data"
fi
forms_sync "$check" 0
v="$(forms_mount_verdict "${FORMS_DIR}/bahmniforms")" || fail "$v"
ok "forms: ${v#ok }"
