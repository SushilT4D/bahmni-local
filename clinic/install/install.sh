#!/usr/bin/env bash
# Clinic installer -- takes a fresh macOS (podman) or Linux (Docker) host to a
# syncing clinic node of this fleet. Runs clinic/install/tasks/NN-*.sh in order;
# each task is idempotent and ends with a check read back from the live system.
# It never touches the hub, the ledgers or GitHub: task 110 prints the hub join
# for the operator.
#
# Usage:
#   clinic/install/install.sh --clinic <slug> [--secrets <file>] [--baseline <dir>] [--cert-hostname <name>]
#                             [--runtime docker|podman] [--only NNN] [--from NNN] [--dry-run]
#   clinic/install/install.sh --answers clinic-<slug>.env ...   (hand-written answers)
#   clinic/install/install.sh --clinics | --list
# --secrets: the operator's hub secrets file (the four hub credentials).
# --baseline: three dumps to run on until the seed, instead of the pinned baseline images.
# --clinic composes the twelve answers from sync/fleet/<slug>.env, the residue
# ledger, sync/hub.env and --secrets, asking on the terminal for what is still
# missing, and keeps them in ~/clinic-<slug>.env (mode 600) for resumes.
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR
# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"

ORIG_ARGS=("$@")
usage(){ sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
ANSWERS=""; CLINIC=""; CERT_HOSTNAME_ARG=""; SECRETS_FILE=""; BASELINE_DIR=""; ONLY=""; FROM=""; LIST=0; CLINICS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS="$2"; shift 2 ;;
    --clinic)  CLINIC="$2"; shift 2 ;;
    --clinics) CLINICS=1; shift ;;
    --cert-hostname) CERT_HOSTNAME_ARG="$2"; shift 2 ;;
    --secrets)  SECRETS_FILE="$2"; shift 2 ;;
    --baseline) BASELINE_DIR="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --only)    ONLY="$2"; shift 2 ;;
    --from)    FROM="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --list)    LIST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
export DRY RUNTIME="${RUNTIME:-}"
docker_group_reexec "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}

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
if [ -n "$BASELINE_DIR" ]; then [ -d "$BASELINE_DIR" ] || fail "baseline dir not found: $BASELINE_DIR"; BASELINE_DIR="$(cd "$BASELINE_DIR" && pwd)"; fi
export SECRETS_FILE BASELINE_DIR

# --clinic: the answers come from the repo, --secrets and the terminal, and are
# kept for resumes. Nothing secret is printed.
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
  [ -z "${CERT_HOSTNAME_ARG}" ] || CERT_HOSTNAME="${CERT_HOSTNAME_ARG}"
  ask CERT_HOSTNAME "certificate hostname (the name staff will open Bahmni at)" "$(hostname -f 2>/dev/null || hostname)" "sync/fleet/${slug}.env or --cert-hostname"
  ask CLINIC_PHONE "clinic phone, E.164" "+910000000000" "sync/fleet/${slug}.env"
  for k in $SECRET_KEYS; do ask_secret "$k" "--secrets"; done
  export RESIDUE SITE_NUMBER
  answers_write "$out"; ANSWERS="$out"
  info "answers: composed $out (mode 600) from $f, ${LEDGER}, ${HUB_ENV} and the hub secrets"
}
[ -z "$CLINIC" ] || compose_answers "$(printf '%s' "$CLINIC" | tr 'A-Z' 'a-z')"

# The twelve answers. Sourced (same quoting contract as .env); every key must be
# present and non-empty. Secrets are never printed.
REQUIRED="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE CERT_HOSTNAME REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
set -a; . "$ANSWERS"; set +a
# The fleet's image pins (sync/versions.env): every task sees the same pins.
set -a; . "${VERSIONS_FILE}"; set +a
LAN_NAME="${LAN_NAME:-bahmni.clinic}"; export LAN_NAME
missing=""
for k in $REQUIRED; do eval "v=\${$k:-}"; [ -n "$v" ] || missing="$missing $k"; done
[ -z "$missing" ] || fail "answers file is missing:$missing"
printf '%s' "$MRN_PREFIX" | grep -Eq '^[A-Z]{2,4}$' || fail "MRN_PREFIX '$MRN_PREFIX' must be 2-4 capital letters"
printf '%s' "$SITE_NUMBER" | grep -Eq '^[0-9]{1,5}$' || fail "SITE_NUMBER '$SITE_NUMBER' must be digits"
derive_identity "$CLINIC_SLUG" "$RESIDUE"
refuse_inherited_alias "$LOCAL_CLUSTER_ALIAS" "$CLINIC_SLUG"
PLATFORM="$(detect_platform)"; export PLATFORM
export CLINIC_DIR REPO_DIR LEDGER

