#!/usr/bin/env bash
# install.sh's run log: every stop this week had to be pasted by hand from a
# terminal, and nobody could say how long a task took on a given host. Tees
# the whole run, appending, with one header per run and one timing line per
# task. Uses the same TASKS_DIR fake-task technique as test_install.sh.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: output lacks %q\n' "$1" "$3"; fails=$((fails+1)); fi; }
assert_not_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  FAIL %s: output should not have %q\n' "$1" "$3"; fails=$((fails+1)); else printf '  ok   %s\n' "$1"; fi; }
count_of(){ printf '%s' "$1" | grep -c -- "$2" || true; }

I="${HERE}/../install.sh"
mkdir -p "$TMP/seed" "$TMP/clinic" "$TMP/tasks"; : > "$TMP/seed/openmrs.sql.gz"
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
printf '#!/usr/bin/env bash\necho "fake task ran"\n' > "$TMP/tasks/05-probe.sh"

# ---------------------------------------------------------------------------
# 1. dry run, explicit INSTALL_LOG: header + one timing line per task.
# ---------------------------------------------------------------------------
LOG1="$TMP/run1.log"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" INSTALL_LOG="$LOG1" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run 2>&1)"; rc=$?
assert_eq "successful dry run still exits 0" "$rc" "0"
[ -f "$LOG1" ] && printf '  ok   %s\n' "log file was created" || { printf '  FAIL log file was not created\n'; fails=$((fails+1)); }
log1="$(cat "$LOG1" 2>/dev/null)"
assert_contains "log has a header naming the slug" "$log1" "slug=azure"
assert_contains "log header names the platform" "$log1" "platform="
assert_contains "log header names the runtime" "$log1" "runtime="
assert_contains "log header names a git sha" "$log1" "sha="
assert_contains "log has a per-task timing line" "$log1" "05-probe"
assert_contains "log path is printed at the end of the run" "$out" "install log: $LOG1"

# ---------------------------------------------------------------------------
# 2. a failing task: STOPPED rc=N is in the log, exit code unchanged (1).
# ---------------------------------------------------------------------------
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP/tasks/06-boom.sh"
LOG2="$TMP/run2.log"
out="$(TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" INSTALL_LOG="$LOG2" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run 2>&1)"; rc=$?
assert_eq "a failing task still exits 1 (exit code unchanged)" "$rc" "1"
log2="$(cat "$LOG2" 2>/dev/null)"
assert_contains "log names the failing task" "$log2" "06-boom"
assert_contains "log has a STOPPED rc= line" "$log2" "STOPPED rc=3"
assert_contains "STOPPED message on the terminal also names the log path" "$out" "install log: $LOG2"
rm -f "$TMP/tasks/06-boom.sh"

# ---------------------------------------------------------------------------
# 3. running twice appends: two headers, not a fresh file each time.
# ---------------------------------------------------------------------------
LOG3="$TMP/run3.log"
TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" INSTALL_LOG="$LOG3" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run >/dev/null 2>&1
TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" INSTALL_LOG="$LOG3" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run >/dev/null 2>&1
log3="$(cat "$LOG3" 2>/dev/null)"
n_headers="$(count_of "$log3" '===== .*slug=azure')"
assert_eq "running twice appends (two headers)" "$n_headers" "2"

# ---------------------------------------------------------------------------
# 4. --from / --only show up in the header when given.
# ---------------------------------------------------------------------------
LOG4="$TMP/run4.log"
TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" INSTALL_LOG="$LOG4" bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run --only 05 >/dev/null 2>&1
assert_contains "header names --only when given" "$(cat "$LOG4" 2>/dev/null)" "--only 05"

# ---------------------------------------------------------------------------
# 5. a dry run never writes into $HOME -- it logs under ${TMPDIR:-/tmp}.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/home" "$TMP/scratch-tmp"
out="$(env -u INSTALL_LOG TASKS_DIR="$TMP/tasks" LEDGER="$TMP/l" HOME="$TMP/home" TMPDIR="$TMP/scratch-tmp/" \
  bash "$I" --answers "$TMP/answers.env" --seed "$TMP/seed" --dry-run 2>&1)"; rc=$?
assert_eq "dry run (no INSTALL_LOG) still exits 0" "$rc" "0"
home_logs="$(find "$TMP/home" -name 'clinic-install-*.log' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "dry run wrote nothing under \$HOME" "$home_logs" "0"
tmp_logs="$(find "$TMP/scratch-tmp" -name 'clinic-install-*.log' 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "dry run's default log landed under \$TMPDIR" "$tmp_logs" "1"

exit "$fails"
