#!/usr/bin/env bash
# obs, orders and drug_order carry the hub's rows below their floor, so a
# capture line for one must name where its floor comes from. Read as
# sync-only or with a fixed base_id it would render no capture filter and
# every check would stay green while clinics published edits to hub rows:
# the shared reader refuses such a line, and with it every generator.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
. "$RP/sync/local/tables-conf.sh"
for line in 'obs:obs_id' 'orders:order_id' 'obs:obs_id:5000000' 'orders:order_id:300000'; do
  printf 'visit:visit_id:625000\n%s\n' "$line" > "$TMP/t.conf"
  out="$(up_tables_read "$TMP/t.conf" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && case "$out" in *"${line%%:*} is clinical data and needs its floor from the seed"*) true ;; *) false ;; esac \
    && ok_ "refused: '${line}'" || bad "accepted or misnamed: '${line}' rc=$rc $out"
done
printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$TMP/t.conf"
up_tables_read "$TMP/t.conf" >/dev/null 2>&1 && ok_ "accepted: the three with floors from the seed and from orders" || bad "the floored lines were refused"
# drug_order with no floor source keeps its own, more specific reason
printf 'orders:order_id:seed\ndrug_order:order_id\n' > "$TMP/t.conf"
out="$(up_tables_read "$TMP/t.conf" 2>&1)"; case "$out" in *"drug_order:order_id has no floor source"*) ok_ "drug_order without a floor source: still named as such" ;; *) bad "drug_order: $out" ;; esac
printf 'drug_order:order_id\n' > "$TMP/t.conf"
out="$(up_tables_read "$TMP/t.conf" 2>&1)"; [ $? = 1 ] && ok_ "drug_order sync-only with no orders line: refused" || bad "drug_order alone accepted: $out"
# a generator refuses too, writing nothing
C="$TMP/repo"; mkdir -p "$C/clinic"; cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/sync" "$C/"
printf 'visit:visit_id:625000\nobs:obs_id\n' > "$C/sync/local/tables.conf"
printf 'MYSQL_SERVER_NAME=bahmni-t\nRESIDUE=3\nCLINICAL_UP_SYNC=test\n' > "$C/clinic/.env"
bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/out" 2>&1; rc=$?
[ "$rc" != 0 ] && [ ! -f "$C/clinic/connectors/mysql-local-source-connector.json" ] && ok_ "the source generator refuses obs:obs_id and writes nothing" || bad "generator: rc=$rc $(tail -2 "$TMP/out")"
exit $((fails > 0))
