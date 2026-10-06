#!/usr/bin/env bash
# The forms' files on a clinic: the openmrs service mounts the forms folder
# (FORMS_DIR, FORMS_READ_ONLY) at /home/bahmni/clinical_forms and its
# translations/ where the form module reads them, never creating a missing
# source, and nothing into the config tree. Task 075 makes the folder a clone
# of the forms repo, mounted read-only, or with none configured keeps the
# frozen copy, read-write; at seed it checks the concepts (warnings only) and
# that every published form has its file. Task 080 does not start the stack
# without the folder, or at seed while a form lacks its file. A local git
# repository stands in for the forms repo; a rows file, or a fake runtime
# answering the real query, for the database.
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
P=/home/bahmni/clinical_forms/
# r UUID NAME VERSION PUBLISHED RETIRED POINTER : one line of the form rows
r(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }

# --- the mounts ------------------------------------------------------------------
om="$(svc "$CL/docker-compose.yml" openmrs)"
printf '%s' "$om" | grep -q 'masterdata/configuration/bahmniforms' && bad "openmrs still mounts something over the config tree's bahmniforms" || ok_ "nothing is mounted into the config tree's bahmniforms"
printf '%s' "$om" | grep -qF 'source: "${FORMS_DIR:-${CONTAINER_DATA_PATH:?}/bahmni_home/clinical_forms}"' && printf '%s' "$om" | grep -qF 'target: /home/bahmni/clinical_forms' \
  && ok_ "openmrs mounts FORMS_DIR (default: the frozen copy) at /home/bahmni/clinical_forms" || bad "no FORMS_DIR mount at /home/bahmni/clinical_forms"
printf '%s' "$om" | grep -qF 'source: "${FORMS_DIR:-${CONTAINER_DATA_PATH:?}/bahmni_home/clinical_forms}/translations"' \
  && ok_ "the translations mount comes from the same folder" || bad "translations mount does not follow FORMS_DIR"
[ "$(printf '%s\n' "$om" | grep -cF 'read_only: ${FORMS_READ_ONLY:-false}')" = 2 ] && ok_ "both forms mounts are read-only when FORMS_READ_ONLY is true (default false)" || bad "the forms mounts do not both take FORMS_READ_ONLY"
[ "$(printf '%s\n' "$om" | grep -cF 'create_host_path: false')" = 2 ] && ok_ "neither forms mount creates a missing source (create_host_path: false)" || bad "a forms mount would create a missing source"
printf '%s' "$om" | grep -q 'FORMS_MOUNT_MODE' && bad "openmrs still reads FORMS_MOUNT_MODE" || ok_ "FORMS_MOUNT_MODE is gone"
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
        print(t, v.get("type"), v.get("source"), v.get("read_only", False), (v.get("bind") or {}).get("create_host_path", False))' 2>/dev/null; }
  for set in docker-compose.yml docker-compose.yml:docker-compose.macos.yml; do
    got="$(render "$set")"
    want="/home/bahmni/clinical_forms bind /n/bahmni_home/clinical_forms False False
/var/www/bahmni_config/openmrs/apps/forms/translations bind /n/bahmni_home/clinical_forms/translations False False"
    [ "$got" = "$want" ] && ok_ "${set}: no forms repo, the frozen copy and its translations, read-write, never created" || bad "${set}: default renders '${got}'"
    got="$(render "$set" FORMS_DIR=/n/forms/clinical_forms FORMS_READ_ONLY=true)"
    want="/home/bahmni/clinical_forms bind /n/forms/clinical_forms True False
/var/www/bahmni_config/openmrs/apps/forms/translations bind /n/forms/clinical_forms/translations True False"
    [ "$got" = "$want" ] && ok_ "${set}: a forms repo's clone and its translations, read-only, never created" || bad "${set}: repo renders '${got}'"
  done
else
  ok_ "compose not available here; render checks skipped"
fi

