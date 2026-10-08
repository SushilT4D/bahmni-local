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
# 5,000,000 and 300,000.
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
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$T/manifest.env"
printf 'person:person_id:230000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$T/tables.conf"
stride(){ PATH="$T/bin:$PATH" ENV_FILE="$T/env" CLINICS_FILE="$T/ledger" TABLES_FILE="$T/tables.conf" MYSQL_CONTAINER=fake SEED_MANIFEST="$T/manifest.env" "$@" bash "$R/clinic/scripts/configure-pk-offsets.sh" --dry-run 2>&1; }
out="$(stride env MAX_obs=4999990 MAX_orders=299990 MAX_drug_order=299990)"
printf '%s' "$out" | grep -qF 'ALTER TABLE `obs` AUTO_INCREMENT = 5000003;' && ok_ "obs: seed max 4,999,990, floor 5,000,000, residue 3 -> 5,000,003" || bad "obs: $out"
printf '%s' "$out" | grep -qF 'ALTER TABLE `orders` AUTO_INCREMENT = 300003;' && ok_ "orders: seed max 299,990, floor 300,000, residue 3 -> 300,003" || bad "orders: $out"
printf '%s' "$out" | grep -q 'ALTER TABLE `drug_order`' && bad "drug_order is altered: $out" || ok_ "drug_order is never altered (it has no counter; its key is orders.order_id)"
out="$(stride env MAX_obs=5000061 MAX_orders=299990)"
printf '%s' "$out" | grep -qF 'ALTER TABLE `obs` AUTO_INCREMENT = 5000063;' && ok_ "obs above the floor in the seed: next in this residue's series above the max (5,000,063)" || bad "obs above floor: $out"
out="$(stride env SEED_MANIFEST="$T/none.env")"
printf '%s' "$out" | grep -q 'ALTER TABLE `obs`' && bad "obs strided with no manifest floor" || ok_ "no manifest floor: obs is not strided from a guess"
printf 'FLOOR_OBS=5000005\nFLOOR_ORDERS=300000\n' > "$T/odd.env"
out="$(stride env SEED_MANIFEST="$T/odd.env")"; 
printf '%s' "$out" | grep -q 'not a multiple of 10' && ! printf '%s' "$out" | grep -q 'ALTER TABLE `obs`' && ok_ "a floor off the multiple of 10 stops striding" || bad "odd floor: $out"
grep -q 'SEED_MANIFEST="${SEED_DIR}/manifest.env" bash scripts/configure-pk-offsets.sh' "${HERE}/../tasks/060-striding.sh" && ok_ "060 strides from the seed's manifest" || bad "060 does not pass the manifest"
grep -q 'counter_floor_verdict' "${HERE}/../tasks/060-striding.sh" && grep -q 'counter_floor_verdict' "${HERE}/../tasks/100-exit-checks.sh" \
  && ok_ "060 and the exit checks read the counters back against the floors" || bad "counters are not read back in 060 and 100"
rm -rf "$T"

# --- the counter check: next id at or above floor + residue -------------------
CLINIC_DIR="$(mktemp -d)"; . "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
cv(){ counter_floor_verdict "$@" 2>&1; }
out="$(cv obs 5000003 5000000 3)"; [ $? = 0 ] && [ "$out" = "ok obs next id 5000003, at or above floor 5000000 + residue 3" ] && ok_ "counter at floor + residue passes" || bad "at floor: $out"
out="$(cv obs 5000011 5000000 3)"; [ $? = 0 ] && case "$out" in *"next id 5000013"*) true ;; *) false ;; esac && ok_ "a counter between two ids of the series: the next id is the series value above it" || bad "between: $out"
out="$(cv obs 4999991 5000000 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the obs id counter is below this clinic's floor: the next obs id would be 4999993, and clinic-written obs ids start at 5000003"*) true ;; *) false ;; esac \
  && ok_ "a counter below the floor is refused, the check named in words" || bad "below: rc=$rc $out"
out="$(cv orders 1 300000 3)"; [ $? = 1 ] && ok_ "a seed-restored counter (max + 1) below the floor is refused" || bad "orders: $out"
out="$(cv obs '' 5000000 3)"; [ $? = 1 ] && case "$out" in "could not read the obs id counter"*) true ;; *) false ;; esac && ok_ "a counter that could not be read is refused, not taken as zero" || bad "empty: $out"
out="$(cv obs 5000003 '' 3)"; [ $? = 1 ] && case "$out" in "no obs floor is recorded"*) true ;; *) false ;; esac && ok_ "no recorded floor is refused" || bad "no floor: $out"

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
# obs and orders not listed: their recorded floors are checked all the same
out="$(cvs "$CLINIC_DIR/plain.conf")"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^ok ')" = 2 ] && printf '%s' "$out" | grep -q '^ok obs next id 5000003' && printf '%s' "$out" | grep -q '^ok orders next id 300003' \
  && ok_ "counter_floor_verdicts: obs and orders with recorded floors are checked though the list does not take them from the seed" || bad "unlisted with floors: rc=$rc $out"
