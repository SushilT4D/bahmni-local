#!/usr/bin/env bash
# Clinic installer -- takes a fresh macOS (podman) or Linux (Docker) host to a
# syncing clinic node of this fleet. Runs clinic/install/tasks/NN-*.sh in order;
# each task is idempotent and ends with a check read back from the live system.
# It never touches the hub, the ledgers or GitHub: task 110 prints the hub join
# for the operator. Design: Bahmni workspace docs/superpowers/specs/2026-09-15-clinic-installer-design.md
#
# Usage:
#   clinic/install/install.sh --answers clinic-<slug>.env --seed <dir> [--runtime docker|podman]
#                             [--only NN] [--from NN] [--dry-run] [--list]
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export INSTALL_DIR
# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"

usage(){ sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
ANSWERS=""; SEED_DIR=""; ONLY=""; FROM=""; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS="$2"; shift 2 ;;
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
[ -n "$ANSWERS" ] || { usage; fail "--answers <file> is required"; }
[ -f "$ANSWERS" ] || fail "answers file not found: $ANSWERS"
[ -n "$SEED_DIR" ] || { usage; fail "--seed <dir> is required (openmrs.sql.gz, odoo.sql.gz, openelis.sql.gz)"; }
[ -d "$SEED_DIR" ] || fail "seed dir not found: $SEED_DIR"
SEED_DIR="$(cd "$SEED_DIR" && pwd)"; export SEED_DIR

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
  if ! bash "$t"; then
    printf '\n  STOPPED at task %s. Fix what its FAIL line names, then resume with: %s --answers %s --seed %s --from %s\n' "$n" "$0" "$ANSWERS" "$SEED_DIR" "$num" >&2
    exit 1
  fi
done
log ""
log "done: every task's check passed. The hub join printed by task 110 is the operator's next step."
