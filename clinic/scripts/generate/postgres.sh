#!/usr/bin/env bash
# Part of generate-connectors.sh: the Odoo and OpenELIS connectors.
#
# Writes connectors/odoo-source-connector.json, clinlims-source-connector.json,
# odoo-clinic-sink-all.json and clinlims-clinic-sink-all.json from
# scripts/templates/. It fills in everything except passwords:
#   - the table lists, from the [up] sections of sync/tables/odoo.conf and
#     openelis.conf;
#   - MYSQL_SERVER_NAME, from .env;
#   - the OpenELIS source's own-rows filters (CLINLIMS_UP_CONDITION_<TABLE>), from
#     the floors installer task 060 records in .install-state and BHS_SITE_NUMBER;
#   - the OpenELIS down sink's filter (CLINLIMS_DOWN_CONDITION), from
#     scripts/clinlims-down-filter.sh.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/../.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${CLINIC_DIR}/.." && pwd)}"
export CLINIC_DIR REPO_DIR
OUT="${CLINIC_DIR}/connectors"
TEMPLATES="${CLINIC_DIR}/scripts/templates"
die(){ printf 'generate-connectors (postgres): %s\n' "$*" >&2; exit 1; }
# shellcheck source=../../../sync/tables/tables.sh
. "${REPO_DIR}/sync/tables/tables.sh"
# shellcheck source=../../../sync/origin-filter.sh
. "${REPO_DIR}/sync/origin-filter.sh"

file_get(){ # FILE KEY -> the last value of KEY in FILE, quotes and blanks trimmed
  [ -f "$1" ] || return 0
  { grep -E "^$2=" "$1" || true; } | tail -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}
STATE_FILE="${STATE_FILE:-${CLINIC_DIR}/.install-state}"
value_of(){ # KEY -> the environment, else .env, else the installer's state file
  local v="${!1:-}"
  [ -n "$v" ] || v="$(file_get "${CLINIC_DIR}/.env" "$1")"
  [ -n "$v" ] || v="$(file_get "${STATE_FILE}" "$1")"
  printf '%s' "$v"
}

MYSQL_SERVER_NAME="$(value_of MYSQL_SERVER_NAME)"
[ -n "${MYSQL_SERVER_NAME}" ] || die "MYSQL_SERVER_NAME is not set in ${CLINIC_DIR}/.env"
BHS_SITE_NUMBER="$(value_of BHS_SITE_NUMBER)"
export MYSQL_SERVER_NAME

# The table lists.
list_vars(){ # DB SCHEMA PREFIX
  local t
  t="$(tables_list "$1" up)" || die "the $1 [up] list cannot be read (reason above)"
  [ -n "$t" ] || die "the $1 [up] list is empty"
  export "${3}_UP_TABLE_INCLUDE_LIST=$(printf '%s\n' "$t" | sed "s/^/$2./" | paste -sd, -)"
  export "${3}_UP_ALTERNATION=$(printf '%s\n' "$t" | paste -sd'|' -)"
}
list_vars odoo public ODOO
list_vars openelis clinlims CLINLIMS

# The OpenELIS source publishes a lab account or signature only when this
# clinic minted it: at or above the floor task 060 recorded, on this residue.
for t in ${UP_CLINLIMS_OWN_ROWS}; do
  k="CLINLIMS_FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
  fl="$(value_of "$k")"
  [ -n "$fl" ] || die "no ${k} is recorded in ${STATE_FILE} (installer task 060 records it before it strides the OpenELIS ids), so the OpenELIS source cannot tell this clinic's ${t} rows from the hub's"
  c="$(origin_filter_condition id "$fl" "${BHS_SITE_NUMBER}")" || die "the ${t} filter could not be written (reason above)"
  export "CLINLIMS_UP_CONDITION_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')=$c"
done

# The OpenELIS down sink keeps only this clinic's rows.
CLINLIMS_DOWN_CONDITION="$(bash "${CLINIC_DIR}/scripts/clinlims-down-filter.sh")" \
  || die "the OpenELIS down sink's filter cannot be written (reason above), so lab results entered at the hub would never reach this clinic's OpenELIS"
export CLINLIMS_DOWN_CONDITION

mkdir -p "${OUT}"
for name in odoo-source-connector clinlims-source-connector odoo-clinic-sink-all clinlims-clinic-sink-all; do
  python3 "${CLINIC_DIR}/scripts/_fill_template.py" "${TEMPLATES}/${name}.json" "${OUT}/${name}.json" \
    || die "${name} could not be written (reason above)"
  echo "  ${name}.json"
done
