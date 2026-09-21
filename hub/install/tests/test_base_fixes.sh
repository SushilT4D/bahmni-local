#!/usr/bin/env bash
# Unit tests for hub/install/tasks/085-base-fixes.sh (D7 login stopgap, D8
# quiet odoo-connect log). No docker, no network, no real BASE_DIR -- the
# pieces that actually touch a live proxy/odoo-connect container (the
# config-test/reload/recreate calls in the task's own main flow) are not
# exercised here, only the pure/marker-guarded functions the task extracts
# into named blocks, the same way clinic/install/tests/test_boot_budget.sh
# pulls `# cpu-budget:begin`...`:end` out of 000-preflight.sh and runs it
# standalone. Runs under plain bash and stock macOS /bin/bash 3.2 (no
# associative arrays, no mapfile, no ${var,,}).
#
# Every extracted block is written to its own temp SCRIPT FILE and run with
# `bash file`, never `bash -c "$string"` -- the d7-rules block contains a
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
d7_rules_blk="$(sed -n '/# d7-rules:begin/,/# d7-rules:end/p' "$TASK")"
d7_insert_blk="$(sed -n '/# d7-insert:begin/,/# d7-insert:end/p' "$TASK")"
comma_ref_blk="$(sed -n '/# comma-strip-ref:begin/,/# comma-strip-ref:end/p' "$TASK")"
d8_override_blk="$(sed -n '/# d8-override:begin/,/# d8-override:end/p' "$TASK")"

[ -n "$d7_rules_blk" ]     || bad "085 has no d7-rules block"
[ -n "$d7_insert_blk" ]    || bad "085 has no d7-insert block"
[ -n "$comma_ref_blk" ]    || bad "085 has no comma-strip-ref block"
[ -n "$d8_override_blk" ]  || bad "085 has no d8-override block"

# mkscript NAME BLOCK... : writes STUBS + the given block(s) + a trailing
# invocation (read from stdin) to ${TMP_ROOT}/NAME.sh and prints its path.
mkscript(){ # NAME
  local out="${TMP_ROOT}/$1.sh"
  { printf '%s\n' "$STUBS"; shift; for b in "$@"; do printf '%s\n' "$b"; done; cat; } > "$out"
  printf '%s' "$out"
}

# --- (ii) the rewrite rules themselves --------------------------------------
rules_script="$(mkscript rules "$d7_rules_blk" <<'EOF'
d7_block
EOF
)"
block_out="$(bash "$rules_script")"
first_comma_pos="$(printf '%s\n' "$block_out" | grep -n 'RewriteCond %{QUERY_STRING}' | head -1 | cut -d: -f1)"
last_comma_pos="$(printf '%s\n' "$block_out" | grep -n 'RewriteCond %{QUERY_STRING}' | tail -1 | cut -d: -f1)"
if [ -n "$first_comma_pos" ] && [ -n "$last_comma_pos" ] && [ "$first_comma_pos" -lt "$last_comma_pos" ]; then
  ok "d7_block: two RewriteCond lines present, in order (two-comma rule before the one-comma rule)"
else
  bad "d7_block: expected two RewriteCond lines with the two-comma rule first (first=${first_comma_pos:-<none>} last=${last_comma_pos:-<none>})"
fi
# The two-comma rule's own RewriteCond line must appear before the one-comma
# rule's: confirmed by checking the FIRST RewriteCond line carries FOUR
# capture-group markers (two ,|%2C)(\)|%29) pairs), the last only two.
first_line="$(printf '%s\n' "$block_out" | grep 'RewriteCond %{QUERY_STRING}' | sed -n '1p')"
last_line="$(printf '%s\n' "$block_out" | grep 'RewriteCond %{QUERY_STRING}' | sed -n '$p')"
first_pairs="$(printf '%s' "$first_line" | grep -o '(?:,|%2C)(\\)|%29)' | wc -l | tr -d ' ')"
last_pairs="$(printf '%s' "$last_line" | grep -o '(?:,|%2C)(\\)|%29)' | wc -l | tr -d ' ')"
if [ "${first_pairs:-0}" -eq 2 ] && [ "${last_pairs:-0}" -eq 1 ]; then
  ok "d7_block: the FIRST RewriteCond matches two comma-before-paren occurrences, the LAST matches one (two-comma case really is handled first)"
