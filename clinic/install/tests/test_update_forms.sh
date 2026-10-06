#!/usr/bin/env bash
# scripts/update-forms.sh against a local git repository as the forms repo and
# a fake runtime: it refuses a clinic/forms that is not a fast-forward of the
# forms repo, refuses forms whose concepts the node lacks (before they are put
# in place), changes nothing on --dry-run, and otherwise recreates the openmrs
# service alone, waits for OpenMRS within its budget and verifies every form
# MANIFEST.tsv lists is published under its uuid, whatever version the node
# gave it.
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

# --- fakes: the runtime, compose and curl log their calls -----------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
echo "ct $*" >> "$FAKE_LOG"
# exec: the query is logged; the answer is FAKE_VERSION (the version of the
# published form with that uuid), nothing when it is empty
case "$1" in exec) q="$(cat)"; echo "sql $q" >> "$FAKE_LOG"; [ -z "${FAKE_VERSION-4}" ] || printf '%s\n' "${FAKE_VERSION-4}" ;; *) exit 2 ;; esac
SH
cat > "$TMP/bin/fakecompose" <<'SH'
#!/usr/bin/env bash
echo "compose $*" >> "$FAKE_LOG"
SH
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl" >> "$FAKE_LOG"
printf '%s' "${FAKE_HTTP:-200}"
SH
chmod +x "$TMP/bin/"*
export FAKE_LOG="$TMP/calls.log"

# --- the forms repo ---------------------------------------------------------------
B="$TMP/forms.git"; W="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$B"
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/bahmniforms" "$W/tools"
echo '{"name":"ANC Form","v":3}' > "$W/bahmniforms/ANC Form_3.json"
printf 'form_name\tversion\tuuid\nANC Form\t3\tu-anc\n' > "$W/MANIFEST.tsv"
CHECK_OK='#!/usr/bin/env bash\n[ "$1" = --known ] && [ -s "$2" ] && [ "$3" = --known-forms ] && [ -f "$4" ] || { echo "checker called as: $*"; exit 2; }\n'
printf "$CHECK_OK" > "$W/tools/check-concepts.sh"
( cd "$W" && git add -A && git commit -qm one && git remote add origin "$B" && git push -q origin main ) || bad "fixture repo"
push(){ ( cd "$W" && git add -A && git commit -qm "$1" && git push -q origin main ) || bad "fixture push: $1"; }
printf 'c1\nc2\n' > "$TMP/concepts.txt"; printf 'u-anc\n' > "$TMP/published.txt"

