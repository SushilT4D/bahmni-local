#!/usr/bin/env bash
# Clinic installer -- takes a fresh macOS (podman) or Linux (Docker) host to a
# syncing clinic node of this fleet. Runs clinic/install/tasks/NN-*.sh in order;
# each task is idempotent and ends with a check read back from the live system.
# It never touches the hub, the ledgers or GitHub: task 110 prints the hub join
# for the operator. Design: Bahmni workspace docs/superpowers/specs/2026-09-15-clinic-installer-design.md
#
# Usage:
#   clinic/install/install.sh --clinic <slug> --seed <dir> [--cert-hostname <name>]
#                             [--runtime docker|podman] [--only NNN] [--from NNN] [--dry-run]
#   clinic/install/install.sh --answers clinic-<slug>.env --seed <dir> ...   (hand-written answers)
#   clinic/install/install.sh --clinics | --list
# --clinic composes the twelve answers from sync/fleet/<slug>.env, the residue
# ledger, sync/hub.env and <seed>/secrets.env, asking on the terminal for what
# is still missing, and keeps them in ~/clinic-<slug>.env (mode 600) for resumes.
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR
# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"

usage(){ sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
ANSWERS=""; CLINIC=""; CERT_HOSTNAME_ARG=""; SEED_DIR=""; ONLY=""; FROM=""; LIST=0; CLINICS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS="$2"; shift 2 ;;
    --clinic)  CLINIC="$2"; shift 2 ;;
    --clinics) CLINICS=1; shift ;;
    --cert-hostname) CERT_HOSTNAME_ARG="$2"; shift 2 ;;
    --seed)    SEED_DIR="$2"; shift 2 ;;
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
[ -n "$SEED_DIR" ] || { usage; fail "--seed <dir> is required (openmrs.sql.gz, odoo.sql.gz, openelis.sql.gz)"; }
[ -d "$SEED_DIR" ] || fail "seed dir not found: $SEED_DIR"
SEED_DIR="$(cd "$SEED_DIR" && pwd)"; export SEED_DIR

# --clinic: the answers come from the repo, the seed and the terminal, and are
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
  set -a; . "$f"; . "${HUB_ENV}"; [ ! -f "${SEED_DIR}/secrets.env" ] || . "${SEED_DIR}/secrets.env"; set +a
  [ "$(printf '%s' "${CLINIC_SLUG:-}" | tr 'A-Z' 'a-z')" = "$slug" ] || fail "$f says CLINIC_SLUG='${CLINIC_SLUG:-}', not $slug"
  RESIDUE="$r"; [ -n "${SITE_NUMBER:-}" ] || SITE_NUMBER="$r"
  [ -z "${CERT_HOSTNAME_ARG}" ] || CERT_HOSTNAME="${CERT_HOSTNAME_ARG}"
  ask CERT_HOSTNAME "certificate hostname (the name staff will open Bahmni at)" "$(hostname -f 2>/dev/null || hostname)" "sync/fleet/${slug}.env or --cert-hostname"
  ask CLINIC_PHONE "clinic phone, E.164" "+910000000000" "sync/fleet/${slug}.env"
  for k in $SECRET_KEYS; do ask_secret "$k" "${SEED_DIR}/secrets.env (written by install-clinic.sh seed)"; done
  export RESIDUE SITE_NUMBER
  answers_write "$out"; ANSWERS="$out"
  info "answers: composed $out (mode 600) from $f, ${LEDGER}, ${HUB_ENV} and the seed's secrets"
}
[ -z "$CLINIC" ] || compose_answers "$(printf '%s' "$CLINIC" | tr 'A-Z' 'a-z')"

# The twelve answers. Sourced (same quoting contract as .env); every key must be
# present and non-empty. Secrets are never printed.
REQUIRED="CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CLINIC_PHONE CERT_HOSTNAME REMOTE_KAFKA_BOOTSTRAP_SERVERS REMOTE_KAFKA_USERNAME REMOTE_KAFKA_PASSWORD OPENMRS_ATOMFEED_PASSWORD OPENELIS_ATOMFEED_PASSWORD ODOO_ATOMFEED_PASSWORD"
set -a; . "$ANSWERS"; set +a
missing=""
for k in $REQUIRED; do eval "v=\${$k:-}"; [ -n "$v" ] || missing="$missing $k"; done
[ -z "$missing" ] || fail "answers file is missing:$missing"
printf '%s' "$MRN_PREFIX" | grep -Eq '^[A-Z]{2,4}$' || fail "MRN_PREFIX '$MRN_PREFIX' must be 2-4 capital letters"
printf '%s' "$SITE_NUMBER" | grep -Eq '^[0-9]{1,5}$' || fail "SITE_NUMBER '$SITE_NUMBER' must be digits"
derive_identity "$CLINIC_SLUG" "$RESIDUE"
refuse_inherited_alias "$LOCAL_CLUSTER_ALIAS"
PLATFORM="$(detect_platform)"; export PLATFORM
export CLINIC_DIR REPO_DIR LEDGER

log "clinic installer  slug=${CLINIC_SLUG} residue=${RESIDUE} platform=${PLATFORM} runtime=$(detect_runtime) dry=${DRY}"
log "  clinic dir: ${CLINIC_DIR}"
log "  seed:       ${SEED_DIR}"

for t in "${TASKS_DIR}"/[0-9]*-*.sh; do
  n="$(basename "$t" .sh)"; num="${n%%-*}"
  if [ -n "$ONLY" ] && [ "$num" != "$ONLY" ]; then continue; fi
  if [ -n "$FROM" ] && [ "$num" -lt "$FROM" ]; then continue; fi
  if [ -n "$CLINIC" ]; then how="--clinic $CLINIC"; else how="--answers $ANSWERS"; fi
  rc=0; bash "$t" || rc=$?
  if [ "$rc" = 75 ] && [ "${_KRAFT_SG:-}" != 1 ] && command -v sg >/dev/null 2>&1; then
    # task 010 added us to the docker group; re-exec the remaining tasks under the
    # group so no manual re-login is needed. _KRAFT_SG guards against a loop.
    log "  activating the docker group and continuing (no re-login needed)..."
    export _KRAFT_SG=1
    if [ -n "$CLINIC" ]; then sel="--clinic $(printf '%q' "$CLINIC")"; else sel="--answers $(printf '%q' "$ANSWERS")"; fi
    exec sg docker -c "$(printf '%q' "$0") ${sel} --seed $(printf '%q' "$SEED_DIR") --from ${num}"
  fi
  if [ "$rc" != 0 ]; then
    printf '\n  STOPPED at task %s. Fix what its FAIL (or FAILED rc=) line names, then resume with: %s %s --seed %s --from %s\n' "$n" "$0" "$how" "$SEED_DIR" "$num" >&2
    exit 1
  fi
done
log ""
log "done: every task's check passed. The hub join printed by task 110 is the operator's next step."
