#!/usr/bin/env bash
# The clinic's two Odoo filters:
#   - own rows up: the clinic's Odoo source publishes a row of a table the hub
#     sends down only when the clinic minted it (id at or above the clinic's
#     floor, on its residue); the transfer tables, which the clinic completes
#     for the hub, and the link tables pass whole, as does every up-only table.
#     The step comes first, while the topic still names the table; installer
#     task 060 records the floors before it strides (state.sh
#     record_odoo_floors), task 090 writes the condition from them
#     (clinic/scripts/odoo-up-filter.sh) and stops without them;
#   - transfers down: the clinic's Odoo down sink keeps a stock transfer row
#     only when it goes to one of the locations of the clinic's warehouse,
#     ODOO_WAREHOUSE, read from the clinic's Odoo database
#     (clinic/scripts/odoo-down-filter.sh); every other record, and every
#     delete, is kept; with no warehouse no transfer is kept;
#   - the clinic's register-odoo.sh refuses either connector without its
#     condition.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$R/sync/local/tables-conf.sh"
cfg(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("config") or d).get(sys.argv[2], "<absent>"))' "$1" "$2"; }
DOWN="$(bash "$R/sync/hub-down.sh" odoo | tr '\n' ' ')"
for t in $UP_ODOO_SHARED_ROWS $UP_ODOO_LINK_TABLES; do
  case " $DOWN " in *" $t "*) ;; *) bad "$t is named in sync/local/tables-conf.sh but is not an Odoo down table" ;; esac
done
[ "$UP_ODOO_SHARED_ROWS" = "stock_picking stock_move stock_move_line" ] && ok_ "the tables written by the hub and completed at a clinic: the three transfer tables" || bad "UP_ODOO_SHARED_ROWS is '$UP_ODOO_SHARED_ROWS'"
OWN=""; for t in $DOWN; do case " $UP_ODOO_SHARED_ROWS $UP_ODOO_LINK_TABLES " in *" $t "*) ;; *) OWN="$OWN $t" ;; esac; done
for t in sale_shop product_pricelist product_template stock_location; do case " $OWN " in *" $t "*) ;; *) bad "$t is not published by its own rows" ;; esac; done

# --- the source step -------------------------------------------------------------------
SRC="$R/clinic/connectors/odoo-source-connector.json"
[ "$(cfg "$SRC" transforms)" = "ownRows,route,agg" ] && ok_ "the source's steps: the own-rows filter first, then the two that route every table into the one topic" || bad "transforms: $(cfg "$SRC" transforms)"
got="$(cfg "$SRC" transforms.ownRows.type)|$(cfg "$SRC" transforms.ownRows.language)|$(cfg "$SRC" transforms.ownRows.condition)|$(cfg "$SRC" transforms.ownRows.null.handling.mode)|$(cfg "$SRC" transforms.ownRows.predicate)"
[ "$got" = 'io.debezium.transforms.Filter|jsr223.groovy|${ODOO_UP_CONDITION}|evaluate|<absent>' ] \
  && ok_ "own-rows: a Groovy Filter over every topic, tombstones judged, its condition filled at registration" || bad "own-rows step: $got"

