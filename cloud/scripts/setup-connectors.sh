#!/bin/bash
# Generates the hub's up sinks and registers exactly those with Kafka Connect.
# usage: setup-connectors.sh [--db openmrs,odoo,clinlims] [slug ...]
#   --db    the databases (default: all three)
#   slug    the clinics (default: every clinic in sync/clinics.json)
# An OpenMRS sink needs HUB_MYSQL_CONTAINER set, for the foreign-key check before it is registered.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINICS_JSON="${CLINICS_JSON:-${SCRIPT_DIR}/../../sync/clinics.json}"
export OUT_DIR="${OUT_DIR:-$PWD/connectors}"

DBS="openmrs,odoo,clinlims"
gen_args=()
if [ "${1:-}" = "--db" ]; then
  DBS="${2:-}"; gen_args=(--db "$DBS"); shift 2 || shift $#
fi

"${SCRIPT_DIR}/generate-sink-connectors.sh" "${gen_args[@]}" "$@"

slugs="$*"
[ -n "$slugs" ] || slugs="$(jq -r 'to_entries[] | select(.key != "cloud" and .value.site_number != null) | .key' "${CLINICS_JSON}")"
files=()
for slug in $slugs; do
  for d in ${DBS//,/ }; do
    files+=("${OUT_DIR}/${d}-${slug}-sink.json")
  done
done

echo ""
CONNECTORS_DIR="${OUT_DIR}" "${SCRIPT_DIR}/register-all-sink-connectors.sh" "${files[@]}"
