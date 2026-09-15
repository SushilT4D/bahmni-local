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
mkdir -p "$TMP/clinic" "$TMP/seed"
for f in openmrs odoo openelis; do printf 'x' | gzip > "$TMP/seed/$f.sql.gz"; done
printf 'rawach:4\nghated:3\n' > "$TMP/ledger"
base(){ env -i PATH="$PATH" HOME="$HOME" PREFLIGHT_SKIP_HOST=1 DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" LEDGER="$TMP/ledger" SEED_DIR="$TMP/seed" PLATFORM=linux RUNTIME=docker CLINIC_SLUG=azure RESIDUE=7 LOCAL_CLUSTER_ALIAS=azure "$@"; }

out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "no ledger row refused" "$rc" 1; assert_contains "prints the row to add" "$out" "azure:7"
printf 'rawach:4\nghated:3\nazure:7\n' > "$TMP/ledger"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "ledger row present passes" "$rc" 0
printf 'rawach:4\nghated:3\nazure:7\nother:7\n' > "$TMP/ledger"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "residue conflict refused" "$rc" 1; assert_contains "names the other slug" "$out" "other"
printf 'rawach:4\nghated:3\nazure:7\n' > "$TMP/ledger"
rm "$TMP/seed/odoo.sql.gz"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "missing seed refused" "$rc" 1; assert_contains "names the file" "$out" "odoo.sql.gz"
printf 'x' > "$TMP/seed/odoo.sql.gz"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "corrupt gzip refused" "$rc" 1
printf 'x' | gzip > "$TMP/seed/odoo.sql.gz"
: > "$TMP/clinic/.env"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "existing .env refused" "$rc" 1; assert_contains "says fresh install only" "$out" "fresh"
exit "$fails"