else
  bad "d7_block: first RewriteCond has ${first_pairs:-0} comma-before-paren groups (want 2), last has ${last_pairs:-0} (want 1)"
fi
case "$block_out" in
  *'(?:,|%2C)(\)|%29)'*) ok "d7_block: contains the ,/%2C and )/%29 alternations" ;;
  *) bad "d7_block: missing the (?:,|%2C)(\\)|%29) alternation" ;;
esac
case "$block_out" in
  *'[PT,NE]'*) ok "d7_block: carries the [PT,NE] flags" ;;
  *) bad "d7_block: missing [PT,NE] flags" ;;
esac
case "$block_out" in
  *'# F-080 login stopgap (hub/install 085)'*) ok "d7_block: opens with the F-080 marker" ;;
  *) bad "d7_block: missing the opening F-080 marker" ;;
esac
case "$block_out" in
  *'# F-080 end'*) ok "d7_block: closes with the F-080 end marker" ;;
  *) bad "d7_block: missing the F-080 end marker" ;;
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

# --- (i) the D7 inserter against a fixture Apache conf ----------------------
D7_HARNESS="$(mkscript d7harness "$d7_rules_blk" "$d7_insert_blk" <<'EOF'
d7_insert "$1"
EOF
)"

mk_fixture(){ # DIR
  mkdir -p "$1"
  cat > "$1/bahmni-proxy.conf" <<'EOF'
<VirtualHost *:443>
    ServerName bahmni.xoyo.ad
    SSLEngine on

    <Location /openmrs>
        Header always edit Set-Cookie ^(.*)$ $1;HttpOnly
    </Location>

    ProxyPass /openmrs http://openmrs:8080/openmrs
    ProxyPassReverse /openmrs http://openmrs:8080/openmrs
</VirtualHost>
EOF
}

d7dir="${TMP_ROOT}/d7"; mk_fixture "$d7dir"
orig_content="$(cat "${d7dir}/bahmni-proxy.conf")"
out="$(DRY=0 bash "$D7_HARNESS" "${d7dir}/bahmni-proxy.conf" 2>&1)"; rc=$?
assert_rc "d7_insert: first run exits 0" "$rc" 0
assert_contains "d7_insert: first run reports it inserted" "$out" "inserted the login-stopgap"
[ -f "${d7dir}/bahmni-proxy.conf.bak-pre-f080" ] && ok "d7_insert: backup created" || bad "d7_insert: no backup created"
grep -qF '# F-080 login stopgap (hub/install 085)' "${d7dir}/bahmni-proxy.conf" && ok "d7_insert: marker present after insert" || bad "d7_insert: marker missing after insert"
assert_eq "d7_insert: the backup holds the ORIGINAL, unmodified file" "$(cat "${d7dir}/bahmni-proxy.conf.bak-pre-f080")" "$orig_content"
after_first="$(cat "${d7dir}/bahmni-proxy.conf")"
backup_first="$(cat "${d7dir}/bahmni-proxy.conf.bak-pre-f080")"

out2="$(DRY=0 bash "$D7_HARNESS" "${d7dir}/bahmni-proxy.conf" 2>&1)"; rc2=$?
assert_rc "d7_insert: second run exits 0" "$rc2" 0
assert_contains "d7_insert: second run is a no-op (already carries the stopgap)" "$out2" "already carries the login stopgap"
after_second="$(cat "${d7dir}/bahmni-proxy.conf")"
assert_eq "d7_insert: second run leaves the file byte-identical" "$after_second" "$after_first"
backup_second="$(cat "${d7dir}/bahmni-proxy.conf.bak-pre-f080")"
assert_eq "d7_insert: backup is never overwritten by a second run" "$backup_second" "$backup_first"

