#!/usr/bin/env bash
# Form files reach a clinic only through forms-sync: no forms repository route and no tracked copy is left.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL="$(cd "${HERE}/../.." && pwd)"; RP="$(cd "${CL}/.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- nothing names the removed route -----------------------------------------------------
T20=clinic/install/tasks/020-env.sh
for w in FORMS_REPO_URL FORMS_REPO_KEY FORMS_CLONE_DIR FORMS_READ_ONLY FORMS_FROZEN_DIR FORMS_MOUNT_MODE 'clinic/forms/' 'forms repo' 'bahmni_home/clinical_forms' \
         pull-clinical-forms test_update_forms '.forms.lock' '.forms.new'; do
  hits="$(git -C "$RP" grep -n -I -i -F -e "$w" -- . ":!clinic/install/tests/test_no_forms_repo.sh" ":!clinic/install/tests/test_forms_folder.sh" ":!${T20}" | head -5)"
  [ -z "$hits" ] && ok_ "nothing names ${w}" || bad "${w} is still named: ${hits}"
done
hits="$(git -C "$RP" grep -n -I -F -e MANIFEST.tsv -- . ":!clinic/install/tests/test_no_forms_repo.sh" ":!clinic/install/tests/test_check_form_concepts.sh" ":!clinic/install/check-form-concepts.py" | head -5)"
[ -z "$hits" ] && ok_ "only the concept checker and its test name MANIFEST.tsv, its input" || bad "MANIFEST.tsv is still named: ${hits}"
for p in bahmni_home scripts/pull-clinical-forms.sh install/tests/test_update_forms.sh; do
  [ ! -e "$CL/$p" ] && [ -z "$(git -C "$CL" ls-files -- "$p" | head -1)" ] && ok_ "${p} is gone" || bad "${p} is still in the tree"
done
retired="$(sed -n 's/^RETIRED_KEYS="\([^"]*\)".*/\1/p' "$RP/$T20")"
for k in FORMS_REPO_URL FORMS_REPO_KEY FORMS_READ_ONLY FORMS_MOUNT_MODE; do
  case " $retired " in *" $k "*) ok_ "020 drops ${k} from an existing clinic/.env" ;; *) bad "020 does not retire ${k}" ;; esac
done
hits="$(git -C "$RP" grep -n -e 'FORMS_REPO' -e 'FORMS_READ_ONLY' -e 'FORMS_MOUNT_MODE' -- "$T20" | grep -v '^[^:]*:[0-9]*:RETIRED_KEYS=')"
[ -z "$hits" ] && ok_ "020 names the retired keys only in its retired list" || bad "020 still uses a retired key: ${hits}"

# --- what serves forms in general is kept ------------------------------------------------
F="${HERE}/../forms.sh"
for fn in forms_folder_verdict forms_rowfile_gate forms_retire_demo forms_concept_warn; do
  grep -q "^${fn}(){" "$F" && ok_ "forms.sh still defines ${fn}" || bad "forms.sh no longer defines ${fn}"
done
[ -x "$CL/scripts/fetch-cloud-forms.sh" ] && ok_ "fetch-cloud-forms.sh is kept" || bad "fetch-cloud-forms.sh is gone or not executable"
for s in install/forms.sh install/lib.sh install/tasks/020-env.sh install/tasks/075-forms.sh install/tasks/080-stack.sh scripts/recreate-openmrs.sh scripts/fetch-cloud-forms.sh scripts/update-forms.sh; do
  bash -n "$CL/$s" 2>/dev/null && ok_ "$s parses" || bad "$s does not parse"
done

# --- fakes: ssh and every runtime entry point log their call -----------------------------
mkdir -p "$TMP/bin"
for b in ssh docker podman docker-compose podman-compose; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_LOG"\nexit 0\n' "$b" > "$TMP/bin/$b"
done
chmod +x "$TMP/bin/"*
export FAKE_LOG="$TMP/calls.log"

# --- fetch-cloud-forms.sh needs the clinic's forms folder --------------------------------
N="$TMP/n"; mkdir -p "$N"; printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example.invalid:9092\n' > "$N/.env"; : > "$FAKE_LOG"
out="$(env -i PATH="$TMP/bin:$PATH" HOME="$TMP" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$N" bash "$CL/scripts/fetch-cloud-forms.sh" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'FORMS_DIR is not set' && [ ! -s "$FAKE_LOG" ] && [ -z "$(ls -A "$N" | grep -v '^\.env$')" ] \
  && ok_ "fetch-cloud-forms.sh refuses a clinic/.env without FORMS_DIR, before it reaches the cloud" || bad "fetch without FORMS_DIR: rc=$rc out=$out calls=$(cat "$FAKE_LOG")"

# --- update-forms.sh is the row/file check -----------------------------------------------
U1=11111111-1111-1111-1111-111111111111; U2=22222222-2222-2222-2222-222222222222; P=/home/bahmni/clinical_forms/
r(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }   # UUID NAME VERSION PUBLISHED RETIRED POINTER
N2="$TMP/n2"; D="$N2/data/clinical_forms"; mkdir -p "$D/translations"; echo '{}' > "$D/$U1.json"
printf 'FORMS_DIR=%s\n' "$D" > "$N2/.env"
r "$U1" ANC 3 1 0 "${P}$U1.json" > "$TMP/rows1"
{ r "$U1" ANC 3 1 0 "${P}$U1.json"; r "$U2" PNC 2 1 0 "${P}$U2.json"; } > "$TMP/rows2"
check(){ env -i PATH="$TMP/bin:$PATH" HOME="$TMP" FAKE_LOG="$FAKE_LOG" CLINIC_DIR="$N2" FORMS_ROWS_FILE="$1" bash "$CL/scripts/update-forms.sh" 2>&1; }
before="$(cd "$N2" && find . | sort && cat .env)"; : > "$FAKE_LOG"
out="$(check "$TMP/rows1")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'row/file check: 1 published forms, 1 with their file, 0 missing' && ok_ "update-forms.sh: every published form has its file, exit 0" || bad "check, all present: rc=$rc out=$out"
out="$(check "$TMP/rows2")"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "missing $U2.json (PNC v2)" && printf '%s' "$out" | grep -q 'FAIL row/file check: 2 published forms, 1 with their file, 1 missing' \
  && ok_ "update-forms.sh: a published form without its file is exit 1, by file, name and version" || bad "check, one missing: rc=$rc out=$out"
[ "$(cd "$N2" && find . | sort && cat .env)" = "$before" ] && [ ! -s "$FAKE_LOG" ] && ok_ "update-forms.sh changes nothing and starts nothing" || bad "the check changed something or made calls: $(cat "$FAKE_LOG")"
rm -rf "$D/translations"; out="$(check "$TMP/rows1")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no translations/ folder' && ok_ "update-forms.sh refuses a forms folder OpenMRS would not start on" || bad "check, bad folder: rc=$rc out=$out"
exit "$fails"
