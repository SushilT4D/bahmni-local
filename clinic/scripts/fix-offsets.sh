# Step 1: Find Your Connector Name

  # List all connectors
  curl -s http://localhost:8083/connectors | jq .

  # Or check your connector config files
  ls /Users/sunshine/Documents/Develop/bahmni/bahmni-local/connectors/

# Step 2: Stop the Connector

  # Replace <connector-name> with your actual connector name
  curl -X PUT http://localhost:8083/connectors/<connector-name>/pause

# Step 3: Check Offset Storage

# Debezium stores offsets in Kafka topic (default: connect-offsets). Check what's there:

  # Access Kafka container
  podman exec -it <kafka-container-name> bash

  # List offset topic contents
  kafka-console-consumer --bootstrap-server localhost:9092 \
    --topic connect-offsets \
    --from-beginning \
    --property print.key=true \
    | grep <connector-name>

# Step 4: Reset the Offset

# Option A: Delete via Kafka Connect API (if your version supports it)
  # Some Kafka Connect versions support DELETE
  curl -X DELETE http://localhost:8083/connectors/<connector-name>/offsets

# Option B: Delete Connector & Recreate (simpler)
  # Delete connector (removes offset tracking)
  curl -X DELETE http://localhost:8083/connectors/<connector-name>

  # Wait a few seconds, then recreate
# curl -X POST -H "Content-Type: application/json" \
    --data @connectors/<your-connector-config>.json \
    http://localhost:8083/connectors

# Option C: Manual Kafka Topic Deletion (advanced)
  # Delete offset entries for this connector from Kafka
  kafka-delete-records --bootstrap-server localhost:9092 \
    --offset-json-file <offset-delete-spec.json>

# Step 5: Configure Fresh Start

  When recreating, add to your connector config:

  {
    "name": "your-connector-name",
    "config": {
      ...
      "snapshot.mode": "when_needed",
      "database.history.skip.unparseable.ddl": true
    }
  }

  Step 6: Resume

  # Resume the connector
  curl -X PUT http://localhost:8083/connectors/<connector-name>/resume

  # Check status
  curl -s http://localhost:8083/connectors/<connector-name>/status | jq .

  Simplest Approach

  Just delete and recreate the connector:

  # Check current connectors
  curl -s http://localhost:8083/connectors

  # Delete
  curl -X DELETE http://localhost:8083/connectors/bahmni-connector  # use your actual name

  # Recreate using your deployment script
  cd /Users/sunshine/Documents/Develop/bahmni/bahmni-local
  ./deploy-connectors.sh

  Which connector are you using? Want me to help find the name and connector config?

> mysql connector 

⏺ Let me help you reset the MySQL Debezium connector:

⏺ Bash(curl -s http://localhost:8083/connectors 2>/dev/null || echo "Kafka Connect not accessible on localhost:8083")
  ⎿  [                         
       "mysql-source-connector"
     ]

⏺ Bash(ls /Users/sunshine/Documents/Develop/bahmni/bahmni-local/connectors/ 2>/dev/null | head -10)
  ⎿  mirrormaker.json                     
     mysql-local-sink-connector-users.json
     mysql-local-source-connector.json

⏺ Bash(podman ps --filter "name=connect" --format "{{.Names}}")
  ⎿  kafka-connect      
     mirrormaker-connect

⏺ Perfect! Found your MySQL connector. Here's how to reset it:

  Reset MySQL Source Connector

⏺ Bash(curl -s http://localhost:8083/connectors/mysql-source-connector/status | jq .)
  ⎿  {                                  
       "name": "mysql-source-connector",
       "connector": {
     … +26 lines (ctrl+o to expand)

⏺ Bash(curl -X DELETE http://localhost:8083/connectors/mysql-source-connector)
  ⎿  Running…

⏺ Bash(sleep 3 && curl -X POST -H "Content-Type: application/json" --data
      @/Users/sunshine/Documents/Develop/bahmni/bahmni-local/connectors/mysql-local-source-connecto…)
  ⎿  Waiting…

⏺ Bash(sleep 2 && curl -s http://localhost:8083/connectors/mysql-source-connector/status | jq .)
  ⎿  Waiting…
