#!/usr/bin/env bash
# Add 127.0.0.1 LOCAL_HOSTNAME to /etc/hosts.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "07 · /etc/hosts → ${LOCAL_HOSTNAME}"

if grep -E "[[:space:]]${LOCAL_HOSTNAME}([[:space:]]|$)" /etc/hosts >/dev/null 2>&1; then
  if [[ "${FORCE}" != true ]]; then
    skip "${LOCAL_HOSTNAME} already present in /etc/hosts"
    dim "$(grep -E "[[:space:]]${LOCAL_HOSTNAME}([[:space:]]|$)" /etc/hosts | head -1)"
    exit 0
  fi
  warn "--force set but /etc/hosts entry already exists — leaving as-is (no duplicate append)"
  exit 0
fi

info "Adding '127.0.0.1 ${LOCAL_HOSTNAME}' (sudo required)…"
echo "127.0.0.1 ${LOCAL_HOSTNAME}" | sudo tee -a /etc/hosts >/dev/null
ok "Added ${LOCAL_HOSTNAME} → 127.0.0.1"
