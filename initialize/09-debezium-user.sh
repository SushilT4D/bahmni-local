#!/usr/bin/env bash
# Create Debezium MySQL user + replication grants (idempotent).
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "09 · Debezium MySQL user"

if [[ "${SKIP_DEBEZIUM_USER}" == "true" ]]; then
  warn "Skipping Debezium user (SKIP_DEBEZIUM_USER=true)"
  exit 0
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  warn ".env not found at ${ENV_FILE} — skip"
  dim "Configure .env, start MySQL, then: ./initialize/09-debezium-user.sh"
  exit 0
fi

root_pw="$(env_value MYSQL_ROOT_PASSWORD)"
db_name="$(env_value OPENMRS_DB_NAME)"
db_name="${db_name:-openmrs}"
debezium_user="$(env_value DEBEZIUM_USER)"
debezium_user="${debezium_user:-debezium}"
debezium_pw="$(env_value DEBEZIUM_PASSWORD)"
[[ -z "${debezium_pw}" ]] && debezium_pw="$(env_value MYSQL_DEBEZIUM_PASSWORD)"

if [[ -z "${root_pw}" || -z "${debezium_pw}" ]]; then
  warn "MYSQL_ROOT_PASSWORD or DEBEZIUM_PASSWORD missing in .env — skip"
  exit 0
fi

container="$(env_value BAHMNI_MYSQL_HOST)"
container="${container:-bahmni-mysql}"
if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "${container}"; then
  if ! podman ps --format '{{.Names}}' 2>/dev/null | grep -q "${container}"; then
    warn "MySQL container '${container}' is not running — skip"
    exit 0
  fi
  container="$(podman ps --format '{{.Names}}' | grep "${container}" | head -1)"
fi

exists="$(podman exec "${container}" mysql -N -uroot -p"${root_pw}" \
  -e "SELECT COUNT(*) FROM mysql.user WHERE user='${debezium_user}' AND host='%';" 2>/dev/null || echo 0)"
exists="$(echo "${exists}" | tr -d '[:space:]')"

if [[ "${exists}" == "1" && "${FORCE}" != true ]]; then
  skip "MySQL user '${debezium_user}'@'%' already exists in ${container}"
  dim "Re-apply grants/password with: ./initialize/09-debezium-user.sh --force"
  exit 0
fi

info "Creating/updating MySQL user '${debezium_user}'@'%' inside ${container}…"
podman exec -i "${container}" mysql -uroot -p"${root_pw}" <<EOF
CREATE USER IF NOT EXISTS '${debezium_user}'@'%' IDENTIFIED BY '${debezium_pw}';
ALTER USER '${debezium_user}'@'%' IDENTIFIED BY '${debezium_pw}';
GRANT SELECT, INSERT, UPDATE, DELETE, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
  ON *.* TO '${debezium_user}'@'%';
FLUSH PRIVILEGES;
EOF
ok "Debezium user '${debezium_user}' granted replication privileges"
dim "Target database name in .env: ${db_name}"
warn "Confirm MySQL binlog / server-id are enabled for Debezium (not set by this script)"
