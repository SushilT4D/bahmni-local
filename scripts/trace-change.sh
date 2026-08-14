#!/bin/bash
# Trace a database change through LOCAL components
# Usage: ./trace-change.sh <table_name> <record_id>
# Example: ./trace-change.sh person 99999
# Run this from the local/ directory

# Don't exit on error - we want to check all components
set +e

TABLE=$1
RECORD_ID=$2

if [ -z "$TABLE" ] || [ -z "$RECORD_ID" ]; then
    echo "Usage: $0 <table_name> <record_id>"
    echo "Example: $0 person 99999"
    exit 1
fi

echo "============================================================"
echo "Tracing change for $TABLE.$RECORD_ID (LOCAL COMPONENTS)"
echo "============================================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Podman containers are running
check_container() {
    local container=$1
    if podman ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Check if service is accessible
check_service() {
    local url=$1
    local name=$2
    if curl -s --connect-timeout 2 "$url" > /dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}✗${NC}   $name service not accessible at $url"
        echo "   Is the service running? Check: podman-compose ps"
        return 1
    fi
}

check_status() {
    local name=$1
    local url=$2
    local status=$(curl -s "$url" 2>/dev/null | jq -r '.connector.state // .state // empty' 2>/dev/null || echo "ERROR")
    if [ "$status" = "RUNNING" ]; then
        echo -e "${GREEN}✓${NC} $name: $status"
    elif [ "$status" = "ERROR" ] || [ -z "$status" ]; then
        echo -e "${RED}✗${NC} $name: ERROR or not accessible"
    else
        echo -e "${YELLOW}⚠${NC} $name: $status"
    fi
}

echo "1. Debezium Source Connector"
# Check if Kafka Connect container is running
if ! check_container "kafka-connect"; then
    echo -e "${RED}✗${NC}   Kafka Connect container not running"
    echo "   Start it with: podman-compose up -d kafka-connect"
    echo ""
else
    # Check if service is accessible
    if check_service "http://localhost:8083/connectors" "Kafka Connect"; then
        check_status "  Connector" "http://localhost:8083/connectors/mysql-source-connector/status"
        TASKS=$(curl -s http://localhost:8083/connectors/mysql-source-connector/status 2>/dev/null | jq -r '.tasks[]?.state // empty' 2>/dev/null)
        if [ -n "$TASKS" ]; then
            for task in $TASKS; do
                if [ "$task" = "RUNNING" ]; then
                    echo -e "${GREEN}✓${NC}   Task: $task"
                else
                    echo -e "${RED}✗${NC}   Task: $task"
                fi
            done
        fi
    fi
fi
echo ""

echo "2. Local Kafka Topic"
# Check if Kafka container is running
if ! check_container "kafka"; then
    echo -e "${RED}✗${NC}   Kafka container not running"
    echo "   Start it with: podman-compose up -d kafka"
    echo ""
else
    TOPIC=$(podman exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -i "$TABLE" | head -1 || echo "")
    if [ -n "$TOPIC" ]; then
        echo -e "${GREEN}✓${NC}   Topic found: $TOPIC"
        OFFSET=$(podman exec kafka kafka-run-class kafka.tools.GetOffsetShell \
          --broker-list localhost:9092 \
          --topic "$TOPIC" \
          --time -1 2>/dev/null | awk -F: '{sum+=$3} END {print sum}' || echo "0")
        echo "   Total messages: $OFFSET"
        
        # Check for recent messages
        echo "   Checking for messages containing: $RECORD_ID"
        MSG_COUNT=$(podman exec kafka kafka-console-consumer \
          --bootstrap-server localhost:9092 \
          --topic "$TOPIC" \
          --from-beginning \
          --max-messages 100 \
          --timeout-ms 5000 2>/dev/null | grep -i "$RECORD_ID" | wc -l || echo "0")
        if [ "$MSG_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓${NC}   Found $MSG_COUNT message(s) containing $RECORD_ID"
        else
            echo -e "${YELLOW}⚠${NC}   No messages found containing $RECORD_ID"
        fi
    else
        echo -e "${RED}✗${NC}   Topic not found for table: $TABLE"
        echo "   Available topics:"
        podman exec kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | head -5 || echo "   (Could not list topics)"
    fi
fi
echo ""

echo "3. MirrorMaker Connector"
# Check if MirrorMaker container is running
if ! check_container "mirrormaker-connect"; then
    echo -e "${RED}✗${NC}   MirrorMaker Connect container not running"
    echo "   Start it with: podman-compose up -d mirrormaker-connect"
    echo ""
else
    # Check if service is accessible
    if check_service "http://localhost:8084/connectors" "MirrorMaker Connect"; then
        MM_CONNECTOR=$(curl -s http://localhost:8084/connectors 2>/dev/null | jq -r '.[0]' 2>/dev/null || echo "")
        if [ -n "$MM_CONNECTOR" ] && [ "$MM_CONNECTOR" != "null" ]; then
            echo "   Connector: $MM_CONNECTOR"
            check_status "  Status" "http://localhost:8084/connectors/$MM_CONNECTOR/status"
            MM_TASKS=$(curl -s http://localhost:8084/connectors/$MM_CONNECTOR/status 2>/dev/null | jq -r '.tasks[]?.state // empty' 2>/dev/null)
            if [ -n "$MM_TASKS" ]; then
                for task in $MM_TASKS; do
                    if [ "$task" = "RUNNING" ]; then
                        echo -e "${GREEN}✓${NC}   Task: $task"
                    else
                        echo -e "${RED}✗${NC}   Task: $task"
                    fi
                done
            fi
        else
            echo -e "${RED}✗${NC}   No MirrorMaker connectors found"
            echo "   Register MirrorMaker connector with: ./scripts/register-mirrormaker.sh"
        fi
    fi
fi
echo ""

echo "============================================================"
echo "Local trace complete"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Check if messages reached remote Kafka (run remote/trace-change.sh)"
echo "  2. Check Debezium logs: podman logs kafka-connect -f | grep -i '$TABLE'"
echo "  3. Check MirrorMaker logs: podman logs mirrormaker-connect -f | grep -i '$TABLE'"
echo ""
echo "To view recent messages from topic:"
if [ -n "$TOPIC" ]; then
    echo "  podman exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic $TOPIC --from-beginning --max-messages 10"
fi

