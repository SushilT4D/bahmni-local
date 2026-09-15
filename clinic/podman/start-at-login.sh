#!/usr/bin/env bash
# Start Podman machine at login, then restore containers with a restart policy.
# restart: always alone is not enough on macOS — the machine must start first,
# and Podman machine does not always reattach those containers by itself.
set -euo pipefail

LOG_PREFIX="[podman-start-at-login]"
log() { printf '%s %s\n' "${LOG_PREFIX}" "$*"; }

# LaunchDaemon may not set a full user environment — normalize.
export HOME="${HOME:-$(eval echo "~$(id -un)")}"
export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-${USER}}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

PODMAN_BIN="$(command -v podman || true)"
if [[ -z "${PODMAN_BIN}" && -x /opt/homebrew/bin/podman ]]; then
  PODMAN_BIN=/opt/homebrew/bin/podman
elif [[ -z "${PODMAN_BIN}" && -x /usr/local/bin/podman ]]; then
  PODMAN_BIN=/usr/local/bin/podman
fi
[[ -x "${PODMAN_BIN}" ]] || { log "podman not found"; exit 1; }

# Homebrew / mysql-client etc. for any PATH-dependent tooling
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
fi

log "user=${USER} home=${HOME} podman=${PODMAN_BIN}"

log "Starting Podman machine…"
"${PODMAN_BIN}" machine start 2>&1 || true

log "Waiting for Podman API…"
ready=false
for _ in $(seq 1 60); do
  if "${PODMAN_BIN}" info >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "${ready}" != true ]]; then
  log "Podman API not ready — giving up"
  exit 1
fi
log "Podman API ready"

# Restore containers that compose created with restart policies.
# (always + unless-stopped cover Bahmni stack + MirrorMaker)
log "Starting containers with restart-policy always / unless-stopped…"
"${PODMAN_BIN}" start --all --filter restart-policy=always 2>&1 || true
"${PODMAN_BIN}" start --all --filter restart-policy=unless-stopped 2>&1 || true

log "Done"
"${PODMAN_BIN}" ps --format '{{.Names}} {{.Status}}' 2>&1 || true
