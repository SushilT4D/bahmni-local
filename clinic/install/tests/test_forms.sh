#!/usr/bin/env bash
# The forms' files on a clinic: the openmrs service mounts the forms folder
# (FORMS_DIR, FORMS_MOUNT_MODE) at /home/bahmni/clinical_forms and its
# translations/ where the form module reads them, and nothing into the config
# tree. Task 075 makes the folder a clone of the forms repo, mounted read-only,
# or with none configured keeps the frozen copy, read-write; at seed it checks
# the concepts (warnings only) and that every published form row has its file.
# Task 080 does not start the stack without the folder, or at seed while a
# row lacks its file. A local git repository stands in for the forms repo and
# a rows file for the database.
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
U1=11111111-1111-1111-1111-111111111111; U2=22222222-2222-2222-2222-222222222222; U3=33333333-3333-3333-3333-333333333333

# --- the mounts ------------------------------------------------------------------
om="$(svc "$CL/docker-compose.yml" openmrs)"
printf '%s' "$om" | grep -q 'masterdata/configuration/bahmniforms' && bad "openmrs still mounts something over the config tree's bahmniforms" || ok_ "nothing is mounted into the config tree's bahmniforms"
printf '%s' "$om" | grep -qF '"${FORMS_DIR:-${CONTAINER_DATA_PATH:?}/bahmni_home/clinical_forms}:/home/bahmni/clinical_forms:${FORMS_MOUNT_MODE:-rw}"' \
  && ok_ "openmrs mounts FORMS_DIR (default: the frozen copy) at /home/bahmni/clinical_forms, mode FORMS_MOUNT_MODE (default rw)" || bad "no FORMS_DIR mount at /home/bahmni/clinical_forms"
printf '%s' "$om" | grep -qF '"${FORMS_DIR:-${CONTAINER_DATA_PATH:?}/bahmni_home/clinical_forms}/translations:/var/www/bahmni_config/openmrs/apps/forms/translations:${FORMS_MOUNT_MODE:-rw}"' \
  && ok_ "the translations mount comes from the same folder, same mode" || bad "translations mount does not follow FORMS_DIR/FORMS_MOUNT_MODE"
if command -v docker >/dev/null 2>&1; then
  { grep -E '^[A-Z_0-9]+=' "$CL/.env.example" | cut -d= -f1
    grep -ohE '\$\{[A-Z_0-9]+:\?' "$CL/docker-compose.yml" "$CL/docker-compose.macos.yml" | sed -E 's/.*\{([A-Z_0-9]+):\?/\1/'
  } | sort -u | awk '/PATH$|DIR$|BACKUP$/{print $0"=/p"; next} {print $0"=1"}' > "$TMP/render.vars"
  render(){ # COMPOSE_FILE [VAR=value...]
    local cf="$1"; shift
    ( cd "$CL" && env HOME="$REAL_HOME" CONTAINER_DATA_PATH=/n COMPOSE_FILE="$cf" "$@" docker compose --env-file "$TMP/render.vars" --profile local config --format json 2>/dev/null ) \
      | python3 -c 'import json,sys
d=json.load(sys.stdin)
for v in d["services"]["openmrs"]["volumes"]:
    t=v.get("target","")
    if t in ("/home/bahmni/clinical_forms","/var/www/bahmni_config/openmrs/apps/forms/translations") or "bahmniforms" in t:
        print(t, v.get("type"), v.get("source"), v.get("read_only", False))' 2>/dev/null; }
  for set in docker-compose.yml docker-compose.yml:docker-compose.macos.yml; do
    got="$(render "$set")"
    want="/home/bahmni/clinical_forms bind /n/bahmni_home/clinical_forms False
/var/www/bahmni_config/openmrs/apps/forms/translations bind /n/bahmni_home/clinical_forms/translations False"
    [ "$got" = "$want" ] && ok_ "${set}: no forms repo, the frozen copy and its translations, read-write" || bad "${set}: default renders '${got}'"
    got="$(render "$set" FORMS_DIR=/n/forms/clinical_forms FORMS_MOUNT_MODE=ro)"
    want="/home/bahmni/clinical_forms bind /n/forms/clinical_forms True
/var/www/bahmni_config/openmrs/apps/forms/translations bind /n/forms/clinical_forms/translations True"
    [ "$got" = "$want" ] && ok_ "${set}: a forms repo's clone and its translations, read-only" || bad "${set}: repo renders '${got}'"
  done
else
  ok_ "compose not available here; render checks skipped"
fi

# --- the clone is node-local --------------------------------------------------------
git -C "$RP" check-ignore -q clinic/forms/clinical_forms/x.json && ok_ "clinic/forms is gitignored" || bad "clinic/forms is not gitignored"
git -C "$RP" check-ignore -q clinic/.forms.new.abc123/x && ok_ "a clone in progress (clinic/.forms.new.*) is gitignored" || bad "clinic/.forms.new.* is not gitignored"
git -C "$RP" check-ignore -q clinic/bahmni_home/clinical_forms/x.json && bad "the frozen copy is gitignored" || ok_ "the frozen copy stays tracked"

# --- the folder verdict ------------------------------------------------------------------
[ -f "$F" ] || { bad "no clinic/install/forms.sh"; exit 1; }
mkdir -p "$TMP/v"
verdict(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_folder_verdict "$1" ); }
out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not exist' && ok_ "a missing forms folder is refused, by name" || bad "missing folder: rc=$rc out=$out"
mkdir -p "$TMP/v/f"; echo '{}' > "$TMP/v/f/$U1.json"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no translations/ folder' && ok_ "a forms folder without translations/ is refused (the runtime would create it)" || bad "no translations: rc=$rc out=$out"
rm "$TMP/v/f/$U1.json"; mkdir -p "$TMP/v/f/translations"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'holds no form file' && ok_ "an empty forms folder is refused" || bad "empty folder: rc=$rc out=$out"
echo '{}' > "$TMP/v/f/$U1.json"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ok 1 form files' && ok_ "a forms folder with forms and translations/ passes" || bad "populated: rc=$rc out=$out"

