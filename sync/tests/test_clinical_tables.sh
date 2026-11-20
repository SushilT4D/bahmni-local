#!/usr/bin/env bash
# The committed clinic list carries obs, orders, drug_order and test_order, and
# every clinic sends them:
#   - the lines take their floors from the seed (drug_order and test_order
#     from orders);
#   - the source connector rendered from the committed list carries a capture
#     filter step for each of the four and captures the signal table;
#   - MirrorMaker forwards the ordered topic;
#   - the hub renders one up sink per clinic that keeps every table (errors not
#     tolerated, upsert on the record key, the hub's schema never altered), and
#     the validator accepts it and refuses one that filters tables;
#   - the hub's own list (openmrs.conf [down]) never names them (the hub does not publish them).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
L="$(bash "$R/sync/tables/tables.sh" openmrs up)"
D="$(bash "$R/sync/tables/tables.sh" openmrs down)"
for line in 'obs:obs_id:seed' 'orders:order_id:seed' 'drug_order:order_id:floor=orders' 'test_order:order_id:floor=orders'; do
  printf '%s\n' "$L" | grep -qx "$line" && ok_ "openmrs.conf [up]: $line" || bad "openmrs.conf [up] lacks $line"
done
C="$TMP/repo"; mkdir -p "$C/clinic/config" "$C/cloud"
cp -R "$R/clinic/scripts" "$C/clinic/"; cp -R "$R/clinic/config/mirrormaker" "$C/clinic/config/"; cp -R "$R/sync" "$C/"
cp -R "$R/cloud/scripts" "$C/cloud/"
printf 'MYSQL_SERVER_NAME=bahmni-t\nBHS_LOCATION=alpha\nRESIDUE=3\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\nMYSQL_ROOT_PASSWORD=x\n' > "$C/clinic/.env"
printf 'OPENMRS_DB_HOST=h\nOPENMRS_DB_NAME=openmrs\nDEBEZIUM_DB_PASSWORD=x\nODOO_DB_HOST=o\nODOO_DB_NAME=odoo\nODOO_SINK_PASSWORD=x\nOPENELIS_DB_HOST=e\nCLINLIMS_SINK_PASSWORD=x\n' > "$C/cloud/.env"
printf 'alpha:3\ncloud:10\n' > "$TMP/clinics.txt"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/generate/mysql-source.sh" > "$TMP/gc" 2>&1 || bad "the source does not render from the committed list: $(tail -2 "$TMP/gc")"
python3 - "$C/clinic/connectors/mysql-source-connector.json" > "$TMP/src" 2>&1 <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["config"]
inc = c["table.include.list"].split(",")
print("transforms", c.get("transforms", ""))
print("agg", c.get("transforms.agg.replacement", ""))
for t in ("obs", "orders", "drug_order", "test_order", "debezium_signal"):
    print("include", t, "openmrs." + t in inc)
PY
grep -qx 'transforms origin_obs,origin_orders,origin_drug_order,origin_test_order,agg' "$TMP/src" && ok_ "the source carries the capture filter for the four tables, then routes into one topic" || bad "source transforms: $(cat "$TMP/src")"
grep -qx 'agg bahmni-t.openmrs.all' "$TMP/src" && ok_ "the source routes every table into bahmni-t.openmrs.all" || bad "source routing: $(cat "$TMP/src")"
[ "$(grep -c '^include .* True$' "$TMP/src")" = 5 ] && ok_ "the source captures obs, orders, drug_order, test_order and the signal table" || bad "source include: $(cat "$TMP/src")"
if command -v envsubst >/dev/null 2>&1; then
  bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/mm" 2>&1 || bad "MirrorMaker does not render: $(tail -2 "$TMP/mm")"
  top="$(grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" | grep -oE 'bahmni-t\\\.openmrs\\\.[a-z_]+' | sed 's/\\//g' | tr '\n' ' ')"
  for t in obs orders drug_order test_order; do case " $top " in *" bahmni-t.openmrs.$t "*) ;; *) bad "MirrorMaker does not forward $t: $top" ;; esac; done
  case "$top" in *signal*) bad "MirrorMaker forwards the signal table" ;; *) ok_ "MirrorMaker forwards the four topics, not the signal table" ;; esac
  grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" | grep -q 'bahmni-t\\\.openmrs\\\.all' && ok_ "MirrorMaker forwards bahmni-t.openmrs.all" || bad "MirrorMaker does not forward bahmni-t.openmrs.all"
fi
CLINICS_FILE="$TMP/clinics.txt" bash "$C/cloud/scripts/generate-sink-connectors.sh" > "$TMP/hs" 2>&1 || bad "the hub sinks do not render: $(tail -2 "$TMP/hs")"
f="$C/cloud/connectors/openmrs-alpha-sink.json"
got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(c.get("topics"), c.get("collection.name.format"), c.get("primary.key.mode"), c.get("schema.evolution"), bool(c.get("transforms")))' "$f" 2>&1)"
[ "$got" = 'alpha.bahmni-alpha.openmrs.all openmrs.${source.table} record_key none False' ] && ok_ "hub: one sink for alpha on its ordered topic, no table filtered" || bad "hub sink: ${got}"
python3 "$C/cloud/scripts/validate-sink-config.py" "$f" --known-good "$C/cloud/scripts/templates/known-good.json" > "$TMP/val" 2>&1 \
  && ok_ "validate-sink-config.py accepts the sink" || bad "validator refused: $(cat "$TMP/val")"
grep -q 'sessionVariables=sql_log_bin=0' "$f" && ok_ "hub: the sink keeps the clinic's rows out of the hub's binlog" || bad "hub: the sink's connection.url lacks sql_log_bin=0"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["config"]["connection.url"]=d["config"]["connection.url"].replace("&sessionVariables=sql_log_bin=0", ""); json.dump(d, open(sys.argv[2], "w"))' "$f" "$TMP/logged.json"
python3 "$C/cloud/scripts/validate-sink-config.py" "$TMP/logged.json" > "$TMP/val" 2>&1 \
  && bad "validate-sink-config.py accepts a sink that writes to the hub's binlog" || ok_ "validate-sink-config.py refuses a sink without sql_log_bin=0"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["config"]["transforms"]="dropSome"; json.dump(d, open(sys.argv[2], "w"))' "$f" "$TMP/filtered.json"
python3 "$C/cloud/scripts/validate-sink-config.py" "$TMP/filtered.json" > "$TMP/val" 2>&1 \
  && bad "validate-sink-config.py accepts a sink that filters tables" || ok_ "validate-sink-config.py refuses a sink that filters tables"
printf '%s\n' "$D" | grep -qE '^(orders|drug_order|test_order):' && bad "openmrs.conf [down] names orders, drug_order or test_order" || ok_ "openmrs.conf [down] names none of orders, drug_order, test_order"
printf '%s\n' "$D" | grep -E '^obs:' | grep -vqE '^obs:obs_id:clinic=order_id$' && bad "openmrs.conf [down] names obs other than as the hub's lab results, routed by order" || ok_ "openmrs.conf [down] names obs only as the hub's lab results, routed by order"
exit $((fails > 0))
