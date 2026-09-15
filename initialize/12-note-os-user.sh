#!/usr/bin/env bash
# Manual step — non-privileged OS user (no-op info).
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "12 · Non-privileged OS user (manual)"

warn "Not automated — clinic layout (e.g. /Users/admin/bahmni) is site-specific"
dim "Create a standard macOS user, own the data dirs, run Podman as that user"
dim "Then re-run: ./initialize/11-restart-policy.sh under that account"
ok "noted (no-op)"
