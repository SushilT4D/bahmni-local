#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "10 · host (${PLATFORM}, $(detect_runtime))"
case "${PLATFORM}" in
  macos) . "${INSTALL_DIR}/host-macos.sh"; host_macos ;;
  linux) . "${INSTALL_DIR}/host-linux.sh"; host_linux ;;
  *) fail "unsupported platform: ${PLATFORM}" ;;
esac
[ "${DRY}" = 1 ] && { ok "dry run: runtime checks skipped"; exit 0; }
setup_compose
if ! ct info >/dev/null 2>&1; then
  # Most common cause on a fresh Linux host: we just added this user to the docker
  # group (above) and the current shell has not activated it. Membership is read from
  # the group DATABASE (user_in_group_db): the process's own list cannot show it yet. Signal install.sh to
  # re-exec the rest under the group (exit 75) instead of failing -- no manual
  # re-login/newgrp. Any other cause still fails loudly.
  # Only on the FIRST pass: once the runner has re-executed us under `sg docker`
  # (_KRAFT_SG=1) the group is active, so a docker that still does not answer is a
  # real fault and must reach the FAIL line below, not another silent exit 75.
  if [ "${_KRAFT_SG:-}" != 1 ] && [ "$(detect_runtime)" = docker ] && command -v docker >/dev/null 2>&1 \
     && user_in_group_db docker; then
    info "docker installed and ${USER} added to the docker group; activating it and continuing"
    exit 75
  fi
  [ "${_KRAFT_SG:-}" != 1 ] || fail "${CT} still does not answer after the docker group was activated for this run (sg docker): is the docker service running? try: sudo systemctl status docker"
  fail "${CT} is not answering (podman machine down? docker service stopped? user not in docker group?)"
fi
ok "${CT} answers"
v="$(compose version 2>/dev/null | head -1)"; [ -n "$v" ] || fail "compose is not available"
ok "compose: $v"