# --- the clone is node-local --------------------------------------------------------
git -C "$RP" check-ignore -q clinic/forms/clinical_forms/x.json && ok_ "clinic/forms is gitignored" || bad "clinic/forms is not gitignored"
git -C "$RP" check-ignore -q clinic/.forms.new.abc123/x && ok_ "a clone in progress (clinic/.forms.new.*) is gitignored" || bad "clinic/.forms.new.* is not gitignored"
git -C "$RP" check-ignore -q clinic/.forms.lock/pid && ok_ "the forms lock (clinic/.forms.lock) is gitignored" || bad "clinic/.forms.lock is not gitignored"
git -C "$RP" check-ignore -q clinic/bahmni_home/clinical_forms/x.json && bad "the frozen copy is gitignored" || ok_ "the frozen copy stays tracked"

# --- the folder verdict ------------------------------------------------------------------
[ -f "$F" ] || { bad "no clinic/install/forms.sh"; exit 1; }
mkdir -p "$TMP/v"
verdict(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_folder_verdict "$1" ); }
out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not exist' && ok_ "a missing forms folder is refused, by name" || bad "missing folder: rc=$rc out=$out"
mkdir -p "$TMP/v/f"; echo '{}' > "$TMP/v/f/$U1.json"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no translations/ folder' && ok_ "a forms folder without translations/ is refused" || bad "no translations: rc=$rc out=$out"
rm "$TMP/v/f/$U1.json"; mkdir -p "$TMP/v/f/translations"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'holds no form file' && ok_ "an empty forms folder is refused" || bad "empty folder: rc=$rc out=$out"
echo '{}' > "$TMP/v/f/$U1.json"; out="$(verdict "$TMP/v/f")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^ok 1 form files' && ok_ "a forms folder with forms and translations/ passes" || bad "populated: rc=$rc out=$out"

# --- the deploy key verdict ------------------------------------------------------------------
key(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_key_verdict "$1" ); }
K="$TMP/keys/forms_key"; mkdir -p "$TMP/keys"; echo k > "$K"; chmod 600 "$K"
out="$(key "$K")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^ok deploy key $K" && ok_ "key: an absolute path to a mode-600 key passes" || bad "good key: rc=$rc out=$out"
chmod 640 "$K"; out="$(key "$K")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'readable by other users; ssh refuses such a key: chmod 600' && ok_ "key: a group-readable key is refused, with the fix" || bad "group-readable key: rc=$rc out=$out"
chmod 604 "$K"; out="$(key "$K")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'readable by other users' && ok_ "key: an other-readable key is refused" || bad "other-readable key: rc=$rc out=$out"
chmod 600 "$K"
out="$(key "$TMP/keys/none")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'which does not exist on this machine' && ok_ "key: a missing key is refused" || bad "missing key: rc=$rc out=$out"
out="$(key keys/forms_key)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'a relative path; give the absolute path' && ok_ "key: a relative path is refused (each caller runs from its own directory)" || bad "relative key: rc=$rc out=$out"
mkdir -p "$TMP/keys/a b"; cp "$K" "$TMP/keys/a b/k"; chmod 600 "$TMP/keys/a b/k"
out="$(key "$TMP/keys/a b/k")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'git hands the path to ssh through /bin/sh' && ok_ "key: a path with a space is refused (it would reach ssh through /bin/sh)" || bad "key with a space: rc=$rc out=$out"
out="$(key '')"; rc=$?
[ "$rc" -eq 0 ] && ok_ "key: none is fine (git's own ssh setup)" || bad "no key: rc=$rc out=$out"
grep -vE '^[[:space:]]*#' "$F" | grep -q "printf '%q'" && bad "forms_git quotes the key with printf %q (bash-only output, run by /bin/sh)" || ok_ "forms_git does not use printf %q"

# --- the row/file report ---------------------------------------------------------------------
report(){ ( CLINIC_DIR="$TMP/v"; . "${HERE}/../lib.sh"; . "$F"; forms_rowfile_report "$@" ); }
{ r "$U1" Vitals 2 1 0 "${P}$U1.json"; r "$U2" Vitals 1 1 1 "${P}$U2.json"; r "$U3" Old 1 0 0 "${P}$U3.json"; r "$U1" Vitals 2 1 0 "${P}translations/$U2.json"; } > "$TMP/rows-ok"
out="$(report "$TMP/v/f" "$TMP/rows-ok")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^summary 1 published forms, 1 with their file, 0 missing; 0 files with no form row' \
  && ok_ "row/file: a published, unretired form with its file passes; retired, unpublished and translation pointers are not required" || bad "report ok: rc=$rc out=$out"
