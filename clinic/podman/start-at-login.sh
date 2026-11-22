#!/usr/bin/env bash
# Podman supervisor, run at boot by /Library/LaunchDaemons/com.bahmni.podman.plist.
# Starts the machine and containers (data tier first), stays up, and stops them in reverse on SIGTERM.
set -uo pipefail

log() { printf '%s [podman-supervisor] %s\n' "$(date '+%F %T')" "$*"; }

# LaunchDaemon may not set a full user environment — normalize.
export HOME="${HOME:-$(eval echo "~$(id -un)")}"
export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-${USER}}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

PODMAN="$(command -v podman || true)"
[[ -x "${PODMAN}" ]] || { log "podman not found"; exit 1; }

# Container tiers, matched against container names.
DATA_RE='mysql|postgres|^kafka$'              # stopped last, started first
MIDDLE_RE='kafka-connect|mirrormaker'          # depend on data tier
APP_GRACE=30; MIDDLE_GRACE=30; DATA_GRACE=90   # seconds per tier on shutdown

# Containers that should be running (restart policy always / unless-stopped).
managed() {
  { "${PODMAN}" ps -a --filter restart-policy=always --format '{{.Names}}'
    "${PODMAN}" ps -a --filter restart-policy=unless-stopped --format '{{.Names}}'
  } 2>/dev/null | sort -u
}
running() { "${PODMAN}" ps --format '{{.Names}}' 2>/dev/null | sort -u; }

tier() {  # tier <data|middle|app> < names
  case "$1" in
    data)   grep -E  "${DATA_RE}" ;;
    middle) grep -E  "${MIDDLE_RE}" ;;
    app)    grep -vE "${DATA_RE}|${MIDDLE_RE}" ;;
  esac || true
}

start_tier() {
  local names; names=$(managed | tier "$1")
  [[ -z "${names}" ]] && return
  log "Starting $1 tier: $(echo ${names})"
  # One at a time, so one broken container doesn't block the rest.
  for n in ${names}; do "${PODMAN}" start "${n}" >/dev/null 2>&1 || log "  failed to start ${n}"; done
}

stop_tier() {  # stop_tier <tier> <grace>
  local names; names=$(running | tier "$1")
  [[ -z "${names}" ]] && return
  log "Stopping $1 tier (grace $2s): $(echo ${names})"
  "${PODMAN}" stop -t "$2" ${names} >/dev/null 2>&1 || log "  some $1 containers did not stop cleanly"
}

shutting_down=false
shutdown() {
  ${shutting_down} && return
  shutting_down=true
  log "Shutdown signal received — stopping gracefully"
  stop_tier app    "${APP_GRACE}"
  stop_tier middle "${MIDDLE_GRACE}"
  stop_tier data   "${DATA_GRACE}"
  log "Stopping Podman machine…"
  "${PODMAN}" machine stop 2>&1 || log "  machine stop failed"
  log "Shutdown complete"
  exit 0
}
trap shutdown TERM INT HUP

# ---------- startup ----------
log "user=${USER} home=${HOME} podman=${PODMAN}"
log "Starting Podman machine…"
"${PODMAN}" machine start 2>&1 || true

log "Waiting for Podman API…"
ready=false
for _ in $(seq 1 60); do
  if "${PODMAN}" info >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
if [[ "${ready}" != true ]]; then
  log "Podman API not ready — giving up"
  exit 1
fi
log "Podman API ready"

start_tier data
sleep 10   # let databases / Kafka begin accepting connections
start_tier middle
start_tier app
log "Startup done. Running:"
"${PODMAN}" ps --format '  {{.Names}} {{.Status}}' 2>&1 || true

# ---------- supervise ----------
# Background sleep + wait, so the TERM trap runs immediately.
log "Supervising — waiting for shutdown signal"
while true; do
  sleep 86400 & wait $! || true
done
