#!/bin/bash
# Check if schema history topic exists and can be accessed

CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"
SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
SCHEMA_TOPIC="schema-changes.${SERVER_NAME}"

echo "Checking schema history configuration..."
echo "Schema topic: ${SCHEMA_TOPIC}"
echo ""

# Check if Kafka Connect can reach Kafka
echo "1. Testing Kafka connectivity from Kafka Connect container..."
podman exec kafka-connect kafka-broker-api-versions --bootstrap-server kafka:29092 2>&1 | head -5
echo ""

# Check if schema history topic exists
echo "2. Checking if schema history topic exists..."
podman exec kafka kafka-topics --bootstrap-server localhost:9092 --list | grep -i "schema-changes" || echo "   Schema history topic not found"
echo ""

# Try to create the topic manually if it doesn't exist
echo "3. Creating schema history topic if it doesn't exist..."
podman exec kafka kafka-topics --bootstrap-server localhost:9092 \
    --create \
    --topic "${SCHEMA_TOPIC}" \
    --partitions 1 \
    --replication-factor 1 \
    --if-not-exists 2>&1
echo ""

# Check connector logs for detailed error
echo "4. Recent Kafka Connect logs (last 20 lines):"
podman logs kafka-connect --tail 20 2>&1 | grep -i -E "schema|history|error|exception" || echo "   No relevant errors found in recent logs"
echo ""

echo "If the topic creation failed, check:"
echo "  - Kafka is running: podman ps | grep kafka"
echo "  - Network connectivity: podman exec kafka-connect ping -c 1 kafka"
echo "  - Full logs: podman logs kafka-connect -f"

