#!/usr/bin/env bash
# The forms OpenMRS loads: the openmrs service mounts clinic/forms/bahmniforms
# read-only over the config tree's forms; clinic/forms is gitignored; task 075
# fills it with a clone of the forms repo or, with none configured, a copy of
# the config image's forms, and refuses to leave it empty; task 080 does not
# start the stack without it. Uses a local git repository as the forms repo.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL="$(cd "${HERE}/../.." && pwd)"; RP="$(cd "${CL}/.." && pwd)"
T075="${HERE}/../tasks/075-forms.sh"; T080="${HERE}/../tasks/080-stack.sh"; F="${HERE}/../forms.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
svc(){ # FILE SERVICE : that service's block, comments dropped
  awk -v s="  $2:" '$0==s{p=1;next} p&&/^  [A-Za-z]/{exit} p' "$1" | grep -vE '^[[:space:]]*#'; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# git reads no user or system config here (a signing or hook setting would
# change what the fixture commits do); docker keeps the real HOME, where its
# compose plugin lives
REAL_HOME="$HOME"
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
mkdir -p "$HOME"
MNT='/etc/bahmni_config/masterdata/configuration/bahmniforms'

# --- the mount ---------------------------------------------------------------
line="$(svc "$CL/docker-compose.yml" openmrs | grep -F ":${MNT}" || true)"
printf '%s' "$line" | grep -qF '${CONTAINER_DATA_PATH:?}/forms/bahmniforms:'"${MNT}"':ro"' \
  && ok_ "openmrs mounts clinic/forms/bahmniforms over the config tree's bahmniforms" || bad "openmrs has no forms mount over ${MNT}: '${line}'"
case "$line" in *":${MNT}:ro\""*) ok_ "the forms mount is read-only" ;; *) bad "the forms mount is not read-only: '${line}'" ;; esac
if command -v docker >/dev/null 2>&1; then
  # every variable the compose files and .env.example name, with a placeholder
  # value (a path for the paths), so the render needs no node's clinic/.env
  { grep -E '^[A-Z_0-9]+=' "$CL/.env.example" | cut -d= -f1
    grep -ohE '\$\{[A-Z_0-9]+:\?' "$CL/docker-compose.yml" "$CL/docker-compose.macos.yml" | sed -E 's/.*\{([A-Z_0-9]+):\?/\1/'
  } | sort -u | awk '/PATH$|DIR$|BACKUP$/{print $0"=/p"; next} {print $0"=1"}' > "$TMP/render.vars"
  render(){ ( cd "$CL" && HOME="$REAL_HOME" CONTAINER_DATA_PATH=/n COMPOSE_FILE="$1" docker compose --env-file "$TMP/render.vars" --profile local config --format json 2>/dev/null ); }
  for set in docker-compose.yml docker-compose.yml:docker-compose.macos.yml; do
    got="$(render "$set" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for v in d["services"]["openmrs"]["volumes"]:
    if v.get("target")=="'"${MNT}"'": print(v.get("type"), v.get("source"), v.get("read_only", False))' 2>/dev/null)"
    [ "$got" = "bind /n/forms/bahmniforms True" ] && ok_ "${set}: renders the forms mount as a read-only bind of /n/forms/bahmniforms" || bad "${set}: forms mount renders as '${got}'"
  done
else
  ok_ "compose not available here; render checks skipped"
fi

# --- the checkout is node-local ------------------------------------------------
git -C "$RP" check-ignore -q clinic/forms/bahmniforms/x.json && ok_ "clinic/forms is gitignored" || bad "clinic/forms is not gitignored"
git -C "$RP" check-ignore -q clinic/.forms.new.abc123/x && ok_ "a clone in progress (clinic/.forms.new.*) is gitignored" || bad "clinic/.forms.new.* is not gitignored"

