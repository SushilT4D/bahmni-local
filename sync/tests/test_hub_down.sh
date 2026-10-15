#!/usr/bin/env bash
# The hub sends down only master tables (and the three OpenELIS rows a hub lab
# user completes, routed to one clinic: sync/tests/test_clinlims_down.sh), and
# every artefact that sends tables down is rendered from one list,
# sync/hub-down.conf:
#   - the reader (sync/hub-down.sh) prints exactly the eleven master tables and
#     refuses, by name, every up-only table planted in the list;
#   - the hub Odoo source, rendered by register-odoo.sh, carries exactly that
#     list, and a template edited to carry anything else is refused before any
#     registration;
#   - the clinic MirrorMaker's down regex carries the list's Odoo and OpenELIS
#     topics and no up-only table, while its up regex still carries them all;
#   - on a real PostgreSQL 16 (when docker and the image are here): the floors
#     are recorded by the run that strides the ids, never changed by a re-run,
#     refused when a clinic's origin shows progress or a sequence would restart
#     below its floor; --from-file values are checked against the sequences;
#     the publication publishes no TRUNCATE and holds exactly
#     the list with (id < floor OR id % 10 = 0) on each table with an id, a
#     missing floor or a replica identity that does not cover id is refused
#     before the publication changes, and logical decoding through the
#     publication sends a legacy row's update and delete and a hub row, but
#     nothing of a clinic's row.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
UP_ONLY="res_partner res_partner_attributes sale_order sale_order_line account_move account_move_line stock_quant"
TRANSFER="stock_location stock_warehouse stock_picking_type stock_route stock_rule procurement_group stock_lot stock_warehouse_orderpoint stock_picking stock_move stock_move_line"
WANT="product_template product_product product_category uom_uom res_country_state state_district district_subdistrict village_village product_taxes_rel product_supplier_taxes_rel stock_route_product $TRANSFER"
PGC=""
T="$(mktemp -d)"
cleanup(){ [ -n "$PGC" ] && docker rm -f -v "$PGC" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
# a copy of the files the renderers read, so a planted line never touches the repo
C="$T/repo"; mkdir -p "$C/sync/local" "$C/hub/connectors" "$C/hub/scripts" "$C/hub/odoo" "$C/clinic/scripts" "$C/clinic/config/mirrormaker"
cp "$R/sync/hub-down.sh" "$R/sync/hub-down.conf" "$R/sync/subsystems.conf" "$C/sync/"
cp "$R/sync/local/tables.conf" "$R/sync/local/tables-conf.sh" "$C/sync/local/"
cp "$R/hub/tables.conf" "$C/hub/"
cp "$R/hub/connectors/odoo-cloud-source.json" "$R/hub/connectors/register-odoo.sh" "$R/hub/connectors/_render_connector.py" "$C/hub/connectors/"
mkdir -p "$C/clinic/odoo"
cp "$R/hub/scripts/down-floors.sh" "$R/hub/scripts/record-down-floors.sh" "$R/hub/scripts/apply-down-publication.sh" "$R/hub/scripts/stride-odoo.sh" "$C/hub/scripts/"
cp "$R/hub/odoo/apply-down-publication.sql" "$R/hub/odoo/down-sequence-state.sql" "$C/hub/odoo/"
cp "$R/clinic/odoo/apply-odoo-sequence-striding.sql" "$R/clinic/odoo/apply-master-sequence-striding.sql" "$C/clinic/odoo/"
cp "$R/clinic/scripts/setup-mirrormaker.sh" "$C/clinic/scripts/"
cp "$R/clinic/config/mirrormaker/mm2.properties.template" "$C/clinic/config/mirrormaker/"
words(){ tr '\n' ' ' | sed 's/ $//'; }
has(){ case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# --- the list --------------------------------------------------------------------
got="$(bash "$C/sync/hub-down.sh" odoo | words)"
[ "$got" = "$WANT" ] && ok_ "sync/hub-down.conf holds exactly the eleven master tables and the central-transfer tables" || bad "the down list reads [$got], want [$WANT]"
for t in $TRANSFER; do has "$got" "$t" || bad "the down list lacks transfer table $t"; done
has "$got" stock_quant && bad "stock levels go down" || ok_ "stock levels (stock_quant) stay up-only while transfers go down"
for t in $UP_ONLY; do has "$got" "$t" && bad "the down list carries up-only $t"; done
[ "$(bash "$C/sync/hub-down.sh" clinlims | words)" = "system_user result analysis sample" ] && ok_ "of the OpenELIS tables only the lab accounts, result, analysis and sample go down" || bad "the OpenELIS down rows read [$(bash "$C/sync/hub-down.sh" clinlims 2>&1 | words)]"
[ "$(bash "$C/sync/hub-down.sh" --subsystems | words)" = "odoo clinlims" ] && ok_ "Odoo and OpenELIS send down" || bad "subsystems sending down: $(bash "$C/sync/hub-down.sh" --subsystems | words)"
plant(){ # LINE : the reader on the list with LINE added -> its output; rc in $prc
  { cat "$R/sync/hub-down.conf"; printf '%s\n' "$1"; } > "$C/sync/hub-down.conf"
  pout="$(bash "$C/sync/hub-down.sh" odoo 2>&1)"; prc=$?
  cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"; }
n=0
for t in $UP_ONLY; do
  plant "odoo:$t"
  if [ "$prc" != 0 ] && printf '%s' "$pout" | grep -q "odoo:$t is written at the clinics and never goes down" && ! printf '%s' "$pout" | grep -qx product_template; then n=$((n+1))
  else bad "planted odoo:$t: rc=$prc $pout"; fi
done
[ "$n" = 7 ] && ok_ "each of the seven up-only Odoo tables planted in the list is refused by name, and nothing is printed"
plant "clinlims:sample_item:clinic=id"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:sample_item is written at the clinics and never goes down' && ok_ "an OpenELIS table a hub lab user does not complete, planted in the list, is refused" || bad "planted clinlims:sample_item: rc=$prc $pout"
plant "odoo:ir_config_parameter"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'odoo:ir_config_parameter is not a synced table' && ok_ "a table that is not synced is refused" || bad "planted ir_config_parameter: rc=$prc $pout"
plant "odoo:uom_uom"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'odoo:uom_uom is listed twice' && ok_ "a table listed twice is refused" || bad "planted duplicate: rc=$prc $pout"

# --- the hub Odoo source, as register-odoo.sh renders it -------------------------
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
cat > "$FAKE_BODY"; echo PUT >> "$FAKE_BODY.log"; printf '\n201'
SH
chmod +x "$T/bin/curl"
printf 'ODOO_DB_PASSWORD=x\nREMOTE_SERVER_NAME=bahmni-cloud\n' > "$C/hub/.env"
reg(){ rm -f "$T/body" "$T/body.log"; rout="$(PATH="$T/bin:$PATH" FAKE_BODY="$T/body" NODE=cloud bash "$C/hub/connectors/register-odoo.sh" odoo-cloud-source 2>&1)"; rrc=$?; }
reg
inc="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(" ".join(t.split(".",1)[1] for t in c["table.include.list"].split(",")))' "$T/body" 2>/dev/null)"
agg="$(python3 -c 'import json,re,sys; c=json.load(open(sys.argv[1])); print(" ".join(re.search(r"\(([^()]*)\)\$$", c["transforms.agg.regex"]).group(1).split("|")))' "$T/body" 2>/dev/null)"
[ "$rrc" = 0 ] && [ "$inc" = "$WANT dbz_heartbeat" ] && ok_ "the rendered hub source captures exactly the down list and its heartbeat table" || bad "rendered table.include.list: rc=$rrc [$inc] $rout"
[ "$agg" = "$WANT" ] && ok_ "the rendered hub source's aggregate regex is exactly the down list" || bad "rendered aggregate regex: [$agg]"
for t in $UP_ONLY; do has "$inc $agg" "$t" && bad "the rendered hub source carries up-only $t"; done
python3 - "$C/hub/connectors/odoo-cloud-source.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); c = d['config']
c['table.include.list'] = c['table.include.list'] + ',public.res_partner'
json.dump(d, open(sys.argv[1], 'w'))
PY
reg
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'table.include.list differs from the down list (not down tables: res_partner' && [ ! -s "$T/body.log" ] \
  && ok_ "a template that adds res_partner to the hub source is refused, and nothing is registered" || bad "edited template: rc=$rrc $rout"
cp "$R/hub/connectors/odoo-cloud-source.json" "$C/hub/connectors/"
plant "odoo:sale_order"; { cat "$R/sync/hub-down.conf"; echo odoo:sale_order; } > "$C/sync/hub-down.conf"
reg
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'nothing was registered' && [ ! -s "$T/body.log" ] \
  && ok_ "a down list carrying sale_order stops the hub source's registration" || bad "planted list at registration: rc=$rrc $rout"
cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"

# --- the clinic MirrorMaker --------------------------------------------------------
printf 'BHS_LOCATION=testclinic\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example:9092\nMYSQL_SERVER_NAME=bahmni-test\nREMOTE_SERVER_NAME=bahmni-cloud\n' > "$C/clinic/.env"
mm(){ rm -f "$C/clinic/config/mirrormaker/mm2.properties"; mout="$(bash "$C/clinic/scripts/setup-mirrormaker.sh" 2>&1)"; mrc=$?; }
if command -v envsubst >/dev/null 2>&1; then
  mm
  P="$C/clinic/config/mirrormaker/mm2.properties"
  down="$(sed -n 's/^remote->[a-z_]*\.topics = //p' "$P" 2>/dev/null | tr -d '()\\' | tr '|' '\n')"
  up="$(sed -n 's/^[a-z_]*->remote\.topics = //p' "$P" 2>/dev/null | tr -d '()\\' | tr '|' '\n')"
  dsub="$(printf '%s\n' "$down" | grep -E '^bahmni-cloud\.(odoo|clinlims)\.' | sed 's/^bahmni-cloud\.//' | words)"
  wsub="odoo.all clinlims.all $(printf '%s\n' $WANT | sed 's/^/odoo./' | words) clinlims.system_user clinlims.result clinlims.analysis clinlims.sample"
  # All Odoo traffic rides the aggregate topic, which carries only what the
  # publication sends; the per-table names are listed for parity with the up
  # regex and match no topic. What this guards is that the regex is rendered
  # from the down list, and so names no up-only table.
  [ "$mrc" = 0 ] && [ "$dsub" = "$wsub" ] && ok_ "the clinic MirrorMaker down regex is rendered from the down list: the Odoo and OpenELIS aggregates and the list's names, nothing else" || bad "MirrorMaker down topics: rc=$mrc [$dsub] want [$wsub] $(printf '%s' "$mout" | tail -2)"
  printf '%s\n' "$down" | grep -q '^bahmni-cloud\.openmrs\.' && ok_ "the MirrorMaker down regex still carries the hub's OpenMRS tables" || bad "no OpenMRS topic in the down regex"
  for t in $UP_ONLY; do printf '%s\n' "$down" | grep -qx "bahmni-cloud.odoo.$t" && bad "the MirrorMaker down regex carries up-only $t"; done
  printf '%s\n' "$down" | grep -E '^bahmni-cloud\.clinlims\.' | grep -vqxE 'bahmni-cloud\.clinlims\.(all|system_user|result|analysis|sample)' && bad "the MirrorMaker down regex carries an OpenELIS topic other than the four down rows and their aggregate" || ok_ "of the OpenELIS topics only the aggregate and the four down rows come down"
  usub="$(printf '%s\n' "$up" | grep -cE '^bahmni-test\.(odoo|clinlims)\.')"
  nsub=$(( $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | grep -cE '^(odoo|clinlims):') ))
  [ "$usub" = "$nsub" ] && ok_ "the up regex still carries every synced Odoo and OpenELIS topic ($nsub: every table and the two aggregates)" || bad "up regex carries $usub subsystem topics, want $nsub"
  { cat "$R/sync/hub-down.conf"; echo odoo:stock_quant; } > "$C/sync/hub-down.conf"; mm
  [ "$mrc" != 0 ] && printf '%s' "$mout" | grep -q 'odoo:stock_quant is written at the clinics' && ok_ "a down list carrying stock_quant stops the MirrorMaker render" || bad "planted list at MirrorMaker: rc=$mrc $mout"
  cp "$R/sync/hub-down.conf" "$C/sync/hub-down.conf"
else
  printf '  skip envsubst is not here; the MirrorMaker render was not run\n'
fi

# --- the floors file ------------------------------------------------------------------
F="$T/floors"
printf 'product_template 4520\nuom_uom 40\n' > "$F"
[ "$(bash "$C/hub/scripts/down-floors.sh" "$F" | words)" = "product_template 4520 uom_uom 40" ] && ok_ "a floors file reads back as written" || bad "floors read: $(bash "$C/hub/scripts/down-floors.sh" "$F" 2>&1)"
fl(){ printf '%s\n' "$1" > "$F"; fout="$(bash "$C/hub/scripts/down-floors.sh" "$F" 2>&1)"; frc=$?; }
fl 'res_partner 100'; [ "$frc" != 0 ] && printf '%s' "$fout" | grep -q 'res_partner is not a table the hub sends down' && ok_ "a floor for an up-only table is refused" || bad "floor for res_partner: $fout"
fl 'uom_uom 45';      [ "$frc" != 0 ] && printf '%s' "$fout" | grep -q 'not a multiple of 10' && ok_ "a floor off residue 0 is refused" || bad "floor 45: $fout"
fl 'uom_uom';         [ "$frc" != 0 ] && printf '%s' "$fout" | grep -q "is not '<table> <floor>'" && ok_ "a line without a floor is refused" || bad "no floor: $fout"
fl 'uom_uom 040';     [ "$frc" != 0 ] && printf '%s' "$fout" | grep -q 'without leading zeros' && ok_ "a floor with a leading zero is refused" || bad "floor 040: $fout"
fl 'uom_uom 0';       [ "$frc" != 0 ] && ok_ "a floor of 0 is refused" || bad "floor 0: $fout"
bash "$C/hub/scripts/down-floors.sh" "$T/none" >/dev/null 2>&1 && bad "a missing floors file read as empty" || ok_ "a missing floors file is refused"

# --- a real PostgreSQL 16 --------------------------------------------------------------
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do i=$((i+1)); [ "$i" -gt 20 ] && { kill "$p" 2>/dev/null; return 1; }; sleep 1; done
  wait "$p"
}
IMG=postgres:16
if ! docker_answers || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  printf '  skip docker with %s is not here; the publication was not built on a server\n' "$IMG"
  exit $((fails > 0))
fi
PGC="hub-down-test-$$"
docker run -d --name "$PGC" --tmpfs /var/lib/postgresql/data -e POSTGRES_PASSWORD=x "$IMG" -c wal_level=logical >/dev/null 2>&1 || { bad "could not start $IMG"; exit 1; }
for i in $(seq 1 60); do docker exec "$PGC" pg_isready -U postgres -q >/dev/null 2>&1 && docker exec "$PGC" psql -U postgres -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
PSQL="docker exec -i $PGC psql -U postgres -d odoo"
docker exec "$PGC" createdb -U postgres odoo
# the Odoo shapes: a serial id and primary key on every synced table but the
# link tables, which have composite keys; 37 rows each, issued at increment 1
# as on an unstrided hub; a publication that once held an up-only table
{
  for t in $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | sed -n 's/^odoo://p' | grep -vx all); do
    case "$t" in
      product_taxes_rel|product_supplier_taxes_rel) printf 'CREATE TABLE %s (prod_id int, tax_id int, PRIMARY KEY (prod_id, tax_id));\n' "$t" ;;
      stock_route_product) printf 'CREATE TABLE %s (route_id int, product_id int, PRIMARY KEY (route_id, product_id));\n' "$t" ;;
      *) printf 'CREATE TABLE %s (id serial PRIMARY KEY, name text);\nINSERT INTO %s (name) SELECT %s FROM generate_series(1, 37) g;\n' "$t" "$t" "'r' || g" ;;
    esac
  done
  printf 'CREATE TABLE dbz_heartbeat (id int PRIMARY KEY, ts timestamptz);\n'
  printf 'CREATE PUBLICATION dbz_odoo_owned FOR TABLE res_partner, product_template;\n'
} | $PSQL -q -v ON_ERROR_STOP=1 >/dev/null || bad "fixture schema refused"
pubtables(){ $PSQL -Atc "select tablename || ':' || coalesce(rowfilter, '-') from pg_publication_tables where pubname = 'dbz_odoo_owned'" | LC_ALL=C sort | words; }
seqinc(){ $PSQL -Atc "select increment_by from pg_sequences where sequencename = '$1_id_seq'"; }
FL="$T/hub-floors.local"
stride(){ sout="$(bash "$C/hub/scripts/stride-odoo.sh" --floors "$FL" -- $PSQL 2>&1)"; src=$?; }
W8="product_template 40 product_product 40 product_category 40 uom_uom 40 res_country_state 1010 state_district 40 district_subdistrict 40 village_village 40 stock_location 40 stock_warehouse 40 stock_picking_type 40 stock_route 40 stock_rule 40 procurement_group 40 stock_lot 40 stock_warehouse_orderpoint 40 stock_picking 40 stock_move 40 stock_move_line 40"

