#!/usr/bin/env bash
# scripts/update-forms.sh against a local git repository as the forms repo,
# rows files for the database, and a runtime and compose that log every call:
# it fast-forwards clinic/forms and nothing else (a checkout with local edits
# or commits the repo lacks is refused and left as it is), a concept finding
# is a warning, found by the checker the node already runs, a published form
# row without its file fails the run with the list, --dry-run changes nothing
# and reads no database, one run at a time changes clinic/forms, the exit
# code tells a schedule what happened, and OpenMRS is never restarted.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/update-forms.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no scripts/update-forms.sh"; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# git reads no user or system config (a signing or hook setting would change
# what the fixture commits do)
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$HOME"
U1=11111111-1111-1111-1111-111111111111; U2=22222222-2222-2222-2222-222222222222; U3=33333333-3333-3333-3333-333333333333
P=/home/bahmni/clinical_forms/
r(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }   # UUID NAME VERSION PUBLISHED RETIRED POINTER

# --- fakes: every runtime and compose entry point logs its call ------------------------
mkdir -p "$TMP/bin"
for b in fakect docker podman docker-compose podman-compose; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_LOG"\n[ "$1" = exec ] && cat >/dev/null\nexit 0\n' "$b" > "$TMP/bin/$b"
done
chmod +x "$TMP/bin/"*
export FAKE_LOG="$TMP/calls.log"

# --- the forms repo -----------------------------------------------------------------------
B="$TMP/forms.git"; W="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$B"
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/clinical_forms/translations" "$W/tools"
echo '{"name":"ANC"}' > "$W/clinical_forms/$U1.json"; echo '{}' > "$W/clinical_forms/translations/$U1.json"
# the forms repo's layout: clinical_forms/<uuid>.json, clinical_forms/translations/,
# MANIFEST.tsv with one row per form version (file empty when it has none)
H='form_name\tversion\tuuid\tpublished\tretired\tfile\tsource\texported_at\n'
printf "${H}"'ANC\t2\t%s\t1\t1\t\thub\t2000-01-01T00:00:00Z\nANC\t3\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U3" "$U1" "$U1" > "$W/MANIFEST.tsv"
# a stand-in checker: refuses a wrong call, else says and exits what the test asks
printf '#!/usr/bin/env bash\n[ "$1" = --known ] && [ -s "$2" ] && [ "$3" = --known-forms ] && [ -f "$4" ] || { echo "checker called as: $*"; exit 2; }\n[ -z "${CHECKER_SAY:-}" ] || echo "$CHECKER_SAY"\nexit "${CHECKER_RC:-0}"\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git add -A && git commit -qm "ANC v3" && git remote add origin "$B" && git push -q origin main ) || bad "fixture repo"
push(){ ( cd "$W" && git add -A && git commit -qm "$1" && git push -q origin main ) || bad "fixture push: $1"; }
printf 'c1\nc2\n' > "$TMP/concepts.txt"; printf '%s\n' "$U1" > "$TMP/published.txt"
r "$U1" ANC 3 1 0 "${P}$U1.json" > "$TMP/rows1"

node(){ # DIR : an installed node whose clinic/forms is a clone of the forms repo, mounted read-only
  mkdir -p "$1"
  printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\nFORMS_REPO_KEY=\nFORMS_DIR=%s\nFORMS_READ_ONLY=true\n' "$B" "$1/forms/clinical_forms" > "$1/.env"
  git clone -q "$B" "$1/forms"
}
run(){ # DIR ARGS... (ROWS= the database's form rows)
  local d="$1"; shift
  env PATH="$TMP/bin:$PATH" CLINIC_DIR="$d" CT="$TMP/bin/fakect" COMPOSE_CMD="$TMP/bin/docker-compose" \
    FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt" FORMS_ROWS_FILE="${ROWS:-$TMP/rows1}" \
    bash "$S" "$@" 2>&1
}
state(){ ( cd "$1/forms" && git rev-parse HEAD && git status --porcelain && ls -R clinical_forms && cat MANIFEST.tsv ); }
restarts(){ grep -E ' (up|restart|stop|start|rm|kill|down|create|run)( |$)' "$FAKE_LOG" || true; }

# --- up to date ------------------------------------------------------------------------------
N0="$TMP/n0"; node "$N0"; : > "$FAKE_LOG"
out="$(run "$N0")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'what the forms repo holds' && printf '%s' "$out" | grep -q 'row/file check: 1 published forms, 1 with their file, 0 missing' \
  && ok_ "up to date: exit 0, the row/file check passes" || bad "up to date: rc=$rc out=$out"
