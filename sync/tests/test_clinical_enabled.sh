#!/usr/bin/env bash
# The committed clinic list carries obs, orders and drug_order. A clinic
# installed with CLINICAL_UP_SYNC=test sends them, and every piece that rides on
# those lines comes with them; a clinic left at the default (off) sends none:
#   - the lines take their floors from the seed (drug_order from orders);
#   - the source connector rendered from the committed list carries a capture
#     filter step for each of the three and captures the signal table;
#   - MirrorMaker forwards the three topics;
#   - the hub renders one up sink per table per clinic, on the clinical
#     profile (errors not tolerated, upsert on the record key, deletes applied,
#     the hub's schema never altered), and the validator accepts them;
#   - the hub's own list never names them (the hub does not publish them);
#   - at an off clinic the source, its include list and MirrorMaker carry none
#     of them, and the hub renders no clinical sink for an unmarked clinic.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
L="$R/sync/local/tables.conf"
for line in 'obs:obs_id:seed' 'orders:order_id:seed' 'drug_order:order_id:floor=orders'; do
  grep -qx "$line" "$L" && ok_ "sync/local/tables.conf: $line" || bad "sync/local/tables.conf lacks $line"
done
C="$TMP/repo"; mkdir -p "$C/clinic/config" "$C/hub"
cp -R "$R/clinic/scripts" "$C/clinic/"; cp -R "$R/clinic/config/mirrormaker" "$C/clinic/config/"; cp -R "$R/sync" "$C/"
cp -R "$R/hub/scripts" "$R/hub/connectors" "$C/hub/"; cp "$R/hub/tables.conf" "$C/hub/"
printf 'MYSQL_SERVER_NAME=bahmni-t\nBHS_LOCATION=alpha\nRESIDUE=3\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\nMYSQL_ROOT_PASSWORD=x\nCLINICAL_UP_SYNC=test\n' > "$C/clinic/.env"
printf 'REMOTE_MYSQL_HOST=h\nREMOTE_MYSQL_PORT=3306\nREMOTE_MYSQL_DATABASE=openmrs\nREMOTE_MYSQL_USER=u\nREMOTE_MYSQL_PASSWORD=p\nDEBEZIUM_DB_PASSWORD=x\n' > "$C/hub/.env"
printf 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha:clinical\n' > "$TMP/clinics.conf"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/gc" 2>&1 || bad "the source does not render from the committed list: $(tail -2 "$TMP/gc")"
python3 - "$C/clinic/connectors/mysql-local-source-connector.json" > "$TMP/src" 2>&1 <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))["config"]
inc = c["table.include.list"].split(",")
print("transforms", c.get("transforms", ""))
for t in ("obs", "orders", "drug_order", "debezium_signal"):
    print("include", t, "openmrs." + t in inc)
PY
grep -qx 'transforms origin_obs,origin_orders,origin_drug_order' "$TMP/src" && ok_ "the source carries the capture filter for the three tables" || bad "source transforms: $(cat "$TMP/src")"
[ "$(grep -c '^include .* True$' "$TMP/src")" = 4 ] && ok_ "the source captures obs, orders, drug_order and the signal table" || bad "source include: $(cat "$TMP/src")"
if command -v envsubst >/dev/null 2>&1; then
  bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/mm" 2>&1 || bad "MirrorMaker does not render: $(tail -2 "$TMP/mm")"
  top="$(grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" | grep -oE 'bahmni-t\\\.openmrs\\\.[a-z_]+' | sed 's/\\//g' | tr '\n' ' ')"
  for t in obs orders drug_order; do case " $top " in *" bahmni-t.openmrs.$t "*) ;; *) bad "MirrorMaker does not forward $t: $top" ;; esac; done
  case "$top" in *signal*) bad "MirrorMaker forwards the signal table" ;; *) ok_ "MirrorMaker forwards the three topics, not the signal table" ;; esac
fi
CLINICS_CONF="$TMP/clinics.conf" bash "$C/hub/scripts/generate-sink-connectors.sh" > "$TMP/hs" 2>&1 || bad "the hub sinks do not render: $(tail -2 "$TMP/hs")"
for s in "obs obs_id" "orders order_id" "drug_order order_id"; do
  t="${s% *}"; k="${s#* }"; f="$C/hub/connectors/mysql-sink-alpha-${t}.json"
  got="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(c.get("errors.tolerance"), c.get("insert.mode"), c.get("primary.key.mode"), c.get("primary.key.fields"), c.get("delete.enabled"), c.get("schema.evolution"), "auto.create" in c, "auto.evolve" in c)' "$f" 2>&1)"
  [ "$got" = "none upsert record_key ${k} true none False False" ] && ok_ "hub sink mysql-sink-alpha-${t}: clinical profile on ${k}" || bad "hub sink ${t}: ${got}"
done
vbad=""
for f in "$C/hub/connectors"/mysql-sink-alpha-*.json; do
  t="${f##*mysql-sink-alpha-}"; t="${t%.json}"; p=default
  case " obs orders drug_order " in *" $t "*) p=clinical ;; esac
  python3 "$C/hub/scripts/validate-sink-config.py" "$f" --known-good "$C/hub/connectors/known-good.json" --profile "$p" > "$TMP/val" 2>&1 || vbad="${vbad} ${t}($(tail -1 "$TMP/val"))"
done
[ -z "$vbad" ] && ok_ "validate-sink-config.py accepts every rendered hub sink, the three on the clinical profile" || bad "validator refused:${vbad}"
grep -qE '^[[:space:]]*(obs|orders|drug_order):' "$R/hub/tables.conf" && bad "hub/tables.conf names a clinical table" || ok_ "hub/tables.conf names none of the three"
# --- the same committed list at a clinic left at the default ---------------------
sed -i.bak '/^CLINICAL_UP_SYNC=/d' "$C/clinic/.env"; rm -f "$C/clinic/.env.bak"
rm -rf "$C/clinic/connectors"
SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/gc" 2>&1 || bad "the source does not render at an off clinic: $(tail -2 "$TMP/gc")"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; inc=c["table.include.list"].split(","); sys.exit(any(("openmrs." + t) in inc for t in ("obs","orders","drug_order")) or bool(c.get("transforms")))' "$C/clinic/connectors/mysql-local-source-connector.json" \
  && ok_ "off (the default): the source captures none of the three and carries no filter" || bad "an off clinic captures a clinical table"
if command -v envsubst >/dev/null 2>&1; then
  bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/mm" 2>&1
  grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" | grep -qE 'openmrs\\\.(obs|orders|drug_order)[|)]' && bad "an off clinic's MirrorMaker forwards a clinical topic" || ok_ "off: MirrorMaker forwards none of them"
fi
printf 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha\n' > "$TMP/clinics.conf"; rm -f "$C/hub/connectors"/mysql-sink-alpha-*
CLINICS_CONF="$TMP/clinics.conf" bash "$C/hub/scripts/generate-sink-connectors.sh" > "$TMP/hs" 2>&1
ls "$C/hub/connectors"/mysql-sink-alpha-obs.json >/dev/null 2>&1 && bad "the hub renders an obs sink for an unmarked clinic" || ok_ "hub: no clinical sink for a clinic not marked clinical"
exit $((fails > 0))
