#!/usr/bin/env bash
# clinic/scripts/catch-up-clinical.sh asks the source connector, through its
# signal table, for the rows of obs, orders and drug_order this clinic owns:
#   - the dry run prints the exact count query and signal row per table for a
#     residue and the seed's floors, drug_order on the orders floor;
#   - a table without a floor from the seed, a missing floor or residue, or a
#     connector that does not capture the table or its signal table: refused,
#     nothing inserted;
#   - a live run (Connect and the database stood in for) counts each table's
#     rows, logs the counts and inserts exactly the rows the dry run prints;
#   - --status reads the connector's offsets for a snapshot still running.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/clinic" "$TMP/bin"
cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/sync" "$C/"
S="$C/clinic/scripts/catch-up-clinical.sh"
printf 'MYSQL_SERVER_NAME=bahmni-t\nRESIDUE=3\nCOMPOSE_PROJECT_NAME=t\n' > "$C/clinic/.env"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
LIST='visit:visit_id:625000
obs:obs_id:seed
orders:order_id:seed
drug_order:order_id:floor=orders
idgen_seq_id_gen:id'
printf '%s\n' "$LIST" > "$C/sync/local/tables.conf"
run(){ SEED_MANIFEST="${MF-$TMP/manifest.env}" PATH="$TMP/bin:$PATH" CONTAINER_TOOL=fakect bash "$S" "$@" > "$TMP/out" 2>&1; echo $? > "$TMP/rc"; }