[ ! -s "$FAKE_LOG" ] && ok_ "nothing is called on the runtime or compose" || bad "calls: $(tr '\n' ';' < "$FAKE_LOG")"
[ ! -e "$N0/.forms.lock" ] && ok_ "the lock is released after the run" || bad "the lock was left behind"

# --- one run at a time ---------------------------------------------------------------------------
sleep 60 & live=$!
mkdir "$N0/.forms.lock"; echo "$live" > "$N0/.forms.lock/pid"
out="$(run "$N0")"; rc=$?
[ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q "another run is changing clinic/forms (pid $live holds" && [ "$(cat "$N0/.forms.lock/pid")" = "$live" ] \
  && ok_ "a lock held by a live run: exit 4, nothing changed, the other run's lock kept" || bad "held lock: rc=$rc out=$out"
touch -t 202001010000 "$N0/.forms.lock"
out="$(run "$N0")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'taking over .*older than 60 min' && [ ! -e "$N0/.forms.lock" ] && ok_ "a lock older than the stale limit is taken over" || bad "old lock: rc=$rc out=$out"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
mkdir "$N0/.forms.lock"; echo "$live" > "$N0/.forms.lock/pid"
out="$(run "$N0")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "the run that took it (pid $live) is gone" && [ ! -e "$N0/.forms.lock" ] && ok_ "a lock whose run is gone is taken over" || bad "dead lock: rc=$rc out=$out"
# an interrupted clone beside clinic/forms is removed; only by its name pattern
mkdir -p "$N0/.forms.new.Ab12Cd/forms" "$N0/.forms.new.keep-me"; touch -t 202001010000 "$N0/.forms.new.Ab12Cd" "$N0/.forms.new.keep-me"
out="$(run "$N0")"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$N0/.forms.new.Ab12Cd" ] && [ -d "$N0/.forms.new.keep-me" ] && printf '%s' "$out" | grep -q 'removed .forms.new.Ab12Cd' \
  && ok_ "an interrupted clone (.forms.new.XXXXXX) is removed; nothing else is" || bad "stale clone: rc=$rc out=$out; left: $(ls -A "$N0")"
# two runs at once on a node with no clone: never a clone inside the clone
N9="$TMP/n9"; mkdir -p "$N9"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\n' "$B" > "$N9/.env"
( run "$N9" > "$TMP/r1.out"; echo $? > "$TMP/r1.rc" ) & p1=$!
( run "$N9" > "$TMP/r2.out"; echo $? > "$TMP/r2.rc" ) & p2=$!
wait "$p1"; wait "$p2"
[ -d "$N9/forms/.git" ] && [ ! -e "$N9/forms/forms" ] && [ -z "$(git -C "$N9/forms" status --porcelain)" ] \
  && case "$(cat "$TMP/r1.rc") $(cat "$TMP/r2.rc")" in "0 0"|"0 4"|"4 0") true ;; *) false ;; esac \
  && ok_ "two runs at once: one clone, clean; the other run waits its turn or is turned away (exit 4)" || bad "two runs: rcs $(cat "$TMP/r1.rc") $(cat "$TMP/r2.rc"); $(ls -A "$N9/forms"); $(cat "$TMP/r1.out" "$TMP/r2.out")"

# --- not a fast-forward / local edits: refused, untouched ----------------------------------------
N1="$TMP/n1"; node "$N1"
( cd "$N1/forms" && echo local > README.md && git add README.md && git commit -qm "local edit" ) || bad "fixture local commit"
echo '{"name":"ANC","v":4}' > "$W/clinical_forms/$U2.json"
printf "${H}"'ANC\t2\t%s\t1\t1\t\thub\t2000-01-01T00:00:00Z\nANC\t3\t%s\t1\t1\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\nANC\t4\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U3" "$U1" "$U1" "$U2" "$U2" > "$W/MANIFEST.tsv"; push "ANC v4"
before="$(state "$N1")"; : > "$FAKE_LOG"
out="$(run "$N1")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not a fast-forward' && [ "$(state "$N1")" = "$before" ] && ok_ "a clinic/forms with commits the forms repo lacks is refused (exit 1) and left exactly as it was" || bad "non-fast-forward: rc=$rc out=$out"
N2="$TMP/n2"; node "$N2"; echo edited >> "$N2/forms/MANIFEST.tsv"; before="$(state "$N2")"
out="$(run "$N2")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'local changes' && [ "$(state "$N2")" = "$before" ] && ok_ "uncommitted edits in clinic/forms are refused and kept" || bad "dirty checkout: rc=$rc out=$out"
[ -z "$(restarts)" ] && ok_ "nothing restarts after a refusal" || bad "a refusal restarted something: $(restarts)"

