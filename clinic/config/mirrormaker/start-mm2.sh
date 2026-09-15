#!/bin/bash
# Reconstructed (missing from repo): inject cloud SASL creds into MM2 config at
# container start, then run the dedicated MirrorMaker 2 driver.
set -euo pipefail
RUNTIME=/tmp/mm2-runtime.properties
cp /etc/kafka-connect/mm2.properties "$RUNTIME"
cat >> "$RUNTIME" <<EOP

# ---- injected at container start (start-mm2.sh) ----
remote.security.protocol=SASL_PLAINTEXT
remote.sasl.mechanism=PLAIN
remote.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${REMOTE_KAFKA_USERNAME}" password="${REMOTE_KAFKA_PASSWORD}";
EOP
echo "start-mm2: launching connect-mirror-maker ($(grep -c . "$RUNTIME") config lines)"
exec connect-mirror-maker "$RUNTIME"
