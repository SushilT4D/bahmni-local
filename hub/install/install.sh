#!/usr/bin/env bash
# Hub installer -- runs hub/install/tasks/NN-*.sh in order against the hub's
# own compose project (hub/docker-compose.yml: Kafka, Schema Registry, Kafka
# Connect), attached to an already-running base stack (cloud/ or a clinic
# acting as the reference hub). Each task is idempotent and ends with a check
# read back from the live system.
#
# Usage:
#   hub/install/install.sh --hub <name> --base-env <path> --secrets <path> [--from NNN] [--dry-run]
# hub/.env is composed once, from sync/hub.env, the base stack's own --base-env
# file (root credentials, existing sink passwords) and an operator --secrets
# file (the fleet SASL password) -- hub_compose_env in lib.sh. Once hub/.env
# exists, --base-env/--secrets may be omitted: a resume never regenerates a
# secret, it just continues the task loop with --from.
set -euo pipefail
HUB_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HUB_INSTALL_DIR
# shellcheck source=lib.sh
. "${HUB_INSTALL_DIR}/lib.sh"
TASKS_DIR="${TASKS_DIR:-${HUB_INSTALL_DIR}/tasks}"

usage(){ sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
HUB_NAME=""; BASE_ENV=""; SECRETS=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hub)      HUB_NAME="$2"; shift 2 ;;
    --base-env) BASE_ENV="$2"; shift 2 ;;
    --secrets)  SECRETS="$2"; shift 2 ;;
    --from)     FROM="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
export DRY

[ -n "$HUB_NAME" ] || { usage; fail "--hub <name> is required"; }

if [ ! -f "${HUB_DIR}/.env" ]; then
  [ -n "$BASE_ENV" ] || { usage; fail "--base-env <path> is required (hub/.env does not exist yet)"; }
  [ -n "$SECRETS" ]  || { usage; fail "--secrets <path> is required (hub/.env does not exist yet)"; }
fi
export BASE_ENV SECRETS

log "hub installer  hub=${HUB_NAME} platform=$(detect_platform) runtime=$(detect_runtime) dry=${DRY}"
log "  hub dir: ${HUB_DIR}"

if [ ! -f "${HUB_DIR}/.env" ]; then
  run hub_compose_env "$BASE_ENV" "$SECRETS" "${HUB_DIR}/.env"
fi

# hub/install/tasks/ has no NNN-*.sh files yet (later dispatches add them);
# nullglob makes that a zero-iteration loop instead of one pass over the
# literal, unmatched glob pattern as $t.
shopt -s nullglob
for t in "${TASKS_DIR}"/[0-9]*-*.sh; do
  n="$(basename "$t" .sh)"; num="${n%%-*}"
  if [ -n "$FROM" ] && [ "$num" -lt "$FROM" ]; then continue; fi
  rc=0; bash "$t" || rc=$?
  if [ "$rc" = 75 ] && [ "${_KRAFT_SG:-}" != 1 ] && command -v sg >/dev/null 2>&1; then
    # a task added us to the docker group; re-exec the remaining tasks under
    # the group so no manual re-login is needed. _KRAFT_SG guards against a loop.
    log "  activating the docker group and continuing (no re-login needed)..."
    export _KRAFT_SG=1
    exec sg docker -c "$(printf '%q' "$0") --hub $(printf '%q' "$HUB_NAME") --from ${num}"
  fi
  if [ "$rc" != 0 ]; then
    printf '\n  STOPPED at task %s. Fix what its FAIL (or FAILED rc=) line names, then resume with: %s --hub %s --from %s\n' "$n" "$0" "$HUB_NAME" "$num" >&2
    exit 1
  fi
done
log ""
log "done"
