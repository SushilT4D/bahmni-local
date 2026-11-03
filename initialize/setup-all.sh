#!/bin/bash

# Complete setup script that runs all setup steps in order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "=========================================="
echo "Debezium MySQL Replication Setup"
echo "=========================================="
echo ""

# Check prerequisites
echo "Step 1: Checking prerequisites..."

if ! command -v podman &> /dev/null; then
    echo "Error: Podman is not installed!"
    exit 1
fi

if ! command -v podman-compose &> /dev/null ; then
    echo "Error: Podman Compose is not installed!"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Warning: jq is not installed. Some scripts may not work properly."
    echo "Install with: brew install jq (macOS)"
fi

echo "✓ Prerequisites check passed"
echo ""

# Check .env file
echo "Step 2: Checking configuration..."
if [ ! -f "${PROJECT_DIR}/.env" ]; then
    echo "Error: .env file not found!"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi
echo "✓ Configuration file found"
echo ""

# Creaet directories
mkdir -p ./certs/ca
mkdir -p ./certs/kafka
mkdir -p ./config/bahmni-app
mkdir -p ./config/odoo
mkdir -p ./data/bahmni-clinical-forms
mkdir -p ./data/bahmni-document-images
mkdir -p ./data/bahmni-patient-images
mkdir -p ./data/bahmni-uploaded-files
mkdir -p ./data/kafka
mkdir -p ./data/kafka-connect
mkdir -p ./data/mirrormaker
mkdir -p ./data/mysql
mkdir -p ./data/odoo
mkdir -p ./data/postgresql
mkdir -p ./data/zookeeper
mkdir -p ./files/odoo
mkdir -p ./files/postgresql
mkdir -p ./logs/zookeeper
chown -R 1000 ./certs .config .data .files .logs


# Generate connector configs
echo "Step 3: Generating connector configurations..."
"${SCRIPT_DIR}/setup-connectors.sh"
echo ""

# Start infrastructure
echo "Step 4: Starting Docker infrastructure..."
cd "${PROJECT_DIR}"
docker-compose up -d
echo ""

# Wait for services to be ready
echo "Step 5: Waiting for services to be ready..."
sleep 15

# Check if services are up
echo "Checking service health..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:8083/connectors > /dev/null 2>&1; then
        echo "✓ Kafka Connect is ready"
        break
    fi
    attempt=$((attempt + 1))
    echo "  Waiting for Kafka Connect... ($attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "Error: Kafka Connect did not become ready in time"
    echo "Check logs with: docker-compose logs kafka-connect"
    exit 1
fi
echo ""

# Install JDBC connector
echo "Step 6: Installing JDBC Sink Connector..."
"${SCRIPT_DIR}/install-jdbc-connector.sh"
echo ""

# Prompt for connector registration
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Review connector configurations in connectors/"
echo "2. Register source connector: ./scripts/register-source-connector.sh"
echo "3. Register sink connector: ./scripts/register-sink-connector.sh"
echo ""
echo "Monitor services:"
echo "  - Kafka UI: http://localhost:8080"
echo "  - Kafka Connect API: http://localhost:8083"
echo ""
read -p "Would you like to register connectors now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Registering source connector..."
    "${SCRIPT_DIR}/register-source-connector.sh"
    echo ""
    echo "Registering sink connector..."
    "${SCRIPT_DIR}/register-sink-connector.sh"
    echo ""
    echo "=========================================="
    echo "Replication is now active!"
    echo "=========================================="
fi

