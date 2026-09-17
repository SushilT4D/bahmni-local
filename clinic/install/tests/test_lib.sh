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
assert_eq "env_put quotes a space" "$(grep -E '^E=' "$f")" 'E="has space"'
assert_eq "env_get strips quotes" "$(env_get "$f" E)" "has space"
assert_eq "env_put keeps other lines" "$(grep -c . "$f")" "6"

# env_put quoting guard also triggers on a single quote or a backslash (Task
# 7 fold-in, hub-side ruling; env_put itself is shared with the hub): a
# generated or operator-typed secret carrying either character must survive
# both env_get's own parse AND being `.`-sourced directly by a real shell --
# hub/.env is `. `-sourced by every install task, not just read with
# env_get, so the round trip through sourcing is the test that actually
# matters. raw_pw mirrors the fixed test value hub/install/tests/test_lib.sh
# already uses for pg_lit_escape/mysql_lit_escape: 5 chars, a ' b \ c.
raw_pw="a'b\\c"
f2="$TMP/e2.env"; : > "$f2"
env_put "$f2" SECRET "$raw_pw"
assert_eq "env_put quotes a value containing a single quote and a backslash" "$(grep -c '^SECRET="' "$f2")" "1"
assert_eq "env_put round-trips a quote+backslash value through env_get" "$(env_get "$f2" SECRET)" "$raw_pw"
( set -a; . "$f2"; set +a; [ "$SECRET" = "$raw_pw" ] )
assert_rc "env_put-written value survives being sourced directly, not just env_get" $? 0

# placeholders
printf 'A=1\nB=<x>\nC=\nMAIL_USER=\n' > "$f"
assert_eq "has_placeholders lists B and C, honours allowlist" "$(has_placeholders "$f" "MAIL_USER" | tr '\n' ' ')" "B C "

# inherited alias
( refuse_inherited_alias source ) >/dev/null 2>&1; assert_rc "alias source refused" $? 1
( refuse_inherited_alias ghated ) >/dev/null 2>&1; assert_rc "alias ghated refused" $? 1
( refuse_inherited_alias azure )  >/dev/null 2>&1; assert_rc "alias azure accepted" $? 0

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
assert_eq "answers_write quotes a space" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$a")" 'REMOTE_KAFKA_PASSWORD="p w"'
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

exit "$fails"