# a clinic's rows have reached this hub: no first recording, nothing strided
$PSQL -q -v ON_ERROR_STOP=1 -c "SELECT pg_replication_origin_create('clinic_t_odoo'); SELECT pg_replication_origin_advance('clinic_t_odoo', '0/1000');" >/dev/null
stride
[ "$src" != 0 ] && printf '%s' "$sout" | grep -q "1 clinic replication origin(s) show progress" && [ ! -e "$FL" ] && [ "$(seqinc product_template)" = 1 ] \
  && ok_ "with a clinic's origin showing progress, no floor is recorded and nothing is strided" || bad "clinic progress: rc=$src $sout"
$PSQL -q -c "SELECT pg_replication_origin_drop('clinic_t_odoo')" >/dev/null

# the striding run records each restart value as it happens
stride
[ "$src" = 0 ] && [ "$(cat "$FL" 2>/dev/null | words)" = "$W8" ] && [ "$(seqinc product_template)" = 10 ] && [ "$(seqinc sale_order)" = 10 ] \
  && ok_ "the striding run strides every synced table and records a floor for every down table with an id at its restart value (res_country_state from the master step)" || bad "first stride: rc=$src [$(cat "$FL" 2>/dev/null | words)] $sout"
# the hub issues ids, then the step runs again: strided forward, floors kept
$PSQL -q -v ON_ERROR_STOP=1 -c "INSERT INTO product_product (name) VALUES ('hub 1'), ('hub 2')" >/dev/null
stride
nxt="$($PSQL -Atc "select last_value from product_product_id_seq")"
[ "$src" = 0 ] && printf '%s' "$sout" | grep -q 'floors kept' && [ "$(cat "$FL" | words)" = "$W8" ] && [ "$nxt" = 60 ] \
  && ok_ "a re-run after the hub issued ids strides forward (product_product restarts at 60) and leaves every recorded floor as it was" || bad "re-stride: rc=$src next=$nxt [$(cat "$FL" | words)] $sout"

