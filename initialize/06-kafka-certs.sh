#!/usr/bin/env bash
# Kafka truststore for MirrorMaker (via setup-certs.sh).
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "06 · Kafka truststore"

if [[ "${SKIP_KAFKA_CERTS}" == "true" ]]; then
  warn "Skipping Kafka certs (SKIP_KAFKA_CERTS=true)"
  exit 0
fi

truststore="${PROJECT_DIR}/certs/kafka/kafka.truststore.p12"
if [[ -f "${truststore}" && "${FORCE}" != true ]]; then
  skip "Kafka truststore already exists"
  dim "${truststore}"
  dim "Regenerate with: ./initialize/06-kafka-certs.sh --force  (or ./setup-certs.sh)"
  exit 0
fi

[[ -f "${PROJECT_DIR}/setup-certs.sh" ]] || { warn "setup-certs.sh not found — skip"; exit 0; }

ensure_path_has_brew
jhome="$(brew --prefix openjdk 2>/dev/null || true)"
[[ -n "${jhome}" && -x "${jhome}/bin/keytool" ]] && export PATH="${jhome}/bin:${PATH}"
if ! command -v keytool >/dev/null 2>&1; then
  warn "keytool missing — install openjdk (02-packages) and re-run"
  exit 0
fi

info "Running setup-certs.sh…"
warn "Edit HOSTNAME in setup-certs.sh if the remote Kafka CN differs"
bash "${PROJECT_DIR}/setup-certs.sh"
ok "Kafka certs generated under certs/"
