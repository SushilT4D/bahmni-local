#!/usr/bin/env bash
# Every script that reads sync/local/tables.conf accepts the same lines and
# agrees on what each means: the source connector's include list, MirrorMaker's
# up topics, the striding script and the hub's up sinks. Each runs on a copy of
# the repo files it needs with a fixture list (no node's .env is read).
#   - the twelve lines the list carries today render exactly as they always have;
#   - a floor taken from the seed manifest (table:pk:seed) and a floor read from
#     another table (table:pk:floor=t) are accepted by all of them;
#   - drug_order, whose key is orders.order_id, is never altered and is refused
#     by every reader when it names no floor source.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/clinic/config" "$C/hub"
cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/clinic/config/mirrormaker" "$C/clinic/config/"; cp -R "$RP/sync" "$C/"
cp -R "$RP/hub/scripts" "$RP/hub/connectors" "$C/hub/"; cp "$RP/hub/tables.conf" "$C/hub/"
printf 'MYSQL_SERVER_NAME=bahmni-t\nBHS_LOCATION=alpha\nRESIDUE=3\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\nMYSQL_ROOT_PASSWORD=x\n' > "$C/clinic/.env"
printf 'REMOTE_MYSQL_HOST=h\nREMOTE_MYSQL_PORT=3306\nREMOTE_MYSQL_DATABASE=openmrs\nREMOTE_MYSQL_USER=u\nREMOTE_MYSQL_PASSWORD=p\nDEBEZIUM_DB_PASSWORD=x\n' > "$C/hub/.env"
printf 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha\n' > "$TMP/clinics.conf"
printf 'alpha:3\n' > "$TMP/ledger"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
# a stand-in for podman: the striding script only asks whether a table exists
# and its MAX(pk); MAX_<table> in the environment answers the second
mkdir -p "$TMP/bin"
cat > "$TMP/bin/podman" <<'SH'
#!/bin/sh
for a; do sql="$a"; done
case "$sql" in
  *information_schema.tables*) echo 1 ;;
  *MAX*) t=$(printf '%s' "$sql" | sed -n 's/.*FROM `\([a-z_]*\)`.*/\1/p'); eval "echo \${MAX_$t:-0}" ;;
esac
SH
chmod +x "$TMP/bin/podman"

TODAY='encounter:encounter_id:528000
encounter_provider:encounter_provider_id:528000
encounter_type:encounter_type_id:500000
patient:patient_id:230000
patient_identifier:patient_identifier_id:230000
person:person_id:230000
person_address:person_address_id:230000
person_attribute:person_attribute_id:750000
person_name:person_name_id:230000
visit:visit_id:625000
visit_attribute:visit_attribute_id:625000
idgen_seq_id_gen:id'
CLINICAL='obs:obs_id:seed
orders:order_id:seed
drug_order:order_id:floor=orders'

# render FIXTURE-TEXT : runs every reader on the fixture; each result in $TMP/out.<reader>, its exit status in $TMP/rc.<reader>
render(){
  printf '%s\n' "$1" > "$C/sync/local/tables.conf"
  rm -rf "$C/clinic/connectors" "$C/hub/connectors"/mysql-sink-alpha-* "$C/clinic/config/mirrormaker/mm2.properties"
  bash "$C/clinic/scripts/generate-table-config.sh" local > "$TMP/out.tc" 2>&1; echo $? > "$TMP/rc.tc"
  SEED_MANIFEST="${MANIFEST-$TMP/manifest.env}" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/out.gc" 2>&1; echo $? > "$TMP/rc.gc"
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$C/clinic/connectors/mysql-local-source-connector.json" > "$TMP/inc.gc" 2>/dev/null
  if command -v envsubst >/dev/null 2>&1; then
    bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/out.mm" 2>&1; echo $? > "$TMP/rc.mm"
    grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" 2>/dev/null | grep -oE 'bahmni-t\\\.openmrs\\\.[a-z_]+' | sed 's/\\//g' | tr '\n' ' ' > "$TMP/top.mm"
  fi
  PATH="$TMP/bin:$PATH" ENV_FILE="$C/clinic/.env" CLINICS_FILE="$TMP/ledger" TABLES_FILE="$C/sync/local/tables.conf" MYSQL_CONTAINER=fake \
    SEED_MANIFEST="${MANIFEST-$TMP/manifest.env}" bash "$C/clinic/scripts/configure-pk-offsets.sh" --dry-run > "$TMP/out.pk" 2>&1; echo $? > "$TMP/rc.pk"
  grep -o 'ALTER TABLE .*;' "$TMP/out.pk" > "$TMP/alter.pk"
  CLINICS_CONF="$TMP/clinics.conf" bash "$C/hub/scripts/generate-sink-connectors.sh" > "$TMP/out.hs" 2>&1; echo $? > "$TMP/rc.hs"
  for f in "$C/hub/connectors"/mysql-sink-alpha-*.json; do
    [ -f "$f" ] && python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(c["topics"].split(".")[-1], c["primary.key.fields"])' "$f"
  done | sort > "$TMP/sinks.hs"
  REPO_DIR="$C" HUB_DIR="$C/hub" bash "$C/hub/scripts/generate-cloud-source-connector.sh" "$TMP/src.json" > "$TMP/out.cs" 2>&1; echo $? > "$TMP/rc.cs"
}
rc(){ cat "$TMP/rc.$1"; }

