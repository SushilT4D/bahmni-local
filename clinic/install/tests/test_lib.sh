#!/usr/bin/env bash
# Unit tests for lib.sh's pure functions. No runtime, no network.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }

export LEDGER="$TMP/clinics.txt"
printf '# ledger\nmanpur:1\nghated:3\nrawach:4\nAzure:7\n' > "$LEDGER"
export CLINIC_DIR="$TMP/clinic"; mkdir -p "$CLINIC_DIR"
export DRY=1
# shellcheck source=../lib.sh
. "${HERE}/../lib.sh"

# identity
derive_identity azure 7
assert_eq "COMPOSE_PROJECT_NAME" "$COMPOSE_PROJECT_NAME" "bahmni-azure"
assert_eq "MYSQL_SERVER_NAME" "$MYSQL_SERVER_NAME" "bahmni-azure"
assert_eq "LOCAL_CLUSTER_ALIAS" "$LOCAL_CLUSTER_ALIAS" "azure"
assert_eq "MYSQL_AUTO_INCREMENT_OFFSET" "$MYSQL_AUTO_INCREMENT_OFFSET" "7"
assert_eq "MYSQL_SERVER_ID" "$MYSQL_SERVER_ID" "7"
assert_eq "DEBEZIUM_SERVER_ID" "$DEBEZIUM_SERVER_ID" "184057"
assert_eq "ODOO_DB_VOLUME_NAME" "$ODOO_DB_VOLUME_NAME" "bahmni-azure_odoodb-data"
assert_eq "ODOO_APP_VOLUME_NAME" "$ODOO_APP_VOLUME_NAME" "bahmni-azure_odooapp-data"
( derive_identity 'Bad Slug' 7 ) >/dev/null 2>&1; assert_rc "bad slug refused" $? 1
( derive_identity azure 10 ) >/dev/null 2>&1;    assert_rc "residue 10 refused" $? 1

# ledger
assert_eq "ledger_residue case-insensitive" "$(ledger_residue AZURE)" "7"
assert_eq "ledger_residue missing" "$(ledger_residue morwal)" ""
assert_eq "ledger_conflicts none" "$(ledger_conflicts azure 7)" ""
assert_eq "ledger_conflicts other row" "$(ledger_conflicts azure 4)" "rawach"

# env_put / env_get
f="$TMP/e.env"; printf 'A=1\nB=<placeholder>\n# c\nC=\n' > "$f"
env_put "$f" B 'x&y/z#w'
env_put "$f" D 'plain'
env_put "$f" E 'has space'
assert_eq "env_put replaces" "$(env_get "$f" B)" 'x&y/z#w'

# ensure_openmrs_jvm_opts: pins the heap cap only (sync-core Task 4, 2026-09-17). The
# container-support flag is retired with the 1.2.0 image pin: this function must no
# longer ADD it (that would silently reintroduce what .env.example just dropped), but
# it also never STRIPS one an operator (or a node still on the old image) set by hand.
j="$TMP/jvm.env"
printf 'A=1\nOMRS_JAVA_MEMORY_OPTS="-XX:NewSize=128m"\nOMRS_JAVA_SERVER_OPTS="-Dfile.encoding=UTF-8 -server -Djava.awt.headless=true"\n' > "$j"
ensure_openmrs_jvm_opts "$j" >/dev/null
assert_eq "jvm opts: server opts untouched (flag not re-added)" "$(env_get "$j" OMRS_JAVA_SERVER_OPTS)" '-Dfile.encoding=UTF-8 -server -Djava.awt.headless=true'
assert_eq "jvm opts: heap pinned when no -Xmx" "$(env_get "$j" OMRS_JAVA_MEMORY_OPTS)" "$OMRS_HEAP_CAP"
before="$(cat "$j")"; ensure_openmrs_jvm_opts "$j" >/dev/null
assert_eq "jvm opts: second call changes nothing" "$(cat "$j")" "$before"
printf 'OMRS_JAVA_MEMORY_OPTS="-Xms1g -Xmx3g"\nOMRS_JAVA_SERVER_OPTS="-server -XX:-UseContainerSupport -Dx=1"\n' > "$j"
ensure_openmrs_jvm_opts "$j" >/dev/null
assert_eq "jvm opts: operator heap kept" "$(env_get "$j" OMRS_JAVA_MEMORY_OPTS)" '-Xms1g -Xmx3g'
assert_eq "jvm opts: an operator's own flag is not stripped" "$(env_get "$j" OMRS_JAVA_SERVER_OPTS)" '-server -XX:-UseContainerSupport -Dx=1'
printf 'A=1\n' > "$j"; ensure_openmrs_jvm_opts "$j" >/dev/null
assert_eq "jvm opts: server opts key not created when absent" "$(env_get "$j" OMRS_JAVA_SERVER_OPTS)" ''
assert_eq "env_put appends" "$(env_get "$f" D)" "plain"
assert_eq "env_put single-quotes a space (Fix round 1: single, not double -- see below)" "$(grep -E '^E=' "$f")" "E='has space'"
assert_eq "env_get strips quotes" "$(env_get "$f" E)" "has space"
assert_eq "env_put keeps other lines" "$(grep -c . "$f")" "6"

