#!/usr/bin/env bash
# Install Homebrew if missing.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "01 · Homebrew"

ensure_path_has_brew
if command -v brew >/dev/null 2>&1 && [[ "${FORCE}" != true ]]; then
  skip "Homebrew already installed: $(brew --prefix)"
  dim "$(brew --version | head -1)"
  exit 0
fi

if command -v brew >/dev/null 2>&1 && [[ "${FORCE}" == true ]]; then
  ok "Homebrew present — --force does not reinstall Homebrew itself"
  dim "$(brew --version | head -1)"
  exit 0
fi

info "Homebrew not found — installing (NONINTERACTIVE=1)…"
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
ensure_path_has_brew
command -v brew >/dev/null 2>&1 || fail "Homebrew install finished but 'brew' is not on PATH. Open a new shell and re-run."
ok "Homebrew installed: $(brew --prefix)"
