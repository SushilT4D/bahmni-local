#!/bin/bash
# Traces one clinic change on the hub: its Kafka topic, the table's up sink, and the row in MySQL.
# usage: trace-change.sh <table> <record_id> [topic]
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'


# ---- arguments ---------------------------------------------------------------

TABLE=$1
RECORD_ID=$2
TOPIC=$3

if [ -z "$TABLE" ] || [ -z "$RECORD_ID" ]; then
  echo "Usage: $0 <table_name> <record_id> [topic_name]"
  echo "Example: $0 person 99999"
  echo "         $0 person 99999 bahmni-local.openmrs.person"
  exit 1
fi

echo "============================================================"
echo "Tracing change for $TABLE.$RECORD_ID (REMOTE COMPONENTS)"
echo "============================================================"
echo ""


# ---- helpers -------------------------------------------------------------------

# prints a connector's state, coloured
check_status() {
  local name=$1
  local url=$2
  local status
  status=$(curl -s "$url" 2>/dev/null | jq -r '.connector.state // .state // empty' 2>/dev/null || echo "ERROR")

  if [ "$status" = "RUNNING" ]; then
    echo -e "${GREEN}✓${NC} $name: $status"
  elif [ "$status" = "ERROR" ] || [ -z "$status" ]; then
    echo -e "${RED}✗${NC} $name: ERROR or not accessible"
  else
    echo -e "${YELLOW}⚠${NC} $name: $status"
  fi
}


# ---- 1. the topic: the clinic's ordered OpenMRS topic when not given ------------

if [ -z "$TOPIC" ]; then
  TOPIC=$(docker exec kafka-remote kafka-topics --bootstrap-server localhost:29092 --list 2>/dev/null \
    | grep '\.openmrs\.all$' | head -1 || echo "")
fi

echo "1. Remote Kafka Topic"
if [ -n "$TOPIC" ]; then
  echo "   Topic: $TOPIC"
  REMOTE_EXISTS=$(docker exec kafka-remote kafka-topics --bootstrap-server localhost:29092 --list 2>/dev/null \
    | grep -F "$TOPIC" || echo "")

  if [ -n "$REMOTE_EXISTS" ]; then
    echo -e "${GREEN}✓${NC}   Topic exists"

    REMOTE_OFFSET=$(docker exec kafka-remote kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:29092 \
        --topic "$TOPIC" \
        --time -1 2>/dev/null \
      | awk -F: '{sum+=$3} END {print sum}' || echo "0")
    echo "   Total messages: $REMOTE_OFFSET"

    echo "   Checking for messages containing: $RECORD_ID"
    MSG_COUNT=$(docker exec kafka-remote kafka-console-consumer \
        --bootstrap-server localhost:29092 \
        --topic "$TOPIC" \
        --from-beginning \
        --max-messages 100 \
        --timeout-ms 5000 2>/dev/null \
      | grep -i "$RECORD_ID" | wc -l || echo "0")

    if [ "$MSG_COUNT" -gt 0 ]; then
      echo -e "${GREEN}✓${NC}   Found $MSG_COUNT message(s) containing $RECORD_ID"
    else
      echo -e "${YELLOW}⚠${NC}   No messages found containing $RECORD_ID"
    fi
  else
    echo -e "${RED}✗${NC}   Topic not found: $TOPIC"
  fi
else
  echo -e "${RED}✗${NC}   Could not determine topic name for table: $TABLE"
  echo "   Available topics:"
  docker exec kafka-remote kafka-topics --bootstrap-server localhost:29092 --list 2>/dev/null | head -5
fi
echo ""


# ---- 2. the up sink and its tasks (one OpenMRS sink per clinic, for every table) -

echo "2. JDBC Sink Connector"
SINK_CONNECTOR="${SINK_CONNECTOR:?set SINK_CONNECTOR to openmrs-<slug>-sink}"
CONNECTOR_EXISTS=$(curl -s http://localhost:8083/connectors 2>/dev/null \
  | jq -r ".[] | select(. == \"$SINK_CONNECTOR\")" 2>/dev/null || echo "")

if [ -n "$CONNECTOR_EXISTS" ]; then
  echo "   Connector: $SINK_CONNECTOR"
  check_status "  Status" "http://localhost:8083/connectors/$SINK_CONNECTOR/status"

  SINK_TASKS=$(curl -s "http://localhost:8083/connectors/$SINK_CONNECTOR/status" 2>/dev/null \
    | jq -r '.tasks[]?.state // empty' 2>/dev/null)
  for task in $SINK_TASKS; do
    if [ "$task" = "RUNNING" ]; then
      echo -e "${GREEN}✓${NC}   Task: $task"
    else
      echo -e "${RED}✗${NC}   Task: $task"
    fi
  done

  ERRORS=$(curl -s "http://localhost:8083/connectors/$SINK_CONNECTOR/status" 2>/dev/null \
    | jq -r '.tasks[]?.trace // empty' 2>/dev/null)
  if [ -n "$ERRORS" ] && [ "$ERRORS" != "null" ]; then
    echo -e "${RED}✗${NC}   Errors found:"
    echo "$ERRORS" | head -3
  fi
else
  echo -e "${RED}✗${NC}   Connector not found: $SINK_CONNECTOR"
  echo "   Available connectors:"
  curl -s http://localhost:8083/connectors 2>/dev/null | jq -r '.[]' 2>/dev/null | head -5
fi
echo ""


# ---- 3. the row in the hub's database -------------------------------------------

echo "3. Remote MySQL Database"
echo "   Checking if record exists..."
if command -v mysql &> /dev/null; then
  MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD:-} openmrs 2>/dev/null || mysql -u root openmrs 2>/dev/null"
  RECORD_EXISTS=$(echo "SELECT COUNT(*) FROM $TABLE WHERE ${TABLE}_id = $RECORD_ID;" \
    | eval "$MYSQL_CMD" 2>/dev/null | tail -1 || echo "0")

  if [ "$RECORD_EXISTS" = "1" ]; then
    echo -e "${GREEN}✓${NC}   Record found in remote database"
  elif [ "$RECORD_EXISTS" = "0" ]; then
    echo -e "${YELLOW}⚠${NC}   Record not found in remote database (may not have been applied yet)"
  else
    echo -e "${YELLOW}⚠${NC}   Could not check database (mysql client may not be available)"
  fi
else
  echo -e "${YELLOW}⚠${NC}   MySQL client not available - cannot check database"
  echo "   Manually check: mysql -u root -p openmrs -e \"SELECT * FROM $TABLE WHERE ${TABLE}_id = $RECORD_ID;\""
fi
echo ""


# ---- next steps ----------------------------------------------------------------

echo "============================================================"
echo "Remote trace complete"
echo "============================================================"
echo ""
echo "For detailed logs:"
echo "  - Sink connector: docker logs kafka-connect-remote -f | grep -i '$TABLE'"
echo ""
echo "To view recent messages from topic:"
if [ -n "$TOPIC" ]; then
  echo "  docker exec kafka-remote kafka-console-consumer --bootstrap-server localhost:29092 --topic $TOPIC --from-beginning --max-messages 10"
fi
echo ""
echo "To verify in remote database:"
echo "  mysql -u root -p openmrs -e \"SELECT * FROM $TABLE WHERE ${TABLE}_id = $RECORD_ID;\""
