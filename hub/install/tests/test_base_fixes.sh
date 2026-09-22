#!/usr/bin/env bash
# Unit tests for hub/install/tasks/085-base-fixes.sh (login stopgap, quiet
# odoo-connect log, InnoDB sizing). No docker, no network, no real BASE_DIR -- the
# pieces that actually touch a live proxy/odoo-connect container (the
# config-test/reload/recreate calls in the task's own main flow) are not
# exercised here, only the pure/marker-guarded functions the task extracts
# into named blocks, the same way clinic/install/tests/test_boot_budget.sh
# pulls `# cpu-budget:begin`...`:end` out of 000-preflight.sh and runs it
# standalone. Runs under plain bash and stock macOS /bin/bash 3.2 (no
# associative arrays, no mapfile, no ${var,,}).
#
# Every extracted block is written to its own temp SCRIPT FILE and run with
# `bash file`, never `bash -c "$string"` -- the stopgap-rules block contains a
# nested `cat <<'APACHE_BLOCK' ... APACHE_BLOCK` heredoc, and folding that
# through a second layer of double-quoted string interpolation (`bash -c
# "...${blk}..."`) silently produced empty output in testing here, even at
# rc=0. Writing the exact extracted bytes to a file and executing that file
# sidesteps the whole question.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK="${HERE}/../tasks/085-base-fixes.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
fails=0
ok(){ printf '  ok   %s\n' "$*"; }
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
assert_eq(){ if [ "$2" = "$3" ]; then ok "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_rc(){ if [ "$2" -eq "$3" ]; then ok "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -qF "$3"; then ok "$1"; else printf '  FAIL %s: expected output to contain %q, got: %s\n' "$1" "$3" "$2"; fails=$((fails+1)); fi; }

[ -f "$TASK" ] || { printf '  FAIL task file not found: %s\n' "$TASK"; exit 1; }

STUBS='ok(){ printf "  ok   %s\n" "$*"; }
fail(){ printf "  FAIL %s\n" "$*" >&2; exit 1; }
info(){ printf "  %s\n" "$*"; }
warn(){ printf "  WARN %s\n" "$*" >&2; }
DRY="${DRY:-0}"'

# Marked blocks, extracted exactly like clinic/install/tests/test_boot_budget.sh
# pulls its cpu-budget block out of 000-preflight.sh.
stopgap_rules_blk="$(sed -n '/# stopgap-rules:begin/,/# stopgap-rules:end/p' "$TASK")"
stopgap_insert_blk="$(sed -n '/# stopgap-insert:begin/,/# stopgap-insert:end/p' "$TASK")"
comma_ref_blk="$(sed -n '/# comma-strip-ref:begin/,/# comma-strip-ref:end/p' "$TASK")"
override_blk="$(sed -n '/# override-edit:begin/,/# override-edit:end/p' "$TASK")"

[ -n "$stopgap_rules_blk" ]     || bad "085 has no stopgap-rules block"
[ -n "$stopgap_insert_blk" ]    || bad "085 has no stopgap-insert block"
[ -n "$comma_ref_blk" ]    || bad "085 has no comma-strip-ref block"
[ -n "$override_blk" ]  || bad "085 has no override-edit block"

# mkscript NAME BLOCK... : writes STUBS + the given block(s) + a trailing
# invocation (read from stdin) to ${TMP_ROOT}/NAME.sh and prints its path.
mkscript(){ # NAME
  local out="${TMP_ROOT}/$1.sh"
  { printf '%s\n' "$STUBS"; shift; for b in "$@"; do printf '%s\n' "$b"; done; cat; } > "$out"
  printf '%s' "$out"
}