# --- the list as it is today: unchanged output ----------------------------------
render "$TODAY"
inc='openmrs.encounter,openmrs.encounter_provider,openmrs.encounter_type,openmrs.patient,openmrs.patient_identifier,openmrs.person,openmrs.person_address,openmrs.person_attribute,openmrs.person_name,openmrs.visit,openmrs.visit_attribute,openmrs.idgen_seq_id_gen'
[ "$(rc tc)" = 0 ] && grep -qxF "TABLE_INCLUDE_LIST=${inc}" "$TMP/out.tc" \
  && grep -qxF '# PRIMARY_KEYS=encounter_id|encounter_provider_id|encounter_type_id|patient_id|patient_identifier_id|person_id|person_address_id|person_attribute_id|person_name_id|visit_id|visit_attribute_id|id' "$TMP/out.tc" \
  && ok_ "generate-table-config: today's include list and keys unchanged" || bad "generate-table-config today: $(cat "$TMP/out.tc")"
[ "$(rc gc)" = 0 ] && [ "$(cat "$TMP/inc.gc")" = "$inc" ] && ok_ "source connector: today's include list unchanged" || bad "source connector today: rc=$(rc gc) $(cat "$TMP/inc.gc") $(cat "$TMP/out.gc")"
want_alter='ALTER TABLE `encounter` AUTO_INCREMENT = 528003;
ALTER TABLE `encounter_provider` AUTO_INCREMENT = 528003;
ALTER TABLE `encounter_type` AUTO_INCREMENT = 500003;
ALTER TABLE `patient` AUTO_INCREMENT = 230003;
ALTER TABLE `patient_identifier` AUTO_INCREMENT = 230003;
ALTER TABLE `person` AUTO_INCREMENT = 230003;
ALTER TABLE `person_address` AUTO_INCREMENT = 230003;
ALTER TABLE `person_attribute` AUTO_INCREMENT = 750003;
ALTER TABLE `person_name` AUTO_INCREMENT = 230003;
ALTER TABLE `visit` AUTO_INCREMENT = 625003;
ALTER TABLE `visit_attribute` AUTO_INCREMENT = 625003;'
[ "$(rc pk)" = 0 ] && [ "$(cat "$TMP/alter.pk")" = "$want_alter" ] && grep -q 'Sync-only (no PK offset): idgen_seq_id_gen' "$TMP/out.pk" \
  && ok_ "striding: today's eleven ALTERs unchanged, idgen_seq_id_gen sync only" || bad "striding today: rc=$(rc pk) $(cat "$TMP/out.pk")"
want_sinks="$(printf '%s\n' "$TODAY" | sed -E 's/^([^:]+):([^:]+).*/\1 \2/' | sort)"
[ "$(rc hs)" = 0 ] && [ "$(cat "$TMP/sinks.hs")" = "$want_sinks" ] && ok_ "hub up sinks: today's twelve, each on its key" || bad "hub sinks today: rc=$(rc hs) $(cat "$TMP/sinks.hs" | tr '\n' ';') $(tail -3 "$TMP/out.hs")"
if [ -f "$TMP/rc.mm" ]; then
  want_top="$(printf '%s\n' "$TODAY" | sed -E 's/^([^:]+):.*/bahmni-t.openmrs.\1/' | tr '\n' ' ')"
  [ "$(rc mm)" = 0 ] && [ "$(cat "$TMP/top.mm")" = "$want_top" ] && ok_ "MirrorMaker: today's up topics unchanged" || bad "MirrorMaker today: rc=$(rc mm) $(cat "$TMP/top.mm")"
