#!/usr/bin/env bash
# The hub sends down only master tables, and every artefact that sends tables
# down is rendered from one list, sync/hub-down.conf:
#   - the reader (sync/hub-down.sh) prints exactly the eleven master tables and
#     refuses, by name, every up-only table planted in the list;
#   - the hub Odoo source, rendered by register-odoo.sh, carries exactly that
#     list, and a template edited to carry anything else is refused before any
#     registration;
#   - the clinic MirrorMaker's down regex carries the list's Odoo topics, no
#     up-only table and no OpenELIS topic, while its up regex still carries them all;
#   - on a real PostgreSQL 16 (when docker and the image are here): the floors
#     are read from the strided sequences once, the publication holds exactly
#     the list with (id < floor OR id % 10 = 0) on each table with an id, a
#     missing floor or a replica identity that does not cover id is refused
#     before the publication changes, and logical decoding through the
#     publication sends a legacy row and a hub row but not a clinic's row.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
UP_ONLY="res_partner res_partner_attributes sale_order sale_order_line account_move account_move_line stock_move stock_picking stock_quant"
WANT="product_template product_product product_category uom_uom res_country_state state_district district_subdistrict village_village product_taxes_rel product_supplier_taxes_rel stock_route_product"
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
cp "$R/hub/scripts/down-floors.sh" "$R/hub/scripts/record-down-floors.sh" "$R/hub/scripts/apply-down-publication.sh" "$C/hub/scripts/"
cp "$R/hub/odoo/apply-down-publication.sql" "$R/hub/odoo/read-down-floors.sql" "$C/hub/odoo/"
cp "$R/clinic/scripts/setup-mirrormaker.sh" "$C/clinic/scripts/"
cp "$R/clinic/config/mirrormaker/mm2.properties.template" "$C/clinic/config/mirrormaker/"
words(){ tr '\n' ' ' | sed 's/ $//'; }
has(){ case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# --- the list --------------------------------------------------------------------
got="$(bash "$C/sync/hub-down.sh" odoo | words)"
[ "$got" = "$WANT" ] && ok_ "sync/hub-down.conf holds exactly the eleven master tables" || bad "the down list reads [$got], want [$WANT]"
for t in $UP_ONLY; do has "$got" "$t" && bad "the down list carries up-only $t"; done
bash "$C/sync/hub-down.sh" clinlims >/dev/null 2>&1 && bad "the down list has OpenELIS rows" || ok_ "no OpenELIS table goes down"
[ "$(bash "$C/sync/hub-down.sh" --subsystems | words)" = odoo ] && ok_ "only Odoo sends anything down" || bad "subsystems sending down: $(bash "$C/sync/hub-down.sh" --subsystems | words)"
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
[ "$n" = 9 ] && ok_ "each of the nine up-only Odoo tables planted in the list is refused by name, and nothing is printed"
plant "clinlims:sample"
[ "$prc" != 0 ] && printf '%s' "$pout" | grep -q 'clinlims:sample: no OpenELIS table goes down' && ok_ "an OpenELIS table planted in the list is refused" || bad "planted clinlims:sample: rc=$prc $pout"
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
  wsub="odoo.all $(printf '%s\n' $WANT | sed 's/^/odoo./' | words)"
  [ "$mrc" = 0 ] && [ "$dsub" = "$wsub" ] && ok_ "the clinic MirrorMaker takes down exactly the Odoo aggregate and the down list's topics" || bad "MirrorMaker down topics: rc=$mrc [$dsub] want [$wsub] $(printf '%s' "$mout" | tail -2)"
  printf '%s\n' "$down" | grep -q '^bahmni-cloud\.openmrs\.' && ok_ "the MirrorMaker down regex still carries the hub's OpenMRS tables" || bad "no OpenMRS topic in the down regex"
  for t in $UP_ONLY; do printf '%s\n' "$down" | grep -qx "bahmni-cloud.odoo.$t" && bad "the MirrorMaker down regex carries up-only $t"; done
  printf '%s\n' "$down" | grep -q 'clinlims' && bad "the MirrorMaker down regex carries an OpenELIS topic" || ok_ "no OpenELIS topic comes down"
  usub="$(printf '%s\n' "$up" | grep -cE '^bahmni-test\.(odoo|clinlims)\.')"
  [ "$usub" = 26 ] && ok_ "the up regex still carries every synced Odoo and OpenELIS topic (20 + 4 tables, 2 aggregates)" || bad "up regex carries $usub subsystem topics, want 26"
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
# the Odoo shapes: serial id + primary key on the master tables, composite keys on
# the link tables, an up-only table the publication once held, the heartbeat table
{
  for t in product_template product_product product_category uom_uom res_country_state state_district district_subdistrict village_village res_partner; do
    printf 'CREATE TABLE %s (id serial PRIMARY KEY, name text);\nINSERT INTO %s (name) SELECT %s FROM generate_series(1, 37) g;\n' "$t" "$t" "'r' || g"
  done
  printf 'CREATE TABLE product_taxes_rel (prod_id int, tax_id int, PRIMARY KEY (prod_id, tax_id));\n'
  printf 'CREATE TABLE product_supplier_taxes_rel (prod_id int, tax_id int, PRIMARY KEY (prod_id, tax_id));\n'
  printf 'CREATE TABLE stock_route_product (route_id int, product_id int, PRIMARY KEY (route_id, product_id));\n'
  printf 'CREATE TABLE dbz_heartbeat (id int PRIMARY KEY, ts timestamptz);\n'
  printf 'CREATE PUBLICATION dbz_odoo_owned FOR TABLE res_partner, product_template;\n'
} | $PSQL -q -v ON_ERROR_STOP=1 >/dev/null || bad "fixture schema refused"
pubtables(){ $PSQL -Atc "select tablename || ':' || coalesce(rowfilter, '-') from pg_publication_tables where pubname = 'dbz_odoo_owned'" | LC_ALL=C sort | words; }

# floors before striding: refused, nothing written
FL="$T/hub-floors.local"
out="$(bash "$C/hub/scripts/record-down-floors.sh" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'steps by 1, not 10' && [ ! -e "$FL" ] && ok_ "floors are refused before the ids are strided, and no file is written" || bad "unstrided floors: rc=$rc $out"
# stride as the hub does (residue 0): restart at the first multiple of 10 above max(id)
$PSQL -q -v ON_ERROR_STOP=1 -c "DO \$\$ DECLARE t text; BEGIN FOREACH t IN ARRAY string_to_array('product_template,product_product,product_category,uom_uom,res_country_state,state_district,district_subdistrict,village_village,res_partner', ',') LOOP EXECUTE format('ALTER SEQUENCE %I INCREMENT BY 10 RESTART WITH 40', t || '_id_seq'); END LOOP; END \$\$;" >/dev/null
$PSQL -q -c "SELECT setval('res_country_state_id_seq', 1010, false)" >/dev/null
out="$(bash "$C/hub/scripts/record-down-floors.sh" --out "$FL" -- $PSQL 2>&1)"; rc=$?
fl8="$(cat "$FL" 2>/dev/null | words)"
[ "$rc" = 0 ] && [ "$fl8" = "product_template 40 product_product 40 product_category 40 uom_uom 40 res_country_state 1010 state_district 40 district_subdistrict 40 village_village 40" ] \
  && ok_ "the floors are read from the strided sequences: eight tables with an id, none for the link tables" || bad "recorded floors: rc=$rc [$fl8] $out"
out="$(bash "$C/hub/scripts/record-down-floors.sh" --out "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'already exists' && [ "$(cat "$FL" | words)" = "$fl8" ] && ok_ "the floors file is never rewritten" || bad "second record: rc=$rc $out"

# the publication
before="$(pubtables)"
printf 'product_template 40\nproduct_product 40\n' > "$T/short"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$T/short" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'no floor recorded for product_category' && [ "$(pubtables)" = "$before" ] \
  && ok_ "a missing floor is refused, naming the table, and the publication is untouched" || bad "missing floor: rc=$rc $out"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
got="$(pubtables)"
f(){ printf '%s:((id < %s) OR ((id %% 10) = 0))' "$1" "$2"; }
want="$(printf '%s\n' dbz_heartbeat:- "$(f district_subdistrict 40)" "$(f product_category 40)" product_supplier_taxes_rel:- product_taxes_rel:- "$(f product_product 40)" "$(f product_template 40)" "$(f res_country_state 1010)" "$(f state_district 40)" stock_route_product:- "$(f uom_uom 40)" "$(f village_village 40)" | LC_ALL=C sort | words)"
[ "$rc" = 0 ] && [ "$got" = "$want" ] && ok_ "dbz_odoo_owned holds exactly the down list and the heartbeat, each table with an id filtered on its floor" || bad "publication: rc=$rc
    got  $got
    want $want
    $out"
case " $got " in *" res_partner:"*) bad "res_partner stayed in the publication" ;; *) ok_ "a table the publication held before and the list does not (res_partner) is gone" ;; esac
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
SQL
msgs="$($PSQL -Atc "select string_agg(chr(get_byte(data, 0)), '' order by lsn) from pg_logical_slot_get_binary_changes('t_down', NULL, NULL, 'proto_version', '1', 'publication_names', 'dbz_odoo_owned') where chr(get_byte(data, 0)) in ('I', 'U', 'D')")"
[ "$msgs" = UI ] && ok_ "decoded through the publication: the legacy edit and the hub's row are sent; the clinic's row, the hub's edit of it, and a partner are not" || bad "decoded row messages '$msgs', want UI"
$PSQL -q -c "SELECT pg_drop_replication_slot('t_down')" >/dev/null
# a table with an id whose replica identity does not cover it
$PSQL -q -v ON_ERROR_STOP=1 -c "ALTER TABLE uom_uom DROP CONSTRAINT uom_uom_pkey" >/dev/null
before="$(pubtables)"
out="$(bash "$C/hub/scripts/apply-down-publication.sh" "$FL" -- $PSQL 2>&1)"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'uom_uom: its replica identity (relreplident d) does not cover id' && [ "$(pubtables)" = "$before" ] \
  && ok_ "a filtered table whose replica identity does not cover id is refused before the publication changes" || bad "replica identity: rc=$rc $out"
exit $((fails > 0))
