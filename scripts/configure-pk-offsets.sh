#!/usr/bin/env bash
# Configure MySQL AUTO_INCREMENT spacing for this clinic.
#
# For Rawach (offset 4, base_id 500000, INCREMENT 10):
#   SET PERSIST auto_increment_increment = 10
#   SET PERSIST auto_increment_offset    = 4
#   ALTER TABLE <t> AUTO_INCREMENT = 500004
# Next ids on those tables: 500004, 500014, 500024, ...
#
# Usage:
#   ./scripts/configure-pk-offsets.sh
#   ./scripts/configure-pk-offsets.sh --dry-run
set -euo pipefail

# How far apart ids are across clinics (must be >= max offset in clinics.txt).
INCREMENT=10

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${PROJECT_DIR}/.env}"
CLINICS_FILE="${CLINICS_FILE:-${PROJECT_DIR}/clinics.txt}"
TABLES_FILE="${TABLES_FILE:-${PROJECT_DIR}/debezium/local/tables.conf}"
MYSQL_SERVICE="${MYSQL_SERVICE:-bahmni-mysql}"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,16p' "$0" | tr -d '#'
      exit 0
      ;;
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

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

env_value() {
  local key="$1"
  # Always succeed under set -euo pipefail when the key is absent.
  grep -E "^${key}=" "${ENV_FILE}" 2>/dev/null | head -1 | cut -d '=' -f 2- | tr -d '"' | tr -d "'" || true
}

resolve_container() {
  local service="$1" name
  if podman ps --format '{{.Names}}' | grep -qx "${service}"; then
    echo "${service}"
    return 0
  fi
  name="$(podman ps --format '{{.Names}}' | grep -E "(^|/)${service}$|_${service}$|-${service}$" | head -1 || true)"
  [[ -n "$name" ]] || return 1
  echo "$name"
}

# No -i: the tables loop reads TABLES_FILE on stdin; podman exec -i would drain it.
mysql_exec() {
  podman exec "${MYSQL_CONTAINER}" mysql -N -uroot -p"${ROOT_PASSWORD}" "${DB_NAME}" "$@" </dev/null
}

mysql_exec_sql() {
  local sql="$1"
  if [[ "${DRY_RUN}" == true ]]; then
    dim "DRY-RUN SQL: ${sql}"
    return 0
  fi
  mysql_exec -e "${sql}"
}

# Smallest value >= candidate, > max_id, and ≡ offset (mod INCREMENT).
next_in_series() {
  local candidate="$1" max_id="$2" offset="$3"
  local v="${candidate}"
  if (( max_id >= v )); then
    v=$(( max_id + 1 ))
  fi
  local rem=$(( v % INCREMENT ))
  if (( rem != offset )); then
    v=$(( v + (offset - rem + INCREMENT) % INCREMENT ))
  fi
  while (( v <= max_id )); do
    v=$(( v + INCREMENT ))
  done
  echo "${v}"
}

# -----------------------------
# Load config
# -----------------------------
[[ -f "${ENV_FILE}" ]] || fail "Missing ${ENV_FILE}"
[[ -f "${CLINICS_FILE}" ]] || fail "Missing ${CLINICS_FILE}"
[[ -f "${TABLES_FILE}" ]] || fail "Missing ${TABLES_FILE}"
command -v podman >/dev/null 2>&1 || fail "podman not found"

BHS_LOCATION="$(env_value BHS_LOCATION)"
[[ -n "${BHS_LOCATION}" ]] || fail "BHS_LOCATION not set in ${ENV_FILE}"
[[ "${INCREMENT}" -ge 1 ]] || fail "INCREMENT must be >= 1"

ROOT_PASSWORD="$(env_value MYSQL_ROOT_PASSWORD)"
DB_NAME="$(env_value OPENMRS_DB_NAME)"
DB_NAME="${DB_NAME:-openmrs}"
[[ -n "${ROOT_PASSWORD}" ]] || fail "MYSQL_ROOT_PASSWORD not set in ${ENV_FILE}"

LOCATION_LC="$(printf '%s' "${BHS_LOCATION}" | tr '[:upper:]' '[:lower:]')"
CLINIC_NAME=""
OFFSET=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  if [[ "$line" =~ ^([^:]+):([0-9]+)$ ]]; then
    name="${BASH_REMATCH[1]}"
    off="${BASH_REMATCH[2]}"
    name_lc="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${name_lc}" == "${LOCATION_LC}" ]]; then
      CLINIC_NAME="${name}"
      OFFSET="${off}"
      break
    fi
  else
    warn "Skipping malformed clinics.txt line: ${line}"
  fi