fi
[ "$(rc cs)" = 0 ] && ok_ "hub source: renders beside today's list" || bad "hub source today: $(cat "$TMP/out.cs")"

# --- the three clinical tables: accepted by every reader, one meaning -----------
render "$TODAY
$CLINICAL"
for r in tc gc pk hs cs; do [ "$(rc $r)" = 0 ] || bad "reader $r refused the clinical lines: $(cat "$TMP/out.$r" | tail -3)"; done
case "$(sed -n 's/^TABLE_INCLUDE_LIST=//p' "$TMP/out.tc")" in *,openmrs.obs,openmrs.orders,openmrs.drug_order) ok_ "generate-table-config includes obs, orders, drug_order" ;; *) bad "include list: $(cat "$TMP/out.tc")" ;; esac
grep -qE '^# PRIMARY_KEYS=.*\|obs_id\|order_id\|order_id$' "$TMP/out.tc" && ok_ "generate-table-config keys: obs_id, order_id, order_id" || bad "keys: $(grep PRIMARY "$TMP/out.tc")"
[ "$(cat "$TMP/inc.gc")" = "$(sed -n 's/^TABLE_INCLUDE_LIST=//p' "$TMP/out.tc")" ] && ok_ "the source connector includes exactly what generate-table-config lists" || bad "source include: $(cat "$TMP/inc.gc")"
if [ -f "$TMP/rc.mm" ]; then
  case "$(cat "$TMP/top.mm")" in *"bahmni-t.openmrs.obs bahmni-t.openmrs.orders bahmni-t.openmrs.drug_order "*) ok_ "MirrorMaker forwards the three topics" ;; *) bad "MirrorMaker topics: rc=$(rc mm) $(cat "$TMP/top.mm")" ;; esac
fi
for s in "obs obs_id" "orders order_id" "drug_order order_id"; do
  grep -qxF "$s" "$TMP/sinks.hs" && ok_ "hub up sink: ${s% *} on ${s#* }" || bad "no hub sink '${s}': $(tr '\n' ';' < "$TMP/sinks.hs")"
done
grep -qxF 'ALTER TABLE `obs` AUTO_INCREMENT = 5000003;' "$TMP/alter.pk" && grep -qxF 'ALTER TABLE `orders` AUTO_INCREMENT = 300003;' "$TMP/alter.pk" \
  && ok_ "striding: obs and orders start at the manifest floor plus the residue" || bad "striding clinical: $(cat "$TMP/alter.pk")"
grep -q 'drug_order' "$TMP/alter.pk" && bad "striding alters drug_order: $(grep drug_order "$TMP/alter.pk")" || ok_ "striding never alters drug_order"
. "$RP/sync/local/tables-conf.sh"
recs="$(up_tables_read "$C/sync/local/tables.conf")"
printf '%s\n' "$recs" | grep -qxF 'obs obs_id seed -' && printf '%s\n' "$recs" | grep -qxF 'drug_order order_id floor orders' \
  && ok_ "the reader: obs floor from the seed, drug_order's from orders" || bad "records: $recs"
[ "$(up_floor_of "$C/sync/local/tables.conf" drug_order "$TMP/manifest.env")" = 300000 ] && ok_ "drug_order's floor is the orders floor from the manifest" || bad "drug_order floor: $(up_floor_of "$C/sync/local/tables.conf" drug_order "$TMP/manifest.env" 2>&1)"
[ -z "$(up_floor_of "$C/sync/local/tables.conf" idgen_seq_id_gen "$TMP/manifest.env")" ] && ok_ "a sync-only table has no floor" || bad "idgen has a floor"

# a seed floor the manifest does not carry stops striding, with nothing altered
MANIFEST="$TMP/none.env" render "$TODAY
$CLINICAL"
[ "$(rc pk)" != 0 ] && grep -q 'FLOOR_OBS' "$TMP/out.pk" && ! grep -q 'ALTER TABLE `obs`' "$TMP/alter.pk" \
  && ok_ "striding refuses a seed floor the manifest lacks, naming FLOOR_OBS" || bad "striding without a manifest: rc=$(rc pk) $(tail -2 "$TMP/out.pk")"

