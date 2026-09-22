#!/usr/bin/env bash
# Pure unit tests for two functions extracted out of 080-sources.sh:
# mysql_major_ok (the Debezium MySQL-major-
# version gate) and slot_wait_state (wait_slot's active/inactive/missing
# classifier). No docker, no network -- distinct from test_sources.sh (the
# live smoke that proves 080-sources.sh end to end) the same way
# test_preflight.sh's binlog_ok tests are distinct from test_base_db.sh.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$(mktemp -d)"; . "$HERE/../lib.sh"

# mysql_major_ok VERSION: the exact three versions the brief names.
mysql_major_ok 8.0.39 >/dev/null; assert_rc "8.0.39 (the fleet's pin) passes" $? 0
mysql_major_ok 5.7.44 >/dev/null; assert_rc "5.7.44 fails (Debezium 3.6.2 needs MySQL 8.0.x)" $? 1
mysql_major_ok 5.6.51 >/dev/null; assert_rc "5.6.51 fails (the Azure hub's old base image)" $? 1
# A couple of shape edges: a trailing qualifier MySQL sometimes appends, and
# an unparseable version string (never seen live, but must fail named, not
# crash the caller with an unbound/non-numeric comparison).
mysql_major_ok 8.0.39-log >/dev/null; assert_rc "8.0.39-log (a qualifier suffix) still passes" $? 0
mysql_major_ok '' >/dev/null; assert_rc "empty version fails" $? 1
out="$(mysql_major_ok not-a-version)"; rc=$?
assert_rc "unparseable version fails rather than crashing" "$rc" 1
case "$out" in *"numeric"*) named=yes ;; *) named=no ;; esac
assert_eq "unparseable version names the reason" "$named" "yes"
out="$(mysql_major_ok 5.7.44)"
case "$out" in *"5.7.44"*"MySQL 8.0.x"*) named=yes ;; *) named=no ;; esac
assert_eq "an unfit version names itself and what Debezium needs" "$named" "yes"

# slot_wait_state ROW SLOT: the three real psql -At shapes named in the brief.
assert_eq "slot_name|true -> active"   "$(slot_wait_state 'dbz_odoo_down|true' dbz_odoo_down)"   "active"
assert_eq "slot_name|false -> inactive" "$(slot_wait_state 'dbz_odoo_down|false' dbz_odoo_down)" "inactive"
assert_eq "empty row -> missing"        "$(slot_wait_state '' dbz_odoo_down)"                     "missing"
# Not just "any truthy string" -- must match THIS slot's own name, not another
# slot's active row (a wrong SQL WHERE clause, or a copy-paste of the wrong
# variable, must show up as "missing"/"inactive", never a false "active").
assert_eq "a different slot's active row does not match this slot"  "$(slot_wait_state 'dbz_clinlims_down|true' dbz_odoo_down)" "missing"
assert_eq "a bare psql 't'/'f' boolean (not the || cast) is not 'active' either" "$(slot_wait_state 'dbz_odoo_down|t' dbz_odoo_down)" "missing"

printf '%s\n' "$fails failure(s)"; exit $((fails>0))
