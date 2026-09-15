#!/bin/bash
# End-to-end replication test
# Makes a change in local MySQL and verifies it reaches remote MySQL
# Usage: ./test-replication.sh [table_name] [test_id]
# Example: ./test-replication.sh person 99999

set -e

TABLE="${1}"
TEST_ID="${2}"
LOCAL_DB="${LOCAL_MYSQL_DATABASE:-openmrs}"
REMOTE_DB="${REMOTE_MYSQL_DATABASE:-openmrs}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo "End-to-End Replication Test"
echo "============================================================"
echo "Table: $TABLE"
echo "Test ID: $TEST_ID"
echo "Timestamp: $(date)"
echo ""

# Step 1: Insert test record in local MySQL
echo -e "${BLUE}Step 1: Inserting test record in LOCAL MySQL...${NC}"
case "$TABLE" in
    person)
        mysql -h "${LOCAL_MYSQL_HOST:-localhost}" \
              -P "${LOCAL_MYSQL_PORT:-3306}" \
              -u "${LOCAL_MYSQL_USER:-root}" \
              -p"${LOCAL_MYSQL_PASSWORD}" \
              "$LOCAL_DB" <<EOF
INSERT INTO person (person_id, gender, birthdate, creator, date_created, uuid)
VALUES ($TEST_ID, 'M', '1990-01-01', 1, NOW(), UUID())
ON DUPLICATE KEY UPDATE 
    gender = 'M',
    birthdate = '1990-01-01',
    date_changed = NOW();
SELECT * FROM person WHERE person_id = $TEST_ID;
EOF
        ;;
    patient)
        # First ensure person exists
        mysql -h "${LOCAL_MYSQL_HOST:-localhost}" \
              -P "${LOCAL_MYSQL_PORT:-3306}" \
              -u "${LOCAL_MYSQL_USER:-root}" \
              -p"${LOCAL_MYSQL_PASSWORD}" \
              "$LOCAL_DB" <<EOF
INSERT INTO person (person_id, gender, birthdate, creator, date_created, uuid)
VALUES ($TEST_ID, 'M', '1990-01-01', 1, NOW(), UUID())
ON DUPLICATE KEY UPDATE person_id = person_id;

INSERT INTO patient (patient_id, creator, date_created, voided, uuid)
VALUES ($TEST_ID, 1, NOW(), 0, UUID())
ON DUPLICATE KEY UPDATE 
    date_changed = NOW();
SELECT * FROM patient WHERE patient_id = $TEST_ID;
EOF
        ;;
    visit)
        mysql -h "${LOCAL_MYSQL_HOST:-localhost}" \
              -P "${LOCAL_MYSQL_PORT:-3306}" \
              -u "${LOCAL_MYSQL_USER:-root}" \
              -p"${LOCAL_MYSQL_PASSWORD}" \
              "$LOCAL_DB" <<EOF
INSERT INTO visit (visit_id, patient_id, visit_type_id, date_started, creator, date_created, uuid)
VALUES ($TEST_ID, 1, 1, NOW(), 1, NOW(), UUID())
ON DUPLICATE KEY UPDATE 
    date_started = NOW(),
    date_changed = NOW();
SELECT * FROM visit WHERE visit_id = $TEST_ID;
EOF
        ;;
    *)
        echo -e "${RED}Error: Unknown table $TABLE${NC}"
        echo "Supported tables: person, patient, visit"
        exit 1
        ;;
esac

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Test record inserted in local MySQL${NC}"
else
    echo -e "${RED}✗ Failed to insert test record${NC}"
    exit 1
fi
echo ""

# Step 2: Wait for replication
echo -e "${BLUE}Step 2: Waiting for replication (15 seconds)...${NC}"
for i in {15..1}; do
    echo -n "  $i... "
    sleep 1
done
echo ""
echo ""

# Step 3: Check remote MySQL
echo -e "${BLUE}Step 3: Checking REMOTE MySQL...${NC}"
REMOTE_HOST="${REMOTE_MYSQL_HOST}"
REMOTE_PORT="${REMOTE_MYSQL_PORT:-3306}"
REMOTE_USER="${REMOTE_MYSQL_USER:-root}"
REMOTE_PASS="${REMOTE_MYSQL_PASSWORD}"

if [ -z "$REMOTE_HOST" ]; then
    echo -e "${YELLOW}⚠ REMOTE_MYSQL_HOST not set - skipping remote check${NC}"
    echo "Set REMOTE_MYSQL_HOST, REMOTE_MYSQL_USER, REMOTE_MYSQL_PASSWORD to test remote"
else
    case "$TABLE" in
        person)
            REMOTE_RESULT=$(mysql -h "$REMOTE_HOST" \
                -P "$REMOTE_PORT" \
                -u "$REMOTE_USER" \
                -p"$REMOTE_PASS" \
                "$REMOTE_DB" \
                -N -e "SELECT COUNT(*) FROM person WHERE person_id = $TEST_ID" 2>/dev/null || echo "0")
            ;;
        patient)
            REMOTE_RESULT=$(mysql -h "$REMOTE_HOST" \
                -P "$REMOTE_PORT" \
                -u "$REMOTE_USER" \
                -p"$REMOTE_PASS" \
                "$REMOTE_DB" \
                -N -e "SELECT COUNT(*) FROM patient WHERE patient_id = $TEST_ID" 2>/dev/null || echo "0")
            ;;
        visit)
            REMOTE_RESULT=$(mysql -h "$REMOTE_HOST" \
                -P "$REMOTE_PORT" \
                -u "$REMOTE_USER" \
                -p"$REMOTE_PASS" \
                "$REMOTE_DB" \
                -N -e "SELECT COUNT(*) FROM visit WHERE visit_id = $TEST_ID" 2>/dev/null || echo "0")
            ;;
    esac
    
    if [ "$REMOTE_RESULT" = "1" ]; then
        echo -e "${GREEN}✓ SUCCESS: Record found in remote MySQL!${NC}"
        echo ""
        echo "Remote record details:"
        mysql -h "$REMOTE_HOST" \
            -P "$REMOTE_PORT" \
            -u "$REMOTE_USER" \
            -p"$REMOTE_PASS" \
            "$REMOTE_DB" \
            -e "SELECT * FROM $TABLE WHERE ${TABLE}_id = $TEST_ID\G" 2>/dev/null | head -20
    else
        echo -e "${RED}✗ FAILED: Record not found in remote MySQL${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "1. Check local Kafka topic: cd local && ./scripts/trace-change.sh $TABLE $TEST_ID"
        echo "2. Check remote Kafka topic: cd remote && ./scripts/trace-change.sh $TABLE $TEST_ID"
        echo "3. Check connector status:"
        echo "   - Local: curl -s http://localhost:8083/connectors/mysql-source-connector/status | jq '.'"
        echo "   - Remote: curl -s http://localhost:8083/connectors/mysql-sink-$TABLE/status | jq '.'"
    fi
fi

echo ""
echo "============================================================"
echo "Test complete"
echo "============================================================"