# --- the mount source verdict ------------------------------------------------------
[ -f "$F" ] || { bad "no clinic/install/forms.sh"; exit 1; }
mkdir -p "$TMP/v" "$TMP/g"
verdict(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_mount_verdict "$1" ); }
out="$(verdict "$TMP/v/forms/bahmniforms")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not exist' && ok_ "a missing mount source is refused, by name" || bad "missing mount source: rc=$rc out=$out"
mkdir -p "$TMP/v/forms/bahmniforms"; out="$(verdict "$TMP/v/forms/bahmniforms")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'holds no form file' && ok_ "an empty mount source is refused" || bad "empty mount source: rc=$rc out=$out"
echo '{}' > "$TMP/v/forms/bahmniforms/A_1.json"; out="$(verdict "$TMP/v/forms/bahmniforms")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ok 1 form files' && ok_ "a mount source with forms passes" || bad "populated mount source: rc=$rc out=$out"

# --- task 080 refuses to start the stack without it ------------------------------------
guard="$(sed -n '/# forms-guard:begin/,/# forms-guard:end/p' "$T080")"
[ -n "$guard" ] || bad "080 has no forms-guard block"
gl="$(grep -n 'forms-guard:end' "$T080" | head -1 | cut -d: -f1)"; ul="$(grep -n ' up -d >/dev/null' "$T080" | head -1 | cut -d: -f1)"
[ -n "$gl" ] && [ -n "$ul" ] && [ "$gl" -lt "$ul" ] && ok_ "080 checks the forms mount source before it starts the stack" || bad "080's forms check is not before compose up (guard ends ${gl:-nowhere}, up at ${ul:-nowhere})"
g080(){ ( CLINIC_DIR="$1"; INSTALL_DIR="${HERE}/.."; . "${HERE}/../lib.sh"; fail(){ printf 'FAIL %s\n' "$*"; exit 1; }; ok(){ printf 'OK %s\n' "$*"; }; eval "$guard" ); }
out="$(g080 "$TMP/g")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL .*does not exist' && ok_ "080's guard stops on a missing mount source" || bad "080 guard, missing source: rc=$rc out=$out"
out="$(g080 "$TMP/v")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK forms: 1 form files' && ok_ "080's guard passes a populated mount source" || bad "080 guard, populated: rc=$rc out=$out"

# --- task 075 ---------------------------------------------------------------------
[ -f "$T075" ] || { bad "no tasks/075-forms.sh"; exit "$fails"; }
[ "$(sed -n 2p "$T075")" = "# phase: both" ] && ok_ "075 runs at install and at seed" || bad "075 is not '# phase: both'"
node(){ # DIR : a clinic dir with an extracted config tree holding two forms
  local d="$1" f="$1/extracted/bahmni_config/masterdata/configuration/bahmniforms"
  mkdir -p "$f"; echo '{"name":"Vitals"}' > "$f/Vitals_1.json"; echo '{"name":"History"}' > "$f/History_2.json"
  printf 'ui=acme/web:1@sha256:aaa\nconfig=acme/config:1@sha256:bbb\n' > "$d/extracted/.source"
  printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$d/.env"
}
t075(){ # DIR PHASE [VAR=value...]
  local d="$1" p="$2"; shift 2
  env CLINIC_DIR="$d" PHASE="$p" DRY=0 COMPOSE_PROJECT_NAME=bahmni-t FORMS_REPO_URL= FORMS_REPO_KEY= "$@" bash "$T075" 2>&1
}
N1="$TMP/n1"; node "$N1"; mkdir -p "$N1/forms/bahmniforms"   # the empty bind source task 030 makes
out="$(t075 "$N1" install)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$N1/forms/bahmniforms/Vitals_1.json" ] && [ -f "$N1/forms/bahmniforms/History_2.json" ] \
  && ok_ "no forms repo: 075 fills clinic/forms/bahmniforms from the config image's forms" || bad "fallback not populated: rc=$rc out=$out"
