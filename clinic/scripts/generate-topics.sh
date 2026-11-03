#!/bin/bash

# Helper script to generate Kafka topics list from database and table configuration
# This script reads .env and generates the KAFKA_TOPICS variable

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
ENV_FILE="${PROJECT_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found!"
    exit 1
fi

# Source environment variables
set -a
source "${ENV_FILE}"
set +a

SERVER_NAME="${MYSQL_SERVER_NAME:-local-mysql-server}"

echo "# Generated Kafka topics list"
echo "# Add this to your .env file as KAFKA_TOPICS"
echo ""

if [ -n "${TABLE_INCLUDE_LIST}" ]; then
    # If specific tables are listed, generate topics for those
    IFS=',' read -ra TABLES <<< "${TABLE_INCLUDE_LIST}"
    topics=()
    for table in "${TABLES[@]}"; do
        # Remove whitespace
        table=$(echo "$table" | xargs)
        # Replace dot with dot (database.table format)
        topic="${SERVER_NAME}.${table}"
        topics+=("$topic")
    done
    echo "KAFKA_TOPICS=$(IFS=','; echo "${topics[*]}")"
else
    # If only databases are listed, you'll need to specify tables manually
    echo "# Note: TABLE_INCLUDE_LIST is empty. Please specify tables or use:"
    echo "# KAFKA_TOPICS=${SERVER_NAME}.database.table1,${SERVER_NAME}.database.table2"
    echo ""
    echo "# Example for openmrs database:"
    echo "# KAFKA_TOPICS=${SERVER_NAME}.openmrs.patient,${SERVER_NAME}.openmrs.encounter,${SERVER_NAME}.openmrs.visit"
fi

