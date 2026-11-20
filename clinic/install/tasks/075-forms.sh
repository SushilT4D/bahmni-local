#!/usr/bin/env bash
# Sets up the observation forms folder (the forms repo clone, or the frozen copy) and checks it against the database.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/forms.sh"
begin_task "75 · forms"
E="${CLINIC_DIR}/.env"
FORMS_REPO_URL="${FORMS_REPO_URL:-}"
FORMS_REPO_KEY="${FORMS_REPO_KEY:-}"
if [ "${DRY}" = 1 ]; then
  if [ -n "${FORMS_REPO_URL}" ]; then info "would: clone or fast-forward the forms repo ${FORMS_REPO_URL} into ${FORMS_CLONE_DIR} and mount its clinical_forms read-only; check every published form row has its file"
  else info "would: mount the frozen forms copy ${FORMS_FROZEN_DIR} read-write (no forms repo configured)"; fi
  exit 0
fi

[ -f "$E" ] || fail "no ${E}; task 020 renders it"

case "${FORMS_REPO_KEY}" in
  ''|/*) ;;
  *) FORMS_REPO_KEY="$(pwd -P)/${FORMS_REPO_KEY#./}"; info "FORMS_REPO_KEY is a relative path; kept as ${FORMS_REPO_KEY}" ;;
esac

env_put "$E" FORMS_REPO_URL "${FORMS_REPO_URL}"; env_put "$E" FORMS_REPO_KEY "${FORMS_REPO_KEY}"

export FORMS_REPO_URL FORMS_REPO_KEY

forms_sync 1 0
dir="$(forms_folder_for "${FORMS_REPO_URL}")"
ro="$(forms_read_only_for "${FORMS_REPO_URL}")"
v="$(forms_folder_verdict "$dir")" || fail "$v"
env_put "$E" FORMS_DIR "$dir"; env_put "$E" FORMS_READ_ONLY "$ro"

grep -q '^FORMS_MOUNT_MODE=' "$E" && { env_del "$E" FORMS_MOUNT_MODE; info "removed FORMS_MOUNT_MODE from clinic/.env: FORMS_READ_ONLY replaces it"; }
if [ -n "${FORMS_REPO_URL}" ]; then ok "forms: ${v#ok }, mounted read-only (the forms repo's clone)"
else ok "forms: ${v#ok }, mounted read-write (no forms repo configured: the frozen copy)"; fi
strict=0; [ -n "${FORMS_REPO_URL}" ] && strict=1
forms_rowfile_gate "$dir" "$strict"