# a strided hub without its floors file: a first recording is refused, nothing strided
mv "$FL" "$T/fl.kept"
stride
[ "$src" != 0 ] && printf '%s' "$sout" | grep -q "no floors file at $FL, and this hub's ids were strided before: product_template (steps by 10)" \
  && printf '%s' "$sout" | grep -q 'record-down-floors.sh --from-file' && [ ! -e "$FL" ] && [ "$($PSQL -Atc "select last_value from product_product_id_seq")" = 60 ] \
  && ok_ "on a hub strided before, with no floors file, no floor is recorded and nothing is strided; the message names --from-file" || bad "strided, no file: rc=$src $sout"
mv "$T/fl.kept" "$FL"

# --from-file: the values captured when the hub was strided, checked against it
rm -f "$T/rec"; printf '%s\n' $W8 | paste -d' ' - - > "$T/from"; rout="$(bash "$C/hub/scripts/record-down-floors.sh" --from-file "$T/from" --out "$T/rec" -- $PSQL 2>&1)"; rrc=$?
[ "$rrc" = 0 ] && [ "$(cat "$T/rec" | words)" = "$W8" ] && ok_ "--from-file records the captured values once they check against the sequences" || bad "from-file: rc=$rrc $rout"
rout="$(bash "$C/hub/scripts/record-down-floors.sh" --from-file "$T/from" --out "$T/rec" -- $PSQL 2>&1)"; rrc=$?
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'already exists' && ok_ "--from-file never rewrites a floors file" || bad "from-file rewrite: rc=$rrc $rout"
rm -f "$T/rec"; sed 's/^product_template 40$/product_template 9990/' "$T/from" > "$T/from2"
rout="$(bash "$C/hub/scripts/record-down-floors.sh" --from-file "$T/from2" --out "$T/rec" -- $PSQL 2>&1)"; rrc=$?
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'the floor given for product_template, 9990, is above the id its sequence issues next' && [ ! -e "$T/rec" ] \
  && ok_ "--from-file refuses a floor above where its sequence stands" || bad "from-file too high: rc=$rrc $rout"
