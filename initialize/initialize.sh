#!/usr/bin/env bash
# Bahmni local server host bootstrap — controller.
# Runs idempotent subtasks under initialize/. Use --force to redo work.
#
# Usage:
#   ./initialize/initialize.sh
#   ./initialize/initialize.sh --force
#   ./initialize/05-proxy-certs.sh --force    # single task
set -euo pipefail

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"

TASKS=(
  01-homebrew.sh
  02-packages.sh
  03-podman-machine.sh
  04-directories.sh
  05-proxy-certs.sh
  06-kafka-certs.sh
  07-hosts.sh
  08-dns.sh
  09-debezium-user.sh
  10-note-openmrs-users.sh
  11-restart-policy.sh
  12-note-os-user.sh
)

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force]

Idempotent host bootstrap for Bahmni local (macOS).
Each subtask skips when already done; --force re-runs work.

Subtasks (also runnable alone):
$(printf '  %s\n' "${TASKS[@]}")

Env: LOCAL_HOSTNAME LAN_HOSTNAME SKIP_DNS SKIP_KAFKA_CERTS SKIP_DEBEZIUM_USER ENV_FILE
EOF
}

if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
  usage
  fail "Unexpected argument: ${REMAINING_ARGS[0]}"
fi

printf '%s\n' "${C_BOLD}Bahmni local server — initialize/${C_RESET}"
dim "Project: ${PROJECT_DIR}"
dim "Local host: ${LOCAL_HOSTNAME} · LAN host: ${LAN_HOSTNAME}"
dim "Env file: ${ENV_FILE}"
[[ "${FORCE}" == true ]] && dim "mode: --force"

force_args=()
[[ "${FORCE}" == true ]] && force_args=(--force)

for task in "${TASKS[@]}"; do
  script="${INIT_DIR}/${task}"
  [[ -x "${script}" || -f "${script}" ]] || fail "Missing task: ${script}"
  chmod +x "${script}"
  /bin/bash "${script}" "${force_args[@]+"${force_args[@]}"}"
done

printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_BOLD}" "${C_RESET}"
printf '%sInitialization complete%s\n' "${C_BOLD}" "${C_RESET}"
printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_BOLD}" "${C_RESET}"
log ""
ok "Subtasks finished (skipped items were already done unless --force)"
warn "Manual / investigate next:"
dim "1. Reserve a static LAN IP for this Mac"
dim "2. OpenMRS users / privileges (see 10-note-openmrs-users.sh)"
dim "3. Non-privileged OS user if required (see 12-note-os-user.sh)"
dim "4. Ensure .env paths/secrets are correct"
dim "5. Start stack, then Debezium user if skipped:"
dim "     podman-compose --profile emr --profile local up -d"
dim "     ./initialize/09-debezium-user.sh"
dim "6. Register CDC connectors:"
dim "     ./scripts/register-source-connector.sh"
dim "     ./scripts/register-mirrormaker.sh"
log ""
info "Browse https://${LOCAL_HOSTNAME}/ once the proxy is up"
log ""
