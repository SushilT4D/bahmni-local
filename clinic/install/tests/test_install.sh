#!/usr/bin/env bash
# install.sh: flags, answer validation, task listing, dry-run wiring.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: output lacks %q\n' "$1" "$3"; fails=$((fails+1)); fi; }

I="${HERE}/../install.sh"
mkdir -p "$TMP/seed" "$TMP/clinic"; : > "$TMP/seed/openmrs.sql.gz"
cat > "$TMP/answers.env" <<EOF
CLINIC_SLUG=azure
RESIDUE=7
MRN_PREFIX=AZR
SITE_NUMBER=7
CLINIC_PHONE=+910000000000
CERT_HOSTNAME=azure.example.test
REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.test:9092
REMOTE_KAFKA_USERNAME=mirrormaker
REMOTE_KAFKA_PASSWORD=mmpw
OPENMRS_ATOMFEED_PASSWORD=a
OPENELIS_ATOMFEED_PASSWORD=b
ODOO_ATOMFEED_PASSWORD=c
EOF

out="$(bash "$I" --list 2>&1)"; assert_contains "--list names tasks" "$out" "00-preflight"
out="$(bash "$I" --seed "$TMP/seed" --dry-run 2>&1)"; assert_contains "missing --answers refused" "$out" "--answers"
sed '/^RESIDUE=/d' "$TMP/answers.env" > "$TMP/short.env"
out="$(bash "$I" --answers "$TMP/short.env" --seed "$TMP/seed" --dry-run 2>&1)"; assert_contains "missing key named" "$out" "RESIDUE"
out="$(bash "$I" --answers "$TMP/answers.env" --seed "$TMP/nope" --dry-run 2>&1)"; assert_contains "missing seed dir refused" "$out" "seed"
# a task that only echoes its environment proves the export contract
mkdir -p "$TMP/tasks"; printf '#!/usr/bin/env bash\necho "T:$COMPOSE_PROJECT_NAME:$DRY:$SEED_DIR:$MRN_PREFIX"\n' > "$TMP/tasks/05-probe.sh"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run 2>&1)"
assert_contains "task sees derived identity, DRY and SEED_DIR" "$out" "T:bahmni-azure:1:$TMP/seed:AZR"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/tasks/06-boom.sh"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run 2>&1)"; rc=$?
assert_eq "failing task stops the run" "$rc" "1"
assert_contains "failing task is named" "$out" "06-boom"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run --only 05 2>&1)"
assert_contains "--only runs the one task" "$out" "T:bahmni-azure"
exit "$fails"
