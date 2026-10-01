#!/usr/bin/env bash
# The clinic runs one Kafka node holding both roles: no separate controller
# service in any compose file or in the scripts that start, size or chown
# services by name; the controller listener is declared, never advertised.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
svc(){ awk -v s="  $1:" '$0==s{p=1;next} p&&/^  [a-z]/{p=0} p' "$C/docker-compose.yml"; }
K="$(svc kafka)"
has(){ printf '%s\n' "$K" | grep -qF -- "$1" && ok_ "kafka: $2" || bad "kafka: $2 (no '$1')"; }
has "KAFKA_PROCESS_ROLES: 'broker,controller'" "both roles"
has "KAFKA_NODE_ID: 1" "node id 1"
has "KAFKA_CONTROLLER_QUORUM_VOTERS: '1@kafka:9093'" "votes for itself"
has "CONTROLLER://0.0.0.0:9093" "declares the controller listener"
has 'KAFKA_HEAP_OPTS: ${KAFKA_NODE_HEAP_OPTS:--Xms256m -Xmx1g}' "one stated heap, 1 GiB"
printf '%s\n' "$K" | grep 'KAFKA_ADVERTISED_LISTENERS' | grep -q CONTROLLER && bad "kafka advertises the controller listener" || ok_ "controller listener not advertised"
printf '%s\n' "$K" | grep -qE '^\s+command:' && bad "kafka still carries a command: override" || ok_ "no command: override"
printf '%s\n' "$K" | grep -q 'kafka-controller' && bad "kafka still depends on kafka-controller" || ok_ "kafka depends on no controller"
for f in "$C"/docker-compose*.yml; do
  grep -qE '^  kafka-controller:' "$f" && bad "$(basename "$f") declares kafka-controller" || ok_ "$(basename "$f") declares no kafka-controller"
done
left="$(cd "$C" && git grep -l 'kafka-controller' -- . ':!install/tests/test_kafka_combined.sh' 2>/dev/null)"
[ -z "$left" ] && ok_ "no file under clinic/ names kafka-controller" || bad "still named in: $(printf '%s' "$left" | tr '\n' ' ')"
exit $((fails > 0))