# --- the row/file report ---------------------------------------------------------------------
report(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_rowfile_report "$@" ); }
printf 'Vitals\t2\t1\t0\t%s.json\nVitals\t1\t1\t1\t%s.json\nOld\t1\t0\t0\t%s.json\nVitals\t2\t1\t0\ttranslations/%s.json\n' "$U1" "$U2" "$U3" "$U2" > "$TMP/rows-ok"
out="$(report "$TMP/v/f" "$TMP/rows-ok")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^summary 1 published forms, 1 with their file, 0 missing; 0 files with no form row' \
  && ok_ "row/file: a published, unretired row with its file passes; retired, unpublished and translation pointers are not required" || bad "report ok: rc=$rc out=$out"
echo '{}' > "$TMP/v/f/$U3.json"; echo '{}' > "$TMP/v/f/$U2.json"
printf 'ANC\t5\t1\t0\t%s.json\n' "$U2" > "$TMP/rows-pend"
out="$(report "$TMP/v/f" "$TMP/rows-pend")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '0 missing; 2 files with no form row' && ok_ "files with no row are counted as pending, never refused" || bad "pending: rc=$rc out=$out"
rm "$TMP/v/f/$U2.json"
out="$(report "$TMP/v/f" "$TMP/rows-pend")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qx "missing $U2.json (ANC v5)" && ok_ "a published row whose file is absent fails, naming the file, the form and its version" || bad "missing: rc=$rc out=$out"
printf 'Evil\t1\t1\t0\t../../etc/passwd\n' > "$TMP/rows-evil"
out="$(report "$TMP/v/f" "$TMP/rows-evil")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not a plain path under the forms folder' && ok_ "a pointer out of the forms folder is reported, never followed" || bad "unsafe path: rc=$rc out=$out"

