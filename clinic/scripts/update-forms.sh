#!/usr/bin/env bash
# Update the clinic's forms checkout.
# Usage: clinic/scripts/update-forms.sh [--dry-run]
# --dry-run shows incoming changes without updating files or clinic/.env.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
. "${HERE}/../install/lib.sh"
. "${INSTALL_DIR}/forms.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
FORMS_REPO_URL="$(env_get "$E" FORMS_REPO_URL)"; FORMS_REPO_KEY="$(env_get "$E" FORMS_REPO_KEY)"
COMPOSE_PROJECT_NAME=bahmni   # name: in docker-compose.yml
export FORMS_REPO_URL FORMS_REPO_KEY COMPOSE_PROJECT_NAME
mounted="$(env_get "$E" FORMS_DIR)"; mounted="${mounted:-${FORMS_FROZEN_DIR}}"
ro="$(env_get "$E" FORMS_READ_ONLY)"; ro="${ro:-false}"
begin_task "update forms$( [ "$DRYRUN" = 1 ] && printf ' (dry run: nothing changes)')"

if [ -z "${FORMS_REPO_URL}" ]; then
  log "no forms repo configured (FORMS_REPO_URL in clinic/.env): this node runs the frozen copy ${mounted}; nothing to update."
  [ "$DRYRUN" = 1 ] && exit 0
  forms_rowfile_gate "$mounted" 0
  exit 0
fi

before="$(mktemp "${TMPDIR:-/tmp}/forms-manifest.XXXXXX")"; trap 'rm -f "$before"' EXIT
[ ! -f "${FORMS_CLONE_DIR}/MANIFEST.tsv" ] || cp "${FORMS_CLONE_DIR}/MANIFEST.tsv" "$before"
forms_sync 1 "$DRYRUN"
[ "$DRYRUN" = 1 ] && { log "dry run: nothing changed."; exit 0; }

dir="$(forms_folder_for "${FORMS_REPO_URL}")"
v="$(forms_folder_verdict "$dir")" || fail "$v"
ok "forms: ${v#ok }"
# FORMS_MOUNT_MODE was the mount setting before FORMS_READ_ONLY; compose no longer reads it
grep -q '^FORMS_MOUNT_MODE=' "$E" && { env_del "$E" FORMS_MOUNT_MODE; info "removed FORMS_MOUNT_MODE from clinic/.env: FORMS_READ_ONLY replaces it"; }
if [ "$mounted" != "$dir" ] || [ "$ro" != true ]; then
  env_put "$E" FORMS_DIR "$dir"; env_put "$E" FORMS_READ_ONLY true
  warn "clinic/.env now mounts ${dir} read-only (it named ${mounted}, $(forms_mount_word "$ro")). The openmrs service reads the old folder until it is recreated; this script does not do that. When convenient: clinic/scripts/recreate-openmrs.sh, which checks the new mount first"
fi

log ""
log "summary"
info "forms repo: $(printf '%s' "${FORMS_OLD_REV:-none}" | cut -c1-7) -> $(printf '%s' "${FORMS_NEW_REV}" | cut -c1-7)"
changes="$(forms_manifest_diff "$before" "${FORMS_CLONE_DIR}/MANIFEST.tsv")"
if [ -n "$changes" ]; then
  info "MANIFEST.tsv changes (< before, > now):"
  printf '%s\n' "$changes" | sed 's/^/    /'
fi
[ "${FORMS_CONCEPTS_UNCHECKED:-0}" = 0 ] || warn "concepts NOT checked: the concept check could not run (its WARN is above); a form may use a concept this node lacks"
info "OpenMRS was not restarted: it reads a form's file when the form is opened"
forms_rowfile_gate "$dir" 1
