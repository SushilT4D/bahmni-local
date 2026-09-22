#!/usr/bin/env bash
# MirrorMaker assigns a topic created after it started only on its topic
# refresh, so task 090 creates the node's up topics first and the template
# shortens the refresh. The pattern parser is exercised on a rendered file.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T90="${HERE}/../tasks/090-local-sync.sh"; TPL="${HERE}/../../config/mirrormaker/mm2.properties.template"
grep -q '^refresh.topics.interval.seconds = 60$' "$TPL" && ok_ "template: topic refresh every 60 s" || bad "template: no 60 s topic refresh"
blk="$(sed -n '/# mm2-topics:begin/,/# mm2-topics:end/p' "$T90")"
[ -n "$blk" ] || { bad "090 has no mm2-topics block"; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cat > "$W/mm2.properties" <<'P'
clusters = ghated, remote
ghated->remote.enabled = true
ghated->remote.topics = (bahmni-ghated\.clinlims\.all|bahmni-ghated\.odoo\.all|bahmni-ghated\.openmrs\.encounter|bahmni-ghated\.openmrs\.person)
remote->ghated.topics = (bahmni-cloud\.openmrs\.role)
P
out="$(bash -c "$blk"$'\n''mm2_up_topics "$1" ghated' _ "$W/mm2.properties")"
[ "$(printf '%s\n' "$out" | grep -c .)" = 4 ] && ok_ "four up topics parsed" || bad "parsed: $out"
printf '%s\n' "$out" | grep -qx 'bahmni-ghated.odoo.all' && ok_ "escapes removed: bahmni-ghated.odoo.all" || bad "odoo.all not plain: $out"
printf '%s\n' "$out" | grep -q 'bahmni-cloud' && bad "the down pattern leaked into the up list" || ok_ "down pattern not included"
code="$(grep -vE '^[[:space:]]*#' "$T90")"
printf '%s' "$code" | grep -q 'kafka-topics --bootstrap-server localhost:9092 --create --if-not-exists' && ok_ "090 creates the topics before MirrorMaker starts" || bad "090 does not create topics"
printf '%s' "$code" | grep -q 'topic-partitions ${LOCAL_CLUSTER_ALIAS}->remote' && ok_ "090 asserts MirrorMaker assigned the node's Odoo topic" || bad "090 does not assert the assignment"
exit "$fails"