grep -v '^uom_uom ' "$T/from" > "$T/from2"
rout="$(bash "$C/hub/scripts/record-down-floors.sh" --from-file "$T/from2" --out "$T/rec" -- $PSQL 2>&1)"; rrc=$?
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'gives no floor for uom_uom' && [ ! -e "$T/rec" ] && ok_ "--from-file refuses a missing table" || bad "from-file missing: rc=$rrc $rout"
{ cat "$T/from"; echo 'product_taxes_rel 10'; } > "$T/from2"
rout="$(bash "$C/hub/scripts/record-down-floors.sh" --from-file "$T/from2" --out "$T/rec" -- $PSQL 2>&1)"; rrc=$?
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'floor for product_taxes_rel, which has no id column' && ok_ "--from-file refuses a floor for a link table" || bad "from-file link: rc=$rrc $rout"
bash "$C/hub/scripts/record-down-floors.sh" --out "$T/rec" -- $PSQL >/dev/null 2>&1 && bad "floors were recorded without --from-file" || ok_ "floors cannot be recorded without --from-file (never read back from the sequences)"

# the database went back below a floor: refused before anything is strided
$PSQL -q -v ON_ERROR_STOP=1 -c "DELETE FROM uom_uom WHERE id >= 10; SELECT setval('uom_uom_id_seq', 1, false);" >/dev/null
stride
[ "$src" != 0 ] && printf '%s' "$sout" | grep -q 'uom_uom would restart at 10, below its recorded floor 40' && [ "$(cat "$FL" | words)" = "$W8" ] \
  && [ "$($PSQL -Atc "select last_value from product_product_id_seq")" = 60 ] \
  && ok_ "a re-run that would restart a sequence below its floor is refused before striding, the file unchanged" || bad "restart below floor: rc=$src $sout"
