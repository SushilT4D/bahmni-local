#!/usr/bin/env bash
# F-045: the Debezium MySQL schema-history topic must never expire. A 7-day broker default
# emptied Ghated's on 2026-09-09 and the source could only come back in snapshot.mode=recovery.
# Run on every node after registering a MySQL source. Usage: scripts/set-schema-history-retention.sh <docker|podman> [bootstrap]
set -euo pipefail
T=${1:-docker}; BS=${2:-localhost:9092}
for t in $($T exec kafka kafka-topics --bootstrap-server "$BS" --list 2>/dev/null | grep -E '^schema-changes\.'); do
  $T exec kafka kafka-configs --bootstrap-server "$BS" --alter --entity-type topics --entity-name "$t" --add-config retention.ms=-1,retention.bytes=-1 >/dev/null
  echo "  $t: $($T exec kafka kafka-configs --bootstrap-server "$BS" --describe --entity-type topics --entity-name "$t" 2>/dev/null | grep -oE 'retention.ms=[-0-9]+' | head -1)"
done