done < "${CLINICS_FILE}"

[[ -n "${OFFSET}" ]] || fail "BHS_LOCATION='${BHS_LOCATION}' not found in ${CLINICS_FILE}"
[[ "${OFFSET}" -ge 1 && "${OFFSET}" -le "${INCREMENT}" ]] \
  || fail "offset ${OFFSET} must be between 1 and INCREMENT (${INCREMENT})"

MYSQL_CONTAINER="$(resolve_container "${MYSQL_SERVICE}" || true)"
[[ -n "${MYSQL_CONTAINER}" ]] || fail "MySQL container '${MYSQL_SERVICE}' is not running"

printf '%s\n' "${C_BOLD}configure-pk-offsets${C_RESET}"
dim "clinic   : ${CLINIC_NAME} (BHS_LOCATION=${BHS_LOCATION})"
dim "offset   : ${OFFSET}"
dim "increment: ${INCREMENT}"
dim "database : ${DB_NAME} @ ${MYSQL_CONTAINER}"
[[ "${DRY_RUN}" == true ]] && warn "DRY-RUN — no changes will be applied"

# -----------------------------
# Global increment / offset (persisted across restart on MySQL 8 data volume)
# -----------------------------
info "Setting GLOBAL auto_increment_increment=${INCREMENT}, auto_increment_offset=${OFFSET}"
mysql_exec_sql "SET PERSIST auto_increment_increment = ${INCREMENT};"
mysql_exec_sql "SET PERSIST auto_increment_offset = ${OFFSET};"

if [[ "${DRY_RUN}" != true ]]; then
  cur_inc="$(mysql_exec -e "SELECT @@GLOBAL.auto_increment_increment;")"
  cur_off="$(mysql_exec -e "SELECT @@GLOBAL.auto_increment_offset;")"
  ok "GLOBAL increment=${cur_inc} offset=${cur_off} (SET PERSIST)"
fi

# -----------------------------
# Per-table AUTO_INCREMENT = base_id + offset (bumped if data already higher)
# -----------------------------
info "Updating AUTO_INCREMENT on tables from ${TABLES_FILE}"

updated=0
skipped=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue

  # Sync-only lines (table:pk) — no AUTO_INCREMENT base_id
  if [[ "$line" =~ ^([^:]+):([^:]+)$ ]]; then
    dim "Sync-only (no PK offset): ${BASH_REMATCH[1]}"
    continue
  fi

  if [[ ! "$line" =~ ^([^:]+):([^:]+):([0-9]+)$ ]]; then
    warn "Skipping malformed tables line: ${line}"
    continue
  fi

  table="${BASH_REMATCH[1]}"
  pk="${BASH_REMATCH[2]}"
  base_id="${BASH_REMATCH[3]}"
  target=$(( base_id + OFFSET ))

  exists="$(mysql_exec -e "SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='${DB_NAME}' AND table_name='${table}';" 2>/dev/null || echo 0)"
  if [[ "${exists}" != "1" ]]; then
    warn "Table ${table} not found — skip"
    skipped=$((skipped + 1))
    continue
  fi

  max_id="$(mysql_exec -e "SELECT IFNULL(MAX(\`${pk}\`), 0) FROM \`${table}\`;")"
  start_id="$(next_in_series "${target}" "${max_id}" "${OFFSET}")"

  if [[ "${start_id}" -ne "${target}" ]]; then
    warn "${table}: max(${pk})=${max_id} ≥ ${target} — using next in series ${start_id}"
  fi

  mysql_exec_sql "ALTER TABLE \`${table}\` AUTO_INCREMENT = ${start_id};"
  ok "${table}: AUTO_INCREMENT → ${start_id}  (base ${base_id} + offset ${OFFSET}; next ids ${start_id}, $((start_id + INCREMENT)), …)"
  updated=$((updated + 1))
done < "${TABLES_FILE}"

echo ""
ok "Done — ${updated} table(s) updated, ${skipped} skipped"
dim "Globals persist via SET PERSIST (mysqld-auto.cnf in the MySQL data volume)."
dim "Verify: podman exec ${MYSQL_CONTAINER} mysql -uroot -p… -e 'SELECT @@GLOBAL.auto_increment_increment, @@GLOBAL.auto_increment_offset'"