# Fix round 1 (code review, live PoC): env_put's old double-quote-on-trigger
# scheme never escaped an embedded `"`, so a value like the reviewer's own
# `pass"; touch ...; echo "` was written as literal shell code that RUNS the
# moment any task `.`-sources the file. The only representation bash and
# docker compose's dotenv parser read identically is a single-quoted value
# with no `'` inside it -- everything between a pair of `'` is fully literal
# to both, so nothing in the value can be reinterpreted by either reader.
#
# Round-trips byte-for-byte through BOTH env_get's own parse AND actually
# `.`-sourcing the file directly (hub/.env and clinic/.env are `.`-sourced by
# every install task, not just read with env_get) -- and, for the injection
# string specifically, PROVES no side effect occurred, rather than just
# checking the string value came back unchanged (a value that round-trips
# but was ALSO executed once on the way would still "pass" a naive
# string-equality check).
marker_dir="$TMP/marker"; mkdir -p "$marker_dir"
check_env_put_value(){ # LABEL VALUE
  local label="$1" val="$2" f3 got
  f3="$TMP/e3-$$-${RANDOM}.env"; : > "$f3"
  env_put "$f3" V "$val"
  got="$(env_get "$f3" V)"
  assert_eq "env_put round-trips ${label} through env_get" "$got" "$val"
  got="$(set -a; . "$f3"; set +a; printf '%s' "$V")"
  assert_eq "env_put round-trips ${label} through . sourcing directly" "$got" "$val"
  rm -f "$f3"
}
check_env_put_value 'a value with a double quote'      'pass"word'
check_env_put_value 'a value with a backslash'         'pass\word'
check_env_put_value 'a value with a dollar sign'       'pass$word'
check_env_put_value 'a value with a space'             'pass word'
check_env_put_value 'a value with a hash'              'pass#word'
check_env_put_value 'a value with a semicolon'         'pass;word'
check_env_put_value "the reviewer's exact injection string" 'pass"; touch '"$marker_dir"'/PWNED; echo "'
assert_eq "the injection string never actually ran (no marker file)" "$([ -e "$marker_dir/PWNED" ] && echo RAN || echo safe)" "safe"

# A value containing a `'` cannot be represented identically for both
# readers -- refused outright, naming the key, rather than silently picking
# one reader's interpretation over the other's.
f4="$TMP/e4.env"; : > "$f4"
out="$(env_put "$f4" QUOTED "can't" 2>&1)"; rc=$?
assert_rc "env_put refuses a value containing a single quote" "$rc" 1
case "$out" in *"QUOTED"*"single quote"*) named=yes ;; *) named=no ;; esac
assert_eq "the refusal names the key and the reason" "$named" "yes"
assert_eq "nothing was written for the refused key" "$(grep -c '^QUOTED=' "$f4")" "0"

