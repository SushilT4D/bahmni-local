#!/bin/bash
# Check sink connector status on remote server
# Usage: ./check-sink-connectors.sh [remote-host] [table]

REMOTE_HOST="${1:-localhost}"
TABLE="${2:-person}"
CONNECT_URL="http://${REMOTE_HOST}:8083"

echo "Checking sink connectors on ${REMOTE_HOST}..."
echo ""

# Check if Kafka Connect is accessible
if ! curl -s --connect-timeout 2 "${CONNECT_URL}/connectors" > /dev/null 2>&1; then
    echo "✗ Cannot connect to Kafka Connect at ${CONNECT_URL}"
    echo "  Is Kafka Connect running on the remote server?"
    echo "  Check: curl ${CONNECT_URL}/connectors"
    exit 1
fi

echo "✓ Kafka Connect is accessible"
echo ""

# List all connectors
echo "All registered connectors:"
ALL_CONNECTORS=$(curl -s "${CONNECT_URL}/connectors" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
if [ -z "$ALL_CONNECTORS" ]; then
    echo "  (no connectors found)"
else
    echo "$ALL_CONNECTORS" | while read -r connector; do
        echo "  - $connector"
    done
fi
echo ""

# Check specific sink connector
SINK_CONNECTOR="mysql-sink-${TABLE}"
echo "Checking connector: ${SINK_CONNECTOR}"

# Check if connector exists
CONNECTOR_EXISTS=$(curl -s "${CONNECT_URL}/connectors" 2>/dev/null | jq -r ".[] | select(. == \"${SINK_CONNECTOR}\")" 2>/dev/null || echo "")

if [ -z "$CONNECTOR_EXISTS" ]; then
    echo "✗ Connector '${SINK_CONNECTOR}' not found"
    echo ""
    echo "Available connectors:"
    curl -s "${CONNECT_URL}/connectors" 2>/dev/null | jq -r '.[]' 2>/dev/null | grep -i sink || echo "  (no sink connectors found)"
    echo ""
    echo "To register connectors, run on remote server:"
    echo "  cd remote"
    echo "  ./scripts/generate-sink-connectors.sh"
    echo "  ./scripts/register-all-sink-connectors.sh"
    exit 1
fi

echo "✓ Connector exists"
echo ""

# Get connector status
echo "Connector status:"
STATUS=$(curl -s "${CONNECT_URL}/connectors/${SINK_CONNECTOR}/status" 2>/dev/null)
if [ -z "$STATUS" ] || echo "$STATUS" | grep -q "error_code"; then
    echo "✗ Error getting status:"
    echo "$STATUS" | jq '.' 2>/dev/null || echo "$STATUS"
else
    echo "$STATUS" | jq '.'
fi