# no ProxyPass /openmrs anchor -> non-zero, names the file
d7dir_noanchor="${TMP_ROOT}/d7-noanchor"; mkdir -p "$d7dir_noanchor"
printf '<VirtualHost *:443>\n    ServerName bahmni.xoyo.ad\n</VirtualHost>\n' > "${d7dir_noanchor}/bahmni-proxy.conf"
out3="$(DRY=0 bash "$D7_HARNESS" "${d7dir_noanchor}/bahmni-proxy.conf" 2>&1)"; rc3=$?
assert_rc "d7_insert: no ProxyPass /openmrs anchor -> non-zero" "$rc3" 1
assert_contains "d7_insert: failure names the file" "$out3" "${d7dir_noanchor}/bahmni-proxy.conf"
assert_contains "d7_insert: failure names the missing anchor" "$out3" "ProxyPass /openmrs"

# --- (iv, D7 half) DRY leaves the temp dir byte-identical -------------------
d7dir_dry="${TMP_ROOT}/d7-dry"; mk_fixture "$d7dir_dry"
before_listing="$(cd "$d7dir_dry" && find . -type f | sort)"
before_sum="$(cksum < "${d7dir_dry}/bahmni-proxy.conf")"
out4="$(DRY=1 bash "$D7_HARNESS" "${d7dir_dry}/bahmni-proxy.conf" 2>&1)"; rc4=$?
assert_rc "d7_insert: DRY run exits 0" "$rc4" 0
assert_contains "d7_insert: DRY prints a would: line" "$out4" "would:"
after_listing="$(cd "$d7dir_dry" && find . -type f | sort)"
after_sum="$(cksum < "${d7dir_dry}/bahmni-proxy.conf")"
assert_eq "d7_insert: DRY creates no new files in the target dir" "$after_listing" "$before_listing"
assert_eq "d7_insert: DRY leaves the conf file byte-identical" "$after_sum" "$before_sum"

# --- (iii) the D8 override edit against a fixture override YAML ------------
D8_HARNESS="$(mkscript d8harness "$d8_override_blk" <<'EOF'
d8_override_ensure "$1" "$2"
EOF
)"
TARGET='/run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/classes/logback.xml'
MOUNT_LINE="./odoo-connect-logback.xml:${TARGET}:ro"

# no override file at all -> created fresh
d8dir_new="${TMP_ROOT}/d8-new"; mkdir -p "$d8dir_new"
out="$(DRY=0 bash "$D8_HARNESS" "${d8dir_new}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "d8_override_ensure: creating a fresh override file exits 0" "$rc" 0
grep -qF "$MOUNT_LINE" "${d8dir_new}/docker-compose.override.yml" && ok "d8_override_ensure: fresh file carries the mount line" || bad "d8_override_ensure: fresh file missing the mount line"
[ -f "${d8dir_new}/docker-compose.override.yml.bak-pre-d8" ] && bad "d8_override_ensure: a backup was made for a file that did not exist before" || ok "d8_override_ensure: no backup made when there was nothing to back up"

# idempotent: a second run on the same file changes nothing
after_new_first="$(cat "${d8dir_new}/docker-compose.override.yml")"
out="$(DRY=0 bash "$D8_HARNESS" "${d8dir_new}/docker-compose.override.yml" "$TARGET" 2>&1)"
assert_contains "d8_override_ensure: second run is a no-op" "$out" "already mounts"
assert_eq "d8_override_ensure: second run leaves the file byte-identical" "$(cat "${d8dir_new}/docker-compose.override.yml")" "$after_new_first"

