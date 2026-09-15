#!/usr/bin/env bash
# Compatibility wrapper -- see install-boot-daemon.sh (same thing).
set -euo pipefail
exec /bin/bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-boot-daemon.sh" "$@"