grep -v '^village_village ' "$FL" > "$T/fl7"; cp "$FL" "$T/fl8"; cp "$T/fl7" "$FL"
$PSQL -q -c "SELECT setval('uom_uom_id_seq', 40, false)" >/dev/null
stride
[ "$src" != 0 ] && printf '%s' "$sout" | grep -q 'records no floor for village_village' && ok_ "a floors file missing a down table is refused, not completed" || bad "incomplete file: rc=$src $sout"
cp "$T/fl8" "$FL"

# the publication
before="$(pubtables)"
printf 'product_template 40\nproduct_product 40\n' > "$T/short"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$T/short" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'no floor recorded for product_category' && [ "$(pubtables)" = "$before" ] \
  && ok_ "a missing floor is refused, naming the table, and the publication is untouched" || bad "missing floor: rc=$rc $out"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
got="$(pubtables)"
f(){ printf '%s:((id < %s) OR ((id %% 10) = 0))' "$1" "$2"; }
want="$( { printf '%s\n' dbz_heartbeat:- "$(f district_subdistrict 40)" "$(f product_category 40)" product_supplier_taxes_rel:- product_taxes_rel:- "$(f product_product 40)" "$(f product_template 40)" "$(f res_country_state 1010)" "$(f state_district 40)" stock_route_product:- "$(f uom_uom 40)" "$(f village_village 40)"; for t in $TRANSFER; do f "$t" 40; echo; done; } | LC_ALL=C sort | words)"
[ "$rc" = 0 ] && [ "$got" = "$want" ] && ok_ "dbz_odoo_owned holds exactly the down list and the heartbeat, each table with an id filtered on its floor" || bad "publication: rc=$rc
    got  $got
    want $want
    $out"
