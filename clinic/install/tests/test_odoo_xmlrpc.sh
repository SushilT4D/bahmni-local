#!/usr/bin/env bash
# task 100 (exit checks): a dead Odoo used to dump a 20-line
# xmlrpc.client.ProtocolError traceback (and lib.sh's ERR trap printed the
# whole heredoc a second time on top of it). The XML-RPC block must reduce
# any exception to exactly one line, and the login-page wait must be named
# (ODOO_BOOT_TIMEOUT_S) so its own message can never drift from what ran.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T100="${HERE}/../tasks/100-exit-checks.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

[ -f "$T100" ] || { bad "no tasks/100-exit-checks.sh"; exit 1; }
code="$(grep -vE '^[[:space:]]*#' "$T100")"

# --- static: the wait is named, and the fail message derives from it -------
printf '%s' "$code" | grep -q 'ODOO_BOOT_TIMEOUT_S:-120' && ok_ "100 names the login-page wait (ODOO_BOOT_TIMEOUT_S, default 120)" || bad "100 has no ODOO_BOOT_TIMEOUT_S:-120"
printf '%s' "$code" | grep -qE 'odoo_boot_s / 10' && ok_ "100 probes every 10s, derived from the named budget" || bad "100 does not derive its probe count from odoo_boot_s"
printf '%s' "$code" | grep -q '\${odoo_boot_s}s' && ok_ "the FAIL message states its own timeout in seconds" || bad "FAIL message does not name odoo_boot_s"
printf '%s' "$code" | grep -q '303' && printf '%s' "$code" | grep -q 'seed-odoo-conf.sh' && printf '%s' "$code" | grep -q '/web/database/selector' && ok_ "FAIL text explains a 303 (missing/ambiguous odoo.conf) and names seed-odoo-conf.sh" || bad "FAIL text is missing the 303/seed-odoo-conf.sh hint"

# --- static: the XML-RPC failure path is one named fail(), not a traceback -
printf '%s' "$code" | grep -q 'Odoo XML-RPC did not answer:' && ok_ "100 turns an XML-RPC exception into one named fail()" || bad "100 has no 'Odoo XML-RPC did not answer:' fail"
printf '%s' "$code" | grep -q 'except Exception as e:' && ok_ "the python block catches any exception itself" || bad "the python block has no catch-all"
printf '%s' "$code" | grep -q 'xmlrpc_err' && ok_ "the exception line is captured on stderr, not left to the ERR trap" || bad "100 does not capture xmlrpc stderr separately"

# --- functional: the extracted python block, run against an unreachable
# endpoint, reduces the failure to one line, no traceback, non-zero exit.
snippet="$(sed -n '/# xmlrpc-marker:begin/,/# xmlrpc-marker:end/p' "$T100")"
[ -n "$snippet" ] || { bad "could not extract the xmlrpc-marker:begin/end block from 100"; exit 1; }
out="$(printf '%s' "$snippet" | python3 - MARK-1 user pw 9 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok_ "unreachable endpoint (port 9): exits non-zero" || bad "unreachable endpoint exited 0: $out"
lines="$(printf '%s' "$out" | grep -c '.')"
[ "$lines" -eq 1 ] && ok_ "unreachable endpoint: exactly one line of output" || bad "expected exactly one line, got ${lines}: $out"
printf '%s' "$out" | grep -qi 'Traceback' && bad "output still shows a Traceback: $out" || ok_ "no Traceback in the output"
printf '%s' "$out" | grep -q '^odoo xml-rpc: ' && ok_ "the one line is the named 'odoo xml-rpc: <Exception>: <message>' form" || bad "output does not match the named form: $out"

exit "$fails"