printf '%s' "$out" | grep -qx "warn 1 retired form versions have no file here (first: $U2); observations saved with them do not open" \
  && ok_ "row/file: a retired version whose file is missing is a warning, counted, with its uuid" || bad "retired warning: $out"
echo '{}' > "$TMP/v/f/$U3.json"; echo '{}' > "$TMP/v/f/$U2.json"
r f-anc ANC 5 1 0 "${P}$U2.json" > "$TMP/rows-pend"
out="$(report "$TMP/v/f" "$TMP/rows-pend")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '0 missing; 2 files with no form row' && ok_ "files with no row are counted as pending, never refused" || bad "pending: rc=$rc out=$out"
rm "$TMP/v/f/$U2.json"
out="$(report "$TMP/v/f" "$TMP/rows-pend")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qx "missing $U2.json (ANC v5)" && ok_ "a published form whose file is absent fails, naming the file, the form and its version" || bad "missing: rc=$rc out=$out"
r f-evil Evil 1 1 0 "${P}../../etc/passwd" > "$TMP/rows-evil"
out="$(report "$TMP/v/f" "$TMP/rows-evil")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not a plain path under the forms folder' && ok_ "a pointer that climbs out of the forms folder is reported, never followed" || bad "unsafe path: rc=$rc out=$out"
r f-evil Evil 1 1 0 /openmrs/data/openmrs-runtime.properties > "$TMP/rows-out"
out="$(report "$TMP/v/f" "$TMP/rows-out")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF 'missing /openmrs/data/openmrs-runtime.properties (Evil v1: the pointer is outside the forms folder' \
  && printf '%s' "$out" | grep -q '^summary 1 published forms, 0 with their file, 1 missing' && ok_ "a published form whose pointer is outside the forms folder fails, never dropped" || bad "outside pointer: rc=$rc out=$out"
{ r f-old Old 1 1 1 /var/lib/forms/old.json; r "$U1" Vitals 2 1 0 "${P}$U1.json"; } > "$TMP/rows-out2"
out="$(report "$TMP/v/f" "$TMP/rows-out2")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF 'outside /var/lib/forms/old.json (Old v1, retired or unpublished' && printf '%s' "$out" | grep -q '^warn 1 pointers of retired or unpublished forms are outside the forms folder' \
  && ok_ "a retired form's pointer outside the forms folder is listed and warned about, not dropped" || bad "retired outside pointer: rc=$rc out=$out"
{ r f-nop NoFile 1 1 0 ''; r f-tr OnlyTr 3 1 0 "${P}translations/$U1.json"; r f-draft Draft 1 0 0 ''; r "$U1" Vitals 2 1 0 "${P}$U1.json"; } > "$TMP/rows-nop"
out="$(report "$TMP/v/f" "$TMP/rows-nop")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qx 'missing - (NoFile v1: no form_resource row points at its file)' && printf '%s' "$out" | grep -qx 'missing - (OnlyTr v3: no form_resource row points at its file)' \
  && ! printf '%s' "$out" | grep -q Draft && printf '%s' "$out" | grep -q '^summary 3 published forms, 1 with their file, 2 missing' \
  && ok_ "a published form with no pointer row (or only a translation one) fails; an unpublished draft does not" || bad "no pointer: rc=$rc out=$out"

