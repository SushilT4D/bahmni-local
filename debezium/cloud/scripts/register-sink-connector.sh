#!/bin/bash

# Script to register the JDBC MySQL Sink Connector
# This script reads environment variables and creates the connector configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
CONNECTORS_DIR="${PROJECT_DIR}/connectors"
CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "Registering JDBC MySQL Sink Connector..."

# Check if connector configuration exists
if [ ! -f "${CONNECTORS_DIR}/mysql-sink-connector.json" ]; then
    echo "Error: mysql-sink-connector.json not found!"
    echo "Please run setup-connectors.sh first to generate connector configurations."
    exit 1
fi

# Register the connector
response=$(curl -s -X POST "${CONNECT_URL}/connectors" \
    -H "Content-Type: application/json" \
    -d @"${CONNECTORS_DIR}/mysql-sink-connector.json")

# Check if registration was successful
if echo "$response" | grep -q "error_code"; then
    echo "Error registering connector:"
    echo "$response" | jq '.'
    exit 1
else
    echo "Connector registered successfully!"
    echo "$response" | jq '.'
fi

# Wait a moment for connector to initialize
sleep 2

# Check connector status
echo ""
echo "Checking connector status..."
curl -s "${CONNECT_URL}/connectors/mysql-sink-connector/status" | jq '.'

