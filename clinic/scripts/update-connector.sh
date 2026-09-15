#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./update-connector.sh <connector-name> <config-file>"
    echo "Example: ./update-connector.sh mirror-source-connector config/mirror-source-connector.json"
    exit 1
fi

CONNECTOR_NAME=$1
CONFIG_FILE=$2

echo "Updating connector: $CONNECTOR_NAME"
echo "Using config file: $CONFIG_FILE"

# Extract just the config section from the JSON file
CONFIG_BODY=$(cat $CONFIG_FILE | jq '.config')

curl -X PUT http://localhost:8084/connectors/$CONNECTOR_NAME/config \
  -H "Content-Type: application/json" \
  -d "$CONFIG_BODY"

echo ""
echo "Connector updated. Checking status..."
sleep 3

curl -s http://localhost:8084/connectors/$CONNECTOR_NAME/status | jq '.'