# --- drug_order with no floor source: every reader refuses ----------------------
render "$TODAY
obs:obs_id:seed
orders:order_id:seed
drug_order:order_id"
for r in tc gc pk hs; do
  [ "$(rc $r)" != 0 ] && grep -q 'drug_order:order_id has no floor source' "$TMP/out.$r" && ok_ "reader $r refuses drug_order with no floor source" || bad "reader $r: rc=$(rc $r) $(tail -2 "$TMP/out.$r")"
done
[ -f "$TMP/rc.mm" ] && { [ "$(rc mm)" != 0 ] && ok_ "MirrorMaker refuses it too, rather than mirroring nothing" || bad "MirrorMaker rendered a refused list: $(cat "$TMP/top.mm")"; }
ls "$C/hub/connectors"/mysql-sink-alpha-* >/dev/null 2>&1 && bad "the hub generator wrote sinks for a refused list" || ok_ "the hub generator writes nothing for a refused list"

# --- other lines no reader may skip ---------------------------------------------
. "$RP/sync/local/tables-conf.sh"
for line in 'drug_order:order_id:floor=obs' 'x:y:sometext' 'x:y:12ab' 'visit:visit_id:seed '; do
  printf 'obs:obs_id:seed\norders:order_id:seed\n%s\n' "$line" > "$TMP/bad.conf"
  up_tables_read "$TMP/bad.conf" >/dev/null 2>&1 && bad "accepted: '${line}'" || ok_ "refused: '${line}'"
done

# --- up_floor_of in a strict caller: a floor it cannot give is reported, never a silent stop ---
printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$TMP/f.conf"
printf 'FLOOR_OBS=5000000\n' > "$TMP/obs-only.env"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=abc\n' > "$TMP/nan.env"
strict(){ # CONF TABLE MANIFEST : up_floor_of called bare under set -euo pipefail
  bash -c 'set -euo pipefail; . "$1"; up_floor_of "$2" "$3" "$4"; echo "carried on"' _ "$RP/sync/local/tables-conf.sh" "$@" 2>&1
}
strict_assigned(){ # the same, its output assigned to a variable
  bash -c 'set -euo pipefail; . "$1"; v="$(up_floor_of "$2" "$3" "$4")"; echo "carried on with $v"' _ "$RP/sync/local/tables-conf.sh" "$@" 2>&1
}
out="$(strict "$TMP/f.conf" orders "$TMP/obs-only.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the orders floor comes from the seed manifest, and $TMP/obs-only.env carries no FLOOR_ORDERS") true ;; *) false ;; esac \
  && ok_ "up_floor_of, bare under set -e: a manifest without the key says so" || bad "bare, missing key: rc=$rc '$out'"
out="$(strict_assigned "$TMP/f.conf" drug_order "$TMP/obs-only.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"carries no FLOOR_ORDERS"*) true ;; *) false ;; esac \
  && ok_ "up_floor_of, assigned under set -e: drug_order's missing orders floor says so" || bad "assigned, missing key: rc=$rc '$out'"
out="$(strict "$TMP/f.conf" obs "$TMP/nowhere.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"there is no manifest at $TMP/nowhere.env"*) true ;; *) false ;; esac && ok_ "up_floor_of: a missing manifest says so" || bad "no manifest: rc=$rc '$out'"
out="$(strict "$TMP/f.conf" orders "$TMP/nan.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"FLOOR_ORDERS in $TMP/nan.env is not a number: abc"*) true ;; *) false ;; esac && ok_ "up_floor_of: a floor that is not a number says so" || bad "nan floor: rc=$rc '$out'"
out="$(strict "$TMP/f.conf" visit "$TMP/obs-only.env")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"f.conf does not list visit"*) true ;; *) false ;; esac && ok_ "up_floor_of: a table the list does not carry says so" || bad "unlisted table: rc=$rc '$out'"
out="$(strict "$TMP/f.conf" obs "$TMP/obs-only.env")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "5000000
carried on" ] && ok_ "up_floor_of: a floor the manifest carries is printed and the caller carries on" || bad "present key: rc=$rc '$out'"
exit $((fails > 0))