# --- run log ----------------------------------------------------------------
# Every stop this week had to be pasted by hand from a terminal, and nobody
# could say how long a task took on a given host. Tee the whole run,
# APPENDING, with one header line per run and one line per task naming its
# wall-clock seconds and result. `exec > >(tee -a "$log") 2>&1` never puts
# tee in THIS script's own pipeline (unlike `... | tee "$log"`), so `set -e`
# under pipefail still sees only this script's own exit status, not tee's --
# and it works under bash 3.2 (macOS stock), verified on /bin/bash. A dry run
# never touches $HOME: it logs under ${TMPDIR:-/tmp} instead. Secrets never
# reach the log beyond what already reaches the terminal (nothing here prints
# one) -- the answers file itself is never logged.
# _INSTALL_LOG_STARTED, exported across the task-010 `sg docker` re-exec
# below, stops the re-exec'd process from printing a second header into the
# same file; it still tees its own output there, just without a second
# header storm. INSTALL_LOG is exported too, so the re-exec'd run resolves to
# the exact same path rather than recomputing one.
if [ "$DRY" = 1 ]; then
  INSTALL_LOG="${INSTALL_LOG:-${TMPDIR:-/tmp}/clinic-install-${CLINIC_SLUG:-node}.log}"
else
  INSTALL_LOG="${INSTALL_LOG:-${HOME}/clinic-install-${CLINIC_SLUG:-node}.log}"
fi
export INSTALL_LOG
exec > >(tee -a "${INSTALL_LOG}") 2>&1
if [ "${_INSTALL_LOG_STARTED:-0}" != 1 ]; then
  gitsha="$(cd "${REPO_DIR}" && git rev-parse --short HEAD 2>/dev/null || true)"; gitsha="${gitsha:-unknown}"
  hdr="$(date -u +%Y-%m-%dT%H:%M:%SZ) clinic-install slug=${CLINIC_SLUG} platform=${PLATFORM} runtime=$(detect_runtime) sha=${gitsha}"
  [ -n "$FROM" ] && hdr="${hdr} --from ${FROM}"
  [ -n "$ONLY" ] && hdr="${hdr} --only ${ONLY}"
  log ""
  log "===== ${hdr} ====="
  export _INSTALL_LOG_STARTED=1
fi
log "install log: ${INSTALL_LOG}"

log "clinic installer  slug=${CLINIC_SLUG} residue=${RESIDUE} platform=${PLATFORM} runtime=$(detect_runtime) dry=${DRY}"
log "  clinic dir: ${CLINIC_DIR}"
log "  baseline:   ${BASELINE_DIR:-the pinned baseline images}"

# never over a seeded machine, whatever --from says (a resume skips task 000's
# fresh-install check and would stamp the machine INSTALLED again)
. "${INSTALL_DIR}/state.sh"
v="$(install_gate_verdict "$(stamp_get STATE)" "${ONLY}")" || fail "$v"
if [ -n "$CLINIC" ]; then how="--clinic $(printf '%q' "$CLINIC")"; else how="--answers $(printf '%q' "$ANSWERS")"; fi
[ -z "${SECRETS_FILE:-}" ] || how="${how} --secrets $(printf '%q' "$SECRETS_FILE")"
[ -z "${BASELINE_DIR:-}" ] || how="${how} --baseline $(printf '%q' "$BASELINE_DIR")"
run_tasks install "$(printf '%q' "$0") ${how}"
. "${INSTALL_DIR}/state.sh"
if [ "${DRY}" != 1 ] && [ -z "${ONLY}" ]; then
  stamp_put STATE INSTALLED; stamp_put INSTALLED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
log ""
log "done: installed on the baseline. At go-live, clinic staff run: clinic/install/seed.sh --seed <folder the operator copied>"
log "install log: ${INSTALL_LOG}"
