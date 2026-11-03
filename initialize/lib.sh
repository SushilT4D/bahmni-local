#!/usr/bin/env bash
# Shared helpers for initialize/* tasks.
# shellcheck shell=bash

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${INIT_DIR}/.." && pwd)"

PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
LOCAL_HOSTNAME="${LOCAL_HOSTNAME:-bahmni.local}"
LAN_HOSTNAME="${LAN_HOSTNAME:-bahmni.clinic}"
UPSTREAM_DNS_1="${UPSTREAM_DNS_1:-1.1.1.1}"
UPSTREAM_DNS_2="${UPSTREAM_DNS_2:-8.8.8.8}"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
SKIP_DNS="${SKIP_DNS:-false}"
SKIP_KAFKA_CERTS="${SKIP_KAFKA_CERTS:-false}"
SKIP_DEBEZIUM_USER="${SKIP_DEBEZIUM_USER:-false}"

FORCE=false

if [[ -t 1 ]]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

log()   { printf '%s\n' "$*"; }
info()  { printf '%s==>%s %s\n' "${C_CYAN}" "${C_RESET}" "$*"; }
ok()    { printf '%s✓%s  %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '%s⚠%s  %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
fail()  { printf '%s✗%s  %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }
dim()   { printf '%s    %s%s\n' "${C_DIM}" "$*" "${C_RESET}"; }
skip()  { ok "skip — $*"; }

begin_task() {
  printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_BOLD}" "${C_RESET}"
  printf '%s%s%s\n' "${C_BOLD}" "$*" "${C_RESET}"
  printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "${C_BOLD}" "${C_RESET}"
  if [[ "${FORCE}" == true ]]; then
    dim "mode: --force"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

env_value() {
  local key="$1" file="${2:-$ENV_FILE}"
  [[ -f "$file" ]] || { echo ""; return 0; }
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'" || true
}

ensure_path_has_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# Parse --force / -h from "$@"; leaves FORCE set; exports remaining in REMAINING_ARGS.
parse_task_args() {
  FORCE=false
  REMAINING_ARGS=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force) FORCE=true ;;
      -h|--help)
        if declare -F task_usage >/dev/null 2>&1; then
          task_usage
        else
          echo "Usage: $0 [--force]"
        fi
        exit 0
        ;;
      *) REMAINING_ARGS+=("$arg") ;;
    esac
  done
}

# Return 0 if we should perform work (missing OR --force).
should_run() {
  local already_done_msg="$1"
  if [[ "${FORCE}" == true ]]; then
    return 0
  fi
  skip "${already_done_msg}"
  return 1
}
