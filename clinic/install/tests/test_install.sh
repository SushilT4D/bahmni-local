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

out="$(bash "$I" --list 2>&1)"; assert_contains "--list names tasks" "$out" "000-preflight"
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

# --clinic: answers composed from the fleet registry, the ledger, hub.env and the seed's secrets
mkdir -p "$TMP/fleet" "$TMP/home"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=\n' > "$TMP/fleet/azure.env"
printf 'CLINIC_SLUG=morwal\nMRN_PREFIX=MOR\nSITE_NUMBER=\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=\n' > "$TMP/fleet/morwal.env"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.test:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$TMP/hub.env"
printf '# ledger\nmanpur:1\nazure:7\n' > "$TMP/l"
printf 'REMOTE_KAFKA_PASSWORD="m&m"\nOPENMRS_ATOMFEED_PASSWORD=a\nOPENELIS_ATOMFEED_PASSWORD=b\nODOO_ATOMFEED_PASSWORD=c\n' > "$TMP/seed/secrets.env"
rm -f "$TMP/tasks/06-boom.sh"
F(){ FLEET_DIR="$TMP/fleet" HUB_ENV="$TMP/hub.env" ANSWERS_DIR="$TMP/home" LEDGER="$TMP/l" TASKS_DIR="$TMP/tasks" "$@"; }
out="$(F bash "$I" --clinics 2>&1)"
assert_contains "--clinics shows azure with its residue" "$out" "azure      residue 7   MRN AZR"
assert_contains "--clinics shows morwal without one" "$out" "morwal     residue -   MRN MOR"
out="$(F bash "$I" --clinic azure --seed "$TMP/seed" --cert-hostname azure.example.test --dry-run --only 05 </dev/null 2>&1)"
assert_contains "composed answers reach the task" "$out" "T:bahmni-azure:1:$TMP/seed:AZR"
assert_contains "composition is reported" "$out" "answers: composed $TMP/home/clinic-azure.env"
A="$TMP/home/clinic-azure.env"
assert_eq "composed file mode 600" "$(stat -f %Lp "$A" 2>/dev/null || stat -c %a "$A")" "600"
assert_eq "RESIDUE comes from the ledger" "$(grep -E '^RESIDUE=' "$A")" "RESIDUE=7"
assert_eq "SITE_NUMBER defaults to the residue" "$(grep -E '^SITE_NUMBER=' "$A")" "SITE_NUMBER=7"
assert_eq "CERT_HOSTNAME from the flag" "$(grep -E '^CERT_HOSTNAME=' "$A")" "CERT_HOSTNAME=azure.example.test"
assert_eq "hub endpoint from hub.env" "$(grep -E '^REMOTE_KAFKA_BOOTSTRAP_SERVERS=' "$A")" "REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.test:9092"
assert_eq "secret keeps its quoting (Fix round 1: single-quoted)" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$A")" "REMOTE_KAFKA_PASSWORD='m&m'"
out="$(F bash "$I" --clinic azure --seed "$TMP/seed" --dry-run --only 05 </dev/null 2>&1)"
assert_contains "second run reuses the composed file" "$out" "answers: reusing $A"
assert_contains "and still reaches the task" "$out" "T:bahmni-azure"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/tasks/06-boom.sh"
out="$(F bash "$I" --clinic azure --seed "$TMP/seed" --dry-run </dev/null 2>&1)"
assert_contains "resume line names --clinic" "$out" "resume with: $I --clinic azure --seed $TMP/seed --from 06"
rm -f "$TMP/tasks/06-boom.sh"
out="$(F bash "$I" --clinic AZURE --seed "$TMP/seed" --dry-run --only 05 </dev/null 2>&1)"
assert_contains "slug is case-insensitive" "$out" "T:bahmni-azure"
out="$(F bash "$I" --clinic morwal --seed "$TMP/seed" --cert-hostname h --dry-run </dev/null 2>&1)"; rc=$?
assert_eq "no residue refuses" "$rc" "1"
assert_contains "no residue names the allocate command" "$out" "allocate morwal"
out="$(F bash "$I" --clinic nope --seed "$TMP/seed" --dry-run </dev/null 2>&1)"
assert_contains "unknown clinic lists the known ones" "$out" "known: azure morwal"
rm -f "$A" "$TMP/seed/secrets.env"
out="$(F bash "$I" --clinic azure --seed "$TMP/seed" --cert-hostname h --dry-run </dev/null 2>&1)"; rc=$?
assert_eq "no secrets and no terminal refuses" "$rc" "1"
assert_contains "and names the secrets file" "$out" "REMOTE_KAFKA_PASSWORD is not set and there is no terminal to ask on: put it in $TMP/seed/secrets.env"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\nCLINIC_PHONE=\nCERT_HOSTNAME=\n' > "$TMP/fleet/azure.env"   # phone empty: it must be asked
out="$(printf 'h.test\n\nmm\na\nb\nc\n' | INSTALL_INTERACTIVE=1 F bash "$I" --clinic azure --seed "$TMP/seed" --dry-run --only 05 2>&1)"
assert_contains "terminal answers reach the task" "$out" "T:bahmni-azure:1:$TMP/seed:AZR"
assert_eq "typed hostname kept" "$(grep -E '^CERT_HOSTNAME=' "$A")" "CERT_HOSTNAME=h.test"
assert_eq "empty answer takes the default" "$(grep -E '^CLINIC_PHONE=' "$A")" "CLINIC_PHONE=+910000000000"
assert_eq "typed secret kept, quoted only when needed" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$A")" "REMOTE_KAFKA_PASSWORD=mm"
[ "$(printf '%s' "$out" | grep -c 'mm')" = 0 ] && printf '  ok   secret never echoed\n' || { printf '  FAIL secret echoed in output\n'; fails=$((fails+1)); }
rm -f "$A"
out="$(printf 'azure\nh.test\n\nmm\na\nb\nc\n' | INSTALL_INTERACTIVE=1 F bash "$I" --seed "$TMP/seed" --dry-run --only 05 2>&1)"
assert_contains "no flag on a terminal: picks from the table" "$out" "which clinic is this host?"
assert_contains "and installs it" "$out" "T:bahmni-azure"
out="$(F bash "$I" --seed "$TMP/seed" --dry-run </dev/null 2>&1)"
assert_contains "no flag and no terminal: says what is required" "$out" "--clinic <slug> or --answers <file> is required"
exit "$fails"
