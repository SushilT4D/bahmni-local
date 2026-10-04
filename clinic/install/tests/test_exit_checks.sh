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
# Tomcat's own 404 page names the path ("/openelis/"), so the word alone proves
# nothing: the page must answer 200 and not be a Tomcat error page
grep -q 'HTTP Status' "$S" && ok_ "a Tomcat error page is not taken for OpenELIS" || bad "a Tomcat 404 would pass as OpenELIS"
grep -q '"$elis_code" = 200' "$S" && ok_ "OpenELIS must answer 200" || bad "OpenELIS status code not checked"
# OpenELIS starts after OpenMRS answers and can take minutes more on a small
# machine: one early probe would stop a healthy install. The check waits on a
# named budget, and its FAIL says how long it waited.
grep -q 'OPENELIS_BOOT_TIMEOUT_S' "$S" && ok_ "OpenELIS waited for on a named budget" || bad "OpenELIS probed once, no wait"
grep -qE 'does not answer as OpenELIS.*within' "$S" && ok_ "OpenELIS FAIL names the wait" || bad "OpenELIS FAIL does not name the wait"
exit $((fails > 0))