# --- the dry run: exact rows for residue 3 ----------------------------------------
run --dry-run --id t1
want="-- catch-up, residue 3, run t1 (dry run: nothing counted, nothing inserted)
-- obs: rows this clinic owns
SELECT COUNT(*) FROM openmrs.\`obs\` WHERE obs_id >= 5000000 AND obs_id % 10 = 3;
INSERT INTO openmrs.debezium_signal (id, type, data) VALUES ('catch-up-obs-t1', 'execute-snapshot', '{\"data-collections\": [\"openmrs.obs\"], \"type\": \"incremental\", \"additional-conditions\": [{\"data-collection\": \"openmrs.obs\", \"filter\": \"obs_id >= 5000000 AND obs_id % 10 = 3\"}]}');
-- orders: rows this clinic owns
SELECT COUNT(*) FROM openmrs.\`orders\` WHERE order_id >= 300000 AND order_id % 10 = 3;
INSERT INTO openmrs.debezium_signal (id, type, data) VALUES ('catch-up-orders-t1', 'execute-snapshot', '{\"data-collections\": [\"openmrs.orders\"], \"type\": \"incremental\", \"additional-conditions\": [{\"data-collection\": \"openmrs.orders\", \"filter\": \"order_id >= 300000 AND order_id % 10 = 3\"}]}');
-- drug_order: rows this clinic owns
SELECT COUNT(*) FROM openmrs.\`drug_order\` WHERE order_id >= 300000 AND order_id % 10 = 3;
INSERT INTO openmrs.debezium_signal (id, type, data) VALUES ('catch-up-drug_order-t1', 'execute-snapshot', '{\"data-collections\": [\"openmrs.drug_order\"], \"type\": \"incremental\", \"additional-conditions\": [{\"data-collection\": \"openmrs.drug_order\", \"filter\": \"order_id >= 300000 AND order_id % 10 = 3\"}]}');"
[ "$(cat "$TMP/rc")" = 0 ] && [ "$(cat "$TMP/out")" = "$want" ] && ok_ "dry run, residue 3: the exact count query and signal row for obs, orders and drug_order (on the orders floor)" \
  || { bad "dry run: rc=$(cat "$TMP/rc")"; diff <(printf '%s\n' "$want") "$TMP/out" | head -10; }
python3 - "$TMP/out" <<'PY' && ok_ "every signal's data is JSON naming one table and its own filter" || bad "a signal's data is not the JSON Debezium reads"
import json, re, sys
for line in open(sys.argv[1]):
    m = re.match(r"INSERT INTO openmrs\.debezium_signal \(id, type, data\) VALUES \('([^']+)', 'execute-snapshot', '(.*)'\);$", line.strip())
    if not m: continue
    d = json.loads(m.group(2)); assert len(m.group(1)) <= 42
    assert d["type"] == "incremental" and d["data-collections"] == [d["additional-conditions"][0]["data-collection"]]
PY
run --dry-run --id t1 drug_order
[ "$(cat "$TMP/rc")" = 0 ] && [ "$(grep -c '^INSERT' "$TMP/out")" = 1 ] && grep -q "catch-up-drug_order-t1" "$TMP/out" && ok_ "one table named: only its signal" || bad "drug_order only: $(cat "$TMP/out")"
grep -q 'order_id >= 300000' "$TMP/out" && ok_ "drug_order alone still reads the orders floor" || bad "drug_order floor: $(cat "$TMP/out")"

# --- refusals ---------------------------------------------------------------------
run --dry-run visit
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'visit is not a table' "$TMP/out" && ok_ "a table without a seed floor is refused" || bad "visit: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
printf 'FLOOR_OBS=5000000\n' > "$TMP/obs-only.env"
MF="$TMP/obs-only.env" run --dry-run
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'FLOOR_ORDERS' "$TMP/out" && ! grep -q '^INSERT' "$TMP/out" && ok_ "a missing orders floor is refused, nothing printed to insert" || bad "no orders floor: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
printf 'MYSQL_SERVER_NAME=bahmni-t\n' > "$C/clinic/.env"; run --dry-run
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'RESIDUE' "$TMP/out" && ok_ "no residue: refused" || bad "no residue: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
printf 'MYSQL_SERVER_NAME=bahmni-t\nRESIDUE=3\nCOMPOSE_PROJECT_NAME=t\n' > "$C/clinic/.env"
grep -v ':seed\|floor=' <<EOF > "$C/sync/local/tables.conf"
$LIST
EOF
run --dry-run
[ "$(cat "$TMP/rc")" = 0 ] && grep -q 'nothing to catch up' "$TMP/out" && ok_ "a list without seed floors: nothing to catch up" || bad "no clinical tables: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
printf '%s\n' "$LIST" > "$C/sync/local/tables.conf"

# --- a live run, Connect and the database stood in for ----------------------------
# fakect records every SQL it is given and answers a count with 7
cat > "$TMP/bin/fakect" <<EOF
#!/bin/sh
sql="\$(cat)"; printf '%s\n' "\$sql" >> "$TMP/sql.log"
case "\$sql" in SELECT\ COUNT*) echo 7 ;; esac
EOF
chmod +x "$TMP/bin/fakect"
inc_good='openmrs.visit,openmrs.obs,openmrs.orders,openmrs.drug_order,openmrs.idgen_seq_id_gen,openmrs.debezium_signal'
fake_connect(){ # INCLUDE_LIST
  cat > "$TMP/bin/curl" <<EOF
#!/bin/sh
for a; do u="\$a"; done
case "\$u" in
  */config) printf '{"name": "mysql-source-connector", "table.include.list": "%s"}' "$1" ;;
  */offsets) cat "$TMP/offsets.json" ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$TMP/bin/curl"
}
fake_connect "$inc_good"; rm -f "$TMP/sql.log"
run --id t1
[ "$(cat "$TMP/rc")" = 0 ] || bad "live run: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
grep '^INSERT' "$TMP/sql.log" > "$TMP/live.ins"; SEED_MANIFEST="$TMP/manifest.env" bash "$S" --dry-run --id t1 | grep '^INSERT' > "$TMP/dry.ins"
[ -s "$TMP/live.ins" ] && cmp -s "$TMP/live.ins" "$TMP/dry.ins" && ok_ "a live run inserts exactly the rows the dry run prints" || bad "live inserts differ: $(cat "$TMP/live.ins")"
for t in obs orders drug_order; do grep -qE "^  ${t}: 7 row\(s\) with .*, signalled as catch-up-${t}-t1$" "$TMP/out" || bad "no count logged for ${t}: $(cat "$TMP/out")"; done
grep -q '21 row(s) in all' "$TMP/out" && ok_ "a live run logs each table's count and the total" || bad "counts: $(cat "$TMP/out")"
order_ok=1; for t in obs orders drug_order; do
  c="$(grep -n "FROM openmrs.\`${t}\` WHERE" "$TMP/sql.log" | head -1 | cut -d: -f1)"; s="$(grep -n "'catch-up-${t}-t1'" "$TMP/sql.log" | head -1 | cut -d: -f1)"
  [ -n "$c" ] && [ -n "$s" ] && [ "$c" -lt "$s" ] || order_ok=0
done
[ "$order_ok" = 1 ] && ok_ "each table is counted before its signal is inserted" || bad "a signal was inserted before its table was counted: $(cat "$TMP/sql.log")"
fake_connect 'openmrs.visit,openmrs.obs,openmrs.orders,openmrs.drug_order'; rm -f "$TMP/sql.log"
run --id t2
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'does not capture openmrs.debezium_signal' "$TMP/out" && [ ! -s "$TMP/sql.log" ] && ok_ "a connector that does not capture its signal table: refused, nothing inserted" || bad "no signal capture: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
fake_connect 'openmrs.visit,openmrs.orders,openmrs.drug_order,openmrs.debezium_signal'; rm -f "$TMP/sql.log"
run --id t3
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'does not capture openmrs.obs' "$TMP/out" && [ ! -s "$TMP/sql.log" ] && ok_ "a connector that does not capture obs: refused, nothing inserted" || bad "no obs capture: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"

# --- progress from the offsets ----------------------------------------------------
fake_connect "$inc_good"
printf '%s' '{"offsets": [{"partition": {"server": "bahmni-t"}, "offset": {"file": "binlog.000003", "pos": 1, "incremental_snapshot_collections": "[{\"incremental_snapshot_collections_id\":\"openmrs.obs\",\"incremental_snapshot_collections_additional_condition\":\"obs_id >= 5000000 AND obs_id % 10 = 3\"}]"}}]}' > "$TMP/offsets.json"
run --status
[ "$(cat "$TMP/rc")" = 0 ] && grep -qx 'in progress: openmrs.obs' "$TMP/out" && ok_ "--status: a snapshot still reading obs is reported from the offsets" || bad "status busy: $(cat "$TMP/out")"
printf '%s' '{"offsets": [{"partition": {"server": "bahmni-t"}, "offset": {"file": "binlog.000003", "pos": 9}}]}' > "$TMP/offsets.json"
run --status
[ "$(cat "$TMP/rc")" = 0 ] && grep -q '^no incremental snapshot in progress' "$TMP/out" && ok_ "--status: offsets with no collection left read as done" || bad "status idle: $(cat "$TMP/out")"
exit $((fails > 0))