AI_OBS=4999993; out="$(cvs "$CLINIC_DIR/plain.conf")"; rc=$?; AI_OBS=5000003
[ "$rc" = 1 ] && case "$out" in "the obs id counter is below this clinic's floor"*) true ;; *) false ;; esac \
  && ok_ "counter_floor_verdicts: an unlisted obs counter below its recorded floor refuses" || bad "unlisted below: rc=$rc $out"
stamp_del FLOOR_OBS; stamp_del FLOOR_ORDERS
out="$(cvs "$CLINIC_DIR/plain.conf")"; rc=$?
[ "$rc" = 0 ] && case "$out" in "ok no table in sync/local/tables.conf takes its floor from the seed, and no obs or orders floor is recorded"*) true ;; *) false ;; esac \
  && ok_ "counter_floor_verdicts: a list with no floored table and no recorded floor says so" || bad "plain list: rc=$rc $out"
stamp_put FLOOR_OBS 5000000; stamp_put FLOOR_ORDERS 300000

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

# --- obs and orders start above the seed's floors, listed or not ---------------
# seed_counter_plan: the first id on this residue at or above the floor
sp(){ seed_counter_plan "$@" 2>&1; }
[ "$(sp obs 4999992 5000000 3)" = "set 5000003" ] && ok_ "seed_counter_plan: floor 5000000, residue 3, restored counter 4999992 -> set 5000003" || bad "plan below: $(sp obs 4999992 5000000 3)"
[ "$(sp obs 1 5000000 3)" = "set 5000003" ] && ok_ "seed_counter_plan: an empty table's counter goes to the same first id" || bad "plan from 1: $(sp obs 1 5000000 3)"
[ "$(sp orders 300000 300000 7)" = "set 300007" ] && ok_ "seed_counter_plan: a counter at the floor itself is below the first id (300000, residue 7 -> 300007)" || bad "plan at floor: $(sp orders 300000 300000 7)"
[ "$(sp obs 5000003 5000000 3)" = keep ] && ok_ "seed_counter_plan: a counter at the first id is unchanged" || bad "plan at first: $(sp obs 5000003 5000000 3)"
[ "$(sp obs 5000093 5000000 3)" = keep ] && ok_ "seed_counter_plan: a counter above it on this residue (rows this clinic wrote) is unchanged" || bad "plan above: $(sp obs 5000093 5000000 3)"
out="$(sp obs 5000007 5000000 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "the obs id counter is 5000007, above the first obs id this clinic may write (5000003, on residue 3 at or above the seed's floor 5000000) and not on residue 3"*) true ;; *) false ;; esac \
  && ok_ "seed_counter_plan: a counter above the floor on another residue is refused, the check named in words" || bad "plan off residue: rc=$rc $out"
out="$(sp obs '' 5000000 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "could not read the obs id counter"*) true ;; *) false ;; esac && ok_ "seed_counter_plan: a counter that could not be read is refused, not taken as zero" || bad "plan empty: rc=$rc $out"
out="$(sp obs 1 x 3)"; [ $? = 1 ] && ok_ "seed_counter_plan: a floor that is not a number is refused" || bad "plan bad floor: $out"

# task 060's seed-counters block against a stand-in MySQL that keeps each
# table's AUTO_INCREMENT in a file, takes ALTER TABLE ... AUTO_INCREMENT, and
# logs every ALTER; the list here does not carry obs or orders
T060="${HERE}/../tasks/060-striding.sh"
SB="$(sed -n '/^# seed-counters:begin/,/^# seed-counters:end/p' "$T060")"
[ -n "$SB" ] || bad "060 has no seed-counters block"
sl="$(grep -n '^# seed-counters:begin' "$T060" | cut -d: -f1)"; pl="$(grep -n 'bash scripts/configure-pk-offsets.sh' "$T060" | head -1 | cut -d: -f1)"; cl="$(grep -n '^# counter-check:begin' "$T060" | cut -d: -f1)"
[ -n "$sl" ] && [ -n "$pl" ] && [ -n "$cl" ] && [ "$pl" -lt "$sl" ] && [ "$sl" -lt "$cl" ] \
  && ok_ "060 lifts obs and orders after the striding script and before the counters are read back" || bad "060 block order: pk=${pl:-none} seed-counters=${sl:-none} counter-check=${cl:-none}"
MYF="$CLINIC_DIR/mysql"; mkdir -p "$MYF"
sb_run(){ # obs-AUTO_INCREMENT orders-AUTO_INCREMENT
  printf '%s\n' "$1" > "$MYF/obs"; printf '%s\n' "$2" > "$MYF/orders"; : > "$MYF/alters"
  ( INSTALL_DIR="${HERE}/.."; RESIDUE=3
    fail(){ printf 'FAIL %s\n' "$*"; exit 1; }; ok(){ printf 'OK %s\n' "$*"; }
    mysql_root(){ local q t n; q="$(cat)"
      case "$q" in
        ALTER*) t="$(printf '%s' "$q" | sed -n 's/.*`\([a-z_]*\)`.*/\1/p')"; n="$(printf '%s' "$q" | sed -n 's/.*AUTO_INCREMENT = \([0-9]*\);.*/\1/p')"
                printf '%s\n' "$q" >> "$MYF/alters"; printf '%s\n' "$n" > "$MYF/$t" ;;
        *) t="$(printf '%s' "$q" | sed -n "s/.*table_name='\([a-z_]*\)'.*/\1/p")"; cat "$MYF/$t" ;;
      esac; }
    eval "$SB" ) 2>&1
}
stamp_put FLOOR_OBS 5000000; stamp_put FLOOR_ORDERS 300000
out="$(sb_run 4999993 299991)"; rc=$?
[ "$rc" = 0 ] && grep -qxF 'ALTER TABLE openmrs.`obs` AUTO_INCREMENT = 5000003;' "$MYF/alters" && grep -qxF 'ALTER TABLE openmrs.`orders` AUTO_INCREMENT = 300003;' "$MYF/alters" \
  && [ "$(cat "$MYF/obs")" = 5000003 ] && [ "$(cat "$MYF/orders")" = 300003 ] \
  && ok_ "060: floors 5000000 and 300000, residue 3: obs AUTO_INCREMENT 5000003, orders 300003, though the list does not carry them" || bad "060 set: rc=$rc $out alters=$(cat "$MYF/alters")"
