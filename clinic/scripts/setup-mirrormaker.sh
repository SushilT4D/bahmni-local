#!/usr/bin/env bash
# Generate MirrorMaker 2 config from the template.
# Usage: ./scripts/setup-mirrormaker.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
TEMPLATE="${PROJECT_DIR}/config/mirrormaker/mm2.properties.template"
OUTPUT="${PROJECT_DIR}/config/mirrormaker/mm2.properties"
LEGACY_TEMPLATE="${PROJECT_DIR}/../sync/local/mirrormaker-config/mm2.properties.template"
LEGACY_OUTPUT="${PROJECT_DIR}/../sync/local/mirrormaker-config/mm2.properties"
TABLES_CONF="${PROJECT_DIR}/../sync/tables/openmrs.conf"
DOWN_TABLES_CONF="${TABLES_CONF}"
# shellcheck source=../../sync/tables/tables.sh
. "${PROJECT_DIR}/../sync/tables/tables.sh"

echo "Setting up MirrorMaker configuration..."

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env file not found at ${ENV_FILE}"
  exit 1
fi

if [[ ! -f "${TEMPLATE}" ]]; then
  echo "Error: template not found: ${TEMPLATE}"
  exit 1
fi

command -v envsubst >/dev/null 2>&1 || {
  echo "Error: envsubst not found (install gettext)"
  exit 1
}

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ -z "${BHS_LOCATION:-}" ]]; then
  echo "Error: BHS_LOCATION is not set in .env"
  echo "Set it to a short clinic id (e.g. rawach) so consumer groups are unique."
  exit 1
fi