# gen_secret must never itself produce a value env_put would have to refuse.
bad_secret=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  case "$(gen_secret)" in *"'"*) bad_secret=yes ;; esac
done
assert_eq "gen_secret never emits a single quote (env_put would refuse it)" "${bad_secret:-no}" "no"

# placeholders
printf 'A=1\nB=<x>\nC=\nMAIL_USER=\n' > "$f"
assert_eq "has_placeholders lists B and C, honours allowlist" "$(has_placeholders "$f" "MAIL_USER" | tr '\n' ' ')" "B C "

# inherited alias
# the alias must be this node's own slug; a name from another node's env is inherited
( refuse_inherited_alias source azure ) >/dev/null 2>&1; assert_rc "alias source on node azure refused" $? 1
( refuse_inherited_alias ghated azure ) >/dev/null 2>&1; assert_rc "alias ghated on node azure refused" $? 1
( refuse_inherited_alias ghated ghated ) >/dev/null 2>&1; assert_rc "alias ghated on node ghated accepted (a node may be ghated)" $? 0
( refuse_inherited_alias azure azure )  >/dev/null 2>&1; assert_rc "alias azure on node azure accepted" $? 0
( refuse_inherited_alias manpur azure ) >/dev/null 2>&1; assert_rc "any alias that is not the slug is refused" $? 1
( refuse_inherited_alias source ) >/dev/null 2>&1; assert_rc "without a slug, a template name is still refused" $? 1
( refuse_inherited_alias azure )  >/dev/null 2>&1; assert_rc "without a slug, an unlisted name passes" $? 0

# secrets and ids
s1="$(gen_secret)"; s2="$(gen_secret)"
assert_eq "gen_secret length" "${#s1}" "32"
[ "$s1" != "$s2" ] && printf '  ok   gen_secret differs\n' || { printf '  FAIL gen_secret repeats\n'; fails=$((fails+1)); }
k="$(kafka_cluster_id)"; assert_eq "kafka_cluster_id length" "${#k}" "22"

# fleet registry
export FLEET_DIR="$TMP/fleet"; mkdir -p "$FLEET_DIR"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\n' > "$FLEET_DIR/azure.env"
printf 'CLINIC_SLUG=morwal\nMRN_PREFIX=MOR\nSITE_NUMBER=\n' > "$FLEET_DIR/morwal.env"
assert_eq "fleet_slugs" "$(fleet_slugs | tr '\n' ' ')" "azure morwal "
assert_eq "fleet_file case-insensitive" "$(fleet_file AZURE)" "$FLEET_DIR/azure.env"
( fleet_file nope ) >/dev/null 2>&1; assert_rc "fleet_file unknown is non-zero" $? 1
assert_eq "fleet_table" "$(fleet_table | tr '\n' '|')" "  azure      residue 7   MRN AZR|  morwal     residue -   MRN MOR|"
# answers
a="$TMP/a.env"; printf 'CLINIC_SLUG=azure\nRESIDUE=7\nMRN_PREFIX=\n' > "$a"
assert_eq "answers_missing lists empty and absent keys" "$(answers_missing "$a" | head -3 | tr '\n' ' ')" "MRN_PREFIX SITE_NUMBER CLINIC_PHONE "
( CLINIC_SLUG=azure RESIDUE=7 MRN_PREFIX=AZR SITE_NUMBER=7 CLINIC_PHONE=+910000000000 CERT_HOSTNAME=h REMOTE_KAFKA_BOOTSTRAP_SERVERS=b:9092 REMOTE_KAFKA_USERNAME=u REMOTE_KAFKA_PASSWORD='p w' OPENMRS_ATOMFEED_PASSWORD=a OPENELIS_ATOMFEED_PASSWORD=b ODOO_ATOMFEED_PASSWORD=c answers_write "$a" )
assert_eq "answers_write writes twelve keys" "$(grep -c '^[A-Z_]*=' "$a")" "12"
assert_eq "answers_write nothing missing" "$(answers_missing "$a" | tr '\n' ' ')" ""
assert_eq "answers_write quotes a space (Fix round 1: single-quoted)" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$a")" "REMOTE_KAFKA_PASSWORD='p w'"
assert_eq "answers_write mode 600" "$(stat -f %Lp "$a" 2>/dev/null || stat -c %a "$a")" "600"
# ask / ask_secret
X=set; ask X "q" "d" "here" </dev/null; assert_eq "ask keeps a set value" "$X" "set"
X=""; ( ask X "q" "d" "here" </dev/null ) >/dev/null 2>&1; assert_rc "ask with no terminal fails" $? 1
X=""; INSTALL_INTERACTIVE=1 ask X "q" "d" "here" <<< "" 2>/dev/null; assert_eq "ask empty answer = default" "$X" "d"
X=""; INSTALL_INTERACTIVE=1 ask X "q" "d" "here" <<< "typed" 2>/dev/null; assert_eq "ask typed answer" "$X" "typed"
X=""; ( INSTALL_INTERACTIVE=1 ask X "q" "" "here" <<< "" ) >/dev/null 2>&1; assert_rc "ask empty with no default fails" $? 1
X=""; INSTALL_INTERACTIVE=1 ask_secret X "here" <<< "s3cret" 2>/dev/null; assert_eq "ask_secret reads hidden" "$X" "s3cret"
X=""; ( ask_secret X "here" </dev/null ) >/dev/null 2>&1; assert_rc "ask_secret with no terminal fails" $? 1

