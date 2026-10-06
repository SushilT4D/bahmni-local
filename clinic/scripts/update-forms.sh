#!/usr/bin/env bash
# Take new forms on a running clinic node (or the hub's OpenMRS, which takes
# them first): fast-forward clinic/forms to the forms repo, check the incoming
# forms' concepts against this node's OpenMRS, recreate the openmrs service
# only (the Initializer loads forms at start), wait for it, and verify every
# form MANIFEST.tsv lists is published at the listed version.
#
#   clinic/scripts/update-forms.sh [--dry-run] [--restart]
#
# --dry-run fetches the forms repo and shows what would change (the commits,
# the MANIFEST.tsv lines, the form files); nothing under clinic/ changes and
# nothing restarts.
# --restart recreates openmrs even when clinic/forms is already current (an
# earlier run that stopped after the fast-forward). Without it, a current
# checkout only has its published versions verified.
#
# Reads FORMS_REPO_URL and FORMS_REPO_KEY from clinic/.env (install task 075
# writes them from the answers). With no forms repo configured it refreshes
# clinic/forms/bahmniforms from the config image's forms and restarts nothing.
#
# Settings:
#   FORMS_OPENMRS_WAIT_S          how long to wait for OpenMRS after the restart
#                                 (default 1200: the Initializer runs first)
#   FORMS_ALLOW_MISSING_CONCEPTS  1 = take forms whose concepts this node lacks
#   FORMS_CONCEPTS_FILE           a concept uuid list taken elsewhere, instead
#                                 of reading this node's database
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
. "${HERE}/../install/lib.sh"
. "${INSTALL_DIR}/forms.sh"
usage(){ sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
DRYRUN=0; RESTART=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRYRUN=1; shift ;;
    --restart) RESTART=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
FORMS_REPO_URL="$(env_get "$E" FORMS_REPO_URL)"; FORMS_REPO_KEY="$(env_get "$E" FORMS_REPO_KEY)"
COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
export FORMS_REPO_URL FORMS_REPO_KEY COMPOSE_PROJECT_NAME
begin_task "update forms$( [ "$DRYRUN" = 1 ] && printf ' (dry run: nothing changes)')"

if [ -z "${FORMS_REPO_URL}" ]; then
  forms_sync 0 "$DRYRUN"
  [ "$DRYRUN" = 1 ] && { log "dry run: nothing changed."; exit 0; }
  v="$(forms_mount_verdict "${FORMS_DIR}/bahmniforms")" || fail "$v"
  ok "forms: ${v#ok }"
  log "no forms repo configured (FORMS_REPO_URL in clinic/.env): OpenMRS reads these forms at its next start; nothing was restarted."
  exit 0
fi

before_manifest="$(mktemp "${TMPDIR:-/tmp}/forms-manifest.XXXXXX")"; trap 'rm -f "$before_manifest"' EXIT
[ ! -f "${FORMS_DIR}/MANIFEST.tsv" ] || cp "${FORMS_DIR}/MANIFEST.tsv" "$before_manifest"
forms_sync 1 "$DRYRUN"
[ "$DRYRUN" = 1 ] && { log "dry run: nothing changed."; exit 0; }
v="$(forms_mount_verdict "${FORMS_DIR}/bahmniforms")" || fail "$v"
ok "forms: ${v#ok }"
[ -f "${FORMS_DIR}/MANIFEST.tsv" ] || fail "the forms repo has no MANIFEST.tsv; the published versions cannot be verified"
rows="$(forms_manifest_rows "${FORMS_DIR}/MANIFEST.tsv")" || fail "MANIFEST.tsv could not be read (above)"
[ -n "${CT:-}" ] || setup_compose

if [ "${FORMS_CHANGED}" = 0 ] && [ "$RESTART" = 0 ]; then
  info "clinic/forms already holds what the forms repo holds: OpenMRS is not restarted, the published versions are checked (--restart recreates it)"
else
  # The openmrs service alone, recreated so a compose file that gained the
  # forms mount since the container was made takes effect.
  compose up -d --no-deps --force-recreate openmrs >/dev/null || fail "could not recreate the openmrs service: ${COMPOSE_CMD} ${PROFILES} up -d openmrs"
  ok "openmrs recreated; the Initializer loads the changed forms as it starts"
  url="${OPENMRS_SESSION_URL:-https://localhost/openmrs/ws/rest/v1/session}"
  budget="${FORMS_OPENMRS_WAIT_S:-1200}"
  info "waiting up to ${budget}s for ${url} to answer 200 (FORMS_OPENMRS_WAIT_S overrides)"
  t0="$(date +%s)"; last=none
  while :; do
    last="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || true)"; last="${last:-none}"
    [ "$last" = 200 ] && break
    el=$(( $(date +%s) - t0 ))
    [ "$el" -lt "$budget" ] || fail "OpenMRS did not answer 200 at ${url}: budget ${budget}s (FORMS_OPENMRS_WAIT_S), waited ${el}s, last HTTP status ${last} (302 = still starting). Once it answers, run this script again: it verifies the published versions without another restart. ${COMPOSE_CMD} logs openmrs"
    sleep 10
  done
  ok "OpenMRS answers 200 after $(( $(date +%s) - t0 ))s"
fi

# Every form the manifest lists must be published at the listed version.
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
n=0; good=0; bad_list=""
TAB="$(printf '\t')"
while IFS="$TAB" read -r name ver; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  q="select count(*) from form where name=$(forms_sql_quote "$name") and version=$(forms_sql_quote "$ver") and published=1 and retired=0"
  c="$(printf '%s' "$q" | ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N openmrs' 2>/dev/null || true)"
  if [ "${c:-0}" -ge 1 ] 2>/dev/null; then good=$((good + 1)); else bad_list="${bad_list}${bad_list:+, }${name} v${ver}"; fi
done <<EOF
$rows
EOF

log ""
log "summary"
info "forms repo: $(printf '%s' "${FORMS_OLD_REV:-none}" | cut -c1-7) -> $(printf '%s' "${FORMS_NEW_REV}" | cut -c1-7)"
changes="$(diff "$before_manifest" "${FORMS_DIR}/MANIFEST.tsv" 2>/dev/null | grep -E '^[<>]' || true)"
if [ -n "$changes" ]; then
  info "MANIFEST.tsv changes (< before, > now):"
  printf '%s\n' "$changes" | sed 's/^/    /'
fi
info "published at the listed version: ${good} of ${n}"
[ -z "$bad_list" ] || fail "not published at the listed version in this node's OpenMRS: ${bad_list}. The Initializer loads forms only at start: if OpenMRS has not restarted since clinic/forms changed, run this again with --restart; otherwise ${COMPOSE_CMD} logs openmrs | grep -i -e initializer -e form"
ok "every form in MANIFEST.tsv is published at its listed version"