case " $got " in *" res_partner:"*) bad "res_partner stayed in the publication" ;; *) ok_ "a table the publication held before and the list does not (res_partner) is gone" ;; esac
[ "$($PSQL -Atc "select pubinsert::text || pubupdate::text || pubdelete::text || pubtruncate::text from pg_publication where pubname = 'dbz_odoo_owned'")" = truetruetruefalse ] \
  && ok_ "the publication publishes insert, update and delete, never truncate (which ignores row filters)" || bad "publish flags: $($PSQL -Atc "select pubinsert, pubupdate, pubdelete, pubtruncate from pg_publication where pubname = 'dbz_odoo_owned'")"
$PSQL -q -v ON_ERROR_STOP=1 -c "UPDATE product_template SET name = 'x' WHERE id = 3; DELETE FROM uom_uom WHERE id = 7; DELETE FROM product_taxes_rel;" >/dev/null 2>&1 \
  && ok_ "the hub can still UPDATE and DELETE filtered tables (the primary key covers id)" || bad "UPDATE/DELETE refused on a filtered table"
# what logical decoding sends through the publication
$PSQL -q -c "SELECT pg_create_logical_replication_slot('t_down', 'pgoutput')" >/dev/null
$PSQL -q -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
UPDATE product_template SET name = 'legacy edit' WHERE id = 23;      -- legacy row, below the floor
INSERT INTO product_template (id, name) VALUES (50, 'hub minted');   -- residue 0, above the floor
INSERT INTO product_template (id, name) VALUES (44, 'clinic minted'); -- residue 4, above the floor
UPDATE product_template SET name = 'hub edits clinic row' WHERE id = 44;
INSERT INTO res_partner (id, name) VALUES (60, 'hub partner');       -- up-only table
DELETE FROM product_template WHERE id = 44;                          -- the clinic's row
DELETE FROM product_template WHERE id = 23;                          -- the legacy row
SQL
msgs="$($PSQL -Atc "select string_agg(chr(get_byte(data, 0)), '' order by lsn) from pg_logical_slot_get_binary_changes('t_down', NULL, NULL, 'proto_version', '1', 'publication_names', 'dbz_odoo_owned') where chr(get_byte(data, 0)) in ('I', 'U', 'D')")"
[ "$msgs" = UID ] && ok_ "decoded through the publication: the legacy row's update and delete and the hub's row are sent; the clinic's row (insert, update, delete) and a partner are not" || bad "decoded row messages '$msgs', want UID"
$PSQL -q -c "SELECT pg_drop_replication_slot('t_down')" >/dev/null
# a table with an id whose replica identity does not cover it
$PSQL -q -v ON_ERROR_STOP=1 -c "ALTER TABLE uom_uom DROP CONSTRAINT uom_uom_pkey" >/dev/null
before="$(pubtables)"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'uom_uom: its replica identity (relreplident d) does not cover id' && [ "$(pubtables)" = "$before" ] \
  && ok_ "a filtered table whose replica identity does not cover id is refused before the publication changes" || bad "replica identity: rc=$rc $out"
exit $((fails > 0))