# --- the condition ---------------------------------------------------------------------
mkdir -p "$T/clinic/scripts"; cp "$R/clinic/scripts/odoo-up-filter.sh" "$R/clinic/scripts/odoo-down-filter.sh" "$T/clinic/scripts/"
floors_env(){ for t in $OWN; do printf 'ODOO_FLOOR_%s=%s\n' "$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')" "$1"; done; }
up(){ uout="$(env -i PATH="$PATH" CLINIC_DIR="$T/clinic" REPO_DIR="$R" "$@" bash "$T/clinic/scripts/odoo-up-filter.sh" 2>&1)"; urc=$?; }
floors_env 4520 > "$T/clinic/.install-state"; : > "$T/clinic/.env"
up RESIDUE=3
[ "$urc" = 0 ] && ok_ "the condition is written from the floors task 060 recorded" || bad "odoo-up-filter: rc=$urc $uout"
for t in $OWN; do case "$uout" in *"'$t': 4520L"*) ;; *) bad "the condition has no floor for $t" ;; esac; done
for t in $UP_ODOO_SHARED_ROWS $UP_ODOO_LINK_TABLES res_partner sale_order stock_quant; do case "$uout" in *"'$t':"*) bad "the condition filters $t" ;; esac; done
ok_ "it names every own-rows table with its floor, and none of the transfer, link or up-only tables"
case "$uout" in "def t = topic.substring(topic.lastIndexOf('.') + 1); def f = ["*"]; !f.containsKey(t) || (key != null && key.get('id') instanceof Number && key.get('id').longValue() >= f[t] && key.get('id').longValue() % 10 == 3)") ok_ "it reads the table from the topic and keeps a key at or above the table's floor on residue 3; any other table passes" ;; *) bad "condition: $uout" ;; esac
up RESIDUE=3 ODOO_FLOOR_SALE_SHOP=90
case "$uout" in *"'sale_shop': 90L"*) ok_ "a floor in the environment wins over the recorded one" ;; *) bad "env floor: $uout" ;; esac
grep -v '^ODOO_FLOOR_SALE_SHOP=' "$T/clinic/.install-state" > "$T/st"; cp "$T/st" "$T/clinic/.install-state"
up RESIDUE=3
[ "$urc" != 0 ] && [ -z "$(printf '%s' "$uout" | grep -v '^odoo-up-filter:')" ] && printf '%s' "$uout" | grep -q 'no Odoo floor for this clinic: ODOO_FLOOR_SALE_SHOP' \
  && ok_ "a missing floor is refused, naming it, and no condition is printed" || bad "missing floor: rc=$urc $uout"
floors_env 4520 > "$T/clinic/.install-state"
up; [ "$urc" != 0 ] && printf '%s' "$uout" | grep -q 'residue (RESIDUE, 1-9) is not set' && ok_ "no residue: refused" || bad "no residue: rc=$urc $uout"
up RESIDUE=3 ODOO_FLOOR_UOM_UOM=45; [ "$urc" != 0 ] && printf '%s' "$uout" | grep -q 'ODOO_FLOOR_UOM_UOM is 45, not a multiple of 10' && ok_ "a floor off residue 0 is refused" || bad "floor 45: rc=$urc $uout"

# --- the floors task 060 records -------------------------------------------------------
cat > "$T/reader" <<'SH'
#!/bin/sh
printf '%s\n' "$1" > "$READER_LOG"
printf 'product_template|4520|4521|10\nsale_shop|40|38|1\n'
SH
chmod +x "$T/reader"
rec(){ rout="$(CLINIC_DIR="$T/c2" REPO_DIR="$R" READER_LOG="$T/rlog" bash -c '. "$1/clinic/install/lib.sh"; . "$1/clinic/install/state.sh"; record_odoo_floors "$2"' _ "$R" "$T/reader" 2>&1)"; rrc=$?; }
mkdir -p "$T/c2"; : > "$T/c2/.install-state"
rec
[ "$rrc" = 0 ] && grep -qx 'ODOO_FLOOR_PRODUCT_TEMPLATE=4520' "$T/c2/.install-state" && grep -qx 'ODOO_FLOOR_SALE_SHOP=40' "$T/c2/.install-state" \
  && printf '%s' "$rout" | grep -q 'ok ODOO_FLOOR_SALE_SHOP=40 (recorded from the sequence before the stride)' && ok_ "060 records each table's restart value as its floor" || bad "record: rc=$rrc $rout"