# --- task 080 ----------------------------------------------------------------------------------
guard="$(sed -n '/# forms-guard:begin/,/# forms-guard:end/p' "$T080")"
[ -n "$guard" ] || bad "080 has no forms-guard block"
gl="$(grep -n 'forms-guard:end' "$T080" | head -1 | cut -d: -f1)"; ul="$(grep -n ' up -d >/dev/null' "$T080" | head -1 | cut -d: -f1)"
[ -n "$gl" ] && [ -n "$ul" ] && [ "$gl" -lt "$ul" ] && ok_ "080 checks the forms folder before it starts the stack" || bad "080's forms check is not before compose up (guard ends ${gl:-nowhere}, up at ${ul:-nowhere})"
grep -vE '^[[:space:]]*#' "$T080" | grep -q 'bahmniforms' && bad "080 still checks bahmniforms" || ok_ "080 no longer looks for bahmniforms"
g080(){ # CLINIC_DIR [VAR=value...]
  local c="$1"; shift
  env -i PATH="$PATH" HOME="$HOME" "$@" bash -c "CLINIC_DIR='$c'; INSTALL_DIR='${HERE}/..'; . '${HERE}/../lib.sh'; fail(){ printf 'FAIL %s\n' \"\$*\"; exit 1; }; ok(){ printf 'OK %s\n' \"\$*\"; }; warn(){ printf 'WARN %s\n' \"\$*\"; }
${guard}" 2>&1; }
G="$TMP/g"; mkdir -p "$G"
out="$(g080 "$G")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL .*bahmni_home/clinical_forms does not exist' && ok_ "080 stops on a missing forms folder" || bad "080, missing: rc=$rc out=$out"
mkdir -p "$G/bahmni_home/clinical_forms/translations"; echo '{}' > "$G/bahmni_home/clinical_forms/$U1.json"
out="$(g080 "$G")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK forms: 1 form files .*(mounted rw)' && ok_ "080 passes the frozen copy when no forms repo is configured" || bad "080, frozen: rc=$rc out=$out"
out="$(g080 "$G" FORMS_REPO_URL=git@h:o/r.git)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL clinic/.env names a forms repo, but the forms mount is .*not its clone' && ok_ "080 stops when a forms repo is configured but the mount is not its clone" || bad "080, repo vs mount: rc=$rc out=$out"
out="$(g080 "$G" FORMS_MOUNT_MODE=rwx)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FORMS_MOUNT_MODE is 'rwx'" && ok_ "080 stops on a mount mode other than ro or rw" || bad "080, mode: rc=$rc out=$out"
mkdir -p "$G/forms/clinical_forms/translations"; echo '{}' > "$G/forms/clinical_forms/$U1.json"
printf 'Vitals\t2\t1\t0\t%s.json\nANC\t5\t1\t0\t%s.json\n' "$U1" "$U2" > "$TMP/rows-080"
out="$(g080 "$G" PHASE=seed FORMS_REPO_URL=git@h:o/r.git FORMS_DIR="$G/forms/clinical_forms" FORMS_MOUNT_MODE=ro FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "missing $U2.json (ANC v5)" && printf '%s' "$out" | grep -q '^FAIL row/file check' && ok_ "080 at seed stops while a published row lacks its file (forms repo)" || bad "080, seed missing: rc=$rc out=$out"
out="$(g080 "$G" PHASE=seed FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^WARN row/file check' && ok_ "080 at seed only warns on the frozen copy" || bad "080, seed frozen: rc=$rc out=$out"
echo '{}' > "$G/forms/clinical_forms/$U2.json"
out="$(g080 "$G" PHASE=seed FORMS_REPO_URL=git@h:o/r.git FORMS_DIR="$G/forms/clinical_forms" FORMS_MOUNT_MODE=ro FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK row/file check: 2 published forms, 2 with their file' && ok_ "080 at seed passes when every published row has its file" || bad "080, seed ok: rc=$rc out=$out"

# --- task 075 --------------------------------------------------------------------------------------
[ -f "$T075" ] || { bad "no tasks/075-forms.sh"; exit "$fails"; }
[ "$(sed -n 2p "$T075")" = "# phase: both" ] && ok_ "075 runs at install and at seed" || bad "075 is not '# phase: both'"
node(){ # DIR : a clinic dir with a frozen copy and a clinic/.env
  mkdir -p "$1/bahmni_home/clinical_forms/translations"; echo '{}' > "$1/bahmni_home/clinical_forms/$U1.json"
  printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$1/.env"
}
envv(){ ( . "${HERE}/../lib.sh"; env_get "$1/.env" "$2" ); }
t075(){ # DIR PHASE [VAR=value...]
  local d="$1" p="$2"; shift 2
  env CLINIC_DIR="$d" PHASE="$p" DRY=0 COMPOSE_PROJECT_NAME=bahmni-t FORMS_REPO_URL= FORMS_REPO_KEY= "$@" bash "$T075" 2>&1
}
N1="$TMP/n1"; node "$N1"
out="$(t075 "$N1" install)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(envv "$N1" FORMS_DIR)" = "$N1/bahmni_home/clinical_forms" ] && [ "$(envv "$N1" FORMS_MOUNT_MODE)" = rw ] && [ ! -e "$N1/forms" ] \
  && ok_ "no forms repo: 075 points the mount at the frozen copy, read-write, and makes no clinic/forms" || bad "frozen: rc=$rc out=$out env=$(cat "$N1/.env")"
grep -qx 'FORMS_REPO_URL=' "$N1/.env" && grep -qx 'FORMS_REPO_KEY=' "$N1/.env" && ok_ "075 records the (empty) forms repo settings in clinic/.env for the seed sitting" || bad "clinic/.env lacks FORMS_REPO_URL/FORMS_REPO_KEY: $(cat "$N1/.env")"
N2="$TMP/n2"; mkdir -p "$N2"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$N2/.env"
out="$(t075 "$N2" install)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'bahmni_home/clinical_forms does not exist' && ok_ "no forms repo and no frozen copy: 075 refuses" || bad "no frozen copy: rc=$rc out=$out"