if [[ ! "${BHS_LOCATION}" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Error: BHS_LOCATION must match [A-Za-z0-9_]+ (got: ${BHS_LOCATION})"
  exit 1
fi

if [[ -z "${REMOTE_KAFKA_BOOTSTRAP_SERVERS:-}" ]]; then
  echo "Error: REMOTE_KAFKA_BOOTSTRAP_SERVERS not set in .env"
  exit 1
fi

# Always derive from location so two clinics never share a cloud consumer group.
export BHS_LOCATION
export MIRRORMAKER_CONSUMER_GROUP_ID="mirrormaker-consumer-group-${BHS_LOCATION}"
export MIRRORMAKER_CLUSTER_GROUP_ID="mirrormaker-cluster-${BHS_LOCATION}"
export REMOTE_KAFKA_BOOTSTRAP_SERVERS
# Cloud secrets stay out of mm2.properties: it reads them as ${env:...} from the container's environment.

echo "✓ BHS_LOCATION=${BHS_LOCATION}"
echo "✓ MIRRORMAKER_CONSUMER_GROUP_ID=${MIRRORMAKER_CONSUMER_GROUP_ID}"
echo "✓ MIRRORMAKER_CLUSTER_GROUP_ID=${MIRRORMAKER_CLUSTER_GROUP_ID}"
echo "✓ cloud secrets read from the container environment (\${env:REMOTE_KAFKA_*})"

# Generate topic patterns for both replication directions.
SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
REMOTE_SERVER_NAME="${REMOTE_SERVER_NAME:-bahmni-cloud}"

# Build an escaped topic regex from the validated table lists.
build_topic_pattern() {
  local sn="$1" tconf="$2" grammar="${3:-}"
  local aggs=() omrs=() subs=() line schema topic table recs dsubs dtabs

  if [[ "${grammar}" == down ]]; then
    for schema in odoo clinlims; do
      dtabs="$(tables_list "${schema}" down)" || { echo "Error: the hub's down list cannot be read (reason above)" >&2; return 2; }
      dtabs="$(printf '%s\n' "$dtabs" | cut -d: -f1)"
      aggs+=("${sn}\\.${schema}\\.all")
      for table in ${dtabs}; do subs+=("${sn}\\.${schema}\\.${table}"); done
    done
  else
    # Odoo and OpenELIS: each [up] table, and the aggregate topic <schema>.all
    # every table is captured into.
    for schema in clinlims odoo; do
      dtabs="$(tables_list "${schema}" up)" || { echo "Error: the ${schema} [up] list cannot be read (reason above)" >&2; return 2; }
      aggs+=("${sn}\\.${schema}\\.all")
      for table in ${dtabs}; do subs+=("${sn}\\.${schema}\\.${table}"); done
    done
  fi

  if [[ -f "${tconf}" && "${grammar}" == up ]]; then
    # shellcheck source=../../sync/tables/tables.sh
    . "${PROJECT_DIR}/../sync/tables/tables.sh"
    recs="$(up_tables_read "${tconf}")" || { echo "Error: ${tconf} cannot be read as the clinic's table list (reason above)" >&2; return 2; }
    while read -r table _rest; do
      [[ -n "${table}" ]] || continue
      omrs+=("${sn}\\.openmrs\\.${table}")
    done <<EOF
${recs}
EOF
  elif [[ -f "${tconf}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^([^:]+):(.+)$ ]] || continue
      table="${BASH_REMATCH[1]}"
      omrs+=("${sn}\\.openmrs\\.${table}")
    done < <(tables_section "${tconf}" down)
  fi

  # OpenMRS: the aggregate topic <database>.all every table is routed into; the per-table
  # topics stay listed until every clinic has drained them
  aggs+=("${sn}\\.openmrs\\.all")
  local all=("${aggs[@]}" "${omrs[@]}" "${subs[@]}")
  (( ${#all[@]} > 0 )) || return 1
  printf '(%s)' "$(IFS='|'; echo "${all[*]}")"
}

if [[ -z "${KAFKA_TOPIC_PATTERNS:-}" ]]; then
  up_rc=0; KAFKA_TOPIC_PATTERNS="$(build_topic_pattern "${SERVER_NAME}" "${TABLES_CONF}" up)" || up_rc=$?
  [[ "${up_rc}" -ne 2 ]] || exit 1
  if [[ "${up_rc}" -eq 0 ]]; then
    export KAFKA_TOPIC_PATTERNS
    echo "✓ UP   topics ($(grep -o '|' <<<"${KAFKA_TOPIC_PATTERNS}" | wc -l | tr -d ' ') separators): ${SERVER_NAME}.*"
  fi
fi

if [[ -z "${KAFKA_DOWN_TOPIC_PATTERNS:-}" ]]; then
  down_rc=0; KAFKA_DOWN_TOPIC_PATTERNS="$(build_topic_pattern "${REMOTE_SERVER_NAME}" "${DOWN_TABLES_CONF}" down)" || down_rc=$?
  [[ "${down_rc}" -ne 2 ]] || exit 1
  if [[ "${down_rc}" -eq 0 ]]; then
    export KAFKA_DOWN_TOPIC_PATTERNS
    echo "✓ DOWN topics ($(grep -o '|' <<<"${KAFKA_DOWN_TOPIC_PATTERNS}" | wc -l | tr -d ' ') separators): ${REMOTE_SERVER_NAME}.*"
  fi
fi
export REMOTE_SERVER_NAME

# Substitute only these; the ${env:...} references stay for MirrorMaker to resolve.
SUBST_VARS='${KAFKA_TOPIC_PATTERNS} ${KAFKA_DOWN_TOPIC_PATTERNS} ${BHS_LOCATION} ${MIRRORMAKER_CONSUMER_GROUP_ID} ${MIRRORMAKER_CLUSTER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}'

GENERATED_NOTE="# Generated by clinic/scripts/setup-mirrormaker.sh from its template and sync/tables/*.conf. Do not edit: change those and run setup-mirrormaker.sh again."
{ printf '%s\n' "${GENERATED_NOTE}"; envsubst "${SUBST_VARS}" < "${TEMPLATE}"; } > "${OUTPUT}"
echo "✓ Generated: ${OUTPUT}"

# Keep legacy debezium/local template in sync when present
if [[ -f "${LEGACY_TEMPLATE}" ]]; then
  mkdir -p "$(dirname "${LEGACY_OUTPUT}")"
  # Legacy template only needs the consumer group + remote bootstrap vars
  LEGACY_SUBST='${MIRRORMAKER_CONSUMER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} ${KAFKA_TOPIC_PATTERNS} ${MIRRORMAKER_PRODUCER_RETRIES} ${MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT}'
  export KAFKA_TOPIC_PATTERNS="${KAFKA_TOPIC_PATTERNS:-.*}"
  export MIRRORMAKER_PRODUCER_RETRIES="${MIRRORMAKER_PRODUCER_RETRIES:-2147483647}"
  export MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT="${MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT:-1}"
  { printf '%s\n' "${GENERATED_NOTE}"; envsubst "${LEGACY_SUBST}" < "${LEGACY_TEMPLATE}"; } > "${LEGACY_OUTPUT}"
  echo "✓ Generated: ${LEGACY_OUTPUT}"
fi

echo ""
echo "MirrorMaker configuration generated successfully."
echo "Restart mirrormaker-connect to apply:"
echo "  podman-compose --profile debezium up -d mirrormaker-connect"