rl=",$(cat "$T/rlog"),"; miss=""; for t in $DOWN; do case " $UP_ODOO_SHARED_ROWS " in *" $t "*) case "$rl" in *",$t,"*) bad "060 reads a floor for transfer table $t" ;; esac ;; *) case "$rl" in *",$t,"*) ;; *) miss="$miss $t" ;; esac ;; esac; done
[ -z "$miss" ] && ok_ "060 reads the sequences of every own-rows table and none of the transfer tables" || bad "060 does not read:$miss"
printf 'ODOO_FLOOR_SALE_SHOP=10\n' > "$T/c2/.install-state"
rec
[ "$rrc" = 0 ] && grep -qx 'ODOO_FLOOR_SALE_SHOP=10' "$T/c2/.install-state" && ! grep -q 'ODOO_FLOOR_SALE_SHOP=40' "$T/c2/.install-state" && printf '%s' "$rout" | grep -q 'ODOO_FLOOR_SALE_SHOP=10 (kept' \
  && ok_ "a floor recorded before is kept, never moved" || bad "keep: rc=$rrc $rout"
printf 'ODOO_FLOOR_SALE_SHOP=15\n' > "$T/c2/.install-state"
rec
[ "$rrc" != 0 ] && printf '%s' "$rout" | grep -q 'ODOO_FLOOR_SALE_SHOP=15, not a multiple of 10' && ! grep -q 'ODOO_FLOOR_PRODUCT_TEMPLATE' "$T/c2/.install-state" \
  && ok_ "a recorded floor off residue 0 is refused, and nothing is recorded" || bad "bad recorded: rc=$rrc $rout"
blk="$(sed -n '/^# odoo-floors:begin/,/^# odoo-floors:end/p' "$R/clinic/install/tasks/060-striding.sh")"
s060="$R/clinic/install/tasks/060-striding.sh"
[ -n "$blk" ] && printf '%s' "$blk" | grep -q 'record_odoo_floors odoo_seq_state' && printf '%s' "$blk" | grep -q 'down-sequence-state.sql' \
  && [ "$(grep -n 'odoo-floors:end' "$s060" | cut -d: -f1)" -lt "$(grep -n 'apply-odoo-sequence-striding.sql' "$s060" | head -1 | cut -d: -f1)" ] \
  && ok_ "060 records the Odoo floors before it strides the Odoo sequences" || bad "060 order"

# --- the transfer condition ------------------------------------------------------------
SINK="$R/clinic/connectors/odoo-clinic-sink-all.json"
got="$(cfg "$SINK" transforms)|$(cfg "$SINK" transforms.transfersForThisClinic.type)|$(cfg "$SINK" transforms.transfersForThisClinic.language)|$(cfg "$SINK" transforms.transfersForThisClinic.condition)|$(cfg "$SINK" transforms.transfersForThisClinic.null.handling.mode)"
[ "$got" = 'transfersForThisClinic|io.debezium.transforms.Filter|jsr223.groovy|${ODOO_DOWN_CONDITION}|evaluate' ] \
  && ok_ "the down sink carries one Groovy Filter, its condition filled at registration" || bad "down sink step: $got"
cat > "$T/psql" <<'SH'
#!/bin/sh
# answers like psql -At for the two queries odoo-down-filter.sh sends; the warehouse name arrives as -v code=
code=""; for a in "$@"; do case "$a" in code=*) code="${a#code=}" ;; esac; done
cat > /dev/null
case "$code" in
  MNP) printf 'n|1\nl|17\nl|18\nl|23\n' ;;
  TWO) printf 'n|2\n' ;;
  *) printf 'n|0\n' ;;
esac
SH
chmod +x "$T/psql"
dn(){ dout="$(env -i PATH="$PATH" CLINIC_DIR="$T/clinic" "$@" bash "$T/clinic/scripts/odoo-down-filter.sh" -- "$T/psql" 2>"$T/derr")"; drc=$?; derr="$(cat "$T/derr")"; }
dn ODOO_WAREHOUSE=MNP
[ "$drc" = 0 ] && [ "$dout" = "value == null || value.get('op') == 'd' || !(['stock_picking', 'stock_move', 'stock_move_line'].contains(value.get('source').get('table'))) || (value.get('after') != null && value.get('after').get('location_dest_id') instanceof Number && [17L, 18L, 23L].contains(value.get('after').get('location_dest_id').longValue()))" ] \
  && ok_ "with a warehouse: a transfer row is kept when it goes to one of the warehouse's locations; every other table, and every delete, passes" || bad "warehouse condition: rc=$drc $dout $derr"
