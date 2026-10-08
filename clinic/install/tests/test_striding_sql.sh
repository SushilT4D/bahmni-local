#!/usr/bin/env bash
# clinic/odoo/apply-odoo-sequence-striding.sql against a REAL PostgreSQL, because
# a version of it passed every fixture test and failed on a database:
# pg_get_serial_sequence('t','id') does not return NULL for a table that has no
# `id` column -- it RAISES, which rolled back the whole transaction, so even the
# id tables listed beside a link table stayed unstrided (found by running it
# on a dev box's PostgreSQL before any clinic did).
# A host without psql keeps a static guard.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL="${HERE}/../../odoo/apply-odoo-sequence-striding.sql"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
grep -q "attname = 'id'" "$SQL" && ok_ "the SQL asks whether an id column exists before resolving its sequence" || bad "no id-column existence check before pg_get_serial_sequence"
db="${STRIDING_TEST_DB:-bahmni_test}"
if command -v psql >/dev/null 2>&1 && psql -d "$db" -qAt -c 'select 1' >/dev/null 2>&1; then
  p="zz_$$"
  psql -d "$db" -q -v ON_ERROR_STOP=1 >/dev/null <<DDL
CREATE TABLE public.${p}_village (id serial PRIMARY KEY, name text);
INSERT INTO public.${p}_village(name) SELECT 'v'||g FROM generate_series(1,37) g;
CREATE TABLE public.${p}_empty (id serial PRIMARY KEY);
CREATE TABLE public.${p}_link (prod_id int, tax_id int, PRIMARY KEY (prod_id, tax_id));
CREATE TABLE public.${p}_nopk (a int, b int);
CREATE TABLE public.${p}_onecol (code text PRIMARY KEY);
DDL
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_village,${p}_link,${p}_empty" -q -f "$SQL" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q ERROR && ok_ "an id table, a composite link table and an empty id table stride together" || bad "mixed list failed: $out"
  printf '%s' "$out" | grep -q "${p}_link.*composite" && ok_ "the link table is skipped with a NOTICE naming its composite key" || bad "no composite NOTICE for the link table: $out"
  [ "$(psql -d "$db" -qAt -c "select increment_by from pg_sequences where sequencename='${p}_village_id_seq'")" = 10 ] && ok_ "id table: step 10" || bad "village sequence step is not 10"
  [ "$(psql -d "$db" -qAt -c "select nextval('${p}_village_id_seq')")" = 43 ] && ok_ "id table: next id 43 (above max 37, residue 3)" || bad "village next id is not 43"
  [ "$(psql -d "$db" -qAt -c "select nextval('${p}_empty_id_seq')")" = 13 ] && ok_ "empty id table: next id 13 (residue 3)" || bad "empty table next id is not 13"
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_nopk" -q -f "$SQL" 2>&1)"
  printf '%s' "$out" | grep -q "no composite primary key" && ok_ "a table with no key at all is still refused, in the script's own words" || bad "no-pk table: $out"
  out="$(psql -d "$db" -v residue=3 -v tables="${p}_onecol" -q -f "$SQL" 2>&1)"
  printf '%s' "$out" | grep -q "no composite primary key" && ok_ "a single-column non-serial key is still refused" || bad "one-column pk table: $out"
  psql -d "$db" -q -c "DROP TABLE public.${p}_village, public.${p}_empty, public.${p}_link, public.${p}_nopk, public.${p}_onecol" >/dev/null 2>&1
else
  ok_ "live PostgreSQL proof skipped (no psql / no ${db})"
fi

# --- MySQL: obs and orders start at the seed's floor plus the residue ----------
# configure-pk-offsets.sh --dry-run against a stand-in for podman that answers
# "the table exists" and MAX(pk) from MAX_<table>; residue 3, the seed's floors
# 7,963,440 and 441,560.
R="$(cd "${HERE}/../../.." && pwd)"
T="$(mktemp -d)"
mkdir -p "$T/bin"
cat > "$T/bin/podman" <<'SH'
#!/bin/sh
for a; do sql="$a"; done
case "$sql" in
  *information_schema.tables*) echo 1 ;;
  *MAX*) t=$(printf '%s' "$sql" | sed -n 's/.*FROM `\([a-z_]*\)`.*/\1/p'); eval "echo \${MAX_$t:-0}" ;;