# --- the row/file check reads the database through the real query ----------------------------
# a fake runtime records the SQL forms_sql pipes in and answers with rows
cat > "$TMP/fakect" <<'SH'
#!/usr/bin/env bash
[ "$1" = exec ] || exit 0
cat > "$SQL_LOG"
cat "$CANNED"
SH
chmod +x "$TMP/fakect"
{ r "$U1" Vitals 2 1 0 "${P}$U1.json"; r f-evil Evil 1 1 0 /openmrs/data/openmrs-runtime.properties; } > "$TMP/canned"
gate(){ env -i PATH="$PATH" HOME="$HOME" CT="$TMP/fakect" SQL_LOG="$TMP/sql.log" CANNED="$TMP/canned" COMPOSE_PROJECT_NAME=bahmni-t bash -c "CLINIC_DIR='$TMP/v'; . '${HERE}/../lib.sh'; . '$F'; forms_rowfile_gate '$TMP/v/f' 1" 2>&1; }
out="$(gate)"; rc=$?
sql="$(cat "$TMP/sql.log" 2>/dev/null)"
printf '%s' "$sql" | grep -qi 'left join form_resource' && ok_ "the query lists every form, with or without a pointer row (left join)" || bad "the query does not left-join form_resource: $sql"
printf '%s' "$sql" | grep -qF "like '${P}%'" && bad "the query still drops pointers outside the forms folder before the report sees them: $sql" || ok_ "the query does not filter pointers by the forms folder"
printf '%s' "$sql" | grep -qF "value_reference like '/%'" && printf '%s' "$sql" | grep -q 'FileSystemStorageDatatype' && ok_ "the query takes every file pointer: a file-storage datatype or any path" || bad "the query's pointer rule: $sql"
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF 'missing /openmrs/data/openmrs-runtime.properties (Evil v1: the pointer is outside the forms folder' && printf '%s' "$out" | grep -q 'FAIL row/file check: 2 published forms, 1 with their file, 1 missing' \
  && ok_ "through the real query, a pointer outside the forms folder fails the check" || bad "gate through the query: rc=$rc out=$out"

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
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK forms: 1 form files .*(mounted read-write)' && ok_ "080 passes the frozen copy when no forms repo is configured" || bad "080, frozen: rc=$rc out=$out"
out="$(g080 "$G" FORMS_REPO_URL=git@h:o/r.git)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^FAIL clinic/.env names a forms repo, but the forms mount is .*not its clone' && ok_ "080 stops when a forms repo is configured but the mount is not its clone" || bad "080, repo vs mount: rc=$rc out=$out"
out="$(g080 "$G" FORMS_READ_ONLY=yes)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FORMS_READ_ONLY is 'yes'" && ok_ "080 stops on a FORMS_READ_ONLY other than true or false" || bad "080, read-only value: rc=$rc out=$out"
mkdir -p "$G/forms/clinical_forms/translations"; echo '{}' > "$G/forms/clinical_forms/$U1.json"
{ r "$U1" Vitals 2 1 0 "${P}$U1.json"; r "$U2" ANC 5 1 0 "${P}$U2.json"; } > "$TMP/rows-080"
out="$(g080 "$G" PHASE=seed FORMS_REPO_URL=git@h:o/r.git FORMS_DIR="$G/forms/clinical_forms" FORMS_READ_ONLY=true FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "missing $U2.json (ANC v5)" && printf '%s' "$out" | grep -q '^FAIL row/file check' && ok_ "080 at seed stops while a published row lacks its file (forms repo)" || bad "080, seed missing: rc=$rc out=$out"
out="$(g080 "$G" PHASE=seed FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^WARN row/file check' && ok_ "080 at seed only warns on the frozen copy" || bad "080, seed frozen: rc=$rc out=$out"
echo '{}' > "$G/forms/clinical_forms/$U2.json"
out="$(g080 "$G" PHASE=seed FORMS_REPO_URL=git@h:o/r.git FORMS_DIR="$G/forms/clinical_forms" FORMS_READ_ONLY=true FORMS_ROWS_FILE="$TMP/rows-080")"; rc=$?
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
[ "$rc" -eq 0 ] && [ "$(envv "$N1" FORMS_DIR)" = "$N1/bahmni_home/clinical_forms" ] && [ "$(envv "$N1" FORMS_READ_ONLY)" = false ] && [ ! -e "$N1/forms" ] \
  && ok_ "no forms repo: 075 points the mount at the frozen copy, read-write, and makes no clinic/forms" || bad "frozen: rc=$rc out=$out env=$(cat "$N1/.env")"
grep -qx 'FORMS_REPO_URL=' "$N1/.env" && grep -qx 'FORMS_REPO_KEY=' "$N1/.env" && ok_ "075 records the (empty) forms repo settings in clinic/.env for the seed sitting" || bad "clinic/.env lacks FORMS_REPO_URL/FORMS_REPO_KEY: $(cat "$N1/.env")"
N2="$TMP/n2"; mkdir -p "$N2"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$N2/.env"
out="$(t075 "$N2" install)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'bahmni_home/clinical_forms does not exist' && ok_ "no forms repo and no frozen copy: 075 refuses" || bad "no frozen copy: rc=$rc out=$out"

