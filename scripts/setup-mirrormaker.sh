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
LEGACY_TEMPLATE="${PROJECT_DIR}/debezium/local/mirrormaker-config/mm2.properties.template"
LEGACY_OUTPUT="${PROJECT_DIR}/debezium/local/mirrormaker-config/mm2.properties"
TABLES_CONF="${PROJECT_DIR}/debezium/local/tables.conf"

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
# Cloud SASL + truststore secrets are NOT written into mm2.properties —
# injected at container start by config/mirrormaker/start-mm2.sh from:
#   REMOTE_KAFKA_USERNAME, REMOTE_KAFKA_PASSWORD, REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD

echo "✓ BHS_LOCATION=${BHS_LOCATION}"
echo "✓ MIRRORMAKER_CONSUMER_GROUP_ID=${MIRRORMAKER_CONSUMER_GROUP_ID}"
echo "✓ MIRRORMAKER_CLUSTER_GROUP_ID=${MIRRORMAKER_CLUSTER_GROUP_ID}"
echo "✓ cloud secrets left as \${REMOTE_KAFKA_*} placeholders (runtime inject)"

# Optional: topic patterns from tables.conf
SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
DATABASE_NAME="${DATABASE_NAME:-openmrs}"
if [[ -z "${KAFKA_TOPIC_PATTERNS:-}" && -f "${TABLES_CONF}" ]]; then
  topics=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    if [[ "$line" =~ ^([^:]+):(.+)$ ]]; then
      table="${BASH_REMATCH[1]}"
      topics+=("${SERVER_NAME}\\.${DATABASE_NAME}\\.${table}")
    fi
  done < "${TABLES_CONF}"
  if [[ ${#topics[@]} -gt 0 ]]; then
    export KAFKA_TOPIC_PATTERNS="($(IFS='|'; echo "${topics[*]}"))"
    echo "✓ Generated topic pattern from tables.conf: ${KAFKA_TOPIC_PATTERNS}"
  fi
fi

# Omit cloud credential vars so placeholders remain for start-mm2.sh.
SUBST_VARS='${BHS_LOCATION} ${MIRRORMAKER_CONSUMER_GROUP_ID} ${MIRRORMAKER_CLUSTER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}'

envsubst "${SUBST_VARS}" < "${TEMPLATE}" > "${OUTPUT}"
echo "✓ Generated: ${OUTPUT}"

# Keep legacy debezium/local template in sync when present
if [[ -f "${LEGACY_TEMPLATE}" ]]; then
  mkdir -p "$(dirname "${LEGACY_OUTPUT}")"
  # Legacy template only needs the consumer group + remote bootstrap vars
  LEGACY_SUBST='${MIRRORMAKER_CONSUMER_GROUP_ID} ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} ${KAFKA_TOPIC_PATTERNS} ${MIRRORMAKER_PRODUCER_RETRIES} ${MIRRORMAKER_PRODUCER_MAX_IN_FLIGHT}'
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
