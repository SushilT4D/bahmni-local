#!/usr/bin/env python3
"""
Send a Debezium-formatted change event directly to remote Kafka.
This bypasses local MySQL and tests: Remote Kafka → JDBC Sink → Remote MySQL

Usage:
    # With SASL authentication:
    python3 send-to-remote-kafka.py --bootstrap-servers kafka.example.com:9092 \
        --topic bahmni-local.openmrs.person --table person --record-id 99999 \
        --username mirrormaker --password secret

    # Without SASL (plaintext):
    python3 send-to-remote-kafka.py --bootstrap-servers kafka.example.com:9092 \
        --topic bahmni-local.openmrs.person --table person --record-id 99999
"""

import argparse
import json
import sys
import uuid
from datetime import datetime, timezone
from kafka import KafkaProducer
from kafka.errors import KafkaError


def generate_debezium_message(table, record_id, operation="create", server_name="bahmni-local"):
    """Generate a Debezium-formatted change event message."""
    timestamp_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    
    base_source = {
        "version": "3.2.4.Final",
        "connector": "mysql",
        "name": server_name,
        "ts_ms": timestamp_ms,
        "snapshot": "false",
        "db": "openmrs",
        "sequence": None,
        "table": table,
        "server_id": 0,
        "gtid": None,
        "file": "mysql-bin.000001",
        "pos": 1234,
        "row": 0,
        "thread": None,
        "query": None
    }
    
    if operation == "create":
        if table == "person":
            message = {
                "before": None,
                "after": {
                    "person_id": record_id,
                    "gender": "M",
                    "birthdate": "1990-01-01",
                    "birthdate_estimated": 0,
                    "dead": 0,
                    "death_date": None,
                    "cause_of_death": None,
                    "creator": 1,
                    "date_created": now_iso,
                    "changed_by": None,
                    "date_changed": None,
                    "voided": 0,
                    "voided_by": None,
                    "date_voided": None,
                    "void_reason": None,
                    "uuid": str(uuid.uuid4()),
                    "deathdate_estimated": 0,
                    "birthtime": None,
                    "cause_of_death_non_coded": None
                },
                "source": base_source,
                "op": "c",
                "ts_ms": timestamp_ms,
                "transaction": None
            }
        elif table == "patient":
            message = {
                "before": None,
                "after": {
                    "patient_id": record_id,
                    "patient_identifier": None,
                    "creator": 1,
                    "date_created": now_iso,
                    "changed_by": None,
                    "date_changed": None,
                    "voided": 0,
                    "voided_by": None,
                    "date_voided": None,
                    "void_reason": None,
                    "uuid": str(uuid.uuid4())
                },
                "source": base_source,
                "op": "c",
                "ts_ms": timestamp_ms,
                "transaction": None
            }
        elif table == "visit":
            message = {
                "before": None,
                "after": {
                    "visit_id": record_id,
                    "patient_id": 1,
                    "visit_type_id": 1,
                    "date_started": now_iso,
                    "date_stopped": None,
                    "indication_concept_id": None,
                    "location_id": None,
                    "creator": 1,
                    "date_created": now_iso,
                    "changed_by": None,
                    "date_changed": None,
                    "voided": 0,
                    "voided_by": None,
                    "date_voided": None,
                    "void_reason": None,
                    "uuid": str(uuid.uuid4())
                },
                "source": base_source,
                "op": "c",
                "ts_ms": timestamp_ms,
                "transaction": None
            }
        else:
            raise ValueError(f"Unknown table: {table}. Supported: person, patient, visit")
    
    elif operation == "update":
        if table == "person":
            message = {
                "before": {
                    "person_id": record_id,
                    "gender": "M"
                },
                "after": {
                    "person_id": record_id,
                    "gender": "F",
                    "date_changed": now_iso
                },
                "source": base_source,
                "op": "u",
                "ts_ms": timestamp_ms,
                "transaction": None
            }
        else:
            raise ValueError(f"Update not implemented for table: {table}")
    
    elif operation == "delete":
        message = {
            "before": {
                f"{table}_id": record_id
            },
            "after": None,
            "source": base_source,
            "op": "d",
            "ts_ms": timestamp_ms,
            "transaction": None
        }
    
    else:
        raise ValueError(f"Unknown operation: {operation}. Supported: create, update, delete")
    
    return message