# a forms repo. Its checker is a stand-in that records its arguments and says
# and exits what the test asks (CHECKER_SAY, CHECKER_RC)
B="$TMP/forms.git"; W="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$B"
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/clinical_forms/translations" "$W/tools"
echo '{"name":"Vitals"}' > "$W/clinical_forms/$U1.json"; echo '{}' > "$W/clinical_forms/translations/$U1.json"
# the forms repo's layout: clinical_forms/<uuid>.json, clinical_forms/translations/,
# MANIFEST.tsv with one row per form version (file empty when it has none)
printf 'form_name\tversion\tuuid\tpublished\tretired\tfile\tsource\texported_at\n' > "$W/MANIFEST.tsv"
printf 'Vitals\t1\t%s\t1\t1\t\thub\t2000-01-01T00:00:00Z\n' "$U3" >> "$W/MANIFEST.tsv"
printf 'Vitals\t2\t%s\t1\t0\tclinical_forms/%s.json\thub\t2000-01-01T00:00:00Z\n' "$U1" "$U1" >> "$W/MANIFEST.tsv"
printf '#!/usr/bin/env bash\necho "$*" > "$CHECKER_ARGS"\n[ -z "${CHECKER_SAY:-}" ] || echo "$CHECKER_SAY"\nexit "${CHECKER_RC:-0}"\n' > "$W/tools/check-concepts.sh"
( cd "$W" && git add -A && git commit -qm one && git remote add origin "$B" && git push -q origin main ) || bad "fixture repo"
push(){ ( cd "$W" && git add -A && git commit -qm "$1" && git push -q origin main ) || bad "fixture push: $1"; }
printf 'c1\nc2\n' > "$TMP/concepts.txt"; printf '%s\n' "$U1" > "$TMP/published.txt"
export CHECKER_ARGS="$TMP/checker.args"
N3="$TMP/n3"; node "$N3"; mkdir -p "$N3/forms"   # an empty clinic/forms is replaced
out="$(t075 "$N3" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$N3/forms/.git" ] && [ -f "$N3/forms/clinical_forms/$U1.json" ] \
  && [ "$(envv "$N3" FORMS_DIR)" = "$N3/forms/clinical_forms" ] && [ "$(envv "$N3" FORMS_READ_ONLY)" = true ] \
  && ok_ "with a forms repo: 075 clones it into clinic/forms and points the mount at its clinical_forms, read-only" || bad "clone at install: rc=$rc out=$out env=$(cat "$N3/.env")"
grep -qx "FORMS_REPO_URL=${B}" "$N3/.env" && ok_ "the forms repo URL is kept in clinic/.env" || bad "FORMS_REPO_URL not in clinic/.env"
printf '%s' "$out" | grep -q 'row/file check runs at seed' && [ ! -e "$CHECKER_ARGS" ] && ok_ "install checks neither concepts nor rows against the baseline it replaces at seed" || bad "install-phase checks: $out"
[ ! -e "$N3/.forms.lock" ] && ok_ "the forms lock is released after the run" || bad "the forms lock was left behind"
out="$(t075 "$N3" install)"; rc=$?
[ "$rc" -ne 0 ] && [ -d "$N3/forms/.git" ] && printf '%s' "$out" | grep -q 'no forms repo is configured' && ok_ "a clone with no forms repo configured is refused, not dropped" || bad "clone with empty URL: rc=$rc out=$out"
N4="$TMP/n4"; node "$N4"; mkdir -p "$N4/forms"; echo mine > "$N4/forms/notes.txt"
out="$(t075 "$N4" install FORMS_REPO_URL="$B")"; rc=$?
[ "$rc" -ne 0 ] && [ -f "$N4/forms/notes.txt" ] && printf '%s' "$out" | grep -q 'did not put there' && ok_ "files 075 did not put in clinic/forms are refused and left alone" || bad "foreign clinic/forms: rc=$rc out=$out"
printf '%s' "$out" | grep -q 'move clinic/forms aside, then at once run clinic/scripts/update-forms.sh' && ! printf '%s' "$out" | grep -q 'move it aside and run again' \
  && ok_ "the refusal says to take a fresh clone at once, since nothing can recreate OpenMRS without one" || bad "refusal advice: $out"
