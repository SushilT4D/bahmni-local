#!/bin/bash
# Check source connector status on local machine (Debezium/MySQL source)
# Usage: ./scripts/check-source-connectors.sh [host] [connector-name]

HOST="${1:-localhost}"
CONNECTOR_NAME="${2:-mysql-source-connector}"
CONNECT_URL="http://${HOST}:8083"

echo "Checking source connectors on ${HOST}..."
echo ""

# Verify Kafka Connect is reachable
if ! curl -s --connect-timeout 2 "${CONNECT_URL}/connectors" > /dev/null 2>&1; then
    echo "✗ Cannot reach Kafka Connect at ${CONNECT_URL}"
    echo "  Is the local Kafka Connect container running?"
    echo "  Try: podman ps | grep kafka-connect"
    exit 1
fi

echo "✓ Kafka Connect REST API reachable"
echo ""

# List all connectors
echo "Registered connectors:"
all_connectors=$(curl -s "${CONNECT_URL}/connectors" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
if [ -z "${all_connectors}" ]; then
    echo "  (none found)"
else
    echo "${all_connectors}" | while read -r connector; do
        echo "  - ${connector}"
    done
fi
echo ""

echo "Checking connector: ${CONNECTOR_NAME}"

# Ensure connector exists
connector_exists=$(echo "${all_connectors}" | grep -Fx "${CONNECTOR_NAME}")
if [ -z "${connector_exists}" ]; then
    echo "✗ Connector '${CONNECTOR_NAME}' not found"
    echo ""
    echo "To register it locally:"
    echo "  cd local"
    echo "  ./scripts/setup-connectors.sh"
    echo "  ./scripts/register-source-connector.sh"
    exit 1
fi

echo "✓ Connector exists"
echo ""

# Fetch connector status
status_json=$(curl -s "${CONNECT_URL}/connectors/${CONNECTOR_NAME}/status" 2>/dev/null)
if [ -z "${status_json}" ]; then
    echo "✗ Unable to retrieve connector status"
    exit 1
fi

echo "Connector status:"
echo "${status_json}" | jq '.' 2>/dev/null || echo "${status_json}"

echo ""
echo "Summary:"
connector_state=$(echo "${status_json}" | jq -r '.connector.state // empty' 2>/dev/null)
task_states=$(echo "${status_json}" | jq -r '.tasks[]? | "  - Task \(.id): \(.state)"' 2>/dev/null)

echo "  Connector state: ${connector_state:-unknown}"
if [ -n "${task_states}" ]; then
    echo "${task_states}"
else
    echo "  Tasks: none reported"
fi


