#!/usr/bin/env bash
# Order numbers in the clinic's own range. A clinic of residue r issues
# ORD-<k> with k from r x 10,000,000 + 1 to (r + 1) x 10,000,000 - 1; the hub
# issues below 10,000,000. The seed sitting sets order.nextOrderNumberSeed to
# the start of the range before OpenMRS first starts (task 060) and reads it
# back, and the exit checks read it again after the applications have started.
# A value in another node's range is refused, never passed.
#
# The rules are state.sh's pure functions; 060's block runs between its
# order-seed:begin/:end markers against a stand-in for the database that holds
# one global_property value in a file.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
CLINIC_DIR="$(mktemp -d)"; trap 'rm -rf "$CLINIC_DIR"' EXIT
. "${HERE}/../lib.sh"; . "${HERE}/../state.sh"

# --- the range ------------------------------------------------------------------
[ "$(order_seed_range 3)" = "30000001 39999999" ] && ok_ "residue 3: 30,000,001 to 39,999,999" || bad "residue 3 range: $(order_seed_range 3)"
[ "$(order_seed_range 1)" = "10000001 19999999" ] && [ "$(order_seed_range 9)" = "90000001 99999999" ] && ok_ "residues 1 and 9 bound the clinic ranges" || bad "residue 1/9 ranges"
out="$(order_seed_range 0)"; [ $? = 1 ] && case "$out" in *"below 10,000,000 is the hub's"*) true ;; *) false ;; esac && ok_ "residue 0 has no clinic range (the hub's)" || bad "residue 0: $out"
out="$(order_seed_range '')"; [ $? = 1 ] && ok_ "no residue has no range" || bad "empty residue: $out"

# --- what 060 does with the seed's value ----------------------------------------
pl(){ order_seed_plan "$@" 2>&1; }
[ "$(pl 250000 3)" = "set 30000001" ] && ok_ "the hub's value from the seed (250,000), residue 3 -> set 30,000,001" || bad "hub value: $(pl 250000 3)"
[ "$(pl '' 3)" = "set 30000001" ] && ok_ "no value in the seed -> set 30,000,001 (OpenMRS would start at 1)" || bad "absent: $(pl '' 3)"
[ "$(pl 30000150 3)" = keep ] && ok_ "a value already in range is kept (a rerun does not move it back)" || bad "in range: $(pl 30000150 3)"
out="$(pl 10000005 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"in the range of the clinic with residue 1, not this clinic's (30000001 to 39999999)"*) true ;; *) false ;; esac \
  && ok_ "a value copied from another clinic is refused, naming whose range it is in" || bad "copied: rc=$rc $out"
out="$(pl 120000000 3)"; [ $? = 1 ] && case "$out" in *"no node's range"*) true ;; *) false ;; esac && ok_ "a value above every range is refused" || bad "above: $out"
out="$(pl ORD-5 3)"; [ $? = 1 ] && case "$out" in *"not a number"*) true ;; *) false ;; esac && ok_ "a value that is not a number is refused" || bad "nan: $out"

# --- the read-back ----------------------------------------------------------------
vd(){ order_seed_verdict "$@" 2>&1; }
out="$(vd 30000001 3)"; [ $? = 0 ] && [ "$out" = "ok order.nextOrderNumberSeed 30000001, in this clinic's range 30000001 to 39999999" ] && ok_ "30,000,001 read back on residue 3 passes" || bad "start: $out"
out="$(vd 10000005 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in "order.nextOrderNumberSeed is 10000005, in the range of the clinic with residue 1"*) true ;; *) false ;; esac \
  && ok_ "a value from another clinic's range read back is refused" || bad "other clinic: rc=$rc $out"
out="$(vd 250000 3)"; [ $? = 1 ] && case "$out" in *"the hub's range"*) true ;; *) false ;; esac && ok_ "the hub's value read back (never set, or reset by a start) is refused" || bad "hub: $out"
out="$(vd 40000000 3)"; [ $? = 1 ] && ok_ "one past the top of the range is refused" || bad "past top: $out"
out="$(vd '' 3)"; [ $? = 1 ] && case "$out" in "could not read order.nextOrderNumberSeed"*) true ;; *) false ;; esac && ok_ "a value that could not be read is refused" || bad "empty: $out"
err="$(order_seed_verdict 39000001 3 2>&1 >/dev/null)"; out="$(order_seed_verdict 39000001 3 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && case "$out" in ok*) true ;; *) false ;; esac && case "$err" in *"within 1,000,000 of the top"*) true ;; *) false ;; esac \
  && ok_ "a value within 1,000,000 of the top passes and is reported" || bad "near top: rc=$rc out=$out err=$err"