[ -f "$N1/forms/.from-config-image" ] && grep -q 'acme/config:1' "$N1/forms/.from-config-image" && ok_ "the copy is marked with the config image it came from" || bad "fallback copy is not marked"
grep -qx 'FORMS_REPO_URL=' "$N1/.env" && grep -qx 'FORMS_REPO_KEY=' "$N1/.env" && ok_ "075 records the (empty) forms repo settings in clinic/.env for the seed sitting" || bad "clinic/.env lacks FORMS_REPO_URL/FORMS_REPO_KEY: $(cat "$N1/.env")"
rm "$N1/extracted/bahmni_config/masterdata/configuration/bahmniforms/History_2.json"; echo '{}' > "$N1/extracted/bahmni_config/masterdata/configuration/bahmniforms/ANC_7.json"
out="$(t075 "$N1" seed)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$N1/forms/bahmniforms/ANC_7.json" ] && [ ! -e "$N1/forms/bahmniforms/History_2.json" ] \
  && ok_ "a rerun follows the config image: new forms in, removed forms out" || bad "fallback refresh: rc=$rc out=$out; $(ls "$N1/forms/bahmniforms")"

N2="$TMP/n2"; node "$N2"; rm -f "$N2/extracted/bahmni_config/masterdata/configuration/bahmniforms/"*.json
out="$(t075 "$N2" install)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'holds no form file' && ok_ "no forms repo and no forms in the config image: 075 refuses, OpenMRS is not left with an empty mount" || bad "empty image forms not refused: rc=$rc out=$out"
N3="$TMP/n3"; node "$N3"; rm -rf "$N3/extracted/bahmni_config/masterdata/configuration/bahmniforms"
out="$(t075 "$N3" install)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'the config tree has no' && ok_ "no forms directory in the config tree: 075 refuses, naming it" || bad "missing image forms dir not refused: rc=$rc out=$out"
N4="$TMP/n4"; node "$N4"; mkdir -p "$N4/forms"; echo mine > "$N4/forms/notes.txt"
out="$(t075 "$N4" install)"; rc=$?
[ "$rc" -ne 0 ] && [ -f "$N4/forms/notes.txt" ] && printf '%s' "$out" | grep -q 'did not put there' && ok_ "files 075 did not put in clinic/forms are refused and left alone" || bad "foreign clinic/forms: rc=$rc out=$out"

# a forms repo
B="$TMP/forms.git"; W="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$B"
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/bahmniforms" "$W/tools"
echo '{"name":"Adult Case Sheet"}' > "$W/bahmniforms/Adult Case Sheet_7.json"
printf 'name\tversion\nAdult Case Sheet\t7\n' > "$W/MANIFEST.tsv"
printf '#!/usr/bin/env bash\n[ "$1" = --known ] && [ -s "$2" ] || exit 2\necho "no missing concepts"\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git add -A && git commit -qm one && git remote add origin "$B" && git push -q origin main ) || bad "fixture repo"
printf 'c1\nc2\n' > "$TMP/concepts.txt"
N5="$TMP/n5"; node "$N5"; mkdir -p "$N5/forms/bahmniforms"
out="$(t075 "$N5" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$N5/forms/.git" ] && [ -f "$N5/forms/bahmniforms/Adult Case Sheet_7.json" ] && [ ! -e "$N5/forms/bahmniforms/Vitals_1.json" ] \
  && ok_ "with a forms repo: 075 clones it into clinic/forms in place of task 030's empty directory" || bad "clone at install: rc=$rc out=$out"
