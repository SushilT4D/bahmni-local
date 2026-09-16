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
  # group (above) and the current shell has not activated it. Signal install.sh to
  # re-exec the rest under the group (exit 75) instead of failing -- no manual
  # re-login/newgrp. Any other cause still fails loudly.
  if [ "$(detect_runtime)" = docker ] && command -v docker >/dev/null 2>&1 \
     && id -nG 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    info "docker installed and ${USER} added to the docker group; activating it and continuing"
    exit 75
  fi
  fail "${CT} is not answering (podman machine down? docker service stopped? user not in docker group?)"
fi
ok "${CT} answers"
v="$(compose version 2>/dev/null | head -1)"; [ -n "$v" ] || fail "compose is not available"
ok "compose: $v"