err="$(order_seed_verdict 38999999 3 2>&1 >/dev/null)"; [ -z "$err" ] && ok_ "a value further from the top is not reported" || bad "not near top: $err"

# --- the statement ------------------------------------------------------------------
sql="$(order_seed_sql 30000001)"
case "$sql" in "INSERT INTO global_property (property, property_value, description, uuid) VALUES ('order.nextOrderNumberSeed', '30000001',"*"UUID()) ON DUPLICATE KEY UPDATE property_value = '30000001';") ok_ "the write creates the row when the seed lacks it and updates it otherwise" ;; *) bad "sql: $sql" ;; esac

# --- 060's block against a stand-in database ----------------------------------------
TF="$(sed -n '/^# order-seed:begin/,/^# order-seed:end/p' "${HERE}/../tasks/060-striding.sh")"
[ -n "$TF" ] || bad "060-striding.sh has no order-seed:begin/:end block"
DB="$(mktemp -d)"
run060(){ # STORED-VALUE|ABSENT|DOWN -> output; the stored value after, in $DB/value
  rm -f "$DB/value"; case "$1" in ABSENT|DOWN) ;; *) printf '%s' "$1" > "$DB/value" ;; esac
  ( RESIDUE=3; DOWN=0; [ "$1" = DOWN ] && DOWN=1
    fail(){ printf 'FAIL %s\n' "$*"; exit 1; }; ok(){ printf 'ok %s\n' "$*"; }
    mysql_root(){ local q; q="$(cat)"
      [ "$DOWN" = 1 ] && return 1
      case "$q" in
        *"INSERT INTO global_property"*) printf '%s' "$q" | sed -n "s/.*ON DUPLICATE KEY UPDATE property_value = '\([0-9]*\)';.*/\1/p" | tr -d '\n' > "$DB/value" ;;
        *"select concat('v='"*) printf 'v=%s\n' "$(cat "$DB/value" 2>/dev/null)" ;;
      esac; }
    eval "$TF" ) 2>&1
}
out="$(run060 250000)"; [ "$(cat "$DB/value")" = 30000001 ] && case "$out" in *"ok order.nextOrderNumberSeed 30000001"*) true ;; *) false ;; esac \
  && ok_ "060 on the seed's value: writes 30,000,001 and reads it back" || bad "060 seed value: $out / $(cat "$DB/value")"
out="$(run060 ABSENT)"; [ "$(cat "$DB/value" 2>/dev/null)" = 30000001 ] && ok_ "060 with no row: creates it at 30,000,001" || bad "060 absent: $out"
out="$(run060 30000420)"; [ "$(cat "$DB/value")" = 30000420 ] && case "$out" in *"ok order.nextOrderNumberSeed 30000420"*) true ;; *) false ;; esac \
  && ok_ "060 rerun after orders were issued: leaves 30,000,420" || bad "060 rerun: $out"
out="$(run060 10000005)"; [ "$(cat "$DB/value")" = 10000005 ] && case "$out" in "FAIL order.nextOrderNumberSeed is 10000005, in the range of the clinic with residue 1"*) true ;; *) false ;; esac \
  && ok_ "060 refuses a value copied from another clinic and does not overwrite it" || bad "060 copied: $out"
out="$(run060 DOWN)"; case "$out" in "FAIL could not read order.nextOrderNumberSeed"*) ok_ "060 refuses when the database does not answer (not taken as absent)" ;; *) bad "060 down: $out" ;; esac
rm -rf "$DB"

# --- wiring ---------------------------------------------------------------------------
grep -q '^# phase: seed' "${HERE}/../tasks/060-striding.sh" && ok_ "060 runs in the seed sitting, after the restore (050) and before the stack starts (080)" || bad "060 is not a seed task"
grep -q 'order_seed_verdict' "${HERE}/../tasks/100-exit-checks.sh" && ok_ "the exit checks read the counter back after the applications have started" || bad "100 does not read the order-number counter back"
exit "$fails"
