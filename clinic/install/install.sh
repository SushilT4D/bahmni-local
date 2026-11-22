#!/usr/bin/env bash
# Clinic installer -- takes a fresh macOS host, running podman, to a syncing
# clinic node of this fleet running on the hub's data, loaded once from the
# seed folder. Runs clinic/install/tasks/NN-*.sh in order;
# each task is idempotent and ends with a check read back from the live system.
# It never touches the hub, sync/clinics.json or GitHub: task 110 prints the hub join
# for the operator.
#
# Usage:
#   clinic/install/install.sh [--clinic <slug>] [--seed <folder>] [--secrets <file>] [--versions <file>]
#                             [--only NNN] [--from NNN] [--dry-run]
#   clinic/install/install.sh --clinics | --list
# --seed: the folder the operator took from the cloud (openmrs.sql.gz). Needed only when
#   openmrs is not on this Mac yet. Odoo and OpenELIS load from their baseline images (sync/versions.env).
# --secrets: the operator's hub secrets file (the four hub credentials).
# --versions: application image versions to run instead of the defaults in
#   sync/versions.env, as KEY=value lines (e.g. BAHMNI_WEB_IMAGE=bhs-9.9.9; a bare
#   tag keeps the image name). Without it, the defaults.
# Without --clinic, the clinic is BHS_LOCATION in clinic/.env. Nothing is asked.
# clinic/.env is the source of truth: every value it holds is used as it is.
# A value it lacks comes from sync/clinics.json or --secrets; a feed password still missing is generated. Task 020 writes them all
# into clinic/.env.
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR

# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"

usage(){ sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
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

if [ "$CLINICS" = 1 ]; then log "clinics in ${CLINICS_JSON}:"; clinic_table; exit 0; fi
command -v jq >/dev/null 2>&1 || fail "jq is missing: it reads sync/clinics.json (macOS ships it in /usr/bin; brew install jq)"
ENV_CLINIC=""
if [ -f "${CLINIC_DIR}/.env" ]; then
  ENV_CLINIC="$(env_get "${CLINIC_DIR}/.env" BHS_LOCATION)"
  case "$ENV_CLINIC" in '<'*) ENV_CLINIC="" ;; esac
fi
CLINIC="$(printf '%s' "$CLINIC" | tr 'A-Z' 'a-z')"
if [ -z "$CLINIC" ]; then
  CLINIC="$ENV_CLINIC"
  [ -n "$CLINIC" ] || { usage; fail "no BHS_LOCATION in ${CLINIC_DIR}/.env: --clinic <slug> is required"; }
  log "clinic ${CLINIC} (BHS_LOCATION in ${CLINIC_DIR}/.env)"
elif [ -n "$ENV_CLINIC" ] && [ "$ENV_CLINIC" != "$CLINIC" ]; then
  fail "${CLINIC_DIR}/.env belongs to clinic '${ENV_CLINIC}' (BHS_LOCATION), not '${CLINIC}': move it aside to install ${CLINIC} afresh"
fi

if [ -n "$SECRETS_FILE" ]; then [ -f "$SECRETS_FILE" ] || fail "secrets file not found: $SECRETS_FILE"; SECRETS_FILE="$(cd "$(dirname "$SECRETS_FILE")" && pwd)/$(basename "$SECRETS_FILE")"; fi
if [ -n "$IMAGE_CHOICES_FILE" ]; then [ -f "$IMAGE_CHOICES_FILE" ] || fail "image versions file not found: $IMAGE_CHOICES_FILE"; IMAGE_CHOICES_FILE="$(cd "$(dirname "$IMAGE_CHOICES_FILE")" && pwd)/$(basename "$IMAGE_CHOICES_FILE")"; fi
if [ -n "$SEED_DIR" ]; then
  [ -d "$SEED_DIR" ] || fail "seed folder not found: $SEED_DIR"
  SEED_DIR="$(cd "$SEED_DIR" && pwd)"
fi
export SECRETS_FILE IMAGE_CHOICES_FILE SEED_DIR

