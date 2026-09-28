#!/usr/bin/env bash
# Task 100 reads each application back through the clinic LAN name, by
# content, and the install sitting stops after those pages.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; S="${HERE}/../tasks/100-exit-checks.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
grep -q -- '--resolve' "$S" && ok_ "pages fetched by name, resolved locally" || bad "no --resolve"
grep -q '"authenticated"' "$S" && ok_ "OpenMRS page asserted by content" || bad "OpenMRS not asserted by content"
grep -qi 'openelis' "$S" && grep -q -- '--baseline' "$S" && ok_ "OpenELIS failure names the baseline override" || bad "OpenELIS failure does not name --baseline"
grep -qF 'odoo.${N}' "$S" && ok_ "Odoo checked on its own name" || bad "Odoo not on its own name"
grep -qE '9444|BAHMNI_ODOO_HTTPS_PORT' "$S" && bad "old Odoo port remains" || ok_ "no old Odoo port"
grep -q 'PHASE:-install}" = install' "$S" && ok_ "install sitting stops after the pages" || bad "no install-sitting exit"
exit $((fails > 0))