def send_message(bootstrap_servers, topic, message, username=None, password=None):
    """Send message to Kafka with optional SASL authentication."""
    producer_config = {
        "bootstrap_servers": bootstrap_servers,
        "value_serializer": lambda v: json.dumps(v).encode('utf-8'),
        "request_timeout_ms": 10000,
    }
    
    # Add SASL configuration if credentials provided
    if username and password:
        producer_config.update({
            "security_protocol": "SASL_PLAINTEXT",
            "sasl_mechanism": "PLAIN",
            "sasl_plain_username": username,
            "sasl_plain_password": password,
        })
        print(f"Using SASL authentication (username: {username})")
    else:
        producer_config["security_protocol"] = "PLAINTEXT"
        print("Using PLAINTEXT (no authentication)")
    
    try:
        producer = KafkaProducer(**producer_config)
        future = producer.send(topic, message)
        record_metadata = future.get(timeout=10)
        producer.flush()
        producer.close()
        
        print(f"✓ Message sent successfully!")
        print(f"  Topic: {record_metadata.topic}")
        print(f"  Partition: {record_metadata.partition}")
        print(f"  Offset: {record_metadata.offset}")
        return True
        
    except KafkaError as e:
        print(f"✗ Error sending message: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"✗ Unexpected error: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Send Debezium-formatted change event to remote Kafka",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # With SASL authentication:
  %(prog)s --bootstrap-servers kafka.example.com:9092 \\
      --topic bahmni-local.openmrs.person --table person --record-id 99999 \\
      --username mirrormaker --password secret

  # Without SASL (plaintext):
  %(prog)s --bootstrap-servers kafka.example.com:9092 \\
      --topic bahmni-local.openmrs.person --table person --record-id 99999

  # Using environment variables:
  export REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example.com:9092
  export REMOTE_KAFKA_USERNAME=mirrormaker
  export REMOTE_KAFKA_PASSWORD=secret
  %(prog)s --table person --record-id 99999
        """
    )
    
    parser.add_argument(
        "--bootstrap-servers",
        default=None,
        help="Kafka bootstrap servers (e.g., kafka.example.com:9092). "
             "Can also use REMOTE_KAFKA_BOOTSTRAP_SERVERS env var."
    )
    parser.add_argument(
        "--topic",
        default=None,
        help="Kafka topic name (e.g., bahmni-local.openmrs.person). "
             "If not provided, will be generated from --table and --server-name."
    )
    parser.add_argument(
        "--table",
        required=True,
        choices=["person", "patient", "visit"],
        help="Table name"
    )
    parser.add_argument(
        "--record-id",
        type=int,
        required=True,
        help="Record ID to use in the message"
    )
    parser.add_argument(
        "--operation",
        choices=["create", "update", "delete"],
        default="create",
        help="Operation type (default: create)"
    )
    parser.add_argument(
        "--server-name",
        default="bahmni-local",
        help="Server name for Debezium source (default: bahmni-local)"
    )
    parser.add_argument(
        "--username",
        default=None,
        help="SASL username. Can also use REMOTE_KAFKA_USERNAME env var."
    )
    parser.add_argument(
        "--password",
        default=None,
        help="SASL password. Can also use REMOTE_KAFKA_PASSWORD env var."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate message but don't send it"
    )
    
    args = parser.parse_args()
    
    # Get bootstrap servers from args or env
    bootstrap_servers = args.bootstrap_servers
    if not bootstrap_servers:
        import os
        bootstrap_servers = os.getenv("REMOTE_KAFKA_BOOTSTRAP_SERVERS")
        if not bootstrap_servers:
            print("Error: --bootstrap-servers required or set REMOTE_KAFKA_BOOTSTRAP_SERVERS", file=sys.stderr)
            sys.exit(1)
    
    # Get topic from args or generate it
    topic = args.topic
    if not topic:
        topic = f"{args.server_name}.openmrs.{args.table}"
    
    # Get credentials from args or env
    import os
    username = args.username or os.getenv("REMOTE_KAFKA_USERNAME")
    password = args.password or os.getenv("REMOTE_KAFKA_PASSWORD")
    
    # Generate message
    print("=" * 60)
    print("Sending Debezium Event to Remote Kafka")
    print("=" * 60)
    print(f"Bootstrap Servers: {bootstrap_servers}")
    print(f"Topic: {topic}")
    print(f"Table: {args.table}")
    print(f"Record ID: {args.record_id}")
    print(f"Operation: {args.operation}")
    print(f"Server Name: {args.server_name}")
    print()
    
    try:
        message = generate_debezium_message(
            args.table,
            args.record_id,
            args.operation,
            args.server_name
        )
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    
    print("Generated message:")
    print(json.dumps(message, indent=2))
    print()
    
    if args.dry_run:
        print("(Dry run - message not sent)")
        return
    
    # Send message
    success = send_message(
        bootstrap_servers,
        topic,
        message,
        username,
        password
    )
    
    if success:
        print()
        print("Next steps:")
        print("1. Wait 5-10 seconds for JDBC sink to process")
        print()
        print("2. Check remote MySQL for the change:")
        if args.operation == "create":
            print(f"   mysql -h <remote-host> -u <user> -p <database> -e \"SELECT * FROM {args.table} WHERE {args.table}_id = {args.record_id};\"")
            print()
            print(f"   Expected: A NEW record with {args.table}_id = {args.record_id}")
            if args.table == "person":
                print("   - person_id =", args.record_id)
                print("   - gender = 'M'")
                print("   - birthdate = '1990-01-01'")
            elif args.table == "patient":
                print("   - patient_id =", args.record_id)
            elif args.table == "visit":
                print("   - visit_id =", args.record_id)
                print("   - patient_id = 1")
        elif args.operation == "update":
            print(f"   mysql -h <remote-host> -u <user> -p <database> -e \"SELECT * FROM {args.table} WHERE {args.table}_id = {args.record_id};\"")
            print()
            print(f"   Expected: Record {args.record_id} should be UPDATED")
            if args.table == "person":
                print("   - gender should be changed to 'F'")
                print("   - date_changed should be recent")
        elif args.operation == "delete":
            print(f"   mysql -h <remote-host> -u <user> -p <database> -e \"SELECT COUNT(*) FROM {args.table} WHERE {args.table}_id = {args.record_id};\"")
            print()
            print(f"   Expected: Record {args.record_id} should be DELETED (COUNT = 0)")
        print()
        print("3. If record not found, check sink connector status:")
        print(f"   # List all connectors:")
        print(f"   curl -s http://<remote-host>:8083/connectors | jq '.'")
        print(f"   # Check specific connector:")
        print(f"   curl -s http://<remote-host>:8083/connectors/mysql-sink-{args.table}/status | jq '.'")
        print(f"   # Or use helper script:")
        print(f"   ./scripts/check-sink-connectors.sh <remote-host> {args.table}")
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()

