#!/usr/bin/env bash
# Installs the login LaunchAgent for the podman machine + this stack. That
# lives in clinic/install/host-macos.sh (the initialize/ tree this used to exec
# exists only on main).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="$(cd "${HERE}/.." && pwd)"; export CLINIC_DIR
. "${CLINIC_DIR}/install/lib.sh"
. "${CLINIC_DIR}/install/host-macos.sh"
host_macos
