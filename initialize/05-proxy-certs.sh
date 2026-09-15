#!/usr/bin/env bash
# mkcert proxy TLS certs for LOCAL_HOSTNAME.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "05 · Proxy TLS certs (${LOCAL_HOSTNAME})"

ensure_path_has_brew
require_cmd mkcert
require_cmd openssl
mkdir -p "${PROJECT_DIR}/certs"

cert="${PROJECT_DIR}/certs/cert.pem"
key="${PROJECT_DIR}/certs/key.pem"

if [[ -f "${cert}" && -f "${key}" && "${FORCE}" != true ]]; then
  san="$(openssl x509 -in "${cert}" -noout -ext subjectAltName 2>/dev/null || true)"
  if echo "$san" | grep -q "${LOCAL_HOSTNAME}"; then
    skip "proxy certs already present with SAN ${LOCAL_HOSTNAME}"
    dim "${cert}"
    exit 0
  fi
  warn "Existing certs lack SAN ${LOCAL_HOSTNAME} — regenerating"
elif [[ -f "${cert}" && -f "${key}" && "${FORCE}" == true ]]; then
  info "Regenerating proxy certs (--force)"
fi

info "Installing local mkcert CA (may prompt for password)…"
mkcert -install
info "Generating cert.pem + key.pem for ${LOCAL_HOSTNAME}…"
mkcert -cert-file "${cert}" -key-file "${key}" "${LOCAL_HOSTNAME}"
ok "Proxy TLS certs ready"
