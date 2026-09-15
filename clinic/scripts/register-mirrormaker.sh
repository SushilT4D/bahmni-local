#!/bin/bash

# Script to register MirrorMaker 2.0 connector
# This sets up replication from local Kafka to remote Kafka

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="."
CONNECT_URL="${MIRRORMAKER_CONNECT_URL:-http://localhost:8084}"
CONFIG_DIR="${PROJECT_DIR}/mirrormaker-config"
ENV_FILE="${PROJECT_DIR}/.env"

# Check if .env file exists
if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found!"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi

# Source environment variables
set -a
source "${ENV_FILE}"
set +a

echo "Registering MirrorMaker 2.0 connector..."

# Check if config file exists
if [ ! -f "${CONFIG_DIR}/mm2.properties" ]; then
    echo "Error: mm2.properties not found!"
    echo "Please run setup-mirrormaker.sh first to generate configuration."
    exit 1
fi

# MirrorMaker 2.0 uses MirrorSourceConnector
# We need to register it via REST API
CONNECTOR_CONFIG=$(cat <<EOF
{
  "name": "MirrorSourceConnector",
  "config": {
    "connector.class": "org.apache.kafka.connect.mirror.MirrorSourceConnector",
    "source.cluster.alias": "local",
    "target.cluster.alias": "remote",
    "source.cluster.bootstrap.servers": "kafka:29092",
    "target.cluster.bootstrap.servers": "\${REMOTE_KAFKA_BOOTSTRAP_SERVERS}",
    "topics": "\${KAFKA_TOPIC_PATTERNS:-.*}",
    "replication.policy.class": "org.apache.kafka.connect.mirror.DefaultReplicationPolicy",
    "replication.policy.separator": ".",
    "consumer.poll.timeout.ms": "1000",
    "refresh.topics.interval.seconds": "60",
    "refresh.groups.interval.seconds": "60",
    "sync.topic.configs.enabled": "true",
    "sync.topic.acls.enabled": "false",
    "emit.heartbeats.enabled": "true",
    "emit.heartbeats.interval.seconds": "10",
    "emit.checkpoints.enabled": "true",
    "emit.checkpoints.interval.seconds": "60"
  }
}
EOF
)

# Register the connector
response=$(curl -s -X POST "${CONNECT_URL}/connectors" \
    -H "Content-Type: application/json" \
    -d "${CONNECTOR_CONFIG}")

# Check if registration was successful
if echo "$response" | grep -q "error_code"; then
    echo "Error registering connector:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
    exit 1
else
    echo "MirrorMaker connector registered successfully!"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
fi

# Wait a moment for connector to initialize
sleep 3

# Check connector status
echo ""
echo "Checking connector status..."
curl -s "${CONNECT_URL}/connectors/MirrorSourceConnector/status" | jq '.' 2>/dev/null || \
    curl -s "${CONNECT_URL}/connectors/MirrorSourceConnector/status"

echo ""
echo "Note: MirrorMaker will buffer events locally when remote is unreachable"
echo "and automatically sync when connectivity is restored."

