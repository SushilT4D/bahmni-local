#!/bin/bash

echo "Deleting all MirrorMaker connectors..."

curl -X DELETE http://localhost:8084/connectors/mirror-source-connector
echo "Deleted mirror-source-connector"

curl -X DELETE http://localhost:8084/connectors/mirror-checkpoint-connector
echo "Deleted mirror-checkpoint-connector"

curl -X DELETE http://localhost:8084/connectors/mirror-heartbeat-connector
echo "Deleted mirror-heartbeat-connector"

echo ""
echo "All connectors deleted!"