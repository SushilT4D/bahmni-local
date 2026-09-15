#!/bin/bash
# Send a Debezium-formatted change event directly to remote Kafka
# This bypasses local MySQL and tests: Remote Kafka → JDBC Sink → Remote MySQL
# Usage: ./send-to-remote-kafka.sh <table_name> <record_id> [operation]
# Example: ./send-to-remote-kafka.sh person 99999 create
#          ./send-to-remote-kafka.sh person 99999 update

set -e

TABLE="${1:-person}"
RECORD_ID="${2:-$(date +%s)}"
OP="${3:-create}"  # create, update, or delete
SERVER_NAME="${MYSQL_SERVER_NAME:-bahmni-local}"
TOPIC="${SERVER_NAME}.openmrs.${TABLE}"
REMOTE_KAFKA="${REMOTE_KAFKA_BOOTSTRAP_SERVERS:-bhs-tech4dev.bahmni.in:9092}"
REMOTE_USER="${REMOTE_KAFKA_USERNAME:-mirrormaker}"
REMOTE_PASS="${REMOTE_KAFKA_PASSWORD}"

if [ -z "$REMOTE_PASS" ]; then
    echo "Error: REMOTE_KAFKA_PASSWORD not set"
    echo "Usage: REMOTE_KAFKA_PASSWORD=password $0 <table> <id> [op]"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo "Sending event directly to Remote Kafka"
echo "============================================================"
echo "Topic: $TOPIC"
echo "Table: $TABLE"
echo "Record ID: $RECORD_ID"
echo "Operation: $OP"
echo "Remote Kafka: $REMOTE_KAFKA"
echo ""

# Generate Debezium-formatted message based on table and operation
generate_message() {
    local table=$1
    local id=$2
    local op=$3
    local timestamp_ms=$(($(date +%s) * 1000))
    
    case "$op" in
        create)
            case "$table" in
                person)
                    cat <<EOF
{
  "before": null,
  "after": {
    "person_id": $id,
    "gender": "M",
    "birthdate": "1990-01-01",
    "birthdate_estimated": 0,
    "dead": 0,
    "death_date": null,
    "cause_of_death": null,
    "creator": 1,
    "date_created": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "changed_by": null,
    "date_changed": null,
    "voided": 0,
    "voided_by": null,
    "date_voided": null,
    "void_reason": null,
    "uuid": "$(uuidgen)",
    "deathdate_estimated": 0,
    "birthtime": null,
    "cause_of_death_non_coded": null
  },
  "source": {
    "version": "3.2.4.Final",
    "connector": "mysql",
    "name": "$SERVER_NAME",
    "ts_ms": $timestamp_ms,
    "snapshot": "false",
    "db": "openmrs",
    "sequence": null,
    "table": "$table",
    "server_id": 0,
    "gtid": null,
    "file": "mysql-bin.000001",
    "pos": 1234,
    "row": 0,
    "thread": null,
    "query": null
  },
  "op": "c",
  "ts_ms": $timestamp_ms,
  "transaction": null
}
EOF
                    ;;
                patient)
                    cat <<EOF
{
  "before": null,
  "after": {
    "patient_id": $id,
    "patient_identifier": null,
    "creator": 1,
    "date_created": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "changed_by": null,
    "date_changed": null,
    "voided": 0,
    "voided_by": null,
    "date_voided": null,
    "void_reason": null,
    "uuid": "$(uuidgen)"
  },
  "source": {
    "version": "3.2.4.Final",
    "connector": "mysql",
    "name": "$SERVER_NAME",
    "ts_ms": $timestamp_ms,
    "snapshot": "false",
    "db": "openmrs",
    "sequence": null,
    "table": "$table",
    "server_id": 0,
    "gtid": null,
    "file": "mysql-bin.000001",
    "pos": 1234,
    "row": 0,
    "thread": null,
    "query": null
  },
  "op": "c",
  "ts_ms": $timestamp_ms,
  "transaction": null
}
EOF
                    ;;
                visit)
                    cat <<EOF
{
  "before": null,
  "after": {
    "visit_id": $id,
    "patient_id": 1,
    "visit_type_id": 1,
    "date_started": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "date_stopped": null,
    "indication_concept_id": null,
    "location_id": null,
    "creator": 1,
    "date_created": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")",
    "changed_by": null,
    "date_changed": null,
    "voided": 0,
    "voided_by": null,
    "date_voided": null,
    "void_reason": null,
    "uuid": "$(uuidgen)"
  },
  "source": {
    "version": "3.2.4.Final",
    "connector": "mysql",
    "name": "$SERVER_NAME",
    "ts_ms": $timestamp_ms,
    "snapshot": "false",
    "db": "openmrs",
    "sequence": null,
    "table": "$table",
    "server_id": 0,
    "gtid": null,
    "file": "mysql-bin.000001",
    "pos": 1234,
    "row": 0,
    "thread": null,
    "query": null
  },
  "op": "c",
  "ts_ms": $timestamp_ms,
  "transaction": null
}
EOF
                    ;;
                *)
                    echo "Error: Unknown table $table" >&2
                    exit 1
                    ;;
            esac
            ;;
        update)
            case "$table" in
                person)
                    cat <<EOF
{
  "before": {
    "person_id": $id,
    "gender": "M"
  },
  "after": {
    "person_id": $id,
    "gender": "F",
    "date_changed": "$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
  },
  "source": {
    "version": "3.2.4.Final",
    "connector": "mysql",
    "name": "$SERVER_NAME",
    "ts_ms": $timestamp_ms,
    "snapshot": "false",
    "db": "openmrs",
    "sequence": null,
    "table": "$table",
    "server_id": 0,
    "gtid": null,
    "file": "mysql-bin.000001",
    "pos": 1234,
    "row": 0,
    "thread": null,
    "query": null
  },
  "op": "u",
  "ts_ms": $timestamp_ms,
  "transaction": null
}
EOF
                    ;;
                *)
                    echo "Error: Update not implemented for $table" >&2
                    exit 1
                    ;;
            esac
            ;;
        delete)
            cat <<EOF
{
  "before": {
    "${table}_id": $id
  },
  "after": null,
  "source": {
    "version": "3.2.4.Final",
    "connector": "mysql",
    "name": "$SERVER_NAME",
    "ts_ms": $timestamp_ms,
    "snapshot": "false",
    "db": "openmrs",
    "sequence": null,
    "table": "$table",
    "server_id": 0,
    "gtid": null,
    "file": "mysql-bin.000001",
    "pos": 1234,
    "row": 0,
    "thread": null,
    "query": null
  },
  "op": "d",
  "ts_ms": $timestamp_ms,
  "transaction": null
}
EOF
            ;;
        *)
            echo "Error: Unknown operation $op (use: create, update, delete)" >&2
            exit 1
            ;;
    esac
}

