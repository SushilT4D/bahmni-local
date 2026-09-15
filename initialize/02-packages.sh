#!/usr/bin/env bash
# Install brew packages needed for the local clinic host.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "02 · Packages (podman, mysql-client, mkcert, …)"

ensure_path_has_brew
require_cmd brew

python_formula="python@${PYTHON_VERSION}"
pkgs=(podman podman-compose mysql-client mkcert jq dnsmasq "${python_formula}")

missing=()
for pkg in "${pkgs[@]}"; do
  if brew list --formula "${pkg}" >/dev/null 2>&1 || brew list --cask "${pkg}" >/dev/null 2>&1; then
    dim "present: ${pkg}"
  else
    missing+=("${pkg}")
  fi
done

need_jdk=false
if ! command -v keytool >/dev/null 2>&1; then
  if ! brew list --formula openjdk >/dev/null 2>&1; then
    need_jdk=true
  fi
fi

if [[ ${#missing[@]} -eq 0 && "${need_jdk}" != true && "${FORCE}" != true ]]; then
  skip "all required packages already installed"
else
  if [[ "${FORCE}" == true ]]; then
    info "Ensuring packages (--force): ${pkgs[*]}"
    brew install "${pkgs[@]}"
  elif [[ ${#missing[@]} -gt 0 ]]; then
    info "Installing missing: ${missing[*]}"
    brew install "${missing[@]}"
  fi
  if [[ "${need_jdk}" == true || "${FORCE}" == true ]]; then
    if ! command -v keytool >/dev/null 2>&1; then
      info "Installing openjdk (for keytool)…"
      brew install openjdk
    fi
  fi
fi

# Session PATH for keg-only formulas
python_prefix="$(brew --prefix "${python_formula}" 2>/dev/null || true)"
[[ -n "${python_prefix}" && -d "${python_prefix}/bin" ]] && export PATH="${python_prefix}/bin:${PATH}"
mysql_prefix="$(brew --prefix mysql-client 2>/dev/null || true)"
[[ -n "${mysql_prefix}" && -d "${mysql_prefix}/bin" ]] && export PATH="${mysql_prefix}/bin:${PATH}"
jhome="$(brew --prefix openjdk 2>/dev/null || true)"
[[ -n "${jhome}" && -x "${jhome}/bin/keytool" ]] && export PATH="${jhome}/bin:${PATH}"

python_bin="python${PYTHON_VERSION}"
command -v "${python_bin}" >/dev/null 2>&1 || fail "Python ${PYTHON_VERSION} not found after brew install ${python_formula}"
require_cmd podman
require_cmd podman-compose
require_cmd mkcert
require_cmd openssl
require_cmd mysql
require_cmd mysqldump

ok "${python_bin} $($python_bin --version 2>&1)"
ok "podman $(podman --version 2>/dev/null | head -1)"
ok "mkcert $(mkcert -version 2>/dev/null || echo installed)"
ok "mysql $(mysql --version 2>/dev/null | head -1)"
ok "mysqldump available"