# --- (ii) the rewrite rules themselves --------------------------------------
rules_script="$(mkscript rules "$stopgap_rules_blk" <<'EOF'
stopgap_block
EOF
)"
block_out="$(bash "$rules_script")"
first_comma_pos="$(printf '%s\n' "$block_out" | grep -n 'RewriteCond %{QUERY_STRING}' | head -1 | cut -d: -f1)"
last_comma_pos="$(printf '%s\n' "$block_out" | grep -n 'RewriteCond %{QUERY_STRING}' | tail -1 | cut -d: -f1)"
if [ -n "$first_comma_pos" ] && [ -n "$last_comma_pos" ] && [ "$first_comma_pos" -lt "$last_comma_pos" ]; then
  ok "stopgap_block: two RewriteCond lines present, in order (two-comma rule before the one-comma rule)"
else
  bad "stopgap_block: expected two RewriteCond lines with the two-comma rule first (first=${first_comma_pos:-<none>} last=${last_comma_pos:-<none>})"
fi
# The two-comma rule's own RewriteCond line must appear before the one-comma
# rule's: confirmed by checking the FIRST RewriteCond line carries FOUR
# capture-group markers (two ,|%2C)(\)|%29) pairs), the last only two.
first_line="$(printf '%s\n' "$block_out" | grep 'RewriteCond %{QUERY_STRING}' | sed -n '1p')"
last_line="$(printf '%s\n' "$block_out" | grep 'RewriteCond %{QUERY_STRING}' | sed -n '$p')"
first_pairs="$(printf '%s' "$first_line" | grep -o '(?:,|%2C)(\\)|%29)' | wc -l | tr -d ' ')"
last_pairs="$(printf '%s' "$last_line" | grep -o '(?:,|%2C)(\\)|%29)' | wc -l | tr -d ' ')"
if [ "${first_pairs:-0}" -eq 2 ] && [ "${last_pairs:-0}" -eq 1 ]; then
  ok "stopgap_block: the FIRST RewriteCond matches two comma-before-paren occurrences, the LAST matches one (two-comma case really is handled first)"
else
  bad "stopgap_block: first RewriteCond has ${first_pairs:-0} comma-before-paren groups (want 2), last has ${last_pairs:-0} (want 1)"
fi
case "$block_out" in
  *'(?:,|%2C)(\)|%29)'*) ok "stopgap_block: contains the ,/%2C and )/%29 alternations" ;;
  *) bad "stopgap_block: missing the (?:,|%2C)(\\)|%29) alternation" ;;
esac
case "$block_out" in
  *'[PT,NE]'*) ok "stopgap_block: carries the [PT,NE] flags" ;;
  *) bad "stopgap_block: missing [PT,NE] flags" ;;
esac
case "$block_out" in
  *'# login stopgap (hub/install 085)'*) ok "stopgap_block: opens with its marker comment" ;;
  *) bad "stopgap_block: missing the opening marker comment" ;;
esac
case "$block_out" in
  *'# login stopgap end'*) ok "stopgap_block: closes with its end marker" ;;
  *) bad "stopgap_block: missing the end marker" ;;
esac

# --- (ii cont.) comma_strip_ref table test ----------------------------------
ref_script="$(mkscript ref "$comma_ref_blk" <<'EOF'
comma_strip_ref "$1"
EOF
)"
run_ref(){ bash "$ref_script" "$1"; }

login_q='v=custom:(username,uuid,person:(uuid,),privileges:(name,retired),userProperties)'
login_q_expect='v=custom:(username,uuid,person:(uuid),privileges:(name,retired),userProperties)'
assert_eq "comma_strip_ref: the real login query string (literal ,))" "$(run_ref "$login_q")" "$login_q_expect"

login_q_enc='v=custom:(username,uuid,person:(uuid%2C%29,privileges:(name,retired),userProperties)'
login_q_enc_expect='v=custom:(username,uuid,person:(uuid%29,privileges:(name,retired),userProperties)'
assert_eq "comma_strip_ref: the same query, percent-encoded (%2C%29)" "$(run_ref "$login_q_enc")" "$login_q_enc_expect"

two_comma_q='q=(a,)&r=(b,)'
two_comma_expect='q=(a)&r=(b)'
assert_eq "comma_strip_ref: a string with two such commas -- both stripped" "$(run_ref "$two_comma_q")" "$two_comma_expect"

