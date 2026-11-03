#!/usr/bin/env bash
# Manual step — OpenMRS local users / global privileges (no-op info).
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "10 · OpenMRS users / privileges (manual)"

warn "Not automated — no in-repo procedure for OpenMRS user + global privilege assignment"
dim "Related: connectors/mysql-local-sink-connector-users.json syncs users cloud → local"
dim "Investigate: create users in OpenMRS UI/API and assign roles on the global system"
ok "noted (no-op)"