printf '%s\n' "$out" | grep -q '^OK obs next id 5000003, at or above floor 5000000 + residue 3 (counter set to 5000003)$' && printf '%s\n' "$out" | grep -q '^OK orders next id 300003' \
  && ok_ "060: each counter is read back after it is set, one line each" || bad "060 readback lines: $out"
out="$(sb_run 5000093 300003)"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$MYF/alters" ] && [ "$(cat "$MYF/obs")" = 5000093 ] && printf '%s\n' "$out" | grep -q '^OK obs next id 5000093.*(counter already there, unchanged)$' \
  && ok_ "060: counters already above the floor on this residue are left unchanged, and say so" || bad "060 keep: rc=$rc $out alters=$(cat "$MYF/alters")"
out="$(sb_run 5000007 299991)"; rc=$?
[ "$rc" = 1 ] && [ ! -s "$MYF/alters" ] && case "$out" in "FAIL the obs id counter is 5000007, above the first obs id"*) true ;; *) false ;; esac \
  && ok_ "060: an obs counter on another residue above the floor fails the task, and nothing is altered" || bad "060 off residue: rc=$rc $out alters=$(cat "$MYF/alters")"
out="$(sb_run '' 299991)"; rc=$?
[ "$rc" = 1 ] && [ ! -s "$MYF/alters" ] && case "$out" in "FAIL could not read the obs id counter"*) true ;; *) false ;; esac \
  && ok_ "060: a counter that cannot be read fails the task" || bad "060 unreadable: rc=$rc $out"
stamp_del FLOOR_OBS; stamp_del FLOOR_ORDERS
out="$(sb_run 4999993 299991)"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$MYF/alters" ] && printf '%s\n' "$out" | grep -q '^OK obs id counter left as the seed restored it: the seed gave no obs floor (FLOOR_OBS is not in its manifest.env)$' \
  && printf '%s\n' "$out" | grep -q '^OK orders id counter left as the seed restored it' \
  && ok_ "060: a manifest without floors leaves both counters as restored, with a line saying no floor was given" || bad "060 no floors: rc=$rc $out"

# the exit checks read the unlisted counters again against the recorded floors
stamp_put FLOOR_OBS 5000000; stamp_put FLOOR_ORDERS 300000
cp "$CLINIC_DIR/plain.conf" "$CLINIC_DIR/repo/sync/local/tables.conf"
out="$(blk_run "${HERE}/../tasks/100-exit-checks.sh" "$CLINIC_DIR/repo" 4999993)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "FAIL the obs id counter is below this clinic's floor: the next obs id would be 4999993"*) true ;; *) false ;; esac \
  && ok_ "100: an unlisted obs counter below the seed's floor fails the exit checks" || bad "100 unlisted below: rc=$rc $out"
rm -rf "$CLINIC_DIR"
exit "$fails"
