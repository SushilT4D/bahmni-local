#!/usr/bin/env bash
# Generate MirrorMaker 2 config from template.
# Consumer group IDs are derived from BHS_LOCATION so each clinic
# tracks cloud-topic offsets independently.
#
# Usage: ./scripts/setup-mirrormaker.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
TEMPLATE="${PROJECT_DIR}/config/mirrormaker/mm2.properties.template"
OUTPUT="${PROJECT_DIR}/config/mirrormaker/mm2.properties"
LEGACY_TEMPLATE="${PROJECT_DIR}/../sync/local/mirrormaker-config/mm2.properties.template"
LEGACY_OUTPUT="${PROJECT_DIR}/../sync/local/mirrormaker-config/mm2.properties"
TABLES_CONF="${PROJECT_DIR}/../sync/local/tables.conf"
DOWN_TABLES_CONF="${PROJECT_DIR}/../hub/tables.conf"
SUBSYSTEMS_CONF="${PROJECT_DIR}/../sync/subsystems.conf"

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
export LOCAL_CLUSTER_ALIAS="${LOCAL_CLUSTER_ALIAS:-source}"
export BHS_LOCATION
export MIRRORMAKER_CONSUMER_GROUP_ID="mirrormaker-consumer-group-${BHS_LOCATION}"
export MIRRORMAKER_CLUSTER_GROUP_ID="mirrormaker-cluster-${BHS_LOCATION}"
export REMOTE_KAFKA_BOOTSTRAP_SERVERS
# Cloud SASL + truststore secrets are NOT written into mm2.properties —
# injected at container start by config/mirrormaker/start-mm2.sh from:
#   REMOTE_KAFKA_USERNAME, REMOTE_KAFKA_PASSWORD, REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD

echo "✓ BHS_LOCATION=${BHS_LOCATION}"
echo "✓ MIRRORMAKER_CONSUMER_GROUP_ID=${MIRRORMAKER_CONSUMER_GROUP_ID}"
echo "✓ MIRRORMAKER_CLUSTER_GROUP_ID=${MIRRORMAKER_CLUSTER_GROUP_ID}"
echo "✓ cloud secrets left as \${REMOTE_KAFKA_*} placeholders (runtime inject)"

# ---------------------------------------------------------------------------
# Topic patterns.  BOTH directions are generated here.
#
# Before 2026-09-14 only the UP pattern was built, and only from
# debezium/local/tables.conf -- OpenMRS tables.  The DOWN pattern was a literal
# in the template.  Both omitted every Odoo and OpenELIS topic, so regenerating
# mm2.properties silently dropped two whole subsystems from replication.  The
# subsystem topics now come from debezium/subsystems.conf, which is the tracked
# source of truth for them.
#
# Ordering is deliberate and matches the rendered file this replaced:
# aggregates first, then OpenMRS, then per-table subsystem topics.
# ---------------------------------------------------------------------------
SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
DATABASE_NAME="${DATABASE_NAME:-openmrs}"
REMOTE_SERVER_NAME="${REMOTE_SERVER_NAME:-bahmni-cloud}"

# build_topic_pattern <server-name> <openmrs-tables.conf>
# Emits a MirrorMaker topics regex.  Dots are escaped for the regex, so a topic
# name is matched literally rather than "." matching any character.
build_topic_pattern() {
  local sn="$1" tconf="$2"
  local aggs=() omrs=() subs=() line schema topic table

  if [[ -f "${SUBSYSTEMS_CONF}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^([^:]+):(.+)$ ]] || continue
      schema="${BASH_REMATCH[1]}"; topic="${BASH_REMATCH[2]}"
      if [[ "${topic}" == "all" ]]; then
        aggs+=("${sn}\\.${schema}\\.${topic}")
      else
        subs+=("${sn}\\.${schema}\\.${topic}")
      fi
    done < "${SUBSYSTEMS_CONF}"
  fi

  if [[ -f "${tconf}" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^([^:]+):(.+)$ ]] || continue
      table="${BASH_REMATCH[1]}"
      omrs+=("${sn}\\.${DATABASE_NAME}\\.${table}")
    done < "${tconf}"
  fi

  local all=("${aggs[@]}" "${omrs[@]}" "${subs[@]}")
  (( ${#all[@]} > 0 )) || return 1
  printf '(%s)' "$(IFS='|'; echo "${all[*]}")"
}

if [[ -z "${KAFKA_TOPIC_PATTERNS:-}" ]]; then
  if KAFKA_TOPIC_PATTERNS="$(build_topic_pattern "${SERVER_NAME}" "${TABLES_CONF}")"; then
    export KAFKA_TOPIC_PATTERNS
    echo "✓ UP   topics ($(grep -o '|' <<<"${KAFKA_TOPIC_PATTERNS}" | wc -l | tr -d ' ') separators): ${SERVER_NAME}.*"
  fi
fi

if [[ -z "${KAFKA_DOWN_TOPIC_PATTERNS:-}" ]]; then
  if KAFKA_DOWN_TOPIC_PATTERNS="$(build_topic_pattern "${REMOTE_SERVER_NAME}" "${DOWN_TABLES_CONF}")"; then
    export KAFKA_DOWN_TOPIC_PATTERNS
    echo "✓ DOWN topics ($(grep -o '|' <<<"${KAFKA_DOWN_TOPIC_PATTERNS}" | wc -l | tr -d ' ') separators): ${REMOTE_SERVER_NAME}.*"
  fi
fi
export REMOTE_SERVER_NAME

# Omit cloud credential vars so placeholders remain for start-mm2.sh.
SUBST_VARS='${LOCAL_CLUSTER_ALIAS} ${KAFKA_TOPIC_PATTERNS} ${KAFKA_DOWN_TOPIC_PATTERNS} ${BHS_LOCATION} ${MIRRORMAKER_CONSUMER_GROUP_ID} ${MIRRORMAKER_CLUSTER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}'

envsubst "${SUBST_VARS}" < "${TEMPLATE}" > "${OUTPUT}"
echo "✓ Generated: ${OUTPUT}"

# Keep legacy debezium/local template in sync when present
if [[ -f "${LEGACY_TEMPLATE}" ]]; then
  mkdir -p "$(dirname "${LEGACY_OUTPUT}")"
  # Legacy template only needs the consumer group + remote bootstrap vars
  LEGACY_SUBST='${LOCAL_CLUSTER_ALIAS} ${MIRRORMAKER_CONSUMER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} ${KAFKA_TOPIC_PATTERNS} ${MIRRORMAKER_PRODUCER_RETRIES} ${MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT}'
  export KAFKA_TOPIC_PATTERNS="${KAFKA_TOPIC_PATTERNS:-.*}"
  export MIRRORMAKER_PRODUCER_RETRIES="${MIRRORMAKER_PRODUCER_RETRIES:-2147483647}"
  export MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT="${MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT:-1}"
  envsubst "${LEGACY_SUBST}" < "${LEGACY_TEMPLATE}" > "${LEGACY_OUTPUT}"
  echo "✓ Generated: ${LEGACY_OUTPUT}"
fi

echo ""
echo "MirrorMaker configuration generated successfully."
echo "Restart mirrormaker-connect to apply:"
echo "  podman-compose --profile debezium up -d mirrormaker-connect"
