#!/usr/bin/env bash
# Dump openmrs on the cloud host, download it, and load into local bahmni-mysql.
#
# Usage:
#   ./scripts/pull-openmrs-db.sh <purpose> [--force]
#   ./scripts/pull-openmrs-db.sh seed_local
#   ./scripts/pull-openmrs-db.sh seed_local --force
#
# Remote dump name: openmrs-YYYYMMDD-HHMM-<purpose>.sql
# (kept on the cloud under CLOUD_DUMP_DIR)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# -----------------------------
# Config (override via env)
# -----------------------------
LOCAL_ENV_FILE="${LOCAL_ENV_FILE:-${PROJECT_DIR}/.env}"
CLOUD_ENV_FILE="${CLOUD_ENV_FILE:-/App/.env}"
CLOUD_DUMP_DIR="${CLOUD_DUMP_DIR:-/App/db-dumps}"
LOCAL_DUMP_DIR="${LOCAL_DUMP_DIR:-${PROJECT_DIR}/db-dumps}"
MYSQL_SERVICE="${MYSQL_SERVICE:-bahmni-mysql}"
OPENMRS_SERVICE="${OPENMRS_SERVICE:-openmrs}"
COMPOSE_CMD="${COMPOSE_CMD:-podman-compose}"

# SSH key / optional user from env/.env. Host = hostname from REMOTE_KAFKA_BOOTSTRAP_SERVERS.
CLOUD_SSH_USER="${CLOUD_SSH_USER:-}"
CLOUD_SSH_KEY="${CLOUD_SSH_KEY:-}"
CLOUD_SSH_HOST=""
CLOUD_SSH=""

# Built after resolve_ssh_key (publickey + IdentityFile; no password prompts).
SSH_OPTS=()

# -----------------------------
# Output
# -----------------------------
if [[ -t 1 ]]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

info()  { printf '%s==>%s %s\n' "${C_CYAN}" "${C_RESET}" "$*"; }
ok()    { printf '%s✓%s  %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '%s⚠%s  %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
fail()  { printf '%s✗%s  %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }
dim()   { printf '%s    %s%s\n' "${C_DIM}" "$*" "${C_RESET}"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <purpose> [--force]

  purpose   Why this dump exists (e.g. seed_local). Use letters, digits, _.
            Becomes part of: openmrs-YYYYMMDD-HHMM-<purpose>.sql
  --force   Drop/reload local openmrs even if it already has tables.

Env overrides:
  CLOUD_SSH_KEY    path to private key (required; or set in .env)
  CLOUD_SSH_USER   optional SSH user (else ssh default / config)
  CLOUD_ENV_FILE   (default: /App/.env)
  CLOUD_DUMP_DIR   (default: /App/db-dumps)
  LOCAL_ENV_FILE   (default: ./.env)
  LOCAL_DUMP_DIR   (default: ./db-dumps)

SSH host is taken from REMOTE_KAFKA_BOOTSTRAP_SERVERS in .env (hostname only).
Auth: SSH publickey only (BatchMode). Password auth is disabled.
EOF
}

# -----------------------------
# Args
# -----------------------------
PURPOSE=""
FORCE=false
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=true ;;
    -*) fail "Unknown flag: $arg" ;;
    *)
      if [[ -n "$PURPOSE" ]]; then
        fail "Unexpected argument: $arg"
      fi
      PURPOSE="$arg"
      ;;
  esac
done

[[ -n "$PURPOSE" ]] || { usage; fail "purpose is required"; }
[[ "$PURPOSE" =~ ^[A-Za-z0-9_]+$ ]] || fail "purpose must match [A-Za-z0-9_]+ (got: ${PURPOSE})"

STAMP="$(date +'%Y%m%d-%H%M')"
DUMP_NAME="openmrs-${STAMP}-${PURPOSE}.sql"
REMOTE_DUMP_PATH="${CLOUD_DUMP_DIR}/${DUMP_NAME}"
LOCAL_DUMP_PATH="${LOCAL_DUMP_DIR}/${DUMP_NAME}"

# -----------------------------
# Local .env helpers
# -----------------------------
require_local_env() {
  [[ -f "${LOCAL_ENV_FILE}" ]] || fail "Local env not found: ${LOCAL_ENV_FILE}"
}

env_value() {
  local key="$1" file="${2:-$LOCAL_ENV_FILE}"
  # Always succeed under set -euo pipefail when the key is absent.
  grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'" || true
}

# Expand leading ~/ in a path.
# Quote '~' everywhere: unquoted ~/ in [[ ]] and ${var#~/} tilde-expands to $HOME/.
expand_path() {
  local p="$1"
  if [[ "$p" == '~/'* ]]; then
    echo "${HOME}/${p#"~/"}"
  else
    echo "$p"
  fi
}

