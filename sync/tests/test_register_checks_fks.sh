#!/usr/bin/env bash
# hub/scripts/register-all-sink-connectors.sh runs check-clinical-fks.sh before
# it registers any sink for obs, orders or drug_order, and registers nothing
# when a foreign key points out of one of them. Kafka Connect and the hub's
# MySQL are stood in for.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/hub"; mkdir -p "$C/connectors" "$TMP/bin"
cp -R "$R/hub/scripts" "$C/"; cp "$R/hub/clinical-fks-in.conf" "$C/"
sink(){ printf '{"name": "%s", "config": {"topics": "alpha.bahmni-alpha.openmrs.%s"}}\n' "$1" "$2" > "$C/connectors/$1.json"; }
# the hub's keys, as information_schema would print them
awk '{ sub(/#.*/, "") } NF == 4 { printf "%s\t%s\t%s\t%s\t%s_fk\n", $1, $2, $3, $4, $1 }' "$R/hub/clinical-fks-in.conf" > "$TMP/fks.clean"
{ cat "$TMP/fks.clean"; printf 'obs\tencounter_id\tencounter\tencounter_id\tobs_encounter\n'; } > "$TMP/fks.out"
cat > "$TMP/bin/docker" <<SH
#!/bin/sh
[ "\$1" = ps ] && exit 0
cat >/dev/null; cat "$TMP/fks"; printf 'schema\t3\n'
SH
cat > "$TMP/bin/curl" <<SH
#!/bin/sh
echo "\$*" >> "$TMP/curl.log"
case "\$*" in *"-w"*) printf 404 ;; */status) printf '{"connector":{"state":"RUNNING"},"tasks":[{"id":0,"state":"RUNNING"}]}' ;; *) printf '{}' ;; esac
SH
chmod +x "$TMP/bin/"*
run(){ rm -f "$TMP/curl.log"; env PATH="$TMP/bin:$PATH" "$@" bash "$C/scripts/register-all-sink-connectors.sh" </dev/null > "$TMP/out" 2>&1; echo $? > "$TMP/rc"; }
posts(){ grep -c -- '-X POST' "$TMP/curl.log" 2>/dev/null || echo 0; }

sink mysql-sink-alpha-visit visit; sink mysql-sink-alpha-obs obs
cp "$TMP/fks.out" "$TMP/fks"; run HUB_MYSQL_CONTAINER=hubdb
[ "$(cat "$TMP/rc")" = 1 ] && [ "$(posts)" = 0 ] && grep -q 'obs.encounter_id -> encounter.encounter_id' "$TMP/out" && grep -q 'Nothing was registered' "$TMP/out" \
  && ok_ "a foreign key out of obs on the hub: nothing registered, the key named" || bad "fk out: rc=$(cat "$TMP/rc") posts=$(posts) $(tail -3 "$TMP/out")"
cp "$TMP/fks.clean" "$TMP/fks"; run HUB_MYSQL_CONTAINER=hubdb
[ "$(cat "$TMP/rc")" = 0 ] && [ "$(posts)" = 2 ] && grep -q '^ok   obs: no foreign key out' "$TMP/out" && ok_ "no key out: the check runs first, then both sinks are registered" || bad "clean: rc=$(cat "$TMP/rc") posts=$(posts) $(tail -3 "$TMP/out")"
run
[ "$(cat "$TMP/rc")" = 1 ] && [ "$(posts)" = 0 ] && grep -q 'HUB_MYSQL_CONTAINER' "$TMP/out" && ok_ "clinical sinks with no hub MySQL named: refused, nothing registered" || bad "no container: rc=$(cat "$TMP/rc") posts=$(posts) $(tail -2 "$TMP/out")"
rm -f "$C/connectors/mysql-sink-alpha-obs.json"; run
[ "$(cat "$TMP/rc")" = 0 ] && [ "$(posts)" = 1 ] && ! grep -q 'no foreign key out' "$TMP/out" && ok_ "no clinical sink: registered without the check" || bad "non-clinical: rc=$(cat "$TMP/rc") posts=$(posts) $(tail -2 "$TMP/out")"
exit $((fails > 0))