no_comma_q='v=custom:(uuid,name)'
assert_eq "comma_strip_ref: no comma-before-paren -- unchanged" "$(run_ref "$no_comma_q")" "$no_comma_q"

# --- (i) the stopgap inserter against a fixture Apache conf ----------------------
STOPGAP_HARNESS="$(mkscript stopgapharness "$stopgap_rules_blk" "$stopgap_insert_blk" <<'EOF'
stopgap_insert "$1"
EOF
)"

mk_fixture(){ # DIR -- the live hub's layout: ProxyPass at
  # SERVER scope, the rewrite rules inside the 443 vhost after the cookie rule
  mkdir -p "$1"
  cat > "$1/bahmni-proxy.conf" <<'EOF'
ProxyPass /openmrs/auth http://patient-documents:80/openmrs/auth
ProxyPass /openmrs http://openmrs:8080/openmrs

<VirtualHost *:443>
    ServerName bahmni.xoyo.ad
    SSLEngine on
    RewriteEngine on

    RewriteCond %{REQUEST_URI} ^/openmrs/*
    RewriteCond %{HTTP_COOKIE} ^.*JSESSIONID=([^;]+)
    RewriteRule ^.*$ - [CO=reporting_session:%1:%{HTTP_HOST}:86400:/:true:true]

    RewriteCond %{HTTP_HOST} ^erp-[^.]+
    RewriteRule (.*) http://odoo:8069$1 [P]
</VirtualHost>
EOF
}

stopgapdir="${TMP_ROOT}/stopgap"; mk_fixture "$stopgapdir"
orig_content="$(cat "${stopgapdir}/bahmni-proxy.conf")"
out="$(DRY=0 bash "$STOPGAP_HARNESS" "${stopgapdir}/bahmni-proxy.conf" 2>&1)"; rc=$?
assert_rc "stopgap_insert: first run exits 0" "$rc" 0
assert_contains "stopgap_insert: first run reports it inserted" "$out" "inserted the rewrite block"
[ -f "${stopgapdir}/bahmni-proxy.conf.bak-pre-login-stopgap" ] && ok "stopgap_insert: backup created" || bad "stopgap_insert: no backup created"
grep -qF '# login stopgap (hub/install 085)' "${stopgapdir}/bahmni-proxy.conf" && ok "stopgap_insert: marker present after insert" || bad "stopgap_insert: marker missing after insert"
assert_eq "stopgap_insert: the backup holds the ORIGINAL, unmodified file" "$(cat "${stopgapdir}/bahmni-proxy.conf.bak-pre-login-stopgap")" "$orig_content"
after_first="$(cat "${stopgapdir}/bahmni-proxy.conf")"
backup_first="$(cat "${stopgapdir}/bahmni-proxy.conf.bak-pre-login-stopgap")"

# placement: inside the vhost, directly after the cookie rule, before the next rule -- never at server scope
cookie_ln="$(grep -n 'CO=reporting_session' "${stopgapdir}/bahmni-proxy.conf" | head -n1 | cut -d: -f1)"
mark_ln="$(grep -n 'login stopgap (hub/install 085)' "${stopgapdir}/bahmni-proxy.conf" | head -n1 | cut -d: -f1)"
vhost_ln="$(grep -n '<VirtualHost \*:443>' "${stopgapdir}/bahmni-proxy.conf" | head -n1 | cut -d: -f1)"
erp_ln="$(grep -n 'erp-\[' "${stopgapdir}/bahmni-proxy.conf" | head -n1 | cut -d: -f1)"
[ "$mark_ln" -gt "$cookie_ln" ] && [ "$mark_ln" -gt "$vhost_ln" ] && [ "$mark_ln" -lt "$erp_ln" ] \
  && ok "stopgap_insert: the block sits inside the 443 vhost, after the cookie rule" || bad "stopgap_insert: block at line $mark_ln (vhost $vhost_ln, cookie rule $cookie_ln, next rule $erp_ln)"
[ "$(grep -c 'RewriteCond %{REQUEST_URI} ^/openmrs/$' "${stopgapdir}/bahmni-proxy.conf")" = 2 ] && ok "stopgap_block: both rules are scoped to /openmrs/" || bad "stopgap_block: rules not scoped to /openmrs/"
grep -q '%1%2%3%4%5%6' "${stopgapdir}/bahmni-proxy.conf" && bad "stopgap_block: references a sixth group that does not exist" || ok "stopgap_block: five groups, five back-references"

# a block applied BY HAND on the hub (its own comment, the same rules) counts as present: no second copy
stopgaphand="${TMP_ROOT}/stopgap-hand"; mk_fixture "$stopgaphand"
awk '/^    RewriteCond %\{HTTP_HOST\} \^erp-/{print "    # comma-stripping stopgap, applied by hand"; print "    RewriteCond %{REQUEST_URI} ^/openmrs/"; print "    RewriteCond %{QUERY_STRING} ^(.*)(?:,|%2C)(\\)|%29)(.*)$ [NC]"; print "    RewriteRule ^(.*)$ $1?%1%2%3 [PT,NE]"} {print}' "${stopgaphand}/bahmni-proxy.conf" > "${stopgaphand}/bahmni-proxy.conf.new" && mv "${stopgaphand}/bahmni-proxy.conf.new" "${stopgaphand}/bahmni-proxy.conf"
hand_before="$(cat "${stopgaphand}/bahmni-proxy.conf")"
outh="$(DRY=0 bash "$STOPGAP_HARNESS" "${stopgaphand}/bahmni-proxy.conf" 2>&1)"; rch=$?
assert_rc "stopgap_insert: a hand-applied block exits 0" "$rch" 0
assert_contains "stopgap_insert: a hand-applied block is recognised" "$outh" "already carries the comma-stripping"
assert_eq "stopgap_insert: a hand-applied block is left byte-identical" "$(cat "${stopgaphand}/bahmni-proxy.conf")" "$hand_before"

out2="$(DRY=0 bash "$STOPGAP_HARNESS" "${stopgapdir}/bahmni-proxy.conf" 2>&1)"; rc2=$?
assert_rc "stopgap_insert: second run exits 0" "$rc2" 0
assert_contains "stopgap_insert: second run is a no-op (already carries the stopgap)" "$out2" "already carries the comma-stripping"
after_second="$(cat "${stopgapdir}/bahmni-proxy.conf")"
assert_eq "stopgap_insert: second run leaves the file byte-identical" "$after_second" "$after_first"
backup_second="$(cat "${stopgapdir}/bahmni-proxy.conf.bak-pre-login-stopgap")"
assert_eq "stopgap_insert: backup is never overwritten by a second run" "$backup_second" "$backup_first"

# no reporting_session cookie rule to anchor on -> non-zero, names the file
stopgapdir_noanchor="${TMP_ROOT}/stopgap-noanchor"; mkdir -p "$stopgapdir_noanchor"
printf '<VirtualHost *:443>\n    ServerName bahmni.xoyo.ad\n</VirtualHost>\n' > "${stopgapdir_noanchor}/bahmni-proxy.conf"
out3="$(DRY=0 bash "$STOPGAP_HARNESS" "${stopgapdir_noanchor}/bahmni-proxy.conf" 2>&1)"; rc3=$?
assert_rc "stopgap_insert: no anchor -> non-zero" "$rc3" 1
assert_contains "stopgap_insert: failure names the file" "$out3" "${stopgapdir_noanchor}/bahmni-proxy.conf"
assert_contains "stopgap_insert: failure names the missing anchor" "$out3" "reporting_session"

# --- (iv, stopgap half) DRY leaves the temp dir byte-identical -------------------
stopgapdir_dry="${TMP_ROOT}/stopgap-dry"; mk_fixture "$stopgapdir_dry"
before_listing="$(cd "$stopgapdir_dry" && find . -type f | sort)"
before_sum="$(cksum < "${stopgapdir_dry}/bahmni-proxy.conf")"
out4="$(DRY=1 bash "$STOPGAP_HARNESS" "${stopgapdir_dry}/bahmni-proxy.conf" 2>&1)"; rc4=$?
assert_rc "stopgap_insert: DRY run exits 0" "$rc4" 0
assert_contains "stopgap_insert: DRY prints a would: line" "$out4" "would:"
after_listing="$(cd "$stopgapdir_dry" && find . -type f | sort)"
after_sum="$(cksum < "${stopgapdir_dry}/bahmni-proxy.conf")"
assert_eq "stopgap_insert: DRY creates no new files in the target dir" "$after_listing" "$before_listing"
assert_eq "stopgap_insert: DRY leaves the conf file byte-identical" "$after_sum" "$before_sum"

# --- (iii) the override edit against a fixture override YAML ------------
OVERRIDE_HARNESS="$(mkscript overrideharness "$override_blk" <<'EOF'
override_ensure "$1" "$2"
EOF
)"
TARGET='/run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/classes/logback.xml'
MOUNT_LINE="./odoo-connect-logback.xml:${TARGET}:ro"

# no override file at all -> created fresh
overridedir_new="${TMP_ROOT}/override-new"; mkdir -p "$overridedir_new"
out="$(DRY=0 bash "$OVERRIDE_HARNESS" "${overridedir_new}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "override_ensure: creating a fresh override file exits 0" "$rc" 0
grep -qF "$MOUNT_LINE" "${overridedir_new}/docker-compose.override.yml" && ok "override_ensure: fresh file carries the mount line" || bad "override_ensure: fresh file missing the mount line"
[ -f "${overridedir_new}/docker-compose.override.yml.bak-pre-override" ] && bad "override_ensure: a backup was made for a file that did not exist before" || ok "override_ensure: no backup made when there was nothing to back up"

# idempotent: a second run on the same file changes nothing
after_new_first="$(cat "${overridedir_new}/docker-compose.override.yml")"
out="$(DRY=0 bash "$OVERRIDE_HARNESS" "${overridedir_new}/docker-compose.override.yml" "$TARGET" 2>&1)"
assert_contains "override_ensure: second run is a no-op" "$out" "already mounts"
assert_eq "override_ensure: second run leaves the file byte-identical" "$(cat "${overridedir_new}/docker-compose.override.yml")" "$after_new_first"

# a fixture that ALREADY has an odoo-connect: service with its own volumes:
# list gets the extra entry, not a duplicate odoo-connect: key.
overridedir_existing="${TMP_ROOT}/override-existing"; mkdir -p "$overridedir_existing"
cat > "${overridedir_existing}/docker-compose.override.yml" <<'EOF'
# header comments here
services:
  openmrs:
    platform: linux/amd64
  odoo-connect:
    logging: *rotate
    volumes:
      - './somefile.jar:/opt/somefile.jar:ro'
    environment:
      TZ: UTC
  proxy:
    volumes:
      - './proxy-config/bahmni-proxy.conf:/usr/local/apache2/conf/extra/bahmni-proxy.conf'
EOF
orig_override_content="$(cat "${overridedir_existing}/docker-compose.override.yml")"
# the form live on the hub: a single-quoted entry under odoo-connect -> already present, untouched
overridedir_live="${TMP_ROOT}/override-live"; mkdir -p "$overridedir_live"
cat > "${overridedir_live}/docker-compose.override.yml" <<EOF
services:
  odoo-connect:
    logging: *rotate
    volumes:
      - './odoo-connect-logback.xml:${TARGET}:ro'
EOF
live_before="$(cat "${overridedir_live}/docker-compose.override.yml")"
outl="$(DRY=0 bash "$OVERRIDE_HARNESS" "${overridedir_live}/docker-compose.override.yml" "$TARGET" 2>&1)"; rcl=$?
assert_rc "override_ensure: the hub's live quoted entry exits 0" "$rcl" 0
assert_contains "override_ensure: the hub's live quoted entry is recognised" "$outl" "already mounts"
assert_eq "override_ensure: the hub's live file is left byte-identical" "$(cat "${overridedir_live}/docker-compose.override.yml")" "$live_before"

out="$(DRY=0 bash "$OVERRIDE_HARNESS" "${overridedir_existing}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "override_ensure: editing an existing odoo-connect: service exits 0" "$rc" 0
oc_count="$(grep -c '^  odoo-connect:' "${overridedir_existing}/docker-compose.override.yml")"
assert_eq "override_ensure: exactly one odoo-connect: key after the edit (no duplicate)" "$oc_count" "1"
grep -qF "$MOUNT_LINE" "${overridedir_existing}/docker-compose.override.yml" && ok "override_ensure: the mount line was added" || bad "override_ensure: the mount line is missing"
grep -qF "./somefile.jar:/opt/somefile.jar:ro" "${overridedir_existing}/docker-compose.override.yml" && ok "override_ensure: the pre-existing volume entry survives" || bad "override_ensure: the pre-existing volume entry was lost"
grep -qF "proxy-config/bahmni-proxy.conf" "${overridedir_existing}/docker-compose.override.yml" && ok "override_ensure: an unrelated service's config is untouched" || bad "override_ensure: an unrelated service's config was disturbed"
[ -f "${overridedir_existing}/docker-compose.override.yml.bak-pre-override" ] && ok "override_ensure: backup created for the pre-existing file" || bad "override_ensure: no backup created for the pre-existing file"
assert_eq "override_ensure: the backup holds the ORIGINAL, unmodified file" "$(cat "${overridedir_existing}/docker-compose.override.yml.bak-pre-override")" "$orig_override_content"

# backup is made once and never overwritten by a later run
backup_first="$(cat "${overridedir_existing}/docker-compose.override.yml.bak-pre-override")"
bash "$OVERRIDE_HARNESS" "${overridedir_existing}/docker-compose.override.yml" "$TARGET" >/dev/null 2>&1
backup_second="$(cat "${overridedir_existing}/docker-compose.override.yml.bak-pre-override")"
assert_eq "override_ensure: backup is never overwritten by a later run" "$backup_second" "$backup_first"

# --- (iv, override half) DRY leaves the temp dir byte-identical -------------------
overridedir_dry="${TMP_ROOT}/override-dry"; mkdir -p "$overridedir_dry"
cat > "${overridedir_dry}/docker-compose.override.yml" <<'EOF'
services:
  odoo-connect:
    logging: *rotate
EOF
before_listing="$(cd "$overridedir_dry" && find . -type f | sort)"
before_sum="$(cksum < "${overridedir_dry}/docker-compose.override.yml")"
out="$(DRY=1 bash "$OVERRIDE_HARNESS" "${overridedir_dry}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "override_ensure: DRY run exits 0" "$rc" 0
assert_contains "override_ensure: DRY prints a would: line" "$out" "would:"
after_listing="$(cd "$overridedir_dry" && find . -type f | sort)"
after_sum="$(cksum < "${overridedir_dry}/docker-compose.override.yml")"
assert_eq "override_ensure: DRY creates no new files in the target dir" "$after_listing" "$before_listing"
assert_eq "override_ensure: DRY leaves the override file byte-identical" "$after_sum" "$before_sum"

# DRY against a target that does not exist at all -- must not create it
overridedir_dry_missing="${TMP_ROOT}/override-dry-missing"; mkdir -p "$overridedir_dry_missing"
out="$(DRY=1 bash "$OVERRIDE_HARNESS" "${overridedir_dry_missing}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "override_ensure: DRY against a missing file exits 0" "$rc" 0
[ -f "${overridedir_dry_missing}/docker-compose.override.yml" ] && bad "override_ensure: DRY created a file that did not exist before" || ok "override_ensure: DRY against a missing file creates nothing"


# --- InnoDB sizing for the base MySQL ----------------------------------------
sizing_blk="$(sed -n '/# base-sizing:begin/,/# base-sizing:end/p' "$TASK")"
[ -n "$sizing_blk" ] || bad "085 has no base-sizing block"
sizing(){ bash -c "$sizing_blk"$'\n''"$@"' _ "$@" 2>&1; }   # newline, not ";": the block ends in a comment line
assert_eq "base_pool_mb: 13924 -> 3456" "$(sizing base_pool_mb 13924)" 3456
assert_eq "base_pool_mb: 65536 -> 4096 (cap)" "$(sizing base_pool_mb 65536)" 4096
assert_eq "base_pool_mb: 2048 -> 512 (floor)" "$(sizing base_pool_mb 2048)" 512
sizingcnf="$(sizing base_tuning_cnf 3456)"
assert_contains "base_tuning_cnf: buffer pool line" "$sizingcnf" "innodb_buffer_pool_size = 3456M"
assert_contains "base_tuning_cnf: redo log line" "$sizingcnf" "innodb_redo_log_capacity = 512M"
# one rule on both sides: the clinic's lib.sh must size identically
CLINIC_LIB="$(cd "$(dirname "$TASK")/../../../clinic/install" && pwd)/lib.sh"
for mem in 400 2048 8192 13924 65536; do
  c="$(env -i PATH="$PATH" bash -c ". '$CLINIC_LIB'; mysql_pool_mb $mem" 2>/dev/null)"
  assert_eq "hub and clinic size ${mem} MB the same" "$(sizing base_pool_mb $mem)" "$c"
done
assert_eq "hub and clinic render the same [mysqld] body" "$(sizing base_tuning_cnf 1024 | grep -v '^#')" "$(env -i PATH="$PATH" bash -c ". '$CLINIC_LIB'; mysql_tuning_cnf 1024" | grep -v '^#')"
# the override editor takes the service name: an openmrsdb: mount lands under openmrsdb, not odoo-connect
sizingdir="${TMP_ROOT}/sizing"; mkdir -p "$sizingdir"
cat > "${sizingdir}/docker-compose.override.yml" <<EOF
services:
  odoo-connect:
    volumes:
      - './odoo-connect-logback.xml:${TARGET}:ro'
EOF
SIZING_HARNESS="$(mkscript sizingharness "$override_blk" <<'EOF'
override_ensure "$1" "/etc/mysql/conf.d/sync-tuning.cnf" openmrsdb ./openmrsdb-tuning.cnf "innodb sizing"
EOF
)"
out="$(DRY=0 bash "$SIZING_HARNESS" "${sizingdir}/docker-compose.override.yml" 2>&1)"; rc=$?
assert_rc "innodb sizing: override edit exits 0" "$rc" 0
grep -q "^  openmrsdb:" "${sizingdir}/docker-compose.override.yml" && ok "innodb sizing: openmrsdb: service added" || bad "innodb sizing: no openmrsdb: service"
grep -q "./openmrsdb-tuning.cnf:/etc/mysql/conf.d/sync-tuning.cnf:ro" "${sizingdir}/docker-compose.override.yml" && ok "innodb sizing: mount line present" || bad "innodb sizing: mount line missing"
python3 - "${sizingdir}/docker-compose.override.yml" <<'EOF' && ok "innodb sizing: the mount sits under openmrsdb, odoo-connect untouched" || bad "innodb sizing: mount landed under the wrong service"
import sys,re
t=open(sys.argv[1]).read()
oc=t[t.index('  odoo-connect:'):t.index('  openmrsdb:')] if t.index('  odoo-connect:')<t.index('  openmrsdb:') else t[t.index('  odoo-connect:'):]
db=t[t.index('  openmrsdb:'):]
sys.exit(0 if ('openmrsdb-tuning' in db and 'openmrsdb-tuning' not in oc and 'logback' in oc) else 1)
EOF

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
