#!/usr/bin/env bash
# The clinic's forms folder is a data folder that starts empty and is filled by forms-sync.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CL="$(cd "${HERE}/../.." && pwd)"
T75="${HERE}/../tasks/075-forms.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
U1=11111111-1111-1111-1111-111111111111
printf '%s\tANC\t3\t1\t0\t/home/bahmni/clinical_forms/%s.json\n' "$U1" "$U1" > "$TMP/rows"
: > "$TMP/norows"

node(){ mkdir -p "$1"; printf 'COMPOSE_PROJECT_NAME=bahmni-t\nCONTAINER_DATA_PATH=%s\n' "$1" > "$1/.env"; }
run(){ # DIR (ROWS= the database's form rows)
  env -i PATH="$PATH" HOME="$TMP" CLINIC_DIR="$1" FORMS_ROWS_FILE="${ROWS:-$TMP/rows}" bash "$T75" 2>&1
}
envv(){ ( . "${HERE}/../lib.sh"; env_get "$1/.env" "$2" ); }
listing(){ ( cd "$1" && find . | sort && cat .env ); }
verdict(){ ( CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../forms.sh"; forms_folder_verdict "$1" ); }

# --- a first run -------------------------------------------------------------------------
N="$TMP/n"; node "$N"; D="$N/data/clinical_forms"
out="$(run "$N")"; rc=$?
[ "$rc" -eq 0 ] && [ -d "$D/translations" ] && [ -z "$(find "$D" -type f)" ] \
  && ok_ "the step creates the forms folder and translations/, both empty" || bad "first run: rc=$rc out=$out"
[ "$(envv "$N" FORMS_DIR)" = "$D" ] && ok_ "clinic/.env names it as FORMS_DIR, under CONTAINER_DATA_PATH" || bad "FORMS_DIR is $(envv "$N" FORMS_DIR)"
printf '%s' "$out" | grep -q "missing $U1.json (ANC v3)" && ! printf '%s' "$out" | grep -qE 'FAIL|WARN' \
  && ok_ "a published form whose file has not arrived is listed, not refused" || bad "missing file at install: $out"
before="$(listing "$N")"
out="$(run "$N")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(listing "$N")" = "$before" ] && ok_ "a second run changes nothing" || bad "second run: rc=$rc out=$out"

# --- a folder that already holds files ---------------------------------------------------
N2="$TMP/n2"; node "$N2"; D2="$N2/data/clinical_forms"
mkdir -p "$D2/translations"; echo '{"a":1}' > "$D2/$U1.json"; echo '{"t":1}' > "$D2/translations/$U1.json"
printf 'FORMS_DIR=/somewhere/else\n' >> "$N2/.env"
sums(){ ( cd "$1" && find . -type f | sort | while IFS= read -r f; do cksum "$f"; done ); }
before="$(sums "$D2")"
out="$(run "$N2")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(sums "$D2")" = "$before" ] && ok_ "a folder that already holds files is left exactly as it is" || bad "kept folder: rc=$rc out=$out"
[ "$(envv "$N2" FORMS_DIR)" = "$D2" ] && ok_ "a FORMS_DIR naming another folder is set back to the data folder" || bad "FORMS_DIR is $(envv "$N2" FORMS_DIR)"
printf '%s' "$out" | grep -q 'row/file check: 1 published forms, 1 with their file, 0 missing' && ok_ "the row/file check passes once the file is there" || bad "row/file with the file: $out"

# --- a dry run ---------------------------------------------------------------------------
N3="$TMP/n3"; node "$N3"; before="$(listing "$N3")"
out="$(env -i PATH="$PATH" HOME="$TMP" CLINIC_DIR="$N3" DRY=1 bash "$T75" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(listing "$N3")" = "$before" ] && ok_ "a dry run creates nothing" || bad "dry run: rc=$rc out=$out"

# --- what a start path accepts and refuses -----------------------------------------------
out="$(verdict "$D")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "ok 0 form files in $D" ] && ok_ "an empty forms folder is accepted" || bad "empty folder: rc=$rc out=$out"
out="$(verdict "$TMP/absent")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not exist' && ok_ "a missing folder is refused" || bad "missing folder: rc=$rc out=$out"
out="$(verdict "")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'FORMS_DIR is not set' && ok_ "an unset FORMS_DIR is refused" || bad "unset FORMS_DIR: rc=$rc out=$out"
mkdir -p "$TMP/nt"; out="$(verdict "$TMP/nt")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no translations/ folder' && ok_ "a folder without translations/ is refused" || bad "no translations: rc=$rc out=$out"
mkdir -p "$TMP/ln/translations"; ln -s /etc/hosts "$TMP/ln/translations/x.json"; out="$(verdict "$TMP/ln")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'holds a symlink' && ok_ "a symlink inside the folder is refused" || bad "symlink: rc=$rc out=$out"

# --- every start path checks the folder --------------------------------------------------
for f in install/tasks/075-forms.sh install/tasks/080-stack.sh scripts/recreate-openmrs.sh; do
  grep -vE '^[[:space:]]*#' "$CL/$f" | grep -q 'forms_folder_verdict' && ok_ "$f checks the forms folder" || bad "$f does not call forms_folder_verdict"
done

# --- the mounts --------------------------------------------------------------------------
Y="$CL/docker-compose.yml"
grep -q 'bahmni_home/clinical_forms' "$Y" && bad "docker-compose.yml still mounts bahmni_home/clinical_forms" || ok_ "no mount of bahmni_home/clinical_forms is left"
grep -q 'FORMS_READ_ONLY' "$Y" && bad "docker-compose.yml still reads FORMS_READ_ONLY" || ok_ "the forms mounts are always read-write"
[ "$(grep -c 'source: "${FORMS_DIR:?' "$Y")" = 2 ] && ok_ "openmrs mounts the forms folder and its translations/ from FORMS_DIR, which must be set" || bad "the two openmrs forms mounts do not require FORMS_DIR"
grep -vE '^[[:space:]]*#' "${HERE}/../tasks/020-env.sh" | grep -q 'put FORMS_DIR "${CLINIC_DIR}/data/clinical_forms"' && ok_ "a fresh clinic/.env carries FORMS_DIR before compose first reads it" || bad "020 does not set FORMS_DIR"
exit "$fails"
