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
sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh" | grep -q 'HTTP Status' && ok_ "a Tomcat error page is not taken for OpenELIS" || bad "a Tomcat 404 would pass as OpenELIS"
sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh" | grep -q '"$1" = 200' && ok_ "OpenELIS must answer 200" || bad "OpenELIS status code not checked"
# OpenELIS starts after OpenMRS answers and can take minutes more on a small
# machine: one early probe would stop a healthy install. The check waits on a
# named budget, and its FAIL says how long it waited.
grep -q 'OPENELIS_BOOT_TIMEOUT_S' "$S" && ok_ "OpenELIS waited for on a named budget" || bad "OpenELIS probed once, no wait"
grep -qE 'does not answer as OpenELIS.*within' "$S" && ok_ "OpenELIS FAIL names the wait" || bad "OpenELIS FAIL does not name the wait"
# The check runs under pipefail. A page piped into `grep -q` lets grep exit at
# the first match while the writer is still writing; the writer dies of SIGPIPE
# and pipefail fails the test of a page that matched. A real login page is
# tens of kilobytes, so judge it with a page that size.
. "${HERE}/../lib.sh"
big="<html><head><title>OpenELIS</title></head><body>$(head -c 200000 /dev/zero | tr '\0' 'x')</body></html>"
( set -euo pipefail; elis_page_ok 200 "$big" ) && ok_ "a 200 KB OpenELIS page passes under pipefail" || bad "a large OpenELIS page fails under pipefail (SIGPIPE)"
( set -euo pipefail; elis_page_ok 200 "<html><h1>HTTP Status 404 - /openelis/</h1></html>" ) && bad "a Tomcat error page passes" || ok_ "a Tomcat error page fails"
( set -euo pipefail; elis_page_ok 302 "$big" ) && bad "a non-200 passes" || ok_ "a non-200 fails"
( set -euo pipefail; elis_page_ok 200 "<html>login</html>" ) && bad "a page that is not OpenELIS passes" || ok_ "a page that is not OpenELIS fails"
grep -q 'elis_page_ok "$elis_code" "$elis_body"' "$S" && ok_ "task 100 judges the page with elis_page_ok" || bad "task 100 does not use elis_page_ok"
# Whether the writer loses that race depends on the OS and the page, so the
# behaviour above cannot always show it: no page body may be piped into grep -q.
F="$(sed -n '/^elis_page_ok()/,/^}/p' "${HERE}/../lib.sh")"
printf '%s\n' "$F" | grep -q 'grep -q' && bad "elis_page_ok pipes the page into grep -q (SIGPIPE under pipefail)" || ok_ "elis_page_ok reads the whole page before judging it"
grep -qE 'printf .%s. "\$elis_body" \| grep -q' "$S" && bad "task 100 still pipes the OpenELIS page into grep -q" || ok_ "task 100 pipes no page into grep -q"
exit $((fails > 0))