# run honours DRY
out="$(run echo hello)"; assert_eq "run in dry mode prints" "$out" "  would: echo hello"
DRY=0; out="$(run echo hello)"; assert_eq "run in live mode executes" "$out" "hello"

# subsystem_tables: one parsing path for sync/subsystems.conf, trimmed + validated
# (code review, 2026-09-17 -- an untrimmed row used to silently leave a table
# unstrided; see lib.sh's own comment on the function).
mkdir -p "$REPO_DIR/sync"
SUBS="$REPO_DIR/sync/subsystems.conf"
printf 'odoo:all\nclinlims:all\n\nodoo:res_partner   \nodoo:account_move  # trailing inline comment\nodoo:uom_uom\nclinlims:sample\n' > "$SUBS"
assert_eq "subsystem_tables trims trailing whitespace off a row" "$(subsystem_tables odoo | tr '\n' ' ' | sed 's/ $//')" "res_partner account_move uom_uom"
assert_eq "subsystem_tables strips a trailing # comment" "$(subsystem_tables odoo | sed -n 2p)" "account_move"
assert_eq "subsystem_tables skips the :all row" "$(subsystem_tables odoo | grep -c '^all$')" "0"
assert_eq "subsystem_tables filters by subsystem prefix" "$(subsystem_tables clinlims)" "sample"
printf 'odoo:Bad-Name\n' >> "$SUBS"
out="$(subsystem_tables odoo 2>&1 1>/dev/null)"; rc=$?
assert_rc "subsystem_tables fails on a name that is not a bare identifier" "$rc" "1"
case "$out" in *"Bad-Name"*) named=yes ;; *) named=no ;; esac
assert_eq "subsystem_tables names the offending row in its failure" "$named" "yes"
# A file with NO trailing newline on its last line -- bash's `read` returns
# non-zero there, which would otherwise drop that last row silently (code
# review, round 2, 2026-09-17).
printf 'odoo:a\nodoo:b' > "$SUBS"
assert_eq "subsystem_tables reads an unterminated last line too" "$(subsystem_tables odoo | tr '\n' ' ' | sed 's/ $//')" "a b"
printf 'odoo:all\nclinlims:all\n\nodoo:res_partner\nclinlims:sample\n' > "$SUBS"   # leave a clean file behind

