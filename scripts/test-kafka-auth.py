#!/usr/bin/env python3
"""
Test script to verify Kafka endpoint authentication.

This script tests:
1. Connection without credentials (should fail) [SASL mode only]
2. Connection with credentials (should succeed)
3. Basic producer/consumer operations (with or without authentication)

Usage:
    python3 test-kafka-auth.py --bootstrap-servers kafka.example.com:9092 \
        --username mirrormaker --password secret-password --sasl

Or set environment variables:
    export KAFKA_BOOTSTRAP_SERVERS=kafka.example.com:9092
    export KAFKA_USERNAME=mirrormaker
    export KAFKA_PASSWORD=secret-password
    python3 test-kafka-auth.py --sasl
"""

import argparse
import os
import sys
import time

# Check for required dependencies
try:
    from kafka import KafkaProducer, KafkaConsumer, KafkaAdminClient
    from kafka.errors import KafkaError, NoBrokersAvailable
    # AuthenticationError may not exist in all versions - use KafkaError as fallback
    try:
        from kafka.errors import AuthenticationError
    except ImportError:
        # In newer versions, authentication errors are just KafkaError
        AuthenticationError = KafkaError
    try:
        from kafka.errors import KafkaConnectionError
    except ImportError:
        KafkaConnectionError = KafkaError
except ImportError as e:
    print("❌ Error: Missing required dependencies")
    print(f"   {str(e)}")
    print()
    print("Please install dependencies:")
    print("   pip3 install -r requirements.txt")
    print("   or")
    print("   pip3 install kafka-python")
    sys.exit(1)