# a fixture that ALREADY has an odoo-connect: service with its own volumes:
# list gets the extra entry, not a duplicate odoo-connect: key.
d8dir_existing="${TMP_ROOT}/d8-existing"; mkdir -p "$d8dir_existing"
cat > "${d8dir_existing}/docker-compose.override.yml" <<'EOF'
# D1-D5 header comments here
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
orig_override_content="$(cat "${d8dir_existing}/docker-compose.override.yml")"
out="$(DRY=0 bash "$D8_HARNESS" "${d8dir_existing}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "d8_override_ensure: editing an existing odoo-connect: service exits 0" "$rc" 0
oc_count="$(grep -c '^  odoo-connect:' "${d8dir_existing}/docker-compose.override.yml")"
assert_eq "d8_override_ensure: exactly one odoo-connect: key after the edit (no duplicate)" "$oc_count" "1"
grep -qF "$MOUNT_LINE" "${d8dir_existing}/docker-compose.override.yml" && ok "d8_override_ensure: the mount line was added" || bad "d8_override_ensure: the mount line is missing"
grep -qF "./somefile.jar:/opt/somefile.jar:ro" "${d8dir_existing}/docker-compose.override.yml" && ok "d8_override_ensure: the pre-existing volume entry survives" || bad "d8_override_ensure: the pre-existing volume entry was lost"
grep -qF "proxy-config/bahmni-proxy.conf" "${d8dir_existing}/docker-compose.override.yml" && ok "d8_override_ensure: an unrelated service's config is untouched" || bad "d8_override_ensure: an unrelated service's config was disturbed"
[ -f "${d8dir_existing}/docker-compose.override.yml.bak-pre-d8" ] && ok "d8_override_ensure: backup created for the pre-existing file" || bad "d8_override_ensure: no backup created for the pre-existing file"
assert_eq "d8_override_ensure: the backup holds the ORIGINAL, unmodified file" "$(cat "${d8dir_existing}/docker-compose.override.yml.bak-pre-d8")" "$orig_override_content"

# backup is made once and never overwritten by a later run
backup_first="$(cat "${d8dir_existing}/docker-compose.override.yml.bak-pre-d8")"
bash "$D8_HARNESS" "${d8dir_existing}/docker-compose.override.yml" "$TARGET" >/dev/null 2>&1
backup_second="$(cat "${d8dir_existing}/docker-compose.override.yml.bak-pre-d8")"
assert_eq "d8_override_ensure: backup is never overwritten by a later run" "$backup_second" "$backup_first"

# --- (iv, D8 half) DRY leaves the temp dir byte-identical -------------------
d8dir_dry="${TMP_ROOT}/d8-dry"; mkdir -p "$d8dir_dry"
cat > "${d8dir_dry}/docker-compose.override.yml" <<'EOF'
services:
  odoo-connect:
    logging: *rotate
EOF
before_listing="$(cd "$d8dir_dry" && find . -type f | sort)"
before_sum="$(cksum < "${d8dir_dry}/docker-compose.override.yml")"
out="$(DRY=1 bash "$D8_HARNESS" "${d8dir_dry}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "d8_override_ensure: DRY run exits 0" "$rc" 0
assert_contains "d8_override_ensure: DRY prints a would: line" "$out" "would:"
after_listing="$(cd "$d8dir_dry" && find . -type f | sort)"
after_sum="$(cksum < "${d8dir_dry}/docker-compose.override.yml")"
assert_eq "d8_override_ensure: DRY creates no new files in the target dir" "$after_listing" "$before_listing"
assert_eq "d8_override_ensure: DRY leaves the override file byte-identical" "$after_sum" "$before_sum"

# DRY against a target that does not exist at all -- must not create it
d8dir_dry_missing="${TMP_ROOT}/d8-dry-missing"; mkdir -p "$d8dir_dry_missing"
out="$(DRY=1 bash "$D8_HARNESS" "${d8dir_dry_missing}/docker-compose.override.yml" "$TARGET" 2>&1)"; rc=$?
assert_rc "d8_override_ensure: DRY against a missing file exits 0" "$rc" 0
[ -f "${d8dir_dry_missing}/docker-compose.override.yml" ] && bad "d8_override_ensure: DRY created a file that did not exist before" || ok "d8_override_ensure: DRY against a missing file creates nothing"

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
