#!/usr/bin/env bash
# The installer's seed folder argument, the run gate, and the seed gate's checks.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
: > "$TMP/answers.env"
out="$(bash "${HERE}/../install.sh" --answers "$TMP/answers.env" 2>&1)"; case "$out" in *"--seed <folder> is required"*) ok_ "install.sh without --seed is refused" ;; *) bad "no --seed: $out" ;; esac
out="$(bash "${HERE}/../install.sh" --answers "$TMP/answers.env" --seed "$TMP/nope" 2>&1)"; case "$out" in *"seed folder not found"*) ok_ "missing folder refused" ;; *) bad "missing folder: $out" ;; esac
# --from and --only cannot skip the gate on a machine that never passed it
case "$(run_gate_verdict INSTALLED 050 '')" in *"--from and --only only resume an install that stopped part-way"*) ok_ "--from on a machine that never passed the gate refused" ;; *) bad "--from not refused: $(run_gate_verdict INSTALLED 050 '')" ;; esac
run_gate_verdict SEEDED '' 050 >/dev/null && bad "--only 050 on an installed machine not refused" || ok_ "--only 050 on an installed machine refused"
[ "$(run_gate_verdict SEEDED '' 010)" = ok ] && ok_ "--only 010 runs on an installed machine" || bad "--only 010 refused"
[ "$(run_gate_verdict SEEDING 060 '')" = ok ] && ok_ "--from resumes a run that stopped part-way" || bad "--from on SEEDING refused"
grep -q 'run_gate_verdict "$st" "${FROM}" "${ONLY}"' "${HERE}/../install.sh" && ok_ "install.sh checks the run gate" || bad "install.sh does not check the run gate"
# 005 carries the sync-started flag into the gate, and fails closed on counts
G="${HERE}/../tasks/005-seed-gate.sh"
grep -q 'stamp_gate_verdict "$st" "$(stamp_get SYNC_STARTED)"' "$G" && ok_ "005 refuses a retry after sync started" || bad "005 ignores SYNC_STARTED"
grep -q '|| printf 0' "$G" && bad "005 turns a failed count into 0" || ok_ "005 does not turn a failed count into 0"
grep -q 'stamp_put SYNC_STARTED 1' "${HERE}/../tasks/090-local-sync.sh" && ok_ "090 marks that sync started" || bad "090 does not mark SYNC_STARTED"
# the id floors: every table the OpenMRS [up] list strides from the seed needs
# its floor in the manifest, a positive multiple of 10
printf '[up]\nencounter:encounter_id:528000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n[down]\n' > "$TMP/tables.conf"
fv(){ printf "$1" > "$TMP/fm.env"; seed_floors_verdict "$TMP/fm.env" "${2:-$TMP/tables.conf}" 2>&1; }
out="$(fv 'SEED_TAKEN_AT=x\n')"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"manifest.env carries no obs floor (FLOOR_OBS)"*) true ;; *) false ;; esac && ok_ "a manifest without floors is refused, naming FLOOR_OBS" || bad "no floors: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5000000\n')"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"no orders floor (FLOOR_ORDERS)"*) true ;; *) false ;; esac && ok_ "a manifest with the obs floor only is refused, naming FLOOR_ORDERS" || bad "one floor: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5000001\nFLOOR_ORDERS=300000\n')"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"FLOOR_OBS=5000001 is not a positive multiple of 10"*) true ;; *) false ;; esac && ok_ "a floor that is not a multiple of 10 is refused" || bad "odd floor: rc=$rc $out"
out="$(fv 'FLOOR_OBS=0\nFLOOR_ORDERS=300000\n')"; rc=$?
[ "$rc" = 1 ] && ok_ "a zero floor is refused" || bad "zero floor: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5,000,000\nFLOOR_ORDERS=300000\n')"; rc=$?
[ "$rc" = 1 ] && ok_ "a floor that is not a plain number is refused" || bad "formatted floor: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n')"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "ok obs=5000000 orders=300000" ] && ok_ "both floors: ok obs=5000000 orders=300000 (drug_order reads the orders floor)" || bad "floors: rc=$rc $out"
printf '[up]\nencounter:encounter_id:528000\nidgen_seq_id_gen:id\n[down]\n' > "$TMP/plain.conf"
# obs and orders floors are required whether or not the list carries the
# tables: the striding step lifts their counters by them
out="$(fv 'SEED_TAKEN_AT=x\n' "$TMP/plain.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in "manifest.env carries no obs floor (FLOOR_OBS)"*"Ask the operator for a fresh seed folder."*) true ;; *) false ;; esac \
  && ok_ "a seed without FLOOR_OBS is refused though the list does not carry obs, naming the key" || bad "plain list without floors: rc=$rc $out"
out="$(fv 'SEED_TAKEN_AT=x\nFLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' "$TMP/plain.conf")"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "ok obs=5000000 orders=300000" ] && ok_ "obs and orders floors are taken from the manifest though the list does not carry the tables" || bad "unlisted floors: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5000001\n' "$TMP/plain.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"FLOOR_OBS=5000001 is not a positive multiple of 10"*) true ;; *) false ;; esac && ok_ "an unlisted floor that is not a multiple of 10 is refused" || bad "unlisted odd floor: rc=$rc $out"
out="$(fv 'FLOOR_ORDERS=300000\n' "$TMP/plain.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"no obs floor (FLOOR_OBS)"*) true ;; *) false ;; esac && ok_ "a seed with the orders floor only is refused, naming FLOOR_OBS" || bad "orders alone: rc=$rc $out"
out="$(fv 'FLOOR_OBS=5000000\n' "$TMP/plain.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"no orders floor (FLOOR_ORDERS)"*) true ;; *) false ;; esac && ok_ "a seed with the obs floor only is refused, naming FLOOR_ORDERS" || bad "obs alone: rc=$rc $out"
grep -q 'seed_floors_verdict "${SEED_DIR}/manifest.env" "${REPO_DIR}/sync/tables/openmrs.conf")" || refuse' "$G" && ok_ "005 refuses a seed without its floors" || bad "005 does not check the floors"
grep -q 'stamp_put "FLOOR_' "$G" && ok_ "005 records the floors for the later counter checks" || bad "005 does not record the floors"
exit $((fails > 0))
