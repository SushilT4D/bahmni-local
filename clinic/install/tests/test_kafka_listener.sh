#!/usr/bin/env bash
# Everything that talks to the clinic's Kafka runs on the Docker network and
# dials kafka:29092; the broker publishes no host port at all.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
blk(){ awk '$0=="  kafka:"{p=1;next} p&&/^  [a-z]/{p=0} p' "$1"; }
K="$(blk "$C/docker-compose.yml")"
printf '%s\n' "$K" | grep -q 'PLAINTEXT_HOST' && bad "kafka still declares PLAINTEXT_HOST" || ok_ "one client listener (PLAINTEXT on 29092)"
printf '%s\n' "$K" | grep -qE '^    ports:' && bad "kafka still publishes a host port" || ok_ "kafka publishes no host port"
left="$(cd "$C" && git grep -n 'localhost:9092' -- . ':!install/tests/test_kafka_listener.sh' ':!monitoring' 2>/dev/null)"
[ -z "$left" ] && ok_ "no localhost:9092 left" || bad "still dialling localhost:9092: $(printf '%s' "$left" | cut -d: -f1-2 | tr '\n' ' ')"
exit $((fails > 0))
