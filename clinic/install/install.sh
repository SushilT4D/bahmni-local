#!/usr/bin/env bash
# Clinic installer -- takes a fresh macOS host, running podman, to a syncing
# clinic node of this fleet running on the hub's data, loaded once from the
# seed folder. Runs clinic/install/tasks/NN-*.sh in order;
# each task is idempotent and ends with a check read back from the live system.
# It never touches the hub, the ledgers or GitHub: task 110 prints the hub join
# for the operator.
#
# Usage:
#   clinic/install/install.sh --clinic <slug> --seed <folder> [--secrets <file>] [--versions <file>]
#                             [--only NNN] [--from NNN] [--dry-run]
#   clinic/install/install.sh --answers clinic-<slug>.env ...   (hand-written answers)
#   clinic/install/install.sh --clinics | --list
# --seed: the folder the operator took from the hub (openmrs.sql.gz, odoo.sql.gz,
#   openelis.sql.gz, manifest.env); at most SEED_MAX_AGE_DAYS (6) old.
# --secrets: the operator's hub secrets file (the four hub credentials).
# --versions: application image versions to run instead of the defaults in
#   sync/versions.env, as KEY=value lines (e.g. BAHMNI_WEB_IMAGE=bhs-9.9.9; a bare
#   tag keeps the image name). Without it, --clinic asks on the terminal.
# --clinic composes the eleven answers from sync/fleet/<slug>.env, the residue
# ledger, sync/hub.env and --secrets, asking on the terminal for what is still
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR

# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"

usage(){ sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
ANSWERS=""
CLINIC=""
SECRETS_FILE=""
IMAGE_CHOICES_FILE=""
SEED_DIR=""
ONLY=""
FROM=""
LIST=0
CLINICS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS="$2"; shift 2 ;;
    --clinic)  CLINIC="$2"; shift 2 ;;
    --clinics) CLINICS=1; shift ;;
    --secrets)  SECRETS_FILE="$2"; shift 2 ;;
    --versions) IMAGE_CHOICES_FILE="$2"; shift 2 ;;
    --seed)     SEED_DIR="$2"; shift 2 ;;
    --only)    ONLY="$2"; shift 2 ;;
    --from)    FROM="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --list)    LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done

export DRY
require_macos

if [ "$LIST" = 1 ]; then
  for t in "${TASKS_DIR}"/[0-9]*-*.sh; do printf '  %s\n' "$(basename "$t" .sh)"; done; exit 0
fi

if [ "$CLINICS" = 1 ]; then log "registered clinics (${FLEET_DIR}; residue from ${LEDGER}):"; fleet_table; exit 0; fi
if [ -z "$ANSWERS" ] && [ -z "$CLINIC" ]; then
  if interactive; then
    log "registered clinics:"; fleet_table
    printf '  which clinic is this host? ' >&2; IFS= read -r CLINIC || CLINIC=""
    [ -n "$CLINIC" ] || fail "no clinic chosen"
  else
    usage; fail "--clinic <slug> or --answers <file> is required"
  fi
fi

[ -z "$ANSWERS" ] || [ -f "$ANSWERS" ] || fail "answers file not found: $ANSWERS"
if [ -n "$SECRETS_FILE" ]; then [ -f "$SECRETS_FILE" ] || fail "secrets file not found: $SECRETS_FILE"; SECRETS_FILE="$(cd "$(dirname "$SECRETS_FILE")" && pwd)/$(basename "$SECRETS_FILE")"; fi
if [ -n "$IMAGE_CHOICES_FILE" ]; then [ -f "$IMAGE_CHOICES_FILE" ] || fail "image versions file not found: $IMAGE_CHOICES_FILE"; IMAGE_CHOICES_FILE="$(cd "$(dirname "$IMAGE_CHOICES_FILE")" && pwd)/$(basename "$IMAGE_CHOICES_FILE")"; fi
[ -n "$SEED_DIR" ] || { usage; fail "--seed <folder> is required: the folder the operator took from the hub"; }
[ -d "$SEED_DIR" ] || fail "seed folder not found: $SEED_DIR"
SEED_DIR="$(cd "$SEED_DIR" && pwd)"
export SECRETS_FILE IMAGE_CHOICES_FILE SEED_DIR

compose_answers(){
  local slug="$1" f r out k
  f="$(fleet_file "$slug")" || fail "no clinic '$slug' under ${FLEET_DIR}; known: $(fleet_slugs | tr '\n' ' ')"
  r="$(ledger_residue "$slug")"; [ -n "$r" ] || fail "'$slug' has no residue in ${LEDGER}: the operator allocates first (skills/install-clinic.sh allocate $slug <free residue>), commits, pushes, and this checkout pulls"
  [ -f "${HUB_ENV}" ] || fail "hub endpoint file missing: ${HUB_ENV}"
  out="${ANSWERS_DIR}/clinic-${slug}.env"
  if [ -s "$out" ] && [ -z "$(answers_missing "$out")" ]; then
    info "answers: reusing $out (delete it to compose afresh)"; ANSWERS="$out"; return 0
  fi

  set -a; . "$f"; . "${HUB_ENV}"; [ -z "${SECRETS_FILE}" ] || . "${SECRETS_FILE}"; set +a
  [ "$(printf '%s' "${CLINIC_SLUG:-}" | tr 'A-Z' 'a-z')" = "$slug" ] || fail "$f says CLINIC_SLUG='${CLINIC_SLUG:-}', not $slug"
  RESIDUE="$r"; [ -n "${SITE_NUMBER:-}" ] || SITE_NUMBER="$r"
  ask CLINIC_PHONE "clinic phone, E.164" "+910000000000" "sync/fleet/${slug}.env"
  for k in $SECRET_KEYS; do ask_secret "$k" "--secrets"; done
  [ -n "${IMAGE_CHOICES_FILE}" ] || image_choose
  export RESIDUE SITE_NUMBER; answer_defaults_apply
  answers_write "$out"; image_choices_write "$out"; ANSWERS="$out"
  info "answers: composed $out (mode 600) from $f, ${LEDGER}, ${HUB_ENV} and the hub secrets"
}

