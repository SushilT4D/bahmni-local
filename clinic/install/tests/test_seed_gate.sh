#!/usr/bin/env bash
# The seed gate's refusal for a machine whose LAN name no longer points at it,
# the gate's place in the seed sitting, and the floors it requires.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLINIC_DIR="$TMP"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
v(){ lan_name_verdict "$@" 2>&1; }
[ "$(v 10.0.0.5 10.0.0.5 bahmni.clinic)" = ok ] && ok_ "name on this machine" || bad "same ip: $(v 10.0.0.5 10.0.0.5 bahmni.clinic)"
case "$(v 10.0.0.9 10.0.0.5 bahmni.clinic)" in "bahmni.clinic resolves to 10.0.0.9, but this machine is 10.0.0.5"*) ok_ "moved machine refused" ;; *) bad "moved: $(v 10.0.0.9 10.0.0.5 bahmni.clinic)" ;; esac
case "$(v '' 10.0.0.5 bahmni.clinic)" in "bahmni.clinic does not resolve on this machine"*) ok_ "no answer refused" ;; *) bad "empty: $(v '' 10.0.0.5 bahmni.clinic)" ;; esac
grep -q '^# phase: seed$' "${HERE}/../tasks/005-seed-gate.sh" 2>/dev/null && ok_ "005 runs in the seed sitting" || bad "005 missing or not seed-phase"
# 005 carries the sync-started flag into the gate, and fails closed on counts
G="${HERE}/../tasks/005-seed-gate.sh"
grep -q 'stamp_gate_verdict "$st" "$(stamp_get SYNC_STARTED)"' "$G" && ok_ "005 refuses a retry after sync started" || bad "005 ignores SYNC_STARTED"
grep -q '|| printf 0' "$G" && bad "005 turns a failed count into 0" || ok_ "005 does not turn a failed count into 0"
grep -q 'stamp_put SYNC_STARTED 1' "${HERE}/../tasks/090-local-sync.sh" && ok_ "090 marks that sync started" || bad "090 does not mark SYNC_STARTED"
# the id floors: every table the OpenMRS [up] list strides from the seed needs
# its floor in the manifest, a positive multiple of 10
printf 'encounter:encounter_id:528000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$TMP/tables.conf"
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
printf 'encounter:encounter_id:528000\nidgen_seq_id_gen:id\n' > "$TMP/plain.conf"
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