# --- --dry-run: shows, changes nothing, reads no database ----------------------------------------------
N3="$TMP/n3"; node "$N3"; ( cd "$N3/forms" && git reset -q --hard HEAD~1 ) || bad "fixture: move the node back one commit"
before="$(state "$N3")"; envb="$(cat "$N3/.env")"; : > "$FAKE_LOG"
out="$(env PATH="$TMP/bin:$PATH" CLINIC_DIR="$N3" CT="$TMP/bin/fakect" bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "+ANC	4	$U2" && printf '%s' "$out" | grep -q 'ANC v4' && ok_ "--dry-run shows the incoming commits and MANIFEST.tsv lines" || bad "--dry-run output: rc=$rc out=$out"
[ "$(state "$N3")" = "$before" ] && [ "$(cat "$N3/.env")" = "$envb" ] && [ ! -s "$FAKE_LOG" ] && ok_ "--dry-run changes nothing and calls no runtime (no database read)" || bad "--dry-run changed something or made calls: $(tr '\n' ';' < "$FAKE_LOG")"
N4="$TMP/n4"; mkdir -p "$N4"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\n' "$B" > "$N4/.env"
out="$(run "$N4" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$N4/forms" ] && [ -z "$(ls -A "$N4" | grep -v '^\.env$')" ] && printf '%s' "$out" | grep -qF "ANC	4	$U2" \
  && ok_ "--dry-run on a node with no clone yet shows the forms repo's manifest and leaves nothing behind" || bad "--dry-run, no clone: rc=$rc out=$out; left: $(ls -A "$N4")"

# --- the update: fast-forward, warn on concepts, rows checked, no restart ---------------------------------
# the incoming commit carries a checker of its own; the node runs the one it
# already accepted, never code it has not taken yet
printf '#!/usr/bin/env bash\necho "the incoming checker ran"\nexit 2\n' > "$W/tools/check-concepts.sh"; push "a checker this node has not accepted"
{ r "$U1" ANC 3 1 1 "${P}$U1.json"; r "$U2" ANC 4 1 0 "${P}$U2.json"; } > "$TMP/rows2"
: > "$FAKE_LOG"
out="$(ROWS="$TMP/rows2" CHECKER_SAY="missing concept 9bb0795c-0000-0000-0000-000000000020 (ANC: Temperature)" CHECKER_RC=1 run "$N3")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$N3/forms" rev-parse HEAD)" = "$(git -C "$B" rev-parse main)" ] && ok_ "an update fast-forwards clinic/forms to the forms repo" || bad "update: rc=$rc out=$out"
printf '%s' "$out" | grep -q '9bb0795c' && printf '%s' "$out" | grep -q 'WARN concept check (rc=1)' && ok_ "a concept the node lacks is a warning, named, and does not stop the update" || bad "concept warning: $out"
! printf '%s' "$out" | grep -q 'the incoming checker ran' && printf '%s' "$out" | grep -q 'concept check, with the checker this node already runs' \
  && ok_ "the concept check runs the checker this node already accepted, not the incoming commit's" || bad "which checker ran: $out"
printf '%s' "$out" | grep -q "^    > ANC	4	$U2" && ok_ "the summary names what changed in MANIFEST.tsv" || bad "summary lacks the manifest change: $out"
printf '%s' "$out" | grep -q 'row/file check: 1 published forms, 1 with their file, 0 missing; 0 files with no form row' && ok_ "the retired old version is not required; its file stays for old observations" || bad "row/file after update: $out"
printf '%s' "$out" | grep -q 'concepts NOT checked' && bad "a check that ran is reported as not checked: $out" || ok_ "no 'concepts NOT checked' when the check ran"
[ -z "$(restarts)" ] && ! grep -q '^fakect' "$FAKE_LOG" && ok_ "OpenMRS is not restarted, and nothing else is either" || bad "the update restarted something: $(tr '\n' ';' < "$FAKE_LOG")"
printf '%s' "$out" | grep -q 'OpenMRS was not restarted' && ok_ "the summary says OpenMRS was not restarted" || bad "no no-restart line: $out"

