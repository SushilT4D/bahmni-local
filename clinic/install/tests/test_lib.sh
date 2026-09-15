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
assert_eq "env_put appends" "$(env_get "$f" D)" "plain"
assert_eq "env_put quotes a space" "$(grep -E '^E=' "$f")" 'E="has space"'
assert_eq "env_get strips quotes" "$(env_get "$f" E)" "has space"
assert_eq "env_put keeps other lines" "$(grep -c . "$f")" "6"

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

exit "$fails"
