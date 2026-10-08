#!/usr/bin/env bash
# 00-preflight refusals against temp fixtures. PREFLIGHT_SKIP_HOST=1 skips the
# disk/RAM/port/git facts so the test is hermetic.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: output lacks %q\n' "$1" "$3"; fails=$((fails+1)); fi; }
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
T="${HERE}/../tasks/000-preflight.sh"
mkdir -p "$TMP/clinic"

printf 'rawach:4\nghated:3\n' > "$TMP/ledger"
base(){ env -i PATH="$PATH" HOME="$HOME" PREFLIGHT_SKIP_HOST=1 DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" LEDGER="$TMP/ledger" PLATFORM=linux RUNTIME=docker CLINIC_SLUG=azure RESIDUE=7 LOCAL_CLUSTER_ALIAS=azure OPENMRS_IMAGE_NAME=infoiplitin/openmrs:iplit-1.2.0-1200-03 "$@"; }

out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "no ledger row refused" "$rc" 1; assert_contains "prints the row to add" "$out" "azure:7"
printf 'rawach:4\nghated:3\nazure:7\n' > "$TMP/ledger"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "ledger row present passes" "$rc" 0

printf 'rawach:4\nghated:3\nazure:7\nother:7\n' > "$TMP/ledger"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "residue conflict refused" "$rc" 1; assert_contains "names the other slug" "$out" "other"
printf 'rawach:4\nghated:3\nazure:7\n' > "$TMP/ledger"

# id counters: checked on a machine in service, skipped (and said so) on one that is not
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "no install state: counters skipped, run passes" "$rc" 0; assert_contains "says the counters were not checked, and why" "$out" "id counters not checked: this machine is not seeded yet"
mkdir -p "$TMP/sync/local"
printf 'person:person_id:230000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$TMP/sync/local/tables.conf"
printf 'STATE=SEEDED\nFLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/clinic/.install-state"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007 orders=300017' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, counters at or above their floors: passes" "$rc" 0
assert_contains "names the obs counter it read" "$out" "obs next id 5000007, at or above floor 5000000 + residue 7"
assert_contains "names the orders counter it read" "$out" "orders next id 300017"
assert_contains "names the stride it read" "$out" "MySQL issues ids 10 apart on residue 7"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007 orders=299991' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, orders counter below its floor: refused" "$rc" 1
assert_contains "the refusal names the check in words" "$out" "the orders id counter is below this clinic's floor: the next orders id would be 299997, and clinic-written orders ids start at 300007"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007 orders=300017' PREFLIGHT_STRIDE='10 3' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, MySQL striding on another residue: refused" "$rc" 1
assert_contains "the refusal says new rows would land on another residue" "$out" "increment and offset 10 3, not 10 7"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, a counter that cannot be read: refused" "$rc" 1; assert_contains "not taken as zero" "$out" "could not read the orders id counter"
mv "$TMP/sync/local/tables.conf" "$TMP/sync/local/tables.conf.aside"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007 orders=300017' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, the table list cannot be read: refused" "$rc" 1; assert_contains "says no counter was checked" "$out" "the clinic table list cannot be read, so no id counter was checked"
mv "$TMP/sync/local/tables.conf.aside" "$TMP/sync/local/tables.conf"
printf 'STATE=SEEDING\nFLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/clinic/.install-state"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=1 orders=1' PREFLIGHT_STRIDE='1 1' bash "$T" 2>&1)"; rc=$?
assert_rc "part-way through its data load: counters skipped" "$rc" 0; assert_contains "says the striding step checks them" "$out" "id counters not checked: this machine is part-way through"
# obs and orders not in the list: their recorded floors are checked all the same
printf 'person:person_id:230000\n' > "$TMP/sync/local/tables.conf"
printf 'STATE=SEEDED\nFLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/clinic/.install-state"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=5000007 orders=300007' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, unlisted obs and orders at or above their floors: passes" "$rc" 0
assert_contains "names the unlisted obs counter it read" "$out" "obs next id 5000007, at or above floor 5000000 + residue 7"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=4999991 orders=300007' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded, unlisted obs counter below its floor: refused" "$rc" 1
assert_contains "the refusal names the unlisted counter" "$out" "the obs id counter is below this clinic's floor: the next obs id would be 4999997"
printf 'STATE=SEEDED\n' > "$TMP/clinic/.install-state"
out="$(base PREFLIGHT_AUTO_INCREMENT='obs=1 orders=1' PREFLIGHT_STRIDE='10 7' bash "$T" 2>&1)"; rc=$?
assert_rc "seeded with no floors recorded and none listed: passes" "$rc" 0
assert_contains "says no counter was checked" "$out" "no obs or orders floor is recorded"
printf 'person:person_id:230000\nobs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n' > "$TMP/sync/local/tables.conf"
rm -f "$TMP/clinic/.install-state"
grep -q '^# counters:begin' "$T" && [ "$(grep -n '^# counters:begin' "$T" | cut -d: -f1)" -lt "$(grep -n '^# fresh-only:begin' "$T" | cut -d: -f1)" ] \
  && printf '  ok   the counters are checked before the fresh-install check refuses a live node\n' || { printf '  FAIL the counter check is missing or comes after the fresh-install check\n'; fails=$((fails+1)); }

: > "$TMP/clinic/.env"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "existing .env refused" "$rc" 1; assert_contains "says fresh install only" "$out" "fresh"
grep -q 'for p in 80 443 ' "$T" && printf '  ok   ports 80 and 443 are checked\n' || { printf '  FAIL ports 80/443 not in the port check\n'; fails=$((fails+1)); }
grep -qE '8081|9443|9444' "$T" && { printf '  FAIL the old proxy ports are still checked\n'; fails=$((fails+1)); } || printf '  ok   no old proxy ports\n'
grep -q 'seed' "$T" && { printf '  FAIL preflight still mentions the seed\n'; fails=$((fails+1)); } || printf '  ok   preflight has no seed checks (the seed sitting has its own gate)\n'
exit "$fails"
