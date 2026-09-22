#!/usr/bin/env bash
# The Odoo seed carries ir_attachment rows for its compiled asset bundles, and
# those rows point at files in the source node's filestore. A clinic has no such
# files, so every CSS/JS request answers 500 and the login page has no style.
# Task 050 drops the bundle rows before Odoo first starts (Odoo rebuilds them on
# demand); task 100 reads the CSS bundle back through the proxy.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T50="${HERE}/../tasks/050-databases.sh"; T100="${HERE}/../tasks/100-exit-checks.sh"
blk="$(sed -n '/# odoo-assets:begin/,/# odoo-assets:end/p' "$T50")"
[ -n "$blk" ] || bad "050 has no odoo-assets block"
printf '%s' "$blk" | grep -qE "delete from ir_attachment where res_model *= *'ir.ui.view' and name like '%assets%'" \
  && ok_ "050 drops the asset-bundle attachment rows" || bad "050 does not drop the asset-bundle rows: $blk"
printf '%s' "$blk" | grep -q 'ir_attachment' && ! printf '%s' "$blk" | grep -qE "delete from ir_attachment *(where store_fname|;)" \
  && ok_ "050 deletes only the bundle rows, never every attachment" || bad "050 deletes too much"
# order: the delete must sit after the odoo restore and before any compose up of odoo
code50="$(grep -vE '^[[:space:]]*#' "$T50")"
r="$(printf '%s\n' "$code50" | grep -n 'for db in odoo openelis' | head -1 | cut -d: -f1)"
d="$(printf '%s\n' "$code50" | grep -n "name like '%assets%'" | head -1 | cut -d: -f1)"
[ -n "$r" ] && [ -n "$d" ] && [ "$d" -gt "$r" ] && ok_ "050 drops the rows after the restore" || bad "050 order wrong (restore at $r, delete at $d)"
printf '%s' "$code50" | grep -q 'compose up.* odoo' && bad "050 starts odoo itself" || ok_ "050 never starts odoo (task 080 does, after the rows are gone)"
# task 100 reads the css bundle back through the proxy
code100="$(grep -vE '^[[:space:]]*#' "$T100")"
printf '%s' "$code100" | grep -q 'assets_frontend' && ok_ "100 finds the CSS bundle on the login page" || bad "100 does not look for the CSS bundle"
printf '%s' "$code100" | grep -q 'Odoo CSS bundle' && ok_ "100 names the CSS bundle check" || bad "100 has no named CSS check"
exit "$fails"
