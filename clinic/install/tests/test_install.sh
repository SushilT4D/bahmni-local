#!/usr/bin/env bash
# install.sh: flags, answer validation, task listing, dry-run wiring.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: output lacks %q\n' "$1" "$3"; fails=$((fails+1)); fi; }

I="${HERE}/../install.sh"
mkdir -p "$TMP/clinic"; printf 'REMOTE_KAFKA_PASSWORD=m\nOPENMRS_ATOMFEED_PASSWORD=a\nOPENELIS_ATOMFEED_PASSWORD=b\nODOO_ATOMFEED_PASSWORD=c\n' > "$TMP/secrets.env"
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
out="$(bash "$I" --dry-run </dev/null 2>&1)"; assert_contains "missing --answers refused" "$out" "--answers"
sed '/^RESIDUE=/d' "$TMP/answers.env" > "$TMP/short.env"
out="$(bash "$I" --answers "$TMP/short.env" --secrets "$TMP/secrets.env" --dry-run 2>&1)"; assert_contains "missing key named" "$out" "RESIDUE"
out="$(bash "$I" --answers "$TMP/answers.env" --seed "$TMP/x" --dry-run 2>&1)"; assert_contains "--seed is no longer an install flag" "$out" "unknown argument: --seed"
assert_contains "usage names --secrets" "$out" "--secrets"
out="$(bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/nope" --dry-run 2>&1)"; assert_contains "missing secrets file refused" "$out" "secrets file not found"
# a task that only echoes its environment proves the export contract
mkdir -p "$TMP/tasks"; printf '#!/usr/bin/env bash\necho "T:$COMPOSE_PROJECT_NAME:$DRY:$MRN_PREFIX:$LAN_NAME"\n' > "$TMP/tasks/05-probe.sh"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --dry-run 2>&1)"
assert_contains "task sees derived identity, DRY and the LAN name" "$out" "T:bahmni-azure:1:AZR:bahmni.clinic"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/tasks/06-boom.sh"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --dry-run 2>&1)"; rc=$?
assert_eq "failing task stops the run" "$rc" "1"
assert_contains "failing task is named" "$out" "06-boom"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --dry-run --only 05 2>&1)"
assert_contains "--only runs the one task" "$out" "T:bahmni-azure"

