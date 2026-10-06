#!/usr/bin/env bash
# Take the forms repo's latest form files on a running clinic node. Run it from
# a schedule (every 15 minutes) and on demand:
#
#   clinic/scripts/update-forms.sh [--dry-run]
#
#   1. fetch the forms repo and fast-forward clinic/forms; a checkout with local
#      edits, or at a commit the forms repo does not contain, is refused and
#      left exactly as it is;
#   2. check the incoming forms' concepts against this node's OpenMRS: a form
#      that uses a concept the node lacks is a WARN, never a refusal;
#   3. row/file check: every published, unretired form row in this node's
#      database must have its file in the forms folder; a file with no row is
#      fine (its rows have not synced yet, or it is an old version kept for
#      saved observations);
#   4. print a summary.
#
# OpenMRS is never restarted: it reads a form's file when the form is opened,
# so a user sees a new version after reloading the page. The rows of a new
# form arrive by sync from the hub, independently of this script.
#
# --dry-run fetches and shows the incoming commits and MANIFEST.tsv changes,
# and changes nothing: no fast-forward, no database read, no clinic/.env edit.
#
# Exit 0: clinic/forms holds what the forms repo holds and every published form
# has its file. Non-zero: a FAIL line says why (fetch or clone failed, a
# refused checkout, a missing file). With no forms repo configured
# (FORMS_REPO_URL empty in clinic/.env) the node runs the frozen copy; the run
# reports any form missing its file there as a WARN and exits 0.
#
# On a node whose clinic/.env names a forms repo but that runs from another
# folder (no clone yet, or the frozen copy), the first run clones the repo and
# points FORMS_DIR and FORMS_MOUNT_MODE in clinic/.env at the clone, read-only.
# The openmrs service takes that mount when it is next recreated; the run says
# so, and does not recreate it.
#
# Reads FORMS_REPO_URL, FORMS_REPO_KEY, FORMS_DIR, FORMS_MOUNT_MODE and
# COMPOSE_PROJECT_NAME from clinic/.env. Settings for tests and for lists
# taken elsewhere: FORMS_CONCEPTS_FILE, FORMS_KNOWN_FORMS_FILE, FORMS_ROWS_FILE
# (clinic/install/forms.sh).
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
COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
export FORMS_REPO_URL FORMS_REPO_KEY COMPOSE_PROJECT_NAME
mounted="$(env_get "$E" FORMS_DIR)"; mounted="${mounted:-${FORMS_FROZEN_DIR}}"
mode="$(env_get "$E" FORMS_MOUNT_MODE)"; mode="${mode:-rw}"
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
if [ "$mounted" != "$dir" ] || [ "$mode" != ro ]; then
  env_put "$E" FORMS_DIR "$dir"; env_put "$E" FORMS_MOUNT_MODE ro
  warn "clinic/.env now mounts ${dir} read-only (it named ${mounted}, ${mode}). The openmrs service reads the old folder until it is recreated; this script does not do that. When convenient, from clinic/: docker compose (or docker-compose) with the node's profiles, up -d --no-deps --force-recreate openmrs"
fi

log ""
log "summary"
info "forms repo: $(printf '%s' "${FORMS_OLD_REV:-none}" | cut -c1-7) -> $(printf '%s' "${FORMS_NEW_REV}" | cut -c1-7)"
changes="$(forms_manifest_diff "$before" "${FORMS_CLONE_DIR}/MANIFEST.tsv")"
if [ -n "$changes" ]; then
  info "MANIFEST.tsv changes (< before, > now):"
  printf '%s\n' "$changes" | sed 's/^/    /'
fi
info "OpenMRS was not restarted: it reads a form's file when the form is opened"
forms_rowfile_gate "$dir" 1