# Generate the message
MESSAGE=$(generate_message "$TABLE" "$RECORD_ID" "$OP")

echo -e "${BLUE}Sending message to remote Kafka...${NC}"
echo "Message preview:"
echo "$MESSAGE" | jq '.' | head -10
echo ""

# Check if kafka-console-producer is available locally
if command -v kafka-console-producer &> /dev/null; then
    echo "$MESSAGE" | kafka-console-producer \
        --bootstrap-server "$REMOTE_KAFKA" \
        --topic "$TOPIC" \
        --producer-property security.protocol=SASL_PLAINTEXT \
        --producer-property sasl.mechanism=PLAIN \
        --producer-property "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$REMOTE_USER\" password=\"$REMOTE_PASS\";"
elif command -v docker &> /dev/null; then
    echo "$MESSAGE" | docker run -i --rm confluentinc/cp-kafka:7.6.0 kafka-console-producer \
        --bootstrap-server "$REMOTE_KAFKA" \
        --topic "$TOPIC" \
        --producer-property security.protocol=SASL_PLAINTEXT \
        --producer-property sasl.mechanism=PLAIN \
        --producer-property "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$REMOTE_USER\" password=\"$REMOTE_PASS\";"
elif command -v podman &> /dev/null; then
    echo "$MESSAGE" | podman run -i --rm docker.io/confluentinc/cp-kafka:7.6.0 kafka-console-producer \
        --bootstrap-server "$REMOTE_KAFKA" \
        --topic "$TOPIC" \
        --producer-property security.protocol=SASL_PLAINTEXT \
        --producer-property sasl.mechanism=PLAIN \
        --producer-property "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"$REMOTE_USER\" password=\"$REMOTE_PASS\";"
else
    echo "Error: Need kafka-console-producer, docker, or podman" >&2
    echo ""
    echo "Alternative: Use Python script"
    echo "python3 scripts/send-kafka-message.py --topic $TOPIC --message '$MESSAGE'"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Message sent successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Wait 5-10 seconds for JDBC sink to process"
    echo "2. Check remote MySQL:"
    echo "   mysql -h $REMOTE_MYSQL_HOST -u $REMOTE_MYSQL_USER -p openmrs -e \"SELECT * FROM $TABLE WHERE ${TABLE}_id = $RECORD_ID;\""
    echo "3. Check sink connector status:"
    echo "   curl -s http://$REMOTE_KAFKA_HOST:8083/connectors/mysql-sink-$TABLE/status | jq '.'"
else
    echo ""
    echo "Error: Failed to send message"
    exit 1
fi