esac
SH
chmod +x "$T/bin/podman"
printf 'BHS_LOCATION=alpha\nMYSQL_ROOT_PASSWORD=x\n' > "$T/env"; printf 'alpha:3\n' > "$T/ledger"
printf 'FLOOR_OBS=7963440\nFLOOR_ORDERS=441560\n' > "$T/manifest.env"
printf 'person:person_id:230000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$T/tables.conf"
stride(){ PATH="$T/bin:$PATH" ENV_FILE="$T/env" CLINICS_FILE="$T/ledger" TABLES_FILE="$T/tables.conf" MYSQL_CONTAINER=fake SEED_MANIFEST="$T/manifest.env" "$@" bash "$R/clinic/scripts/configure-pk-offsets.sh" --dry-run 2>&1; }
out="$(stride env MAX_obs=7963430 MAX_orders=441550 MAX_drug_order=441550)"
printf '%s' "$out" | grep -qF 'ALTER TABLE `obs` AUTO_INCREMENT = 7963443;' && ok_ "obs: seed max 7,963,430, floor 7,963,440, residue 3 -> 7,963,443" || bad "obs: $out"
printf '%s' "$out" | grep -qF 'ALTER TABLE `orders` AUTO_INCREMENT = 441563;' && ok_ "orders: seed max 441,550, floor 441,560, residue 3 -> 441,563" || bad "orders: $out"
printf '%s' "$out" | grep -q 'ALTER TABLE `drug_order`' && bad "drug_order is altered: $out" || ok_ "drug_order is never altered (it has no counter; its key is orders.order_id)"
out="$(stride env MAX_obs=7963501 MAX_orders=441550)"
printf '%s' "$out" | grep -qF 'ALTER TABLE `obs` AUTO_INCREMENT = 7963503;' && ok_ "obs above the floor in the seed: next in this residue's series above the max (7,963,503)" || bad "obs above floor: $out"
out="$(stride env SEED_MANIFEST="$T/none.env")"
printf '%s' "$out" | grep -q 'ALTER TABLE `obs`' && bad "obs strided with no manifest floor" || ok_ "no manifest floor: obs is not strided from a guess"
printf 'FLOOR_OBS=7963445\nFLOOR_ORDERS=441560\n' > "$T/odd.env"
out="$(stride env SEED_MANIFEST="$T/odd.env")"; 
printf '%s' "$out" | grep -q 'not a multiple of 10' && ! printf '%s' "$out" | grep -q 'ALTER TABLE `obs`' && ok_ "a floor off the multiple of 10 stops striding" || bad "odd floor: $out"
grep -q 'SEED_MANIFEST="${SEED_DIR}/manifest.env" bash scripts/configure-pk-offsets.sh' "${HERE}/../tasks/060-striding.sh" && ok_ "060 strides from the seed's manifest" || bad "060 does not pass the manifest"
grep -q 'counter_floor_verdict' "${HERE}/../tasks/060-striding.sh" && grep -q 'counter_floor_verdict' "${HERE}/../tasks/100-exit-checks.sh" \
  && ok_ "060 and the exit checks read the counters back against the floors" || bad "counters are not read back in 060 and 100"
rm -rf "$T"

# --- the counter check: next id at or above floor + residue -------------------
CLINIC_DIR="$(mktemp -d)"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
cv(){ counter_floor_verdict "$@" 2>&1; }
out="$(cv obs 7963443 7963440 3)"; [ $? = 0 ] && [ "$out" = "ok obs next id 7963443, at or above floor 7963440 + residue 3" ] && ok_ "counter at floor + residue passes" || bad "at floor: $out"
out="$(cv obs 7963451 7963440 3)"; [ $? = 0 ] && case "$out" in *"next id 7963453"*) true ;; *) false ;; esac && ok_ "a counter between two ids of the series: the next id is the series value above it" || bad "between: $out"
out="$(cv obs 7963431 7963440 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the obs id counter is below this clinic's floor: the next obs id would be 7963433, and clinic-written obs ids start at 7963443"*) true ;; *) false ;; esac \
  && ok_ "a counter below the floor is refused, the check named in words" || bad "below: rc=$rc $out"
out="$(cv orders 1 441560 3)"; [ $? = 1 ] && ok_ "a seed-restored counter (max + 1) below the floor is refused" || bad "orders: $out"
out="$(cv obs '' 7963440 3)"; [ $? = 1 ] && case "$out" in "could not read the obs id counter"*) true ;; *) false ;; esac && ok_ "a counter that could not be read is refused, not taken as zero" || bad "empty: $out"
out="$(cv obs 7963443 '' 3)"; [ $? = 1 ] && case "$out" in "no obs floor is recorded"*) true ;; *) false ;; esac && ok_ "no recorded floor is refused" || bad "no floor: $out"