set -a; . "${VERSIONS_FILE}"; set +a
[ -z "$IMAGE_CHOICES_FILE" ] || image_choices_load "$IMAGE_CHOICES_FILE"
[ -z "$CLINIC" ] || compose_answers "$(printf '%s' "$CLINIC" | tr 'A-Z' 'a-z')"

REQUIRED="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
set -a; . "$ANSWERS"; set +a
answer_defaults_apply

set -a; . "${VERSIONS_FILE}"; set +a
image_keys_from "$ANSWERS"
[ -z "$IMAGE_CHOICES_FILE" ] || image_choices_load "$IMAGE_CHOICES_FILE"
for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || image_set "$k" "$v"; done
missing=""
for k in $REQUIRED; do eval "v=\${$k:-}"; [ -n "$v" ] || missing="$missing $k"; done
[ -z "$missing" ] || fail "answers file is missing:$missing"
printf '%s' "$MRN_PREFIX" | grep -Eq '^[A-Z]{2,4}$' || fail "MRN_PREFIX '$MRN_PREFIX' must be 2-4 capital letters"
printf '%s' "$SITE_NUMBER" | grep -Eq '^[0-9]{1,5}$' || fail "SITE_NUMBER '$SITE_NUMBER' must be digits"
derive_identity "$CLINIC_SLUG" "$RESIDUE"
refuse_inherited_alias "$LOCAL_CLUSTER_ALIAS" "$CLINIC_SLUG"
export CLINIC_DIR REPO_DIR LEDGER

if [ "$DRY" = 1 ]; then
  INSTALL_LOG="${INSTALL_LOG:-${TMPDIR:-/tmp}/clinic-install-${CLINIC_SLUG:-node}.log}"
else
  INSTALL_LOG="${INSTALL_LOG:-${HOME}/clinic-install-${CLINIC_SLUG:-node}.log}"
fi

export INSTALL_LOG
exec > >(tee -a "${INSTALL_LOG}") 2>&1
if [ "${_INSTALL_LOG_STARTED:-0}" != 1 ]; then
  gitsha="$(cd "${REPO_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)"
  gitsha="${gitsha:-unknown}"
  hdr="$(date -u +%Y-%m-%dT%H:%M:%SZ) clinic-install slug=${CLINIC_SLUG} sha=${gitsha}"
  [ -n "$FROM" ] && hdr="${hdr} --from ${FROM}"
  [ -n "$ONLY" ] && hdr="${hdr} --only ${ONLY}"
  log ""
  log "===== ${hdr} ====="
  export _INSTALL_LOG_STARTED=1
fi

log "install log: ${INSTALL_LOG}"

log "clinic installer  slug=${CLINIC_SLUG} residue=${RESIDUE} dry=${DRY}"
log "  clinic dir: ${CLINIC_DIR}"
log "  seed:       ${SEED_DIR}"
image_choices_report

. "${INSTALL_DIR}/state.sh"
st="$(stamp_get STATE)"
v="$(run_gate_verdict "$st" "${FROM}" "${ONLY}")" || { printf '\n  >>> %s\n\n' "$v" >&2; fail "$v"; }
if [ -n "${FROM}${ONLY}" ] && [ "$st" = SEEDING ]; then
  sync_started=0; resume_redoes_drop "${FROM}" "${ONLY}" && sync_started="$(stamp_get SYNC_STARTED)"
  v="$(stamp_gate_verdict "$st" "${sync_started:-0}")" || { printf '\n  >>> %s\n\n' "$v" >&2; fail "$v"; }
fi
if [ -n "$CLINIC" ]; then how="--clinic $(printf '%q' "$CLINIC")"; else how="--answers $(printf '%q' "$ANSWERS")"; fi
[ -z "${SECRETS_FILE:-}" ] || how="${how} --secrets $(printf '%q' "$SECRETS_FILE")"
[ -z "${IMAGE_CHOICES_FILE:-}" ] || how="${how} --versions $(printf '%q' "$IMAGE_CHOICES_FILE")"
how="${how} --seed $(printf '%q' "$SEED_DIR")"
run_tasks "$(printf '%q' "$0") ${how}"
if [ "${DRY}" != 1 ] && [ -z "${ONLY}" ]; then
  stamp_put STATE SEEDED; stamp_put SEEDED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

log ""
if [ "${DRY}" = 1 ]; then log "dry run: nothing was installed or changed. Each 'would:' line above is a step a real install takes; it was not taken."
else log "done: this clinic runs on the hub's data. The operator now joins it to the hub."; fi
log "install log: ${INSTALL_LOG}"