# First broker host from REMOTE_KAFKA_BOOTSTRAP_SERVERS (strip port / extras).
cloud_host_from_env() {
  local brokers first host
  brokers="$(env_value REMOTE_KAFKA_BOOTSTRAP_SERVERS)"
  [[ -n "${brokers}" ]] || return 1
  first="${brokers%%,*}"
  host="${first%%:*}"
  [[ -n "${host}" ]] || return 1
  echo "${host}"
}

resolve_ssh_key() {
  [[ -f "${LOCAL_ENV_FILE}" ]] || fail "Local env not found: ${LOCAL_ENV_FILE}"

  [[ -n "${CLOUD_SSH_KEY}" ]] || CLOUD_SSH_KEY="$(env_value CLOUD_SSH_KEY)"
  [[ -n "${CLOUD_SSH_USER}" ]] || CLOUD_SSH_USER="$(env_value CLOUD_SSH_USER)"

  CLOUD_SSH_HOST="$(cloud_host_from_env)" \
    || fail "Could not derive SSH host from REMOTE_KAFKA_BOOTSTRAP_SERVERS in ${LOCAL_ENV_FILE}"

  if [[ -n "${CLOUD_SSH_USER}" ]]; then
    CLOUD_SSH="${CLOUD_SSH_USER}@${CLOUD_SSH_HOST}"
  else
    CLOUD_SSH="${CLOUD_SSH_HOST}"
  fi

  [[ -n "${CLOUD_SSH_KEY}" ]] || fail "CLOUD_SSH_KEY is not set.
Add to .env, e.g.:
  CLOUD_SSH_KEY=~/.ssh/id_rsa
  CLOUD_SSH_USER=ubuntu
Or: CLOUD_SSH_KEY=~/.ssh/id_rsa ./scripts/pull-openmrs-db.sh ${PURPOSE:-seed_local}"

  CLOUD_SSH_KEY="$(expand_path "${CLOUD_SSH_KEY}")"
  [[ -f "${CLOUD_SSH_KEY}" ]] || fail "Private key not found: ${CLOUD_SSH_KEY}"
  [[ -r "${CLOUD_SSH_KEY}" ]] || fail "Private key not readable: ${CLOUD_SSH_KEY}"

  # Publickey only, this IdentityFile only (no password / agent key spray).
  SSH_OPTS=(
    -i "${CLOUD_SSH_KEY}"
    -o IdentitiesOnly=yes
    -o PreferredAuthentications=publickey
    -o PubkeyAuthentication=yes
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o BatchMode=yes
    -o ConnectTimeout=20
    -o StrictHostKeyChecking=accept-new
  )
  ok "SSH auth: publickey via ${CLOUD_SSH_KEY}"
  dim "target: ${CLOUD_SSH} (from REMOTE_KAFKA_BOOTSTRAP_SERVERS)"
}

resolve_container() {
  local service="$1"
  local name
  # Prefer exact compose service name as container name
  if podman ps -a --format '{{.Names}}' | grep -qx "${service}"; then
    echo "${service}"
    return 0
  fi
  name="$(podman ps -a --format '{{.Names}}' | grep -E "(^|/)${service}$|_${service}$|-${service}$" | head -1 || true)"
  [[ -n "$name" ]] || return 1
  echo "$name"
}

compose() {
  "${COMPOSE_CMD}" --env-file "${LOCAL_ENV_FILE}" "$@"
}