# a relative deploy key path is kept absolute, from where the installer ran
N8="$TMP/n8"; node "$N8"; mkdir -p "$TMP/run/keys"; echo k > "$TMP/run/keys/k"; chmod 600 "$TMP/run/keys/k"
out="$(cd "$TMP/run" && t075 "$N8" install FORMS_REPO_URL="$B" FORMS_REPO_KEY=keys/k)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(envv "$N8" FORMS_REPO_KEY)" = "$(cd "$TMP/run" && pwd -P)/keys/k" ] && ok_ "a relative FORMS_REPO_KEY is kept in clinic/.env as an absolute path" || bad "relative key: rc=$rc out=$out env=$(cat "$N8/.env")"

# seed: concepts warn, rows gate
seed75(){ local d="$1" rows="$2"; shift 2; t075 "$d" seed FORMS_REPO_URL="$B" FORMS_CONCEPTS_FILE="$TMP/concepts.txt" FORMS_KNOWN_FORMS_FILE="$TMP/published.txt" FORMS_ROWS_FILE="$rows" "$@"; }
echo '{"name":"ANC"}' > "$W/clinical_forms/$U2.json"
push "ANC v5"
{ r "$U1" Vitals 2 1 0 "${P}$U1.json"; r "$U2" ANC 5 1 0 "${P}$U2.json"; } > "$TMP/rows-seed"
out="$(seed75 "$N3" "$TMP/rows-seed" CHECKER_SAY="missing concept 9bb0795c-0000-0000-0000-000000000020 (ANC: Temperature)" CHECKER_RC=1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '9bb0795c' && printf '%s' "$out" | grep -q 'WARN concept check (rc=1)' && [ "$(git -C "$N3/forms" rev-parse HEAD)" = "$(git -C "$B" rev-parse main)" ] \
  && ok_ "seed: a failing concept check is a warning, named; the forms are taken" || bad "seed concept warning: rc=$rc out=$out"
grep -qE -- '^--known [^ ]+ --known-forms [^ ]+$' "$CHECKER_ARGS" 2>/dev/null && ok_ "the checker is called as --known <concepts> --known-forms <forms>" || bad "checker args: $(cat "$CHECKER_ARGS" 2>/dev/null)"
printf '%s' "$out" | grep -q 'ok   row/file check: 2 published forms, 2 with their file, 0 missing' && ok_ "seed: every published row has its file in the clone" || bad "seed row/file pass: $out"
echo '{"name":"ANC","v":6}' > "$W/clinical_forms/$U3.json"; push "ANC v6"
out="$(seed75 "$N3" "$TMP/rows-seed" CHECKER_SAY="usage: check-concepts.sh --known <file> [--known-forms <file>]" CHECKER_RC=2)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'WARN concept check (rc=2): the checker could not run' && printf '%s' "$out" | grep -q 'concepts NOT checked' \
  && ok_ "seed: a checker that cannot run (exit 2) is a warning too, saying the concepts were NOT checked" || bad "seed checker rc=2: rc=$rc out=$out"
# retired rows pointing at old-style files that exist nowhere are not required
{ r f-v1 Vitals 1 1 1 "${P}Vitals_1.json"; r "$U1" Vitals 2 1 0 "${P}$U1.json"; r "$U2" ANC 5 1 0 "${P}$U2.json"; } > "$TMP/rows-old"
out="$(seed75 "$N3" "$TMP/rows-old")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'row/file check: 2 published forms, 2 with their file, 0 missing' && printf '%s' "$out" | grep -q 'WARN row/file check: 1 retired form versions have no file here (first: f-v1)' \
  && ok_ "seed: a retired row whose file exists nowhere is not required, only warned about" || bad "seed retired old-style: rc=$rc out=$out"
{ r "$U1" Vitals 2 1 0 "${P}$U1.json"; r "$U2" ANC 5 1 0 "${P}$U2.json"; r f-pnc PNC 2 1 0 "${P}pnc-2.json"; } > "$TMP/rows-seed2"
out="$(seed75 "$N3" "$TMP/rows-seed2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "missing pnc-2.json (PNC v2)" && printf '%s' "$out" | grep -q 'FAIL row/file check: 3 published forms, 2 with their file, 1 missing' \
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
