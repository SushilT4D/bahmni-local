#!/usr/bin/env bash
# phase: both
# The forms folder OpenMRS mounts at /home/bahmni/clinical_forms (forms.sh).
# With a forms repo (FORMS_REPO_URL, FORMS_REPO_KEY in the answers): a clone of
# it in clinic/forms, fast-forwarded on every run, whose clinical_forms/ is
# mounted read-only. Without one: the frozen copy in
# clinic/bahmni_home/clinical_forms, read-write. clinic/.env gets FORMS_DIR and
# FORMS_READ_ONLY for docker-compose.yml. At seed, after the database is
# restored, the incoming forms' concepts are checked (warnings only) and every
# published form row must find its file: with a forms repo a missing file
# stops the seed. Safe to re-run.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/forms.sh"
begin_task "75 · forms"
E="${CLINIC_DIR}/.env"
FORMS_REPO_URL="${FORMS_REPO_URL:-}"; FORMS_REPO_KEY="${FORMS_REPO_KEY:-}"
if [ "${DRY}" = 1 ]; then
  if [ -n "${FORMS_REPO_URL}" ]; then info "would: clone or fast-forward the forms repo ${FORMS_REPO_URL} into ${FORMS_CLONE_DIR} and mount its clinical_forms read-only$( [ "${PHASE:-install}" = seed ] && printf '; check every published form row has its file')"
  else info "would: mount the frozen forms copy ${FORMS_FROZEN_DIR} read-write (no forms repo configured)"; fi
  exit 0
fi
[ -f "$E" ] || fail "no ${E}; task 020 renders it"
# The answers name the forms repo at install; clinic/.env keeps it for the seed
# sitting and for scripts/update-forms.sh, which read nothing else. A relative
# key path is taken from where the installer runs, and kept absolute: the
# schedule runs update-forms.sh from elsewhere.
if [ "${PHASE:-install}" = install ]; then
  case "${FORMS_REPO_KEY}" in
    ''|/*) ;;
    *) FORMS_REPO_KEY="$(pwd -P)/${FORMS_REPO_KEY#./}"; info "FORMS_REPO_KEY is a relative path; kept as ${FORMS_REPO_KEY}" ;;
  esac
  env_put "$E" FORMS_REPO_URL "${FORMS_REPO_URL}"; env_put "$E" FORMS_REPO_KEY "${FORMS_REPO_KEY}"
fi
export FORMS_REPO_URL FORMS_REPO_KEY
# The concept and row/file checks need the database the clinic will run on: the
# seed's. The baseline is replaced at seed, so install checks neither.
check=0; [ "${PHASE:-install}" = seed ] && check=1
forms_sync "$check" 0
dir="$(forms_folder_for "${FORMS_REPO_URL}")"; ro="$(forms_read_only_for "${FORMS_REPO_URL}")"
v="$(forms_folder_verdict "$dir")" || fail "$v"
env_put "$E" FORMS_DIR "$dir"; env_put "$E" FORMS_READ_ONLY "$ro"
if [ -n "${FORMS_REPO_URL}" ]; then ok "forms: ${v#ok }, mounted read-only (the forms repo's clone)"
else ok "forms: ${v#ok }, mounted read-write (no forms repo configured: the frozen copy)"; fi
if [ "$check" = 1 ]; then
  strict=0; [ -n "${FORMS_REPO_URL}" ] && strict=1
  forms_rowfile_gate "$dir" "$strict"
else
  info "the row/file check runs at seed, against the hub's data"
fi