# -----------------------------
# 1) Remote dump
# -----------------------------
ensure_ssh() {
  info "Checking SSH to ${CLOUD_SSH}…"
  local err
  if err="$(ssh "${SSH_OPTS[@]}" "${CLOUD_SSH}" 'true' 2>&1)"; then
    ok "SSH OK"
    return 0
  fi
  if echo "${err}" | grep -qi 'Host key verification failed'; then
    fail "Host key verification failed for ${CLOUD_SSH}.
    First-time trust (preferred):
      ssh ${CLOUD_SSH}
    Or pin the key, then re-run:
      ssh-keyscan -H ${CLOUD_SSH#*@} >> ~/.ssh/known_hosts
    If the host key legitimately changed, remove the old entry:
      ssh-keygen -R ${CLOUD_SSH#*@}"
  fi
  if echo "${err}" | grep -qiE 'Permission denied|publickey'; then
    fail "SSH publickey auth failed for ${CLOUD_SSH} using ${CLOUD_SSH_KEY}.
Ensure the matching public key is in cloud ~/.ssh/authorized_keys and the key is not passphrase-protected
(or loaded in ssh-agent). Test: ssh -i ${CLOUD_SSH_KEY} ${CLOUD_SSH}"
  fi
  fail "SSH to ${CLOUD_SSH} failed: ${err}"
}

remote_dump() {
  info "Connecting to ${CLOUD_SSH} — dump openmrs → ${REMOTE_DUMP_PATH}"
  dim "Credentials from ${CLOUD_ENV_FILE} (root / MYSQL_ROOT_PASSWORD)"

  # shellcheck disable=SC2087
  ssh "${SSH_OPTS[@]}" "${CLOUD_SSH}" bash -s <<EOF
set -euo pipefail
CLOUD_ENV_FILE='${CLOUD_ENV_FILE}'
CLOUD_DUMP_DIR='${CLOUD_DUMP_DIR}'
REMOTE_DUMP_PATH='${REMOTE_DUMP_PATH}'
DUMP_NAME='${DUMP_NAME}'
PURPOSE='${PURPOSE}'

[[ -f "\$CLOUD_ENV_FILE" ]] || { echo "Remote env not found: \$CLOUD_ENV_FILE" >&2; exit 1; }
command -v mysqldump >/dev/null 2>&1 || { echo "mysqldump not found on remote host" >&2; exit 1; }

env_get() {
  grep -E "^\${1}=" "\$CLOUD_ENV_FILE" 2>/dev/null | head -1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'" || true
}

# Root is required (app user lacks PROCESS). Host-side dump → localhost over TCP.
DB_NAME="\$(env_get OPENMRS_DB_NAME)"
DB_PASS="\$(env_get MYSQL_ROOT_PASSWORD)"
DB_HOST="localhost"
DB_PORT="\$(env_get OPENMRS_DB_PORT)"
DB_NAME="\${DB_NAME:-openmrs}"
DB_PORT="\${DB_PORT:-3306}"
DB_USER="root"

[[ -n "\$DB_PASS" ]] || { echo "MYSQL_ROOT_PASSWORD missing in \$CLOUD_ENV_FILE" >&2; exit 1; }

mkdir -p "\$CLOUD_DUMP_DIR"

echo "==> Dumping \$DB_NAME@\$DB_HOST:\$DB_PORT as \$DB_USER"
echo "==> Purpose: \$PURPOSE"
echo "==> File: \$REMOTE_DUMP_PATH"

# Header comment for operators browsing the dump on the cloud box
{
  echo "-- Bahmni cloud openmrs dump"
  echo "-- created: \$(date -Iseconds 2>/dev/null || date)"
  echo "-- purpose: \$PURPOSE"
  echo "-- host: \$(hostname -f 2>/dev/null || hostname)"
  echo "-- source_env: \$CLOUD_ENV_FILE"
  echo "-- file: \$DUMP_NAME"
  echo
} > "\$REMOTE_DUMP_PATH"

MYSQL_PWD="\$DB_PASS" mysqldump \\
  --protocol tcp \\
  -h "\$DB_HOST" -P "\$DB_PORT" -u "\$DB_USER" \\
  --set-gtid-purged=OFF \\
  --single-transaction \\
  --routines --triggers \\
  --add-drop-database \\
  --databases "\$DB_NAME" >> "\$REMOTE_DUMP_PATH"

ls -lh "\$REMOTE_DUMP_PATH"
echo "REMOTE_OK \$REMOTE_DUMP_PATH"
EOF

  ok "Remote dump created (left in place): ${REMOTE_DUMP_PATH}"
}

# -----------------------------
# 2) Download
# -----------------------------
download_dump() {
  info "Downloading dump to ${LOCAL_DUMP_PATH}"
  mkdir -p "${LOCAL_DUMP_DIR}"
  scp "${SSH_OPTS[@]}" "${CLOUD_SSH}:${REMOTE_DUMP_PATH}" "${LOCAL_DUMP_PATH}"
  ok "Downloaded $(ls -lh "${LOCAL_DUMP_PATH}" | awk '{print $5}') → ${LOCAL_DUMP_PATH}"
}

# -----------------------------
# 3) Local MySQL up; OpenMRS stop
# -----------------------------
ensure_local_mysql() {
  require_local_env
  info "Ensuring local ${MYSQL_SERVICE} is running (podman-compose)"

  if ! command -v "${COMPOSE_CMD}" >/dev/null 2>&1; then
    fail "${COMPOSE_CMD} not found on PATH"
  fi
  if ! command -v podman >/dev/null 2>&1; then
    fail "podman not found on PATH"
  fi

  # Start only MySQL; profile emr includes bahmni-mysql
  compose --profile emr up -d "${MYSQL_SERVICE}"

  local container=""
  local i
  for i in $(seq 1 60); do
    container="$(resolve_container "${MYSQL_SERVICE}" || true)"
    if [[ -n "$container" ]] && podman exec "$container" mysqladmin ping -uroot -p"$(env_value MYSQL_ROOT_PASSWORD)" --silent 2>/dev/null; then
      ok "MySQL ready in container ${container}"
      MYSQL_CONTAINER="$container"
      return 0
    fi
    sleep 2
  done
  fail "Timed out waiting for ${MYSQL_SERVICE} to accept connections"
}

stop_openmrs_if_running() {
  local container=""
  container="$(resolve_container "${OPENMRS_SERVICE}" || true)"
  if [[ -z "$container" ]]; then
    dim "OpenMRS container not present — nothing to stop"
    return 0
  fi
  if podman ps --format '{{.Names}}' | grep -qx "$container"; then
    info "Stopping OpenMRS (${container}) for restore…"
    compose stop "${OPENMRS_SERVICE}" >/dev/null || podman stop "$container" >/dev/null
    ok "OpenMRS stopped"
  else
    dim "OpenMRS exists but is not running"
  fi
}

# -----------------------------
# 4) Guard + restore
# -----------------------------
local_db_has_tables() {
  local db_name root_pw count
  db_name="$(env_value OPENMRS_DB_NAME)"
  db_name="${db_name:-openmrs}"
  root_pw="$(env_value MYSQL_ROOT_PASSWORD)"
  [[ -n "$root_pw" ]] || fail "MYSQL_ROOT_PASSWORD missing in ${LOCAL_ENV_FILE}"

  count="$(podman exec "${MYSQL_CONTAINER}" mysql -N -uroot -p"${root_pw}" \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db_name}';" 2>/dev/null || echo 0)"
  [[ "${count:-0}" -gt 0 ]]
}

restore_local() {
  local db_name db_user db_pass root_pw
  db_name="$(env_value OPENMRS_DB_NAME)"
  db_name="${db_name:-openmrs}"
  db_user="$(env_value OPENMRS_DB_USERNAME)"
  db_user="${db_user:-openmrs}"
  db_pass="$(env_value OPENMRS_DB_PASSWORD)"
  db_pass="${db_pass:-openmrs}"
  root_pw="$(env_value MYSQL_ROOT_PASSWORD)"

  if local_db_has_tables; then
    if [[ "$FORCE" != true ]]; then
      fail "Local database '${db_name}' already has tables. Re-run with --force to drop and reload."
    fi
    warn "Local '${db_name}' has tables — --force set, dropping and recreating"
  else
    ok "Local '${db_name}' is empty or missing — safe to load"
  fi

  info "Dropping and recreating '${db_name}'…"
  podman exec -i "${MYSQL_CONTAINER}" mysql -uroot -p"${root_pw}" <<SQL
DROP DATABASE IF EXISTS \`${db_name}\`;
CREATE DATABASE \`${db_name}\` CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
ALTER USER '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';
FLUSH PRIVILEGES;
SQL

  info "Loading ${DUMP_NAME} into local MySQL (as root)…"
  # Dump includes CREATE DATABASE / USE from --databases; root can apply it wholesale.
  podman exec -i "${MYSQL_CONTAINER}" mysql -uroot -p"${root_pw}" < "${LOCAL_DUMP_PATH}"

  # Re-assert grants in case dump rewrote users/grants oddly
  podman exec -i "${MYSQL_CONTAINER}" mysql -uroot -p"${root_pw}" <<SQL
CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
ALTER USER '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';
FLUSH PRIVILEGES;
SQL

  local tables
  tables="$(podman exec "${MYSQL_CONTAINER}" mysql -N -uroot -p"${root_pw}" \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${db_name}';")"
  ok "Restore complete — ${tables} tables in '${db_name}'"
}

print_summary() {
  printf '\n%sDone%s\n' "${C_BOLD}" "${C_RESET}"
  dim "purpose : ${PURPOSE}"
  dim "remote  : ${CLOUD_SSH}:${REMOTE_DUMP_PATH} (kept)"
  dim "local   : ${LOCAL_DUMP_PATH}"
  dim "OpenMRS was stopped if it was running — start when ready:"
  dim "  ${COMPOSE_CMD} --profile emr up -d ${OPENMRS_SERVICE}"
}

# -----------------------------
# Main
# -----------------------------
main() {
  printf '%s\n' "${C_BOLD}pull-openmrs-db · ${DUMP_NAME}${C_RESET}"
  dim "local env: ${LOCAL_ENV_FILE}"

  resolve_ssh_key
  ensure_ssh
  remote_dump
  download_dump
  ensure_local_mysql
  stop_openmrs_if_running
  restore_local
  print_summary
}

main