grep -qx "FORMS_REPO_URL=${B}" "$N5/.env" && ok_ "the forms repo URL is kept in clinic/.env" || bad "FORMS_REPO_URL not in clinic/.env: $(cat "$N5/.env")"
printf '%s' "$out" | grep -q 'concept check runs at seed' && ok_ "install does not check concepts against the baseline it replaces at seed" || bad "install-phase concept message missing: $out"
N6="$TMP/n6"; node "$N6"; t075 "$N6" install >/dev/null; [ -f "$N6/forms/.from-config-image" ] || bad "fixture: fallback copy"
out="$(t075 "$N6" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$N6/forms/.git" ] && [ ! -e "$N6/forms/.from-config-image" ] && ok_ "a forms repo configured later replaces the config image's copy" || bad "fallback -> clone: rc=$rc out=$out"
out="$(t075 "$N6" install)"; rc=$?
[ "$rc" -ne 0 ] && [ -d "$N6/forms/.git" ] && printf '%s' "$out" | grep -q 'no forms repo is configured' && ok_ "a clone with no forms repo configured is refused, not overwritten" || bad "clone with empty URL: rc=$rc out=$out"
# seed: the incoming forms are checked against the node's concepts and its
# published forms first; a checker that only warns lets them through
printf 'f-on-node\n' > "$TMP/published.txt"
head0="$(git -C "$N5/forms" rev-parse HEAD)"
printf '#!/usr/bin/env bash\n[ "$1" = --known ] && [ -s "$2" ] && [ "$3" = --known-forms ] && grep -qx f-on-node "$4" || { echo "checker called as: $*"; exit 2; }\necho "WARN     Old Form: already published on the node"\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git commit -qam "checker warns" && git push -q origin main ) || bad "fixture push"
out="$(t075 "$N5" seed FORMS_REPO_URL="$B" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'WARN     Old Form' && printf '%s' "$out" | grep -q 'no form new to this node' && [ "$(git -C "$N5/forms" rev-parse HEAD)" != "$head0" ] \
  && ok_ "seed: the checker gets the node's concepts (--known) and published forms (--known-forms); a warning alone lets the forms in" || bad "seed check with warnings: rc=$rc out=$out"
head0="$(git -C "$N5/forms" rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho "missing concept 9bb0795c-0000-0000-0000-000000000020"\nexit 1\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git commit -qam "checker refuses" && git push -q origin main ) || bad "fixture push"
out="$(t075 "$N5" seed FORMS_REPO_URL="$B" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '9bb0795c' && [ "$(git -C "$N5/forms" rev-parse HEAD)" = "$head0" ] \
  && ok_ "seed: a failed concept check refuses, names the concept, and leaves clinic/forms where it was" || bad "seed concept refusal: rc=$rc out=$out"
out="$(t075 "$N5" seed FORMS_REPO_URL="$B" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt" FORMS_ALLOW_MISSING_CONCEPTS=1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FORMS_ALLOW_MISSING_CONCEPTS=1 carries on' && [ "$(git -C "$N5/forms" rev-parse HEAD)" != "$head0" ] \
  && ok_ "FORMS_ALLOW_MISSING_CONCEPTS=1 carries on, and says so" || bad "override: rc=$rc out=$out"

# --- the answers keep the forms repo settings ------------------------------------------
a="$TMP/answers.env"
( . "${HERE}/../lib.sh"; FORMS_REPO_URL=git@host:o/r.git FORMS_REPO_KEY=/k/forms answers_write "$a" )
grep -qx 'FORMS_REPO_URL=git@host:o/r.git' "$a" && grep -qx 'FORMS_REPO_KEY=/k/forms' "$a" && ok_ "composed answers keep FORMS_REPO_URL and FORMS_REPO_KEY when set" || bad "answers_write dropped the forms keys: $(cat "$a")"
( . "${HERE}/../lib.sh"; unset FORMS_REPO_URL FORMS_REPO_KEY; answers_write "$a" )
grep -q '^FORMS_' "$a" && bad "answers_write wrote empty forms keys" || ok_ "composed answers leave the forms keys out when unset"
grep -qE '^FORMS_REPO_URL=' "${HERE}/../clinic.env.example" && grep -qE '^FORMS_REPO_KEY=' "${HERE}/../clinic.env.example" && ok_ "clinic.env.example documents both keys" || bad "clinic.env.example lacks the forms keys"
exit "$fails"