# a forms repo
B="$TMP/forms.git"; W="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$B"
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/clinical_forms/translations" "$W/tools"
echo '{"name":"Vitals"}' > "$W/clinical_forms/$U1.json"; echo '{}' > "$W/clinical_forms/translations/$U1.json"
# the forms repo's layout: clinical_forms/<uuid>.json, clinical_forms/translations/,
# MANIFEST.tsv with one row per form version (file empty when it has none)
printf 'form_name\tversion\tuuid\tpublished\tretired\tfile\tsource\texported_at\n' > "$W/MANIFEST.tsv"
printf 'Vitals\t1\t%s\t1\t1\t\thub\t2000-01-01T00:00:00Z\n' "$U3" >> "$W/MANIFEST.tsv"
printf 'Vitals\t2\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U1" "$U1" >> "$W/MANIFEST.tsv"
printf '#!/usr/bin/env bash\necho "$*" > "$CHECKER_ARGS"\necho "no missing concepts"\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git add -A && git commit -qm one && git remote add origin "$B" && git push -q origin main ) || bad "fixture repo"
push(){ ( cd "$W" && git add -A && git commit -qm "$1" && git push -q origin main ) || bad "fixture push: $1"; }
printf 'c1\nc2\n' > "$TMP/concepts.txt"; printf '%s\n' "$U1" > "$TMP/published.txt"
export CHECKER_ARGS="$TMP/checker.args"
N3="$TMP/n3"; node "$N3"; mkdir -p "$N3/forms"   # an empty clinic/forms is replaced
out="$(t075 "$N3" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$N3/forms/.git" ] && [ -f "$N3/forms/clinical_forms/$U1.json" ] \
  && [ "$(envv "$N3" FORMS_DIR)" = "$N3/forms/clinical_forms" ] && [ "$(envv "$N3" FORMS_MOUNT_MODE)" = ro ] \
  && ok_ "with a forms repo: 075 clones it into clinic/forms and points the mount at its clinical_forms, read-only" || bad "clone at install: rc=$rc out=$out env=$(cat "$N3/.env")"
grep -qx "FORMS_REPO_URL=${B}" "$N3/.env" && ok_ "the forms repo URL is kept in clinic/.env" || bad "FORMS_REPO_URL not in clinic/.env"
printf '%s' "$out" | grep -q 'row/file check runs at seed' && [ ! -e "$CHECKER_ARGS" ] && ok_ "install checks neither concepts nor rows against the baseline it replaces at seed" || bad "install-phase checks: $out"
out="$(t075 "$N3" install)"; rc=$?
[ "$rc" -ne 0 ] && [ -d "$N3/forms/.git" ] && printf '%s' "$out" | grep -q 'no forms repo is configured' && ok_ "a clone with no forms repo configured is refused, not dropped" || bad "clone with empty URL: rc=$rc out=$out"
N4="$TMP/n4"; node "$N4"; mkdir -p "$N4/forms"; echo mine > "$N4/forms/notes.txt"
out="$(t075 "$N4" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -ne 0 ] && [ -f "$N4/forms/notes.txt" ] && printf '%s' "$out" | grep -q 'did not put there' && ok_ "files 075 did not put in clinic/forms are refused and left alone" || bad "foreign clinic/forms: rc=$rc out=$out"

