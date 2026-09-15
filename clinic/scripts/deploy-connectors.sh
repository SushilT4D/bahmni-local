#!/bin/bash

# Wait for Kafka Connect to be ready
echo "Waiting for Kafka Connect to be ready..."
until curl -s http://localhost:8084/ > /dev/null; do
    echo "Kafka Connect not ready yet. Waiting..."
    sleep 5
done

echo "Kafka Connect is ready!"
sleep 10

# Deploy MirrorSourceConnector
echo "Deploying MirrorSourceConnector..."
curl -X POST http://localhost:8084/connectors \
  -H "Content-Type: application/json" \
  -d @config/mirror-source-connector.json

echo ""
sleep 2

# Deploy MirrorCheckpointConnector
echo "Deploying MirrorCheckpointConnector..."
curl -X POST http://localhost:8084/connectors \
  -H "Content-Type: application/json" \
  -d @config/mirror-checkpoint-connector.json

echo ""
sleep 2

# Deploy MirrorHeartbeatConnector
echo "Deploying MirrorHeartbeatConnector..."
curl -X POST http://localhost:8084/connectors \
  -H "Content-Type: application/json" \
  -d @config/mirror-heartbeat-connector.json

echo ""
echo "All connectors deployed!"
echo ""
echo "Checking connector status..."
sleep 5

curl -s http://localhost:8083/connectors | jq '.'