# --clinic: answers composed from the fleet registry, the ledger, hub.env and the operator's secrets file
mkdir -p "$TMP/fleet" "$TMP/home"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=\n' > "$TMP/fleet/azure.env"
printf 'CLINIC_SLUG=morwal\nMRN_PREFIX=MOR\nSITE_NUMBER=\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=\n' > "$TMP/fleet/morwal.env"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.test:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$TMP/hub.env"
printf '# ledger\nmanpur:1\nazure:7\n' > "$TMP/l"
printf 'REMOTE_KAFKA_PASSWORD="m&m"\nOPENMRS_ATOMFEED_PASSWORD=a\nOPENELIS_ATOMFEED_PASSWORD=b\nODOO_ATOMFEED_PASSWORD=c\n' > "$TMP/secrets.env"
rm -f "$TMP/tasks/06-boom.sh"
F(){ FLEET_DIR="$TMP/fleet" HUB_ENV="$TMP/hub.env" ANSWERS_DIR="$TMP/home" LEDGER="$TMP/l" TASKS_DIR="$TMP/tasks" "$@"; }
out="$(F bash "$I" --clinics 2>&1)"
assert_contains "--clinics shows azure with its residue" "$out" "azure      residue 7   MRN AZR"
assert_contains "--clinics shows morwal without one" "$out" "morwal     residue -   MRN MOR"
out="$(F bash "$I" --clinic azure --secrets "$TMP/secrets.env" --cert-hostname azure.example.test --dry-run --only 05 </dev/null 2>&1)"
assert_contains "composed answers reach the task" "$out" "T:bahmni-azure:1:AZR:bahmni.clinic"
assert_contains "composition is reported" "$out" "answers: composed $TMP/home/clinic-azure.env"
A="$TMP/home/clinic-azure.env"
assert_eq "composed file mode 600" "$(stat -f %Lp "$A" 2>/dev/null || stat -c %a "$A")" "600"
assert_eq "RESIDUE comes from the ledger" "$(grep -E '^RESIDUE=' "$A")" "RESIDUE=7"
assert_eq "SITE_NUMBER defaults to the residue" "$(grep -E '^SITE_NUMBER=' "$A")" "SITE_NUMBER=7"
assert_eq "CERT_HOSTNAME from the flag" "$(grep -E '^CERT_HOSTNAME=' "$A")" "CERT_HOSTNAME=azure.example.test"
assert_eq "hub endpoint from hub.env" "$(grep -E '^REMOTE_KAFKA_BOOTSTRAP_SERVERS=' "$A")" "REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.test:9092"
assert_eq "secret keeps its quoting (single-quoted)" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$A")" "REMOTE_KAFKA_PASSWORD='m&m'"
out="$(F bash "$I" --clinic azure --secrets "$TMP/secrets.env" --dry-run --only 05 </dev/null 2>&1)"
assert_contains "second run reuses the composed file" "$out" "answers: reusing $A"
assert_contains "and still reaches the task" "$out" "T:bahmni-azure"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/tasks/06-boom.sh"
out="$(F bash "$I" --clinic azure --secrets "$TMP/secrets.env" --dry-run </dev/null 2>&1)"
assert_contains "resume line names --clinic" "$out" "resume with: $I --clinic azure --secrets $TMP/secrets.env --from 06"
rm -f "$TMP/tasks/06-boom.sh"
out="$(F bash "$I" --clinic AZURE --secrets "$TMP/secrets.env" --dry-run --only 05 </dev/null 2>&1)"
assert_contains "slug is case-insensitive" "$out" "T:bahmni-azure"
out="$(F bash "$I" --clinic morwal --secrets "$TMP/secrets.env" --cert-hostname h --dry-run </dev/null 2>&1)"; rc=$?
assert_eq "no residue refuses" "$rc" "1"
assert_contains "no residue names the allocate command" "$out" "allocate morwal"
out="$(F bash "$I" --clinic nope --secrets "$TMP/secrets.env" --dry-run </dev/null 2>&1)"
assert_contains "unknown clinic lists the known ones" "$out" "known: azure morwal"
rm -f "$A"
out="$(F bash "$I" --clinic azure --cert-hostname h --dry-run </dev/null 2>&1)"; rc=$?
assert_eq "no secrets and no terminal refuses" "$rc" "1"
assert_contains "and names the secrets file" "$out" "REMOTE_KAFKA_PASSWORD is not set and there is no terminal to ask on: put it in --secrets"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\nCLINIC_PHONE=\nCERT_HOSTNAME=\n' > "$TMP/fleet/azure.env"   # phone empty: it must be asked
out="$(printf 'h.test\n\nqZ7sekretQ\na\nb\nc\n' | INSTALL_INTERACTIVE=1 F bash "$I" --clinic azure --dry-run --only 05 2>&1)"
assert_contains "terminal answers reach the task" "$out" "T:bahmni-azure:1:AZR:bahmni.clinic"
assert_eq "typed hostname kept" "$(grep -E '^CERT_HOSTNAME=' "$A")" "CERT_HOSTNAME=h.test"
assert_eq "empty answer takes the default" "$(grep -E '^CLINIC_PHONE=' "$A")" "CLINIC_PHONE=+910000000000"
assert_eq "typed secret kept, quoted only when needed" "$(grep -E '^REMOTE_KAFKA_PASSWORD=' "$A")" "REMOTE_KAFKA_PASSWORD=qZ7sekretQ"
[ "$(printf '%s' "$out" | grep -c 'qZ7sekretQ')" = 0 ] && printf '  ok   secret never echoed\n' || { printf '  FAIL secret echoed in output\n'; fails=$((fails+1)); }
rm -f "$A"
out="$(printf 'azure\nh.test\n\nqZ7sekretQ\na\nb\nc\n' | INSTALL_INTERACTIVE=1 F bash "$I" --dry-run --only 05 2>&1)"
assert_contains "no flag on a terminal: picks from the table" "$out" "which clinic is this host?"
assert_contains "and installs it" "$out" "T:bahmni-azure"
out="$(F bash "$I" --dry-run </dev/null 2>&1)"
assert_contains "no flag and no terminal: says what is required" "$out" "--clinic <slug> or --answers <file> is required"
# a seeded machine is never put back to the baseline, not even by a resume
mkdir -p "$TMP/c2"; printf 'STATE=SEEDED\n' > "$TMP/c2/.install-state"
out="$(CLINIC_DIR="$TMP/c2" VERSIONS_FILE="${HERE}/../../../sync/versions.env" TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" bash "$I" --answers "$TMP/answers.env" --from 010 --dry-run 2>&1)"; rc=$?
assert_eq "install --from on a seeded machine refused (rc)" "$rc" "1"
assert_contains "and says why" "$out" "this machine is already seeded"
assert_eq "the stamp still says SEEDED" "$(cat "$TMP/c2/.install-state")" "STATE=SEEDED"

