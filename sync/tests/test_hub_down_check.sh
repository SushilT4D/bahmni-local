#!/usr/bin/env bash
# tables.sh hub-down refuses a down list that would send a clinic's own rows to every
# clinic, and prints nothing when it refuses, so no caller renders from half a list.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$R/sync/tables/tables.sh" "$TMP/"

# lists ODOO_DOWN CLINLIMS_DOWN : a pair of lists that differ from a valid pair only there
lists(){
  printf '[up]\nres_partner\nproduct_template\nuom_uom\n[down]\n%b' "$1" > "$TMP/odoo.conf"
  printf '[up]\nsample\nanalysis\nresult\nsystem_user\n%b[down]\n%b' "${ELIS_UP:-}" "$2" > "$TMP/openelis.conf"
}
OK_ODOO='product_template\nuom_uom\n'
OK_ELIS='system_user\nanalysis:clinic=id\nresult:clinic=analysis_id\ntest\n'
# refused NAME WANT ODOO CLINLIMS [MODE...] : hub-down MODE exits 1, prints nothing, names WANT
refused(){
  local name="$1" want="$2" out err rc; lists "$3" "$4"; shift 4
  out="$(bash "$TMP/tables.sh" hub-down "${@:-odoo}" 2>"$TMP/err")"; rc=$?; err="$(cat "$TMP/err")"
  if [ "$rc" = 1 ] && [ -z "$out" ] && case "$err" in *"$want"*) true ;; *) false ;; esac; then ok_ "$name"
  else bad "$name: rc=$rc out='$out' err='$err'"; fi
}

lists "$OK_ODOO" "$OK_ELIS"
[ "$(bash "$TMP/tables.sh" hub-down odoo)" = "$(printf 'product_template\nuom_uom')" ] && ok_ "a valid list prints its tables" || bad "a valid list: $(bash "$TMP/tables.sh" hub-down odoo 2>&1)"
[ "$(bash "$TMP/tables.sh" hub-down --routes clinlims)" = "$(printf 'analysis id analysis\nresult analysis_id analysis')" ] && ok_ "routes print the floor table" || bad "routes: $(bash "$TMP/tables.sh" hub-down --routes clinlims 2>&1)"

refused "an Odoo table the clinics write is refused" "res_partner: written at the clinics" "${OK_ODOO}res_partner\n" "$OK_ELIS"
refused "an OpenELIS table the clinics write is refused" "clinlims:sample_item: written at the clinics" "$OK_ODOO" "${OK_ELIS}sample_item\n" clinlims
refused "a routed OpenELIS row without its column is refused" "clinlims:sample: it goes to one clinic" "$OK_ODOO" "${OK_ELIS}sample\n" clinlims
refused "an Odoo row with a routing column is refused" "takes no clinic=<column>" "${OK_ODOO}product_template:clinic=id\n" "$OK_ELIS"
refused "a table not in the [up] list is refused" "odoo:stock_move: not a synced table" "${OK_ODOO}stock_move\n" "$OK_ELIS"
ELIS_UP='test\n' refused "a catalogue table also sent up is refused" "written only at the hub" "$OK_ODOO" "${OK_ELIS}" clinlims
refused "a table listed twice is refused" "listed twice" "${OK_ODOO}uom_uom\n" "$OK_ELIS"
refused "a routing column naming no routed row is refused" "is id or <table>_id" "$OK_ODOO" 'system_user\nresult:clinic=sample_id\n' clinlims
refused "a bad third field is refused" "the third field is clinic=<column> or nothing" "${OK_ODOO}uom_uom:x\n" "$OK_ELIS"

# A section header with a trailing comment is still a section header.
printf '[up]   # sent up\nres_partner\nproduct_template\n[down] # sent down\nproduct_template\n' > "$TMP/odoo.conf"
printf '[up]\nsample\n[down]\n' > "$TMP/openelis.conf"
[ "$(bash "$TMP/tables.sh" odoo up | grep -c .)" = 2 ] && [ "$(bash "$TMP/tables.sh" hub-down odoo)" = product_template ] \
  && ok_ "a commented section header still splits the file" || bad "commented header: up=$(bash "$TMP/tables.sh" odoo up | tr '\n' ' ') down=$(bash "$TMP/tables.sh" hub-down odoo 2>&1)"

rm -f "$TMP/openelis.conf"
out="$(bash "$TMP/tables.sh" hub-down odoo 2>&1)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"no such file"*openelis.conf*) true ;; *) false ;; esac && ok_ "a missing list file is refused by name" || bad "missing file: rc=$rc $out"
exit $((fails > 0))
