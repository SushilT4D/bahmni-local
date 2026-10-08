#!/usr/bin/env bash
# A dry run changes nothing and claims nothing was done:
#   - seed.sh --dry-run (every seed task but the gate, which needs a real seed
#     folder) prints no line saying the node is installed, syncing or seeded,
#     ends saying nothing was seeded, and creates no file or directory in the
#     clinic directory or the seed folder;
#   - the join step, dry, says what it would do instead of printing the
#     operator's join steps for a node that was never seeded;
#   - install.sh --dry-run ends saying nothing was installed, not "done".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# --- seed.sh --dry-run ---------------------------------------------------------------
mkdir -p "$TMP/x" "$TMP/c" "$TMP/s" "$TMP/logs"
cp -R "$RP/clinic/install" "$TMP/x/install"; rm -f "$TMP/x/install/tasks/005-seed-gate.sh"
printf 'CLINIC_SLUG=tst\nRESIDUE=7\nMRN_PREFIX=TST\nSITE_NUMBER=7\nCERT_HOSTNAME=t.test\nLAN_NAME=bahmni.clinic\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092\n' > "$TMP/c/.env"
printf 'STATE=INSTALLED\n' > "$TMP/c/.install-state"
before="$(cd "$TMP" && find c s | LC_ALL=C sort; cat c/.install-state c/.env)"
out="$(CLINIC_DIR="$TMP/c" REPO_DIR="$RP" INSTALL_LOG="$TMP/logs/seed.log" bash "$TMP/x/install/seed.sh" --seed "$TMP/s" --dry-run </dev/null 2>&1)"; rc=$?
after="$(cd "$TMP" && find c s | LC_ALL=C sort; cat c/.install-state c/.env)"
[ "$rc" = 0 ] && ok_ "seed.sh --dry-run runs every seed task after the gate" || bad "seed dry run: rc=$rc $(printf '%s' "$out" | tail -5)"
[ "$before" = "$after" ] && ok_ "nothing was created or changed in the clinic directory or the seed folder" || bad "the dry run changed: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -5)"
case "$out" in *"installed and syncing"*) bad "the dry run says the node is installed and syncing" ;; *) ok_ "no line says the node is installed or syncing" ;; esac
case "$out" in *"ok   printed"*) bad "the join step reports its steps printed in a dry run" ;; *) ok_ "the join step prints no steps as done" ;; esac
case "$out" in *SEEDED*) bad "the dry run says SEEDED" ;; *) ok_ "no line says SEEDED" ;; esac
case "$out" in *"would: print the steps the operator runs to join this clinic to the hub"*) ok_ "the join step says what it would do" ;; *) bad "the join step does not say what it would do" ;; esac
last="$(printf '%s\n' "$out" | grep -v '^log: ' | grep . | tail -1)"
case "$last" in "dry run: nothing was seeded or changed."*) ok_ "it ends: $last" ;; *) bad "last line: $last" ;; esac
case "$out" in *"every check above ran"*) bad "it claims every check ran, though the database checks did not" ;; *) ok_ "it does not claim every check ran" ;; esac
# --- install.sh --dry-run --------------------------------------------------------------
mkdir -p "$TMP/tasks" "$TMP/ic"
printf '#!/usr/bin/env bash\necho probe\n' > "$TMP/tasks/05-probe.sh"
printf 'CLINIC_SLUG=tst\nRESIDUE=7\nMRN_PREFIX=TST\nSITE_NUMBER=7\nCLINIC_PHONE=+910000000000\nCERT_HOSTNAME=t.test\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092\nREMOTE_KAFKA_USERNAME=m\nREMOTE_KAFKA_PASSWORD=p\nOPENMRS_ATOMFEED_PASSWORD=a\nOPENELIS_ATOMFEED_PASSWORD=b\nODOO_ATOMFEED_PASSWORD=c\n' > "$TMP/answers.env"
printf 'tst:7\n' > "$TMP/ledger"
out="$(CLINIC_DIR="$TMP/ic" REPO_DIR="$RP" TASKS_DIR="$TMP/tasks" LEDGER="$TMP/ledger" INSTALL_LOG="$TMP/logs/install.log" bash "$RP/clinic/install/install.sh" --answers "$TMP/answers.env" --dry-run </dev/null 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'probe'; then
  case "$out" in *"done: installed"*) bad "install.sh --dry-run says done: installed" ;; *) ok_ "install.sh --dry-run does not say it installed anything" ;; esac
else bad "install dry run did not run its task: rc=$rc $(printf '%s' "$out" | tail -3)"; fi
case "$out" in *"dry run: nothing was installed or changed."*) ok_ "install.sh --dry-run ends saying nothing was installed" ;; *) bad "install dry run end: $(printf '%s' "$out" | tail -2)" ;; esac
exit $((fails > 0))
