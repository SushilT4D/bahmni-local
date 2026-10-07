#!/usr/bin/env bash
# Take the forms repo's latest form files on a running clinic node. Run it from
# a schedule (every 15 minutes) and on demand:
#
#   clinic/scripts/update-forms.sh [--dry-run]
#
#   1. fetch the forms repo and fast-forward clinic/forms; a checkout with local
#      edits, or at a commit the forms repo does not contain, is refused and
#      left exactly as it is;
#   2. check the incoming forms' concepts against this node's OpenMRS, with
#      the checker this node already runs: a form that uses a concept the node
#      lacks is a WARN, never a refusal;
#   3. row/file check: every published, unretired form row in this node's
#      database must have its file in the forms folder; a file with no row is
#      fine (its rows have not synced yet, or it is an old version kept for
#      saved observations);
#   4. print a summary, which says "concepts NOT checked" when the concept
#      check could not run.
#
# One run at a time: a run that finds another holding clinic/forms changes
# nothing and exits 4.
#
# OpenMRS is never restarted: it reads a form's file when the form is opened,
# so a user sees a new version after reloading the page. The rows of a new
# form arrive by sync from the hub, independently of this script. This script
# only ever adds form files to what the node has; the node's form rows come
# from its seed and the down sync.
#
# --dry-run fetches and shows the incoming commits and MANIFEST.tsv changes,
# and changes nothing: no fast-forward, no database read, no clinic/.env edit.
#
# Exit codes:
#   0  clinic/forms holds what the forms repo holds and every published form
#      has its file;
#   1  a check refused (a refused checkout, a missing file, a bad setting):
#      act on the FAIL line;
#   3  the forms repo could not be reached (fetch or clone failed): the forms
#      already here keep working, and the next run tries again;
#   4  another run holds clinic/forms.
# With no forms repo configured (FORMS_REPO_URL empty in clinic/.env) the node
# runs the frozen copy; the run reports any form missing its file there as a
# WARN and exits 0.
#
# On a node whose clinic/.env names a forms repo but that runs from another
# folder (no clone yet, or the frozen copy), the first run clones the repo and
# points FORMS_DIR and FORMS_READ_ONLY in clinic/.env at the clone, read-only.
# The openmrs service takes that mount when it is next recreated, with
# scripts/recreate-openmrs.sh; the run says so, and does not recreate it.
#
# Reads FORMS_REPO_URL, FORMS_REPO_KEY, FORMS_DIR, FORMS_READ_ONLY and
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
