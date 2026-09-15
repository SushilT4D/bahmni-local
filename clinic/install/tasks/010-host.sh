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
ct info >/dev/null 2>&1 || fail "${CT} is not answering (podman machine down? docker service stopped? user not in docker group?)"
ok "${CT} answers"
v="$(compose version 2>/dev/null | head -1)"; [ -n "$v" ] || fail "compose is not available"
ok "compose: $v"
