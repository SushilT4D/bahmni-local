#!/bin/bash

# Script to register the Debezium MySQL Source Connector
# This script reads environment variables and creates the connector configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_DIR="${SCRIPT_DIR}/.."
PROJECT_DIR="."
CONNECTORS_DIR="${PROJECT_DIR}/connectors"
CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "Registering Debezium MySQL Source Connector..."

# Prefer generated alias; fall back to the historical local filename.
CONNECTOR_FILE=""
for candidate in \
  "${CONNECTORS_DIR}/mysql-source-connector.json" \
  "${CONNECTORS_DIR}/mysql-local-source-connector.json"
do
  if [ -f "${candidate}" ]; then
    CONNECTOR_FILE="${candidate}"
    break
  fi
done

if [ -z "${CONNECTOR_FILE}" ]; then
    echo "Error: mysql-source-connector.json not found!"
    echo "Run: ./scripts/generate-connectors.sh"
    exit 1
fi
echo "Using config: ${CONNECTOR_FILE}"

# Check if connector already exists
existing=$(curl -s "${CONNECT_URL}/connectors/mysql-source-connector" 2>/dev/null)
if echo "$existing" | grep -q "error_code"; then
    # Connector doesn't exist, create it
    echo "Creating new connector..."
    response=$(curl -s -X POST "${CONNECT_URL}/connectors" \
        -H "Content-Type: application/json" \
        -d @"${CONNECTOR_FILE}")
else
    # Connector exists, update it
    echo "Connector already exists. Updating configuration..."
    # Extract just the config object for PUT request
    config_json=$(jq '.config' "${CONNECTOR_FILE}")
    response=$(curl -s -X PUT "${CONNECT_URL}/connectors/mysql-source-connector/config" \
        -H "Content-Type: application/json" \
        -d "$config_json")
fi

# Check if registration/update was successful
if echo "$response" | grep -q "error_code"; then
    echo "Error registering/updating connector:"
    echo "$response" | jq '.'
    exit 1
else
    echo "Connector registered/updated successfully!"
    echo "$response" | jq '.'
fi

# Wait a moment for connector to initialize
sleep 2

# Check connector status
echo ""
echo "Checking connector status..."
curl -s "${CONNECT_URL}/connectors/mysql-source-connector/status" | jq '.'

