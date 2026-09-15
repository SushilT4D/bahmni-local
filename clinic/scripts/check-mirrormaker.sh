#!/bin/bash

# Script to check connectivity to remote Kafka with SASL/SSL support
# This helps verify that MirrorMaker can reach the remote server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
# ENV_FILE="${PROJECT_DIR}/.env"
ENV_FILE=".env"

if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: .env file not found!"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi

# Source environment variables
set -a
source "${ENV_FILE}"
set +a

if [ -z "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" ]; then
    echo "Error: REMOTE_KAFKA_BOOTSTRAP_SERVERS not set in .env"
    exit 1
fi

echo "Testing connectivity to remote Kafka..."
echo "Remote Kafka: ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
echo "Security Protocol: ${REMOTE_KAFKA_SECURITY_PROTOCOL:-PLAINTEXT}"
echo ""

# Extract host and port
IFS=':' read -r REMOTE_HOST REMOTE_PORT <<< "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"

# Test basic connectivity
echo "1. Testing network connectivity..."
if [[ "${REMOTE_KAFKA_SECURITY_PROTOCOL}" == *"SSL"* ]]; then
    # TLS handshake only. Do not require CA verify — remote uses a private/self-signed cert
    # (MirrorMaker trusts it via kafka.truststore.p12). Close stdin so openssl exits
    # instead of waiting for interactive input. Avoid GNU timeout (missing on macOS).
    echo "   Testing SSL connectivity to ${REMOTE_HOST}:${REMOTE_PORT:-9092}..."
    # No -brief: macOS LibreSSL rejects it. stdin closed so s_client exits after handshake.
    # openssl often exits non-zero on private/self-signed certs even when TLS succeeded.
    SSL_OUT=$(openssl s_client -connect "${REMOTE_HOST}:${REMOTE_PORT:-9092}" \
        -servername "${REMOTE_HOST}" </dev/null 2>&1 || true)
    if echo "${SSL_OUT}" | grep -Eqi 'CONNECTED|CONNECTION ESTABLISHED|SSL handshake has read'; then
        if echo "${SSL_OUT}" | grep -Eqi 'Verify return code: 0 \(ok\)'; then
            echo "   ✓ Host ${REMOTE_HOST} is reachable (TLS + system CA verified)"
        else
            echo "   ✓ Host ${REMOTE_HOST} is reachable (TLS handshake OK; cert not in system trust store — expected)"
        fi
    elif nc -z -w 5 "${REMOTE_HOST}" "${REMOTE_PORT:-9092}" > /dev/null 2>&1; then
        echo "   ⚠ TCP to ${REMOTE_HOST}:${REMOTE_PORT:-9092} works, but TLS handshake failed"
        echo "   openssl says:"
        echo "${SSL_OUT}" | sed -n '1,8p' | sed 's/^/     /'
        echo "   Will verify with Kafka client"
    else
        echo "   ✗ Host ${REMOTE_HOST} is NOT reachable"
        echo "   MirrorMaker will buffer locally until connectivity is restored"
    fi
else
    # Test plain TCP connection
    if nc -z -w 5 "${REMOTE_HOST}" "${REMOTE_PORT:-9092}" > /dev/null 2>&1; then
        echo "   ✓ Host ${REMOTE_HOST} is reachable"
    else
        echo "   ✗ Host ${REMOTE_HOST} is NOT reachable"
        echo "   MirrorMaker will buffer locally until connectivity is restored"
    fi
fi

# Paths must be valid inside mirrormaker-connect (see docker-compose volume mount).
CONTAINER_TRUSTSTORE="/etc/kafka-connect/secrets/kafka.truststore.p12"

# Test from container if running
echo ""
echo "2. Testing from MirrorMaker container (if running)..."
MM_CONTAINER=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -E '^mirrormaker-connect$' | head -n1 || true)
if [ -z "${MM_CONTAINER}" ]; then
    # Fallback: any running container name containing mirrormaker
    MM_CONTAINER=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -i mirrormaker | head -n1 || true)
fi

