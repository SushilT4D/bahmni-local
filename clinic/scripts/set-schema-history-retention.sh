#!/usr/bin/env bash
# the Debezium MySQL schema-history topic must never expire. A 7-day broker default
# emptied Ghated's on 2026-09-09 and the source could only come back in snapshot.mode=recovery.
# Run on every node after registering a MySQL source. Usage: scripts/set-schema-history-retention.sh <docker|podman> [bootstrap]
set -euo pipefail
T=${1:-docker}; BS=${2:-localhost:9092}
# KAFKA_CONTAINER: the container this exec's into -- "kafka" everywhere real
# (every clinic, the hub), overridden only by a test that must run this
# script for real beside another real stack already holding that bare name.
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
for t in $($T exec "$KAFKA_CONTAINER" kafka-topics --bootstrap-server "$BS" --list 2>/dev/null | grep -E '^schema-changes\.'); do
  $T exec "$KAFKA_CONTAINER" kafka-configs --bootstrap-server "$BS" --alter --entity-type topics --entity-name "$t" --add-config retention.ms=-1,retention.bytes=-1 >/dev/null
  echo "  $t: $($T exec "$KAFKA_CONTAINER" kafka-configs --bootstrap-server "$BS" --describe --entity-type topics --entity-name "$t" 2>/dev/null | grep -oE 'retention.ms=[-0-9]+' | head -1)"
done
