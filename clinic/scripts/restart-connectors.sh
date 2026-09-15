#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./restart-connector.sh <connector-name>"
    echo "Example: ./restart-connector.sh mirror-source-connector"
    exit 1
fi

CONNECTOR_NAME=$1

echo "Restarting connector: $CONNECTOR_NAME"
curl -X POST http://localhost:8084/connectors/$CONNECTOR_NAME/restart

echo ""
echo "Connector restarted. Checking status..."
sleep 3

curl -s http://localhost:8084/connectors/$CONNECTOR_NAME/status | jq '.'