if [ -n "${MM_CONTAINER}" ]; then
    echo "   Container: ${MM_CONTAINER}"
    echo "   Bootstrap: ${REMOTE_KAFKA_BOOTSTRAP_SERVERS}"
    echo "   Truststore: ${CONTAINER_TRUSTSTORE}"

    # Use credentials from the running container (what MirrorMaker actually has),
    # not whatever happens to be in the local shell/.env copy.
    CTR_USER=$(podman exec "${MM_CONTAINER}" printenv REMOTE_KAFKA_USERNAME 2>/dev/null || true)
    CTR_PASS_SET=$(podman exec "${MM_CONTAINER}" sh -c '[ -n "${REMOTE_KAFKA_PASSWORD:-}" ] && echo yes || echo no' 2>/dev/null || echo no)
    CTR_TSPASS_SET=$(podman exec "${MM_CONTAINER}" sh -c '[ -n "${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD:-}" ] && echo yes || echo no' 2>/dev/null || echo no)
    echo "   Container env: REMOTE_KAFKA_USERNAME=${CTR_USER:-<unset>} REMOTE_KAFKA_PASSWORD=${CTR_PASS_SET} REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD=${CTR_TSPASS_SET}"

    if ! podman exec "${MM_CONTAINER}" test -f "${CONTAINER_TRUSTSTORE}"; then
        echo "   ✗ Truststore missing inside container: ${CONTAINER_TRUSTSTORE}"
        echo "   Mount certs (setup-certs / compose volume) and retry."
        echo "   Host path comes from CONTAINER_DATA_PATH/certs/kafka/kafka.truststore.p12"
        echo "   CONTAINER_DATA_PATH=${CONTAINER_DATA_PATH:-unset}"
    elif [ "${CTR_TSPASS_SET}" != "yes" ]; then
        echo "   ✗ REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD is not set inside the container"
    elif [ "${CTR_PASS_SET}" != "yes" ] || [ -z "${CTR_USER}" ]; then
        echo "   ✗ REMOTE_KAFKA_USERNAME/PASSWORD not set inside the container"
    else
        # Explicit truststore password check. A wrong password fails here with
        # keytool "password was incorrect" — not as Kafka METADATA failure.
        set +e
        TS_OUT=$(podman exec "${MM_CONTAINER}" sh -c \
            "keytool -list -keystore '${CONTAINER_TRUSTSTORE}' -storetype PKCS12 \
             -storepass \"\${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}\"" 2>&1)
        TS_RC=$?
        set -e
        if [ "${TS_RC}" -ne 0 ]; then
            echo "   ✗ Truststore password invalid inside container"
            echo "   REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD does not open ${CONTAINER_TRUSTSTORE}"
            echo "   keytool output:"
            echo "${TS_OUT}" | sed 's/^/     /'
        else
            echo "   ✓ Truststore opens with container REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD"
            echo "${TS_OUT}" | grep -E 'Alias name|Certificate fingerprint|Your keystore contains' | sed 's/^/     /' || true

            # Build client config inside the container from its own env (no host secrets).
            SECURITY_PROTOCOL="${REMOTE_KAFKA_SECURITY_PROTOCOL:-SASL_SSL}"
            SASL_MECHANISM="${REMOTE_KAFKA_SASL_MECHANISM:-PLAIN}"
            podman exec "${MM_CONTAINER}" sh -c "cat > /tmp/kafka-client.properties <<EOF
security.protocol=${SECURITY_PROTOCOL}
sasl.mechanism=${SASL_MECHANISM}
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\${REMOTE_KAFKA_USERNAME}\" password=\"\${REMOTE_KAFKA_PASSWORD}\";
ssl.truststore.location=${CONTAINER_TRUSTSTORE}
ssl.truststore.password=\${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}
ssl.truststore.type=PKCS12
EOF"

            echo "   Client config:"
            podman exec "${MM_CONTAINER}" sh -c \
                "sed -E 's/(password=|username=\")[^;\"]+/\\1***/g' /tmp/kafka-client.properties" \
                | sed 's/^/     /'

            set +e
            KAFKA_OUT=$(podman exec "${MM_CONTAINER}" kafka-broker-api-versions \
                --bootstrap-server "${REMOTE_KAFKA_BOOTSTRAP_SERVERS}" \
                --command-config /tmp/kafka-client.properties 2>&1)
            KAFKA_RC=$?
            set -e

            if [ "${KAFKA_RC}" -eq 0 ]; then
                echo "   ✓ Remote Kafka is accessible from MirrorMaker container"
                echo "   Authentication successful!"
                podman exec "${MM_CONTAINER}" rm -f /tmp/kafka-client.properties
            else
                echo "   ✗ Remote Kafka probe failed (exit ${KAFKA_RC})"
                echo "   Exact kafka-broker-api-versions output:"
                if [ -n "${KAFKA_OUT}" ]; then
                    echo "${KAFKA_OUT}" | sed 's/^/     /'
                else
                    echo "     (no output captured)"
                fi
                echo ""
                if echo "${KAFKA_OUT}" | grep -Eqi 'unable to find valid certification path|PKIX|certificate_unknown|SunCertPathBuilderException'; then
                    echo "   Likely cause: truststore password is fine, but it does not trust the remote broker cert"
                elif echo "${KAFKA_OUT}" | grep -Eqi 'password was incorrect|keystore password|integrity check failed'; then
                    echo "   Likely cause: truststore password/type wrong (should have been caught by keytool check)"
                elif echo "${KAFKA_OUT}" | grep -Eqi 'Request METADATA failed'; then
                    echo "   Likely cause: TLS+JAAS setup loaded, but broker METADATA failed."
                    echo "   Truststore password is OK (keytool passed). Common next causes:"
                    echo "     - broker advertised.listeners host unreachable from this container"
                    echo "     - SASL user cannot authorize METADATA / cluster describe"
                    echo "     - listener/security-protocol mismatch after bootstrap"
                elif echo "${KAFKA_OUT}" | grep -Eqi 'Authentication failed|SASL.*fail|Access denied|not authorized'; then
                    echo "   Likely cause: SASL username/password rejected by broker"
                elif echo "${KAFKA_OUT}" | grep -Eqi 'UnknownHostException|Name or service not known'; then
                    echo "   Likely cause: DNS from inside the container cannot resolve ${REMOTE_HOST}"
                elif echo "${KAFKA_OUT}" | grep -Eqi 'Connection refused|Timed out|Timeout|Network is unreachable'; then
                    echo "   Likely cause: network path from container to ${REMOTE_KAFKA_BOOTSTRAP_SERVERS} blocked"
                fi
                echo "   Config left at ${MM_CONTAINER}:/tmp/kafka-client.properties for re-run"
            fi
        fi
    fi
else
    echo "   MirrorMaker container is not running"
    echo "   Start with: docker-compose --profile debezium up -d"
fi

echo ""
echo "Note: MirrorMaker is designed to handle intermittent connectivity."
echo "When offline, events are buffered in local Kafka and synced automatically when connectivity returns."