node(){ # DIR : an installed node whose clinic/forms is a clone of the forms repo
  mkdir -p "$1"
  printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\nFORMS_REPO_KEY=\n' "$B" > "$1/.env"
  git clone -q "$B" "$1/forms"
}
run(){ # DIR ARGS... (environment: the fakes)
  local d="$1"; shift
  env PATH="$TMP/bin:$PATH" CLINIC_DIR="$d" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_OPENMRS_WAIT_S="${WAIT:-30}" \
    FORMS_KNOWN_FORMS_FILE="$TMP/published.txt" \
    CT="$TMP/bin/fakect" COMPOSE_CMD="$TMP/bin/fakecompose" FAKE_HTTP="${HTTP:-200}" FAKE_VERSION="${VER-4}" \
    FORMS_ALLOW_MISSING_CONCEPTS="${ALLOW:-0}" bash "$S" "$@" 2>&1
}
state(){ ( cd "$1/forms" && git rev-parse HEAD && git status --porcelain && cat bahmniforms/* MANIFEST.tsv ); }

# --- a clinic/forms that is not a fast-forward of the forms repo is refused -------
N1="$TMP/n1"; node "$N1"
( cd "$N1/forms" && echo local > README.md && git add README.md && git commit -qm "local edit" ) || bad "fixture local commit"
echo '{"name":"ANC Form","v":4}' > "$W/bahmniforms/ANC Form_4.json"; rm "$W/bahmniforms/ANC Form_3.json"
printf 'form_name\tversion\tuuid\nANC Form\t4\tu-anc\n' > "$W/MANIFEST.tsv"; push "ANC Form v4"
before="$(state "$N1")"; : > "$FAKE_LOG"
out="$(run "$N1")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not a fast-forward' && ok_ "a clinic/forms with commits the forms repo lacks is refused: not a fast-forward" || bad "non-fast-forward not refused: rc=$rc out=$out"
[ "$(state "$N1")" = "$before" ] && ok_ "the refused checkout is left exactly as it was" || bad "a refused update changed clinic/forms"
grep -q '^compose' "$FAKE_LOG" && bad "OpenMRS was restarted after a refusal" || ok_ "nothing restarts after a refusal"

# --- local changes are refused too --------------------------------------------------
N2="$TMP/n2"; node "$N2"; echo edited >> "$N2/forms/MANIFEST.tsv"
out="$(run "$N2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'local changes' && ok_ "uncommitted edits in clinic/forms are refused" || bad "dirty checkout not refused: rc=$rc out=$out"

# --- a failed concept check refuses before the forms are put in place ------------------
N3="$TMP/n3"; node "$N3"
printf '#!/usr/bin/env bash\necho "missing concept 9bb0795c-0000-0000-0000-000000000020 (Vitals: Temperature (F))"\nexit 1\n' > "$W/tools/check-concepts.sh"
echo '{"name":"Vitals","v":2}' > "$W/bahmniforms/Vitals_2.json"; printf 'form_name\tversion\tuuid\nANC Form\t4\tu-anc\nVitals\t2\tu-vitals\n' > "$W/MANIFEST.tsv"
push "Vitals v2, checker refuses"
before="$(state "$N3")"; : > "$FAKE_LOG"
out="$(run "$N3")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'concept check failed' && printf '%s' "$out" | grep -q '9bb0795c' \
  && ok_ "a failed concept check refuses, naming the missing concept" || bad "concept check failure not refused: rc=$rc out=$out"
[ "$(state "$N3")" = "$before" ] && ok_ "clinic/forms stays at the forms it had: the incoming ones are checked before they are put in place" || bad "clinic/forms moved despite the failed check"
grep -q '^compose' "$FAKE_LOG" && bad "OpenMRS was restarted after a failed check" || ok_ "OpenMRS is not restarted after a failed check"

# --- --dry-run shows what would change and changes nothing ------------------------
N4="$TMP/n4"; node "$N4"
printf "$CHECK_OK" > "$W/tools/check-concepts.sh"
printf 'form_name\tversion\tuuid\nANC Form\t4\tu-anc\nVitals\t2\tu-vitals\nPNC Form\t6\tu-pnc\n' > "$W/MANIFEST.tsv"; echo '{"name":"PNC Form"}' > "$W/bahmniforms/PNC Form_6.json"
push "PNC Form v6"
( cd "$N4/forms" && git reset -q --hard HEAD~2 ) || bad "fixture: move the node back two commits"
before="$(state "$N4")"; : > "$FAKE_LOG"
out="$(run "$N4" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF '+PNC Form' && printf '%s' "$out" | grep -qF -- '-ANC Form' && ok_ "--dry-run shows the MANIFEST.tsv lines that would change" || bad "--dry-run output: rc=$rc out=$out"
printf '%s' "$out" | grep -q 'PNC Form v6' && ok_ "--dry-run lists the incoming commits" || bad "--dry-run does not list the commits: $out"
[ "$(state "$N4")" = "$before" ] && ok_ "--dry-run changes nothing in clinic/forms" || bad "--dry-run changed clinic/forms"
[ ! -s "$FAKE_LOG" ] && ok_ "--dry-run calls no runtime, no compose, no OpenMRS" || bad "--dry-run made calls: $(tr '\n' ';' < "$FAKE_LOG")"
N5="$TMP/n5"; mkdir -p "$N5"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\nFORMS_REPO_URL=%s\n' "$B" > "$N5/.env"
out="$(run "$N5" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$N5/forms" ] && [ -z "$(ls -A "$N5" | grep -v '^\.env$')" ] && printf '%s' "$out" | grep -qF 'PNC Form' \
  && ok_ "--dry-run on a node with no clone yet shows the forms repo's manifest and leaves nothing behind" || bad "--dry-run, no clone: rc=$rc out=$out; left: $(ls -A "$N5")"

# --- the whole update: recreate openmrs only, wait, verify ----------------------------
: > "$FAKE_LOG"
out="$(run "$N4")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$N4/forms" rev-parse HEAD)" = "$(git -C "$B" rev-parse main)" ] && ok_ "an update fast-forwards clinic/forms to the forms repo" || bad "update: rc=$rc out=$out"
c="$(grep '^compose' "$FAKE_LOG")"
[ "$(printf '%s\n' "$c" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$c" | grep -qE 'up -d --no-deps --force-recreate openmrs$' && ok_ "only the openmrs service is recreated" || bad "compose calls: $c"
printf '%s' "$c" | grep -q -- '--profile local' && ok_ "compose runs with the node's profiles" || bad "compose ran without the profiles: $c"
[ "$(grep -c '^ct exec' "$FAKE_LOG")" = 3 ] && printf '%s' "$out" | grep -q 'published by uuid: 3 of 3' && ok_ "each of the three forms in MANIFEST.tsv is checked in the database" || bad "verification: $(grep -c '^ct exec' "$FAKE_LOG") queries; $out"
[ "$(grep -c "^sql select version from form where uuid='u-[a-z]*' and published=1 and retired=0$" "$FAKE_LOG")" = 3 ] && ! grep -q '^sql .*version=' "$FAKE_LOG" \
  && ok_ "each form is looked up by its uuid, published and unretired, never by version" || bad "verification queries: $(grep '^sql' "$FAKE_LOG" | tr '\n' ';')"
printf '%s' "$out" | grep -qE '^    PNC Form +file v6 +node v4 +u-pnc$' && ok_ "the summary shows the file's version beside the version the node gave it" || bad "no file/node version line: $out"
printf '%s' "$out" | grep -q '^    > PNC Form' && ok_ "the summary names what changed in MANIFEST.tsv" || bad "summary lacks the manifest change: $out"
# the node numbered the form differently: still published, still a pass
out="$(VER=9 run "$N4" --restart)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '^    PNC Form +file v6 +node v9 ' && ok_ "a form the node published under another version number passes, both numbers shown" || bad "renumbered form: rc=$rc out=$out"
# not published under its uuid
( cd "$N4/forms" && git reset -q --hard HEAD~1 ) || bad "fixture: move the node back one commit"
out="$(VER= run "$N4")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not published, unretired.*PNC Form (uuid u-pnc, file v6)' && ok_ "a form the database does not publish under its uuid fails the update, by name and uuid" || bad "unpublished form not reported: rc=$rc out=$out"
# OpenMRS never answers within the budget
( cd "$N4/forms" && git reset -q --hard HEAD~1 ) || bad "fixture: move the node back one commit"
out="$(HTTP=302 WAIT=0 run "$N4")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'budget 0s (FORMS_OPENMRS_WAIT_S), waited [0-9]*s, last HTTP status 302' && ok_ "OpenMRS not answering within the budget: FAIL names the budget, the time waited and the last status" || bad "wait budget: rc=$rc out=$out"
# nothing new (an earlier run stopped after the fast-forward): nothing
# restarts, the published versions are still checked; --restart recreates
: > "$FAKE_LOG"
out="$(run "$N4")"; rc=$?
[ "$rc" -eq 0 ] && ! grep -q '^compose' "$FAKE_LOG" && [ "$(grep -c '^ct exec' "$FAKE_LOG")" = 3 ] && printf '%s' "$out" | grep -q 'OpenMRS is not restarted' \
  && ok_ "already up to date: nothing restarts, the published versions are still checked" || bad "up to date: rc=$rc out=$out"
out="$(VER= run "$N4")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'run this again with --restart' && ok_ "up to date but not published: the FAIL points at --restart" || bad "up to date, unpublished: rc=$rc out=$out"
: > "$FAKE_LOG"
out="$(run "$N4" --restart)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(grep -c '^compose' "$FAKE_LOG")" = 1 ] && ok_ "--restart recreates openmrs on an up-to-date checkout" || bad "--restart: rc=$rc out=$out"
# the override takes forms with missing concepts, loudly
N6="$TMP/n6"; node "$N6"
printf '#!/usr/bin/env bash\necho "missing concept 1111"\nexit 1\n' > "$W/tools/check-concepts.sh"; push "checker refuses again"
out="$(ALLOW=1 run "$N6")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'concept check FAILED' && printf '%s' "$out" | grep -q 'FORMS_ALLOW_MISSING_CONCEPTS=1 carries on' && ok_ "FORMS_ALLOW_MISSING_CONCEPTS=1 takes the forms and says so" || bad "override: rc=$rc out=$out"
# a MANIFEST.tsv with no uuid column cannot be verified, and says so
printf "$CHECK_OK" > "$W/tools/check-concepts.sh"; printf 'name\tversion\nANC Form\t4\n' > "$W/MANIFEST.tsv"; push "manifest without uuids"
out="$(run "$N6")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'must name a name (or form_name), a version and a uuid column' && ok_ "a MANIFEST.tsv without a uuid column is refused" || bad "manifest without uuid: rc=$rc out=$out"
exit "$fails"
