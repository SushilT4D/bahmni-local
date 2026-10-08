#!/usr/bin/env bash
# At or above the seed's floor every seeded obs and orders row must be the
# hub's (residue 0); the striding step reads it from the restored database
# before it moves a counter, and refuses the seed otherwise. A row there on a
# clinic's residue would pass that clinic's capture filter, and its edits would
# overwrite the hub's row.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLINIC_DIR="$TMP" INSTALL_DIR="${HERE}/.."
. "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
[ "$(seed_floor_residue_sql obs 5000000)" = 'select count(*) from openmrs.`obs` where `obs_id` >= 5000000 and `obs_id` % 10 <> 0;' ] && ok_ "obs: counts rows at or above the floor off residue 0" || bad "obs sql: $(seed_floor_residue_sql obs 5000000)"
[ "$(seed_floor_residue_sql orders 300000)" = 'select count(*) from openmrs.`orders` where `order_id` >= 300000 and `order_id` % 10 <> 0;' ] && ok_ "orders: the same on order_id" || bad "orders sql: $(seed_floor_residue_sql orders 300000)"
out="$(seed_floor_residue_verdict obs 5000000 0)" && ok_ "none there: $out" || bad "0 refused: $out"
out="$(seed_floor_residue_verdict obs 5000000 3)"; [ $? = 1 ] && case "$out" in "the seed holds 3 obs row(s) at or above the floor 5000000 that are not on the hub's residue 0"*) true ;; *) false ;; esac && ok_ "three such obs rows: refused, counted and named" || bad "3 accepted: $out"
out="$(seed_floor_residue_verdict orders 300000 1)"; [ $? = 1 ] && ok_ "one such orders row: refused" || bad "orders 1 accepted: $out"
out="$(seed_floor_residue_verdict obs 5000000 '')"; [ $? = 1 ] && case "$out" in *"could not count"*) true ;; *) false ;; esac && ok_ "a count that cannot be read: refused, never taken as zero" || bad "empty count: $out"
S="${HERE}/../tasks/060-striding.sh"
blk="$(sed -n '/# floor-residue:begin/,/# floor-residue:end/p' "$S")"
printf '%s' "$blk" | grep -q 'seed_floor_residue_verdict' && printf '%s' "$blk" | grep -q 'seed_floor_residue_sql "$t" "$fl" | mysql_root' && ok_ "task 60 reads the count from the restored database for each table" || bad "task 60 does not check the floor's residue"
awk '/# floor-residue:begin/ {b=NR} /ALTER TABLE openmrs/ && !a {a=NR} END {exit !(b && a && b < a)}' "$S" && ok_ "and checks before it moves any counter" || bad "the check comes after a counter is moved"
exit $((fails > 0))
