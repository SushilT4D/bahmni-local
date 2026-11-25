#!/usr/bin/env bash
# Creates the observation forms folder, which forms-sync fills, and checks it against the database.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
. "${INSTALL_DIR}/forms.sh"
begin_task "75 · forms"
E="${CLINIC_DIR}/.env"
if [ "${DRY}" = 1 ]; then info "would: create the forms folder data/clinical_forms and its translations/ if absent; list the published forms whose file has not arrived"; exit 0; fi

[ -f "$E" ] || fail "no ${E}; task 020 renders it"
dir="$(env_get "$E" CONTAINER_DATA_PATH)/data/clinical_forms"
mkdir -p "$dir/translations" || fail "could not create ${dir}/translations"
v="$(forms_folder_verdict "$dir")" || fail "$v"
env_put "$E" FORMS_DIR "$dir"
ok "forms: ${v#ok }"
forms_rowfile_gate "$dir" 0
