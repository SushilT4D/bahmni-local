#!/bin/bash

# Script to install Confluent JDBC Sink Connector in Kafka Connect container
# This script should be run after starting the kafka-connect container

set -e

CONTAINER_NAME="${KAFKA_CONNECT_CONTAINER:-kafka-connect}"
JDBC_CONNECTOR_VERSION="${JDBC_CONNECTOR_VERSION:-10.7.7}"

echo "Installing Confluent JDBC Sink Connector (version ${JDBC_CONNECTOR_VERSION})..."

# Check if container is running
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
    echo "Error: Container ${CONTAINER_NAME} is not running!"
    echo "Please start it first: docker-compose up -d kafka-connect"
    exit 1
fi

# Install JDBC connector using confluent-hub
echo "Installing connector via confluent-hub..."
docker exec -it "${CONTAINER_NAME}" bash -c \
    "confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:${JDBC_CONNECTOR_VERSION}"

# Restart the container to load the new connector
echo "Restarting container to load connector..."
docker restart "${CONTAINER_NAME}"

# Wait for container to be healthy
echo "Waiting for container to be ready..."
sleep 10

# Verify connector is installed
echo "Verifying connector installation..."
docker exec "${CONTAINER_NAME}" bash -c \
    "ls -la /kafka/connect/confluentinc-kafka-connect-jdbc/lib/ | head -5" || {
    echo "Warning: Could not verify connector installation"
}

echo ""
echo "JDBC Connector installation complete!"
echo ""
echo "You can now register the sink connector using:"
echo "  ./scripts/register-sink-connector.sh"

