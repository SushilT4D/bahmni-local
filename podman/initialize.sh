#!/usr/bin/env bash
# Compatibility wrapper — use ./initialize/11-restart-policy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec /bin/bash "${ROOT}/initialize/11-restart-policy.sh" "$@"
