#!/bin/bash

# Script to generate sink connector configuration for each table
# Creates separate connector configs for better control

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
TABLES_CONF="${PROJECT_DIR}/tables.conf"
ENV_FILE="${PROJECT_DIR}/.env"
CONNECTORS_DIR="${PROJECT_DIR}/connectors"

if [ ! -f "${TABLES_CONF}" ]; then
    echo "Error: tables.conf not found!"
    exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# Source environment variables
set -a
source "${ENV_FILE}"
set +a

# Normalize MySQL SSL flag (must be TRUE/FALSE/YES/NO for JDBC driver)
USE_SSL_RAW="${REMOTE_MYSQL_USE_SSL:-false}"
USE_SSL_UPPER=$(echo "${USE_SSL_RAW}" | tr '[:lower:]' '[:upper:]')
case "${USE_SSL_UPPER}" in
    TRUE|FALSE|YES|NO) ;;
    *)
        echo "Warning: REMOTE_MYSQL_USE_SSL='${USE_SSL_RAW}' is invalid. Defaulting to FALSE."
        USE_SSL_UPPER="FALSE"
        ;;
esac

# Server name should match MYSQL_SERVER_NAME from local setup
# This is used to construct topic names: {server-name}.{database}.{table}
SERVER_NAME="${MYSQL_SERVER_NAME:-${REMOTE_SOURCE_SERVER_NAME:-bahmni-local}}"
DATABASE_NAME="${DATABASE_NAME:-openmrs}"

# Create connectors directory if it doesn't exist
mkdir -p "${CONNECTORS_DIR}"

# Parse tables.conf and generate connector configs
connector_count=0
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    
    # Parse table:pk or table:pk:base_id
    if [[ "$line" =~ ^([^:]+):([^:]+)(:([0-9]+))?$ ]]; then
        table="${BASH_REMATCH[1]}"
        pk="${BASH_REMATCH[2]}"
        
        topic="${SERVER_NAME}.${DATABASE_NAME}.${table}"
        connector_name="mysql-sink-${table}"
        config_file="${CONNECTORS_DIR}/${connector_name}.json"
        
        # Generate connector config (pk.fields must be the real column, not ${table}_id)
        cat > "${config_file}" <<EOF
{
  "name": "${connector_name}",
  "config": {
    "connector.class": "io.debezium.connector.jdbc.JdbcSinkConnector",
    "tasks.max": "1",

    "topics": "source.bahmni-local.openmrs.${topic}",
    "transforms": "dropPrefix",
    "transforms.dropPrefix.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.dropPrefix.regex": "source\\.bahmni-local\\.openmrs\\.(.*)",
    "transforms.dropPrefix.replacement": "$1",
    "table.name.format.default": "openmrs.${table}",
    "connection.url": "jdbc:mysql://${REMOTE_MYSQL_HOST}:${REMOTE_MYSQL_PORT}/${REMOTE_MYSQL_DATABASE}?useSSL=${USE_SSL_UPPER}&allowPublicKeyRetrieval=true",
    "connection.username": "${REMOTE_MYSQL_USER}",
    "connection.password": "${REMOTE_MYSQL_PASSWORD}",
    "insert.mode": "upsert",
    "primary.key.mode": "record_value",
    "primary.key.fields": "${pk}",
    "delete.enabled": "false",
    "auto.create": "true",
    "auto.evolve": "true",
    "errors.tolerance": "all",
    "errors.log.enable": "true",
    "errors.log.include.messages": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false"
  }
}
EOF
        
        echo "Generated: ${config_file} (table: ${table}, topic: ${topic}, pk: ${pk})"
        connector_count=$((connector_count + 1))
    fi
done < "${TABLES_CONF}"

echo ""
echo "Generated ${connector_count} sink connector configuration(s)"
echo ""
echo "To register connectors, use:"
echo "  ./scripts/register-all-sink-connectors.sh"

