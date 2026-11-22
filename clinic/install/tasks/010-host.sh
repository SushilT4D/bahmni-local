#!/usr/bin/env bash
# Sets up the Mac (host-macos.sh) and checks that podman and compose answer.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "10 · host (macOS, podman)"
. "${INSTALL_DIR}/host-macos.sh"
host_macos

[ "${DRY}" = 1 ] && { ok "dry run: runtime checks skipped"; exit 0; }
setup_compose
ct info >/dev/null 2>&1 || fail "podman is not answering: is the podman machine running? (podman machine start)"
ok "${CT} answers"

v="$(compose version 2>/dev/null | tail -1)"
[ -n "$v" ] || fail "compose is not available"
ok "compose: $v"