# application image versions: the defaults, the answers file, --versions, the prompt
printf '#!/usr/bin/env bash\necho "IMG:$BAHMNI_WEB_IMAGE:$OPENELIS_IMAGE_TAG:$KAFKA_IMAGE"\n' > "$TMP/tasks/07-images.sh"
V="${HERE}/../../../sync/versions.env"; pin(){ sed -nE "s/^$1=([^#[:space:]]+).*/\1/p" "$V"; }
WEB="$(pin BAHMNI_WEB_IMAGE)"; OE="$(pin OPENELIS_IMAGE_TAG)"; KI="$(pin KAFKA_IMAGE)"; WEB_NAME="${WEB%:*}"
G(){ TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" "$@"; }
out="$(G bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --dry-run --only 07 2>&1)"
assert_contains "no choice: a task sees the defaults" "$out" "IMG:${WEB}:${OE}:${KI}"
assert_contains "and the run says so" "$out" "application images: the defaults in sync/versions.env"
printf 'BAHMNI_WEB_IMAGE=bhs-9.9.9\nOPENELIS_IMAGE_TAG=1.0.0-99\n' > "$TMP/versions.env"
out="$(G bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --versions "$TMP/versions.env" --dry-run --only 07 2>&1)"
assert_contains "--versions: a task sees the chosen images, the sync layer unchanged" "$out" "IMG:${WEB_NAME}:bhs-9.9.9:1.0.0-99:${KI}"
assert_contains "--versions: the change is reported" "$out" "image BAHMNI_WEB_IMAGE=${WEB_NAME}:bhs-9.9.9 (default ${WEB})"
assert_contains "--versions: an OpenELIS change warns about lockstep" "$out" "WARN OPENELIS_IMAGE_TAG"
printf 'KAFKA_IMAGE=confluentinc/cp-kafka:7.6.0\n' > "$TMP/bad-versions.env"
out="$(G bash "$I" --answers "$TMP/answers.env" --secrets "$TMP/secrets.env" --versions "$TMP/bad-versions.env" --dry-run --only 07 2>&1)"; rc=$?
assert_eq "--versions naming the sync layer refused (rc)" "$rc" "1"
assert_contains "and says which images may be chosen" "$out" "is not an application image a node can choose"
out="$(G bash "$I" --answers "$TMP/answers.env" --versions "$TMP/nope.env" --dry-run 2>&1)"
assert_contains "missing --versions file refused" "$out" "image versions file not found"
cp "$TMP/answers.env" "$TMP/answers-img.env"; printf 'BAHMNI_WEB_IMAGE=acme/web:2\nKAFKA_IMAGE=confluentinc/cp-kafka:7.6.0\n' >> "$TMP/answers-img.env"
out="$(G bash "$I" --answers "$TMP/answers-img.env" --secrets "$TMP/secrets.env" --dry-run --only 07 2>&1)"
assert_contains "an answers file chooses an application image, never the sync layer" "$out" "IMG:acme/web:2:${OE}:${KI}"
out="$(G bash "$I" --answers "$TMP/answers-img.env" --secrets "$TMP/secrets.env" --versions "$TMP/versions.env" --dry-run --only 07 2>&1)"
assert_contains "--versions wins over the answers file" "$out" "IMG:${WEB_NAME}:bhs-9.9.9:1.0.0-99:${KI}"
printf 'CLINIC_SLUG=azure\nMRN_PREFIX=AZR\nSITE_NUMBER=\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=\n' > "$TMP/fleet/azure.env"
A="$TMP/home/clinic-azure.env"; rm -f "$A"
out="$(F bash "$I" --clinic azure --secrets "$TMP/secrets.env" --versions "$TMP/versions.env" --cert-hostname azure.example.test --dry-run --only 07 </dev/null 2>&1)"
assert_eq "--clinic keeps the chosen image in the answers file" "$(grep -E '^BAHMNI_WEB_IMAGE=' "$A")" "BAHMNI_WEB_IMAGE=${WEB_NAME}:bhs-9.9.9"
assert_eq "and not the ones left at their default" "$(grep -c '^PATIENT_DOCUMENTS_TAG=' "$A")" "0"
out="$(F bash "$I" --clinic azure --dry-run --only 07 </dev/null 2>&1)"
assert_contains "a resume reuses the choice" "$out" "IMG:${WEB_NAME}:bhs-9.9.9:1.0.0-99:${KI}"
rm -f "$A"
out="$(printf 'n\n\n\n\n\nbhs-7.7.7\n\n\n\n\n' | INSTALL_INTERACTIVE=1 F bash "$I" --clinic azure --secrets "$TMP/secrets.env" --cert-hostname azure.example.test --dry-run --only 07 2>&1)"
assert_contains "the prompt offers to keep the defaults" "$out" "application image versions (sync/versions.env): keep the defaults"
assert_contains "a bare tag typed at the prompt reaches the task" "$out" "IMG:${WEB_NAME}:bhs-7.7.7:${OE}:${KI}"
rm -f "$A" "$TMP/tasks/07-images.sh"
exit "$fails"