load_inputs(){ # SLUG
  local slug="$1" r k v E="${CLINIC_DIR}/.env"
  clinic_known "$slug" || fail "no clinic '$slug' in ${CLINICS_JSON}; known: $(clinic_slugs | tr '\n' ' ')"
  r="$(clinic_residue "$slug")"; [ -n "$r" ] || fail "'$slug' has no site_number in ${CLINICS_JSON}: the operator sets it there, commits, pushes, and this checkout pulls"
  CLINIC_SLUG="$slug"; MRN_PREFIX="$(clinic_get "$slug" mrn_prefix)"
  [ -z "${SECRETS_FILE}" ] || { set -a; . "${SECRETS_FILE}"; set +a; }
  if [ -f "$E" ]; then
    for k in $INPUT_KEYS $OPTIONAL_INPUT_KEYS; do v="$(env_get "$E" "$k")"; [ -z "$v" ] || { eval "$k=\$v"; export "$k"; }; done
  fi
  [ -n "${BHS_SITE_NUMBER:-}" ] || BHS_SITE_NUMBER="$r"
  for k in $CLOUD_KEYS; do eval "[ -n \"\${$k:-}\" ]" || fail "$k is not in ${E}: the hub endpoint (REMOTE_KAFKA_BOOTSTRAP_SERVERS, REMOTE_KAFKA_USERNAME, REMOTE_KAFKA_SECURITY_PROTOCOL) comes from there"; done
  for k in $SECRET_KEYS; do ask_secret "$k" "--secrets"; done
  export CLINIC_SLUG BHS_SITE_NUMBER MRN_PREFIX; input_defaults_apply
  info "clinic values: ${E} first, then ${CLINICS_JSON}${SECRETS_FILE:+ and ${SECRETS_FILE}}"
}

load_inputs "$CLINIC"

REQUIRED="CLINIC_SLUG BHS_SITE_NUMBER MRN_PREFIX REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
set -a; . "${VERSIONS_FILE}"; set +a
[ -z "$IMAGE_CHOICES_FILE" ] || image_choices_load "$IMAGE_CHOICES_FILE"
for k in $IMAGE_KEYS; do eval "v=\${$k:-}"; [ -z "$v" ] || image_set "$k" "$v"; done
missing=""
for k in $REQUIRED; do eval "v=\${$k:-}"; [ -n "$v" ] || missing="$missing $k"; done
[ -z "$missing" ] || fail "no value for:$missing"
printf '%s' "$BHS_SITE_NUMBER" | grep -Eq '^[0-9]{1,5}$' || fail "BHS_SITE_NUMBER '$BHS_SITE_NUMBER' must be digits"
derive_identity "$CLINIC_SLUG" "$BHS_SITE_NUMBER"
export CLINIC_DIR REPO_DIR CLINICS_JSON

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

log "clinic installer  slug=${CLINIC_SLUG} residue=${BHS_SITE_NUMBER} dry=${DRY}"
log "  clinic dir: ${CLINIC_DIR}"
log "  seed:       ${SEED_DIR:-none (databases already on this Mac are kept)}"
image_choices_report

. "${INSTALL_DIR}/state.sh"
how="--clinic $(printf '%q' "$CLINIC")"
[ -z "${SECRETS_FILE:-}" ] || how="${how} --secrets $(printf '%q' "$SECRETS_FILE")"
[ -z "${IMAGE_CHOICES_FILE:-}" ] || how="${how} --versions $(printf '%q' "$IMAGE_CHOICES_FILE")"
[ -z "$SEED_DIR" ] || how="${how} --seed $(printf '%q' "$SEED_DIR")"
if [ -z "${ONLY}" ] || [ "${ONLY}" = 010 ]; then
  if [ -z "${FROM}" ] || [ "${FROM}" -le 10 ]; then . "${INSTALL_DIR}/host-macos.sh"; sudo_upfront; fi
fi
run_tasks "$(printf '%q' "$0") ${how}"
if [ "${DRY}" != 1 ] && [ -z "${ONLY}" ]; then
  stamp_put STATE SEEDED; stamp_put SEEDED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

log ""
if [ "${DRY}" = 1 ]; then log "dry run: nothing was installed or changed. Each 'would:' line above is a step a real install takes; it was not taken."
else log "done: this clinic runs on the hub's data. The operator now joins it to the hub."; fi
log "install log: ${INSTALL_LOG}"
