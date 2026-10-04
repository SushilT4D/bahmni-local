#!/usr/bin/env bash
# Kafka here is one KRaft node per stack. Nothing in the repo may still
# describe or start the older layouts: a ZooKeeper ensemble, a separate
# controller node, a schema registry, or a host-side client of a broker port
# that is no longer published.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${HERE}/../../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
gone(){ [ ! -e "$R/$1" ] && ok_ "removed: $1 ($2)" || bad "still present: $1 ($2)"; }
gone sync/local/docker-compose.yml "a ZooKeeper-era clinic stack"
gone clinic/monitoring "a host-side client of a broker port no longer published"
gone sync/check-schema-history.sh "a copy of clinic/scripts/check-schema-history.sh dialling the removed listener"
# kafka-8-notes.md records how the image upgrade went, including the services
# that existed then; it is history, not configuration
left="$(cd "$R" && git grep -il 'zookeeper' -- clinic hub sync cloud ':!sync/tests/kafka-8-notes.md' ':!clinic/install/tests/test_no_old_kafka.sh' 2>/dev/null)"
[ -z "$left" ] && ok_ "nothing names ZooKeeper" || bad "ZooKeeper still named in: $(printf '%s' "$left" | tr '\n' ' ')"
left="$(cd "$R" && git grep -l 'schema-registry' -- cloud 2>/dev/null)"
[ -z "$left" ] && ok_ "cloud/ names no schema registry" || bad "cloud/ still names schema-registry: $(printf '%s' "$left" | tr '\n' ' ')"
U="$(sed -n '/^  kafka-ui:/,/^  [a-z]/p' "$R/clinic/docker-compose.yml")"
printf '%s' "$U" | grep -q 'KAFKA_CLUSTERS_1_' && bad "clinic kafka-ui still points at a second, external cluster" || ok_ "clinic kafka-ui shows this clinic's cluster only"
exit $((fails > 0))
