#!/bin/bash
# Adds the hub login (and, over TLS, the hub truststore) to the MirrorMaker
# config at container start, then runs the dedicated MirrorMaker 2 driver.
set -euo pipefail
umask 077
RUNTIME=/tmp/mm2-runtime.properties
PROTOCOL="${REMOTE_KAFKA_SECURITY_PROTOCOL:-SASL_PLAINTEXT}"
cp /etc/kafka-connect/mm2.properties "$RUNTIME"
{
  printf '\n# ---- added at container start (start-mm2.sh) ----\n'
  printf 'remote.security.protocol=%s\n' "$PROTOCOL"
  printf 'remote.sasl.mechanism=PLAIN\n'
  printf 'remote.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="%s" password="%s";\n' \
    "${REMOTE_KAFKA_USERNAME}" "${REMOTE_KAFKA_PASSWORD}"
  case "$PROTOCOL" in
    *SSL)
      printf 'remote.ssl.truststore.location=/etc/kafka-connect/secrets/kafka.truststore.p12\n'
      printf 'remote.ssl.truststore.type=PKCS12\n'
      printf 'remote.ssl.truststore.password=%s\n' "${REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}"
      ;;
  esac
} >> "$RUNTIME"
echo "start-mm2: launching connect-mirror-maker, hub link ${PROTOCOL} ($(grep -c . "$RUNTIME") config lines)"
exec connect-mirror-maker "$RUNTIME"