# seed: concepts warn, rows gate
seed75(){ t075 "$1" seed FORMS_REPO_URL="$B" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt" FORMS_ROWS_FILE="$2"; }
echo '{"name":"ANC"}' > "$W/clinical_forms/$U2.json"
printf '#!/usr/bin/env bash\necho "$*" > "$CHECKER_ARGS"\necho "missing concept 9bb0795c-0000-0000-0000-000000000020 (ANC: Temperature)"\nexit 1\n' > "$W/tools/check-concepts.sh"
push "ANC v5; the checker finds a missing concept"
printf 'Vitals\t2\t1\t0\t%s.json\nANC\t5\t1\t0\t%s.json\n' "$U1" "$U2" > "$TMP/rows-seed"
out="$(seed75 "$N3" "$TMP/rows-seed")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '9bb0795c' && printf '%s' "$out" | grep -q 'WARN concept check (rc=1)' && [ "$(git -C "$N3/forms" rev-parse HEAD)" = "$(git -C "$B" rev-parse main)" ] \
  && ok_ "seed: a failing concept check is a warning, named; the forms are taken" || bad "seed concept warning: rc=$rc out=$out"
grep -qE -- '^--known [^ ]+ --known-forms [^ ]+$' "$CHECKER_ARGS" 2>/dev/null && ok_ "the checker is called as --known <concepts> --known-forms <forms>" || bad "checker args: $(cat "$CHECKER_ARGS" 2>/dev/null)"
printf '%s' "$out" | grep -q 'ok   row/file check: 2 published forms, 2 with their file, 0 missing' && ok_ "seed: every published row has its file in the clone" || bad "seed row/file pass: $out"
printf '#!/usr/bin/env bash\necho "usage: check-concepts.sh --known <file> [--known-forms <file>]"\nexit 2\n' > "$W/tools/check-concepts.sh"
push "the checker cannot run"
out="$(seed75 "$N3" "$TMP/rows-seed")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'WARN concept check (rc=2): the checker could not run' && ok_ "seed: a checker that cannot run (exit 2) is a warning too, said as such" || bad "seed checker rc=2: rc=$rc out=$out"
# retired rows pointing at old-style files that exist nowhere are not required
printf 'Vitals\t1\t1\t1\tVitals_1.json\nVitals\t2\t1\t0\t%s.json\nANC\t5\t1\t0\t%s.json\n' "$U1" "$U2" > "$TMP/rows-old"
out="$(seed75 "$N3" "$TMP/rows-old")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'row/file check: 2 published forms, 2 with their file, 0 missing' && ok_ "seed: a retired row whose file exists nowhere is not required" || bad "seed retired old-style: rc=$rc out=$out"
printf 'Vitals\t2\t1\t0\t%s.json\nANC\t5\t1\t0\t%s.json\nPNC\t2\t1\t0\t%s.json\n' "$U1" "$U2" "$U3" > "$TMP/rows-seed2"
out="$(seed75 "$N3" "$TMP/rows-seed2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "missing $U3.json (PNC v2)" && printf '%s' "$out" | grep -q 'FAIL row/file check: 3 published forms, 2 with their file, 1 missing' \
  && ok_ "seed: a published row whose file the forms repo lacks stops the seed, with the list" || bad "seed row/file refusal: rc=$rc out=$out"
N5="$TMP/n5"; node "$N5"
out="$(t075 "$N5" seed FORMS_ROWS_FILE="$TMP/rows-seed2")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "missing $U2.json (ANC v5)" && printf '%s' "$out" | grep -q 'WARN row/file check' && ok_ "seed on the frozen copy: missing files are a warning" || bad "seed frozen: rc=$rc out=$out"
# a forms repo without clinical_forms/translations
B2="$TMP/bare2.git"; W2="$TMP/work2"
git -c init.defaultBranch=main init -q --bare "$B2"; git -c init.defaultBranch=main init -q "$W2"; mkdir -p "$W2/clinical_forms"
echo '{}' > "$W2/clinical_forms/$U1.json"; ( cd "$W2" && git add -A && git commit -qm one && git remote add origin "$B2" && git push -q origin main ) || bad "fixture repo 2"
N6="$TMP/n6"; node "$N6"
out="$(t075 "$N6" install FORMS_REPO_URL="$B2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no translations/ folder' && [ -z "$(envv "$N6" FORMS_DIR)" ] && ok_ "a forms repo without clinical_forms/translations is refused before the mount is pointed at it" || bad "repo without translations: rc=$rc out=$out"

# --- the answers keep the forms repo settings ------------------------------------------
a="$TMP/answers.env"
( . "${HERE}/../lib.sh"; FORMS_REPO_URL=git@host:o/r.git FORMS_REPO_KEY=/k/forms answers_write "$a" )
grep -qx 'FORMS_REPO_URL=git@host:o/r.git' "$a" && grep -qx 'FORMS_REPO_KEY=/k/forms' "$a" && ok_ "composed answers keep FORMS_REPO_URL and FORMS_REPO_KEY when set" || bad "answers_write dropped the forms keys: $(cat "$a")"
( . "${HERE}/../lib.sh"; unset FORMS_REPO_URL FORMS_REPO_KEY; answers_write "$a" )
grep -q '^FORMS_' "$a" && bad "answers_write wrote empty forms keys" || ok_ "composed answers leave the forms keys out when unset"
grep -qE '^FORMS_REPO_URL=' "${HERE}/../clinic.env.example" && grep -qE '^FORMS_REPO_KEY=' "${HERE}/../clinic.env.example" && ok_ "clinic.env.example documents both keys" || bad "clinic.env.example lacks the forms keys"
exit "$fails"
