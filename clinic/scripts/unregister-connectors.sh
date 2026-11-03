#!/bin/bash

# Script to unregister connectors
# This is a utility script - for production use, prefer directory-specific scripts

set -e

CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "Unregistering connectors..."
echo ""
echo "Note: This script attempts to unregister connectors from ${CONNECT_URL}"
echo "For local setup, use: cd local && ./scripts/unregister-connectors.sh"
echo "For remote setup, use: cd remote && ./scripts/unregister-connectors.sh"
echo ""

# Unregister source connector (local)
echo "Unregistering mysql-source-connector..."
if curl -s -X DELETE "${CONNECT_URL}/connectors/mysql-source-connector" > /dev/null; then
    echo "✓ Source connector unregistered"
else
    echo "✗ Failed to unregister source connector (may not exist)"
fi

# Unregister MirrorMaker connector (local)
echo "Unregistering MirrorSourceConnector..."
if curl -s -X DELETE "${CONNECT_URL}/connectors/MirrorSourceConnector" > /dev/null; then
    echo "✓ MirrorMaker connector unregistered"
else
    echo "✗ Failed to unregister MirrorMaker connector (may not exist)"
fi

# Unregister sink connector (remote)
echo "Unregistering mysql-sink-connector..."
if curl -s -X DELETE "${CONNECT_URL}/connectors/mysql-sink-connector" > /dev/null; then
    echo "✓ Sink connector unregistered"
else
    echo "✗ Failed to unregister sink connector (may not exist)"
fi

echo ""
echo "Done!"
echo ""
echo "Note: If connectors are running on different ports, set KAFKA_CONNECT_URL:"
echo "  export KAFKA_CONNECT_URL=http://localhost:8083  # local"
echo "  export KAFKA_CONNECT_URL=http://localhost:8083  # remote"