# --- a published row without its file fails, with the list ------------------------------------------------
{ r "$U2" ANC 4 1 0 "${P}$U2.json"; r "$U3" PNC 2 1 0 "${P}$U3.json"; } > "$TMP/rows3"
out="$(ROWS="$TMP/rows3" run "$N3")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "missing $U3.json (PNC v2)" && printf '%s' "$out" | grep -q 'FAIL row/file check: 2 published forms, 1 with their file, 1 missing' \
  && ok_ "a published form whose file the forms repo lacks fails the run (exit 1), by file, name and version" || bad "missing file: rc=$rc out=$out"
r "$U2" ANC 4 1 0 "${P}$U2.json" > "$TMP/rows4"
out="$(ROWS="$TMP/rows4" run "$N3")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '1 files with no form row' && ok_ "a file whose rows have not synced is counted, never refused" || bad "pending file: rc=$rc out=$out"

# --- the forms repo cannot be reached ------------------------------------------------------------------------
N5="$TMP/n5"; node "$N5"; before="$(state "$N5")"
mv "$B" "$B.away"
out="$(run "$N5")"; rc=$?
mv "$B.away" "$B"
[ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'could not fetch the forms repo' && [ "$(state "$N5")" = "$before" ] && ok_ "an unreachable forms repo: exit 3, the forms left in place" || bad "fetch failure: rc=$rc out=$out"

# --- no forms repo configured ---------------------------------------------------------------------------------
N6="$TMP/n6"; mkdir -p "$N6/bahmni_home/clinical_forms/translations"; echo '{}' > "$N6/bahmni_home/clinical_forms/$U1.json"
printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=\n' > "$N6/.env"
out="$(ROWS="$TMP/rows3" run "$N6")"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$N6/forms" ] && printf '%s' "$out" | grep -q 'no forms repo configured' && printf '%s' "$out" | grep -q 'WARN row/file check' \
  && ok_ "no forms repo: exit 0, nothing cloned, missing files on the frozen copy are a warning" || bad "no repo: rc=$rc out=$out"

# --- a node taking the forms repo for the first time -------------------------------------------------------------
N7="$TMP/n7"; mkdir -p "$N7/bahmni_home/clinical_forms/translations"; echo '{}' > "$N7/bahmni_home/clinical_forms/$U1.json"
printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\n' "$B" > "$N7/.env"; : > "$FAKE_LOG"
out="$(ROWS="$TMP/rows4" run "$N7")"; rc=$?
envv(){ ( . "${HERE}/../lib.sh"; env_get "$1/.env" "$2" ); }
[ "$rc" -eq 0 ] && [ -d "$N7/forms/.git" ] && [ "$(envv "$N7" FORMS_DIR)" = "$N7/forms/clinical_forms" ] && [ "$(envv "$N7" FORMS_READ_ONLY)" = true ] \
  && printf '%s' "$out" | grep -q 'reads the old folder until it is recreated' && printf '%s' "$out" | grep -q 'clinic/scripts/recreate-openmrs.sh' && [ -z "$(restarts)" ] \
  && ok_ "first run with a forms repo: clones it, points clinic/.env at it read-only, names recreate-openmrs.sh, recreates nothing" || bad "adoption: rc=$rc out=$out env=$(cat "$N7/.env") calls=$(restarts)"
printf '%s' "$out" | grep -q "with the incoming commit's own checker: this is the first clone" && ok_ "the first clone runs the incoming checker, and says so" || bad "first-clone checker: $out"
# the incoming checker above exits 2: the summary says so, for a log grep
printf '%s' "$out" | sed -n '/^summary$/,$p' | grep -q 'WARN concepts NOT checked' && ok_ "a checker that cannot run puts 'concepts NOT checked' in the summary" || bad "summary lacks 'concepts NOT checked': $out"

# --- usage --------------------------------------------------------------------------------------------------------
out="$(run "$N0" --restart)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'unknown argument: --restart' && ok_ "there is no --restart" || bad "--restart: rc=$rc out=$out"
grep -vE '^[[:space:]]*#' "$S" | grep -qE 'compose (up|restart)|force-recreate openmrs >|ct restart' && bad "the script carries a restart call" || ok_ "the script carries no restart call"
exit "$fails"