printf 'ODOO_WAREHOUSE=MNP\n' > "$T/clinic/.env"; dn
case "$dout" in *"[17L, 18L, 23L]"*) ok_ "the warehouse is read from clinic/.env" ;; *) bad "from .env: rc=$drc $dout $derr" ;; esac
: > "$T/clinic/.env"; dn
[ "$drc" = 0 ] && case "$dout" in *" && [].contains("*) true ;; *) false ;; esac && printf '%s' "$derr" | grep -q 'keeps no stock transfer' \
  && ok_ "with no warehouse no transfer is kept, and a note says so" || bad "no warehouse: rc=$drc $dout $derr"
dn ODOO_WAREHOUSE=ZZZ; [ "$drc" != 0 ] && [ -z "$dout" ] && printf '%s' "$derr" | grep -q 'no warehouse with the short name ZZZ' && ok_ "a warehouse this clinic does not have is refused, naming it, and nothing is printed" || bad "unknown warehouse: rc=$drc $dout $derr"
dn ODOO_WAREHOUSE=TWO; [ "$drc" != 0 ] && printf '%s' "$derr" | grep -q "'2' warehouses with the short name TWO" && ok_ "a short name two warehouses share is refused" || bad "two warehouses: rc=$drc $derr"
dn "ODOO_WAREHOUSE=a'b"; [ "$drc" != 0 ] && printf '%s' "$derr" | grep -q 'a warehouse short name is 1 to 5' && ok_ "a name that is not a short name is refused before the database is asked" || bad "bad name: rc=$drc $derr"

# --- registration ----------------------------------------------------------------------
mkdir -p "$T/reg/clinic/connectors" "$T/bin"
cp "$R/clinic/connectors/register-odoo.sh" "$R/clinic/connectors/_render_connector.py" "$SRC" "$SINK" "$T/reg/clinic/connectors/"
printf 'MYSQL_SERVER_NAME=bahmni-t\nODOO_DB_PASSWORD=x\nODOO_SINK_PASSWORD=x\n' > "$T/reg/clinic/.env"
printf '#!/bin/sh\ncat >> "$FAKE_LOG"; echo >> "$FAKE_LOG"; printf "\\n200"\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
reg(){ rm -f "$T/log"; gout="$(env PATH="$T/bin:$PATH" FAKE_LOG="$T/log" NODE=t "$@" bash "$T/reg/clinic/connectors/register-odoo.sh" odoo-source-connector odoo-clinic-sink-all 2>&1)"; grc=$?; }
reg ODOO_UP_CONDITION=UPC ODOO_DOWN_CONDITION=DNC
[ "$grc" = 0 ] && grep -q '"transforms.ownRows.condition": "UPC"' "$T/log" && grep -q '"transforms.transfersForThisClinic.condition": "DNC"' "$T/log" \
  && ok_ "both conditions are written into the registered configurations" || bad "register: rc=$grc $gout"
reg
[ "$grc" != 0 ] && printf '%s' "$gout" | grep -q 'unset env for: transforms.ownRows.condition' && [ ! -s "$T/log" ] \
  && ok_ "without its condition the source is refused and nothing is registered" || bad "no condition: rc=$grc $gout"
blk="$(sed -n '/^# odoo-filters:begin/,/^# odoo-filters:end/p' "$R/clinic/install/tasks/090-local-sync.sh")"
s090="$R/clinic/install/tasks/090-local-sync.sh"
[ -n "$blk" ] && printf '%s' "$blk" | grep -q 'export ODOO_UP_CONDITION=' && printf '%s' "$blk" | grep -q 'export ODOO_DOWN_CONDITION=' \
  && [ "$(grep -n 'odoo-filters:end' "$s090" | cut -d: -f1)" -lt "$(grep -n 'register-odoo.sh odoo-source-connector' "$s090" | cut -d: -f1)" ] \
  && ok_ "090 writes both conditions before it registers the Odoo connectors" || bad "090 order"
exit $((fails > 0))
