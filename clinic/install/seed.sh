#!/usr/bin/env bash
# Seeds an installed clinic machine with the hub's data, once, at go-live.
# Run by clinic staff from the machine itself:
#   clinic/install/seed.sh --seed <folder the operator copied> [--discard-baseline-data]
# The folder holds openmrs.sql.gz, odoo.sql.gz, openelis.sql.gz and manifest.env.
# Everything it needs besides the folder was written on this machine at install.
set -euo pipefail
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; export INSTALL_DIR
# shellcheck source=lib.sh
. "${INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${INSTALL_DIR}/tasks}"
ORIG_ARGS=("$@")
usage(){ sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
SEED_DIR=""; DISCARD=0; ONLY=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED_DIR="${2:-}"; shift 2 ;;
    --discard-baseline-data) DISCARD=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
[ -n "$SEED_DIR" ] || { usage; fail "--seed <folder> is required: the folder the operator copied onto this machine"; }
[ -d "$SEED_DIR" ] || fail "seed folder not found: $SEED_DIR"
docker_group_reexec "$0" ${ORIG_ARGS[@]+"${ORIG_ARGS[@]}"}
SEED_DIR="$(cd "$SEED_DIR" && pwd)"
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "this machine is not installed yet (no clinic/.env); the operator runs install.sh first. Call the operator."
set -a; . "$E"; . "${VERSIONS_FILE}"; set +a
image_keys_from "$E"   # the application images this machine was installed with, not today's defaults
derive_identity "$CLINIC_SLUG" "$RESIDUE"
# The machine state decides whether a seed may run at all, and --from/--only
# (which skip the gate task) may only resume one that already passed it.
. "${INSTALL_DIR}/state.sh"
st="$(stamp_get STATE)"
v="$(seed_resume_verdict "$st" "${FROM}" "${ONLY}")" || { printf '\n  >>> %s\n\n' "$v" >&2; fail "$v"; }
# once the sync layer has started, only a resume that would drop the
# databases again (task 050 or earlier) is refused; one past it is safe
if [ -n "${FROM}${ONLY}" ]; then
  sync_started=0; resume_redoes_drop "${FROM}" "${ONLY}" && sync_started="$(stamp_get SYNC_STARTED)"
  v="$(stamp_gate_verdict "$st" "${sync_started:-0}")" || { printf '\n  >>> %s\n\n' "$v" >&2; fail "$v"; }
fi
PLATFORM="$(detect_platform)"
export SEED_DIR DISCARD ONLY FROM PLATFORM DRY CLINIC_DIR REPO_DIR LEDGER CLINIC_SLUG RESIDUE MRN_PREFIX SITE_NUMBER CERT_HOSTNAME LAN_NAME
if [ "$DRY" = 1 ]; then INSTALL_LOG="${INSTALL_LOG:-${TMPDIR:-/tmp}/clinic-seed-${CLINIC_SLUG}.log}"; else INSTALL_LOG="${INSTALL_LOG:-${HOME}/clinic-seed-${CLINIC_SLUG}.log}"; fi
export INSTALL_LOG
exec > >(tee -a "${INSTALL_LOG}") 2>&1
log ""; log "===== $(date -u +%Y-%m-%dT%H:%M:%SZ) clinic-seed slug=${CLINIC_SLUG} folder=${SEED_DIR} dry=${DRY} ====="
hint="$(printf '%q' "$0") --seed $(printf '%q' "$SEED_DIR")"; [ "$DISCARD" = 1 ] && hint="${hint} --discard-baseline-data"
run_tasks seed "$hint"
. "${INSTALL_DIR}/state.sh"
if [ "$DRY" != 1 ] && [ -z "${ONLY}" ]; then stamp_put STATE SEEDED; stamp_put SEEDED_AT "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; fi
log ""
if [ "$DRY" = 1 ]; then log "dry run: every check above ran; nothing was changed."
else log "SEEDED. This clinic now runs on the hub's data. Call the operator to join it to the hub."; fi
log "log: ${INSTALL_LOG}"
