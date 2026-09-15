#!/usr/bin/env bash
# Init/start Podman machine, privileged ports 80/443, mac-helper.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "03 · Podman machine + privileged ports"

ensure_path_has_brew
require_cmd podman

marker='net.ipv4.ip_unprivileged_port_start=80'
conf_dir="${HOME}/.config/containers"
conf_file="${conf_dir}/containers.conf"

# --- machine init ---
# Fail fast if containers.conf is unreadable (duplicate TOML keys, etc.)
if ! podman machine list >/dev/null; then
  fail "podman cannot read config (check ${conf_file} for duplicate [containers] sections)"
fi
if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
  if [[ "${FORCE}" == true ]]; then
    dim "machine already exists (init skipped even with --force)"
  fi
  ok "Podman machine already exists"
else
  info "Initializing Podman machine…"
  podman machine init
  ok "Podman machine initialized"
fi

# --- machine start ---
if podman info >/dev/null 2>&1 && [[ "${FORCE}" != true ]]; then
  ok "Podman API already reachable"
else
  info "Starting Podman machine…"
  podman machine start || true
  if podman info >/dev/null 2>&1; then
    ok "Podman machine started (or already running)"
  else
    fail "Podman API not reachable after machine start"
  fi
fi

# --- privileged ports (host containers.conf) ---
# Podman TOML forbids a second [containers] table — merge into the existing one.
mkdir -p "${conf_dir}"
if [[ -f "${conf_file}" ]] && grep -Fq "${marker}" "${conf_file}" && [[ "${FORCE}" != true ]]; then
  skip "host containers.conf already allows ports >= 80"
elif [[ -f "${conf_file}" ]] && grep -Fq "${marker}" "${conf_file}" ]]; then
  ok "containers.conf already has ${marker}"
elif [[ ! -f "${conf_file}" ]]; then
  cat > "${conf_file}" <<'EOF'
[containers]
default_sysctls = [
  "net.ipv4.ip_unprivileged_port_start=80",
]
EOF
  ok "Wrote ${conf_file}"
else
  # Insert default_sysctls under the first [containers] section (never append another).
  python3 - "${conf_file}" "${marker}" <<'PY'
import sys
from pathlib import Path
path, marker = Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
if marker in text:
    sys.exit(0)
needle = "[containers]\n"
idx = text.find(needle)
insert = f'default_sysctls = [\n  "{marker}",\n]\n'
if idx == -1:
    path.write_text(f"{needle}{insert}\n{text}")
else:
    at = idx + len(needle)
    path.write_text(text[:at] + insert + text[at:])
PY
  ok "Merged ${marker} into ${conf_file}"
fi

# --- privileged ports (in VM) ---
vm_has_sysctl=false
if podman machine ssh -- test -f /etc/sysctl.d/99-podman-unprivileged-ports.conf 2>/dev/null; then
  vm_has_sysctl=true
fi
if [[ "${vm_has_sysctl}" == true && "${FORCE}" != true ]]; then
  skip "VM sysctl.d already configured for ports >= 80"
else
  info "Setting ${marker} inside Podman machine…"
  if podman machine ssh -- sudo sh -c \
    "echo '${marker}' | tee /etc/sysctl.d/99-podman-unprivileged-ports.conf >/dev/null && sysctl -w '${marker}'" \
    >/dev/null; then
    ok "Podman machine can bind ports >= 80 (covers 80 and 443)"
  else
    warn "Could not set in-VM sysctl — is the machine running?"
    dim "Manual: podman machine ssh  then  sudo sysctl -w ${marker}"
  fi
fi

# --- mac-helper ---
helper="$(command -v podman-mac-helper || true)"
if [[ -z "${helper}" ]]; then
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  if [[ -n "${brew_prefix}" && -x "${brew_prefix}/bin/podman-mac-helper" ]]; then
    helper="${brew_prefix}/bin/podman-mac-helper"
  fi
fi
if [[ -z "${helper}" || ! -x "${helper}" ]]; then
  warn "podman-mac-helper not found — skip"
  exit 0
fi
if [[ "${FORCE}" != true && -S /var/run/docker.sock ]]; then
  skip "Docker API socket already present (/var/run/docker.sock)"
  exit 0
fi
info "Installing podman-mac-helper (sudo)…"
sudo "${helper}" install
ok "podman-mac-helper installed"
