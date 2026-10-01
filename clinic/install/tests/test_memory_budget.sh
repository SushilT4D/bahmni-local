#!/usr/bin/env bash
# The whole clinic stack fits a 10 GiB container VM (a 16 GiB Mac mini): every
# JVM in the sync layer runs on a stated heap, the two admin tools are not
# started by default, and the podman machine has swap so a spike slows the
# node instead of killing a database.
# Kafka is one node holding both roles: its 1 GiB is the old controller's
# 256 MB plus the broker's 768 MB, in one JVM.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Y="${HERE}/../../docker-compose.yml"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
svc(){ awk -v s="  $1:" '$0==s{p=1;next} p&&/^  [a-z]/{p=0} p' "$Y"; }
has(){ svc "$1" | grep -q -- "$2" && ok_ "$1: $3" || bad "$1: $3 (no '$2')"; }
has kafka            'KAFKA_HEAP_OPTS: ${KAFKA_NODE_HEAP_OPTS:--Xms256m -Xmx1g}' "one node, both roles, heap up to 1 GiB"
has schema-registry  'SCHEMA_REGISTRY_HEAP_OPTS: ${SCHEMA_REGISTRY_HEAP_OPTS:--Xmx256m}' "heap 256 MB"
has kafka-connect    'HEAP_OPTS: ${CONNECT_HEAP_OPTS:--Xms256m -Xmx768m}' "heap up to 768 MB"
has mirrormaker-connect 'KAFKA_HEAP_OPTS: ${MM2_HEAP_OPTS:--Xms256m -Xmx768m}' "heap up to 768 MB"
svc atomfeed-console | grep -qE 'profiles:.*"local"' && bad "atomfeed-console still starts with the local profile" || ok_ "atomfeed-console only on request"
T90="${HERE}/../tasks/090-local-sync.sh"
grep -q 'CLINIC_KAFKA_UI' "$T90" && ok_ "090 starts kafka-ui only on request" || bad "090 always starts kafka-ui"
. "${HERE}/../lib.sh"
[ "$(mysql_pool_mb 10240)" = 2048 ] && ok_ "mysql pool: a fifth of a 10 GiB VM (2048 MB)" || bad "mysql pool for 10240 MB: $(mysql_pool_mb 10240)"
grep -q 'swapfile' "${HERE}/../host-macos.sh" && ok_ "macOS: the podman machine gets swap" || bad "macOS: no swap in the podman machine"
exit $((fails > 0))