# --- every floored counter at once, and a table list that cannot be read ------
# A broken list must refuse: a loop over an empty list would check no counter
# and pass.
stamp_put FLOOR_OBS 5000000; stamp_put FLOOR_ORDERS 300000
printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$CLINIC_DIR/tables.conf"
AI_OBS=5000003; AI_ORDERS=300003
ai_fake(){ case "$1" in obs) echo "$AI_OBS" ;; orders) echo "$AI_ORDERS" ;; esac; }
cvs(){ counter_floor_verdicts "$1" 3 ai_fake 2>&1; }
out="$(cvs "$CLINIC_DIR/tables.conf")"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^ok ')" = 2 ] && printf '%s' "$out" | grep -q '^ok orders next id 300003' \
  && ok_ "counter_floor_verdicts: one ok line per floored table (drug_order has no counter)" || bad "all counters: rc=$rc $out"
AI_ORDERS=299991; out="$(cvs "$CLINIC_DIR/tables.conf")"; rc=$?; AI_ORDERS=300003
[ "$rc" = 1 ] && case "$out" in "the orders id counter is below this clinic's floor"*) true ;; *) false ;; esac && ! printf '%s' "$out" | grep -q '^ok ' \
  && ok_ "counter_floor_verdicts: one counter below its floor refuses, with only the refusal" || bad "one below: rc=$rc $out"
out="$(cvs "$CLINIC_DIR/no-such.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the clinic table list cannot be read, so no id counter was checked: tables.conf not found"*) true ;; *) false ;; esac \
  && ok_ "counter_floor_verdicts: a missing table list refuses, not zero tables checked" || bad "missing list: rc=$rc $out"
printf 'obs:obs_id:seed   # a trailing note\n' > "$CLINIC_DIR/bad.conf"
out="$(cvs "$CLINIC_DIR/bad.conf")"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the clinic table list cannot be read"*"not table:pk[:floor]"*) true ;; *) false ;; esac \
  && ok_ "counter_floor_verdicts: a list its reader refuses refuses, with the reader's reason" || bad "refused list: rc=$rc $out"
printf 'encounter:encounter_id:528000\nidgen_seq_id_gen:id\n' > "$CLINIC_DIR/plain.conf"
out="$(cvs "$CLINIC_DIR/plain.conf")"; rc=$?
[ "$rc" = 0 ] && case "$out" in "ok no table in sync/local/tables.conf takes its floor from the seed"*) true ;; *) false ;; esac \
  && ok_ "counter_floor_verdicts: a list with no floored table says so" || bad "plain list: rc=$rc $out"

# tasks 060 and 100 run their counter-check block; a table list that cannot be
# read fails the task
mkdir -p "$CLINIC_DIR/repo/sync/local" "$CLINIC_DIR/norepo"; cp "$CLINIC_DIR/tables.conf" "$CLINIC_DIR/repo/sync/local/"
blk_run(){ # TASK-FILE REPO-DIR AUTO_INCREMENT -> the block's output with stand-ins for the database
  local B; B="$(sed -n '/^# counter-check:begin/,/^# counter-check:end/p' "$1")"
  [ -n "$B" ] || { printf 'NO BLOCK\n'; return 2; }
  ( INSTALL_DIR="${HERE}/.."; REPO_DIR="$2"; RESIDUE=3; MY=fake; AI="$3"
    fail(){ printf 'FAIL %s\n' "$*"; exit 1; }; ok(){ printf 'OK %s\n' "$*"; }
    ct(){ cat >/dev/null; echo "$AI"; }; mysql_root(){ cat >/dev/null; echo "$AI"; }
    eval "$B" ) 2>&1
}
for task in 060-striding 100-exit-checks; do
  TF="${HERE}/../tasks/${task}.sh"
  out="$(blk_run "$TF" "$CLINIC_DIR/norepo" 5000003)"; rc=$?
  [ "$rc" = 1 ] && case "$out" in "FAIL the clinic table list cannot be read"*) true ;; *) false ;; esac \
    && ok_ "${task}: a table list that cannot be read fails the task" || bad "${task} unreadable list: rc=$rc $out"
  out="$(blk_run "$TF" "$CLINIC_DIR/repo" 5000003)"; rc=$?
  [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^OK obs next id 5000003' && printf '%s\n' "$out" | grep -q '^OK orders next id 5000003' \
    && ok_ "${task}: each floored counter read back, one ok line each" || bad "${task} counters: rc=$rc $out"
  out="$(blk_run "$TF" "$CLINIC_DIR/repo" 13)"; rc=$?
  [ "$rc" = 1 ] && case "$out" in "FAIL the obs id counter is below this clinic's floor"*) true ;; *) false ;; esac \
    && ok_ "${task}: a counter below its floor fails the task" || bad "${task} below floor: rc=$rc $out"
done
rm -rf "$CLINIC_DIR"
exit "$fails"