# versions_put: a sync/versions.env with NO trailing newline on its last line
# (the same unterminated-last-line trap subsystem_tables was fixed for above)
# must still land its final key in the rendered target file.
printf 'A=1\nB=2' > "$TMP/sync/versions.env"
tgt="$TMP/versions-target.env"; : > "$tgt"
versions_put "$tgt"
assert_eq "versions_put reads an unterminated last line too (A)" "$(env_get "$tgt" A)" "1"
assert_eq "versions_put reads an unterminated last line too (B)" "$(env_get "$tgt" B)" "2"
printf 'A=1\nB=2\n' > "$TMP/sync/versions.env"   # leave a clean file behind

# user_in_group_db reads the group DATABASE (id -nG USER), not the process's groups: right
# after usermod the process list lacks the new group while the database already has it --
# exactly what task 010 must see to hand over to the runner's `sg docker` re-exec.
( id(){ case "$*" in "-nG") echo "adm sudo";; "-nG tester") echo "adm sudo docker";; "-un") echo tester;; esac; }
  USER=tester; user_in_group_db docker ); assert_rc "user_in_group_db sees a group added this minute" "$?" 0
( id(){ case "$*" in "-nG"|"-nG tester") echo "adm sudo";; "-un") echo tester;; esac; }
  USER=tester; user_in_group_db docker ); assert_rc "user_in_group_db says no when the database lacks it" "$?" 1
bare="$(grep -nE 'id -nG' "${HERE}/../tasks/"*.sh "${HERE}/../host-linux.sh" "${HERE}/../host-macos.sh" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#' | grep -v 'id -nG "\$' || true)"
assert_eq "no task or host layer reads group membership from the bare process list" "$bare" ""
# second pass under sg: 010 must reach a FAIL line, never a second silent exit 75
assert_eq "010 exits 75 only when the group is not yet activated for this run" "$(grep -c '_KRAFT_SG:-}" != 1 \] && \[ "$(detect_runtime)" = docker' "${HERE}/../tasks/010-host.sh")" "1"
assert_eq "010 names the fault when docker is down after activation" "$(grep -c 'still does not answer after the docker group was activated' "${HERE}/../tasks/010-host.sh")" "1"

# mysql_ready: an authenticated query over TCP, never `mysqladmin ping` -- ping exits 0 even on
# "Access denied", so it passes against the image's temporary first-boot server (socket-only,
# root not yet passworded) and the restore then dies with ERROR 1045 (manpur, 2026-09-18).
: > "$TMP/ct.log"
( ct(){ printf '%s\n' "$*" >> "$TMP/ct.log"; case "$*" in *-h127.0.0.1*"select 1"*) printf '1\n' ;; *) return 1 ;; esac; }
  mysql_ready fake-mysql ); assert_rc "mysql_ready is true when the authenticated TCP query answers 1" "$?" 0
assert_eq "mysql_ready asks over TCP (the temp server runs --skip-networking)" "$(grep -c -- '-h127.0.0.1' "$TMP/ct.log")" "1"
assert_eq "mysql_ready never uses mysqladmin ping" "$(grep -c mysqladmin "$TMP/ct.log")" "0"
assert_eq "mysql_ready keeps the password off the command line" "$(grep -cE -- ' -p"?\$' "$TMP/ct.log")" "0"
( ct(){ printf 'ERROR 1045 (28000): Access denied\n' >&2; return 1; }; mysql_ready fake-mysql ); assert_rc "mysql_ready is false on access denied" "$?" 1
( ct(){ return 0; }; mysql_ready fake-mysql ); assert_rc "mysql_ready is false when the server answers nothing" "$?" 1
assert_eq "task 050 waits with mysql_ready, not mysqladmin" "$(grep -c mysqladmin "${HERE}/../tasks/050-databases.sh")/$(grep -c 'mysql_ready "\$MY"' "${HERE}/../tasks/050-databases.sh")" "0/1"
assert_eq "task 050 asks postgres over TCP too (its init server is socket-only)" "$(grep -c 'pg_isready -h 127.0.0.1' "${HERE}/../tasks/050-databases.sh")" "1"

exit "$fails"