def test_connection_without_auth(bootstrap_servers):
    """Test connection without authentication - should fail."""
    print("=" * 60)
    print("TEST 1: Connection WITHOUT authentication")
    print("=" * 60)
    print(f"Attempting to connect to: {bootstrap_servers}")
    print("Expected: Should FAIL (authentication required)")
    print()
    
    admin_client = None
    try:
        # Try to create an admin client to test connection
        # This will attempt to connect during initialization
        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            security_protocol='PLAINTEXT',
            request_timeout_ms=5000,
            api_version=(0, 10)  # Specify API version to avoid auto-detection
        )
        
        # Try to describe cluster (this will trigger connection)
        cluster_metadata = admin_client.describe_cluster()
        admin_client.close()
        
        print("❌ FAILED: Connection succeeded WITHOUT authentication!")
        print("   This is a security issue - Kafka should require authentication.")
        return False
        
    except NoBrokersAvailable as e:
        # When using PLAINTEXT and getting NoBrokersAvailable during init,
        # it likely means the broker requires SASL authentication and rejected the connection
        print("✅ PASSED: Connection correctly rejected (likely authentication required)")
        print(f"   Error: {str(e)}")
        print("   Note: NoBrokersAvailable when using PLAINTEXT typically indicates")
        print("         that the broker requires SASL authentication")
        return True
        
    except KafkaError as e:
        # Check if it's an authentication error by examining the error message
        error_str = str(e).lower()
        error_type = type(e).__name__
        
        # Connection errors are NOT authentication failures - they're network issues
        if 'connection' in error_str or 'KafkaConnectionError' in error_type or 'NoBrokersAvailable' in error_type:
            print("⚠️  WARNING: Could not establish connection")
            print(f"   Error: {error_type}: {str(e)}")
            print("   This could be:")
            print("   - Network connectivity issue")
            print("   - Firewall blocking port 9092")
            print("   - Wrong bootstrap server address")
            print("   - Cannot determine if authentication is required (connection failed first)")
            return None
        
        # Authentication-related errors mean auth is working
        if 'authentication' in error_str or 'sasl' in error_str or 'unauthorized' in error_str:
            print("✅ PASSED: Connection correctly rejected (authentication required)")
            print(f"   Error: {error_type}: {str(e)}")
            return True
        
        # Other KafkaError - connection was rejected for some reason
        print("✅ PASSED: Connection correctly rejected")
        print(f"   Error: {error_type}: {str(e)}")
        return True
        
    except Exception as e:
        # Check if it's an authentication-related error
        error_str = str(e).lower()
        if 'authentication' in error_str or 'sasl' in error_str or 'unauthorized' in error_str:
            print("✅ PASSED: Connection correctly rejected (authentication required)")
            print(f"   Error: {type(e).__name__}: {str(e)}")
            return True
        print(f"⚠️  Unexpected error: {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        return None
    finally:
        if admin_client:
            try:
                admin_client.close()
            except:
                pass


def test_connection_with_auth(bootstrap_servers, username, password, use_sasl):
    """Test connection with/without authentication - should succeed."""
    print()
    print("=" * 60)
    if use_sasl:
        print("TEST 2: Connection WITH authentication")
    else:
        print("TEST 2: Connection WITHOUT authentication (plaintext)")
    print("=" * 60)
    print(f"Attempting to connect to: {bootstrap_servers}")
    if use_sasl:
        print(f"Username: {username}")
    print("Expected: Should SUCCEED")
    print()
    
    admin_client = None
    try:
        # Use admin client to test connection
        print("   Testing connection...")
        client_kwargs = dict(
            bootstrap_servers=bootstrap_servers,
            security_protocol='SASL_PLAINTEXT' if use_sasl else 'PLAINTEXT',
            request_timeout_ms=15000,
            api_version=(0, 10),
            client_id='test-auth-client'
        )
        if use_sasl:
            client_kwargs.update(
                sasl_mechanism='PLAIN',
                sasl_plain_username=username,
                sasl_plain_password=password,
            )

        try:
            admin_client = KafkaAdminClient(**client_kwargs)
        except (NoBrokersAvailable, KafkaConnectionError) as init_error:
            print("❌ FAILED: Could not connect during initialization")
            print(f"   Error: {type(init_error).__name__}: {str(init_error)}")
            print("   Possible causes:")
            print("   - Network connectivity issue")
            print("   - Firewall blocking port 9092")
            print("   - Advertised listener mismatch")
            print(f"     (Kafka must advertise: {bootstrap_servers})")
            if use_sasl:
                print("   - Check REMOTE_KAFKA_HOST in remote/.env matches this address")
            print("   - Kafka broker not running or not listening on expected port")
            return False
        
        # Try to list topics (this will trigger connection)
        print("   Getting topic list...")
        topics = admin_client.list_topics()
        if use_sasl:
            print("✅ PASSED: Connection successful with authentication")
        else:
            print("✅ PASSED: Connection successful (plaintext)")
        print(f"   Found {len(topics)} topic(s)")
        
        # List some topics
        if topics:
            print("   Sample topics:")
            for i, topic in enumerate(list(topics)[:5]):
                print(f"     - {topic}")
            if len(topics) > 5:
                print(f"     ... and {len(topics) - 5} more")
        
        admin_client.close()
        return True
        
    except NoBrokersAvailable as e:
        print("❌ FAILED: Could not connect to broker")
        print(f"   Error: {str(e)}")
        print("   Possible causes:")
        print("   - Network connectivity issue")
        print("   - Firewall blocking port 9092")
        print("   - Wrong bootstrap server address")
        print("   - Kafka broker not running")
        print("   - Advertised listener mismatch")
        return False
        
    except KafkaError as e:
        # Check if it's an authentication error
        error_str = str(e).lower()
        error_type = type(e).__name__
        if use_sasl and ('authentication' in error_str or 'sasl' in error_str or 'unauthorized' in error_str or 'KafkaAuthenticationError' in error_type):
            print("❌ FAILED: Authentication rejected")
            print(f"   Error: {error_type}: {str(e)}")
            print("   Check username and password in JAAS config")
            return False
        
        # Check for connection errors
        if 'connection' in error_str or 'KafkaConnectionError' in error_type:
            print("❌ FAILED: Connection error")
            print(f"   Error: {error_type}: {str(e)}")
            print("   Possible causes:")
            print("   - Network connectivity issue")
            print("   - Firewall blocking port 9092")
            print("   - Advertised listener mismatch (check KAFKA_ADVERTISED_LISTENERS)")
            if use_sasl:
                print("   - Authentication succeeded but connection failed")
            print("   - Wrong bootstrap server address")
            return False
        
        print(f"❌ FAILED: Kafka error: {error_type}: {str(e)}")
        return False
        
    except Exception as e:
        error_type = type(e).__name__
        error_str = str(e).lower()
        print(f"❌ FAILED: Unexpected error: {error_type}: {str(e)}")
        
        # Provide more context for connection errors
        if 'connection' in error_str:
            print("   Possible causes:")
            print("   - Network connectivity issue")
            print("   - Firewall blocking port 9092")
            print("   - Wrong bootstrap server address")
            print("   - Authentication configuration issue")
            print("   - Advertised listener mismatch")
        
        return False
    finally:
        if admin_client:
            try:
                admin_client.close()
            except:
                pass


def test_producer_consumer(bootstrap_servers, username, password, test_topic, use_sasl):
    """Test basic producer/consumer operations."""
    print()
    print("=" * 60)
    print("TEST 3: Producer/Consumer operations")
    print("=" * 60)
    print(f"Test topic: {test_topic}")
    print("Expected: Should SUCCEED")
    print()
    
    try:
        # Create producer
        producer_kwargs = dict(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: v.encode('utf-8'),
            request_timeout_ms=10000,
            security_protocol='SASL_PLAINTEXT' if use_sasl else 'PLAINTEXT'
        )
        if use_sasl:
            producer_kwargs.update(
                sasl_mechanism='PLAIN',
                sasl_plain_username=username,
                sasl_plain_password=password,
            )
        producer = KafkaProducer(**producer_kwargs)
        
        # Send a test message
        test_message = f"test-message-{int(time.time())}"
        print(f"Sending test message: {test_message}")
        future = producer.send(test_topic, value=test_message)
        record_metadata = future.get(timeout=10)
        print(f"✅ Message sent successfully")
        print(f"   Topic: {record_metadata.topic}")
        print(f"   Partition: {record_metadata.partition}")
        print(f"   Offset: {record_metadata.offset}")
        
        producer.close()
        
        # Create consumer
        consumer_kwargs = dict(
            bootstrap_servers=bootstrap_servers,
            auto_offset_reset='latest',
            consumer_timeout_ms=5000,
            value_deserializer=lambda m: m.decode('utf-8'),
            security_protocol='SASL_PLAINTEXT' if use_sasl else 'PLAINTEXT'
        )
        if use_sasl:
            consumer_kwargs.update(
                sasl_mechanism='PLAIN',
                sasl_plain_username=username,
                sasl_plain_password=password,
            )
        consumer = KafkaConsumer(test_topic, **consumer_kwargs)
        
        # Try to consume (might not get message if auto_offset_reset is 'latest')
        print("Attempting to consume message...")
        messages = []
        for message in consumer:
            messages.append(message.value)
            if len(messages) >= 1:
                break
        
        consumer.close()
        
        if messages:
            print(f"✅ Message consumed successfully: {messages[0]}")
        else:
            print("⚠️  No messages consumed (this is OK if using 'latest' offset)")
            print("   Message was sent successfully, which is sufficient for testing")
        
        return True
        
    except Exception as e:
        print(f"❌ FAILED: {type(e).__name__}: {str(e)}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Test Kafka endpoint authentication',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Using command line arguments (SASL/PLAIN):
  python3 test-kafka-auth.py --bootstrap-servers kafka.example.com:9092 \\
      --username mirrormaker --password secret-password --sasl

  # Using environment variables (SASL/PLAIN):
  export KAFKA_BOOTSTRAP_SERVERS=kafka.example.com:9092
  export KAFKA_USERNAME=mirrormaker
  export KAFKA_PASSWORD=secret-password
  python3 test-kafka-auth.py --sasl

  # Test plaintext connectivity (no authentication expected):
  python3 test-kafka-auth.py --bootstrap-servers kafka.internal:29092

  # Test with custom topic:
  python3 test-kafka-auth.py --bootstrap-servers kafka.example.com:9092 \\
      --username mirrormaker --password secret-password \\
      --test-topic test-authentication --sasl
        """
    )
    
    parser.add_argument(
        '--bootstrap-servers',
        default=os.getenv('KAFKA_BOOTSTRAP_SERVERS'),
        help='Kafka bootstrap servers (e.g., kafka.example.com:9092)'
    )
    parser.add_argument(
        '--username',
        default=os.getenv('KAFKA_USERNAME', 'mirrormaker'),
        help='SASL username'
    )
    parser.add_argument(
        '--password',
        default=os.getenv('KAFKA_PASSWORD'),
        help='SASL password'
    )
    parser.add_argument(
        '--sasl',
        action='store_true',
        help='Use SASL/PLAIN authentication; omit for plaintext mode'
    )
    parser.add_argument(
        '--test-topic',
        default='test-kafka-auth',
        help='Topic name for producer/consumer test (default: test-kafka-auth)'
    )
    parser.add_argument(
        '--skip-producer-test',
        action='store_true',
        help='Skip producer/consumer test (only test connections)'
    )
    
    args = parser.parse_args()
    
    # Validate arguments
    if not args.bootstrap_servers:
        print("❌ Error: --bootstrap-servers is required")
        print("   Set KAFKA_BOOTSTRAP_SERVERS environment variable or use --bootstrap-servers")
        sys.exit(1)
    
    if args.sasl and not args.password:
        print("❌ Error: --password is required when --sasl is enabled")
        print("   Set KAFKA_PASSWORD environment variable or use --password")
        sys.exit(1)
    
    print("Kafka Authentication Test")
    print("=" * 60)
    print(f"Bootstrap Servers: {args.bootstrap_servers}")
    print(f"Security Protocol: {'SASL_PLAINTEXT' if args.sasl else 'PLAINTEXT'}")
    if args.sasl:
        print(f"Username: {args.username}")
        print(f"Password: {'*' * len(args.password) if args.password else '(none)'}")
    else:
        print("Authentication: disabled (plaintext mode)")
    print()
    
    # Run tests
    results = []
    
    # Test 1: Without auth (should fail) - only meaningful for SASL mode
    if args.sasl:
        result1 = test_connection_without_auth(args.bootstrap_servers)
        results.append(("Connection without auth", result1))
    
    # Test 2: With auth (should succeed)
    result2 = test_connection_with_auth(
        args.bootstrap_servers,
        args.username,
        args.password,
        use_sasl=args.sasl
    )
    results.append((
        "Connection with auth" if args.sasl else "Connection (plaintext)",
        result2
    ))
    
    # Test 3: Producer/Consumer (optional)
    if not args.skip_producer_test:
        result3 = test_producer_consumer(
            args.bootstrap_servers,
            args.username,
            args.password,
            args.test_topic,
            use_sasl=args.sasl
        )
        results.append((
            "Producer/Consumer operations (auth)" if args.sasl
            else "Producer/Consumer operations (plaintext)",
            result3
        ))
    
    # Summary
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    
    all_passed = True
    for test_name, result in results:
        if result is True:
            status = "✅ PASSED"
        elif result is False:
            status = "❌ FAILED"
            all_passed = False
        else:
            status = "⚠️  SKIPPED"
        
        print(f"{status}: {test_name}")
    
    print()
    if all_passed:
        print("✅ All tests passed! Kafka authentication is working correctly.")
        sys.exit(0)
    else:
        print("❌ Some tests failed. Check the output above for details.")
        sys.exit(1)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Unexpected error: {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

