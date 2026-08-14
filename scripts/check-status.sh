#!/bin/bash

echo "=== Kafka Connect Status ==="
curl -s http://localhost:8084/ | jq '.'

echo ""
echo "=== All Connectors ==="
curl -s http://localhost:8084/connectors | jq '.'

echo ""
echo "=== MirrorSourceConnector Status ==="
curl -s http://localhost:8084/connectors/mirror-source-connector/status | jq '.'

echo ""
echo "=== MirrorCheckpointConnector Status ==="
curl -s http://localhost:8084/connectors/mirror-checkpoint-connector/status | jq '.'

echo ""
echo "=== MirrorHeartbeatConnector Status ==="
curl -s http://localhost:8084/connectors/mirror-heartbeat-connector/status | jq '.'

echo ""
echo "=== Task Details for MirrorSourceConnector ==="
curl -s http://localhost:8084/connectors/mirror-source-connector/tasks | jq '.'