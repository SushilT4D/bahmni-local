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
# the base fixture is 1.2.0/Odoo-16 shaped so it clears the seed-shape gate too;
# openelis carries no gate and stays a generic gzip.
printf "INSERT INTO liquibasechangelog VALUES ('20251223-drop-default-value-from-column','iplit');\n" | gzip > "$TMP/seed/openmrs.sql.gz"
printf 'CREATE TABLE uom_uom (x int);\n' | gzip > "$TMP/seed/odoo.sql.gz"
printf 'x' | gzip > "$TMP/seed/openelis.sql.gz"
printf 'rawach:4\nghated:3\n' > "$TMP/ledger"
# OPENMRS_IMAGE_NAME is set here the same way install.sh sets it (sourcing
# sync/versions.env) -- the seed-shape gate reads it to name the pinned image
# in its refusal text.
base(){ env -i PATH="$PATH" HOME="$HOME" PREFLIGHT_SKIP_HOST=1 DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/clinic" REPO_DIR="$TMP" LEDGER="$TMP/ledger" SEED_DIR="${SEED_DIR_OVERRIDE:-$TMP/seed}" PLATFORM=linux RUNTIME=docker CLINIC_SLUG=azure RESIDUE=7 LOCAL_CLUSTER_ALIAS=azure OPENMRS_IMAGE_NAME=infoiplitin/openmrs:iplit-1.2.0-1200-03 "$@"; }

out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "no ledger row refused" "$rc" 1; assert_contains "prints the row to add" "$out" "azure:7"
printf 'rawach:4\nghated:3\nazure:7\n' > "$TMP/ledger"
out="$(base bash "$T" 2>&1)"; rc=$?
assert_rc "ledger row present passes" "$rc" 0

# L-005 seed-shape gate: a 662-4 / Odoo 10 seed is refused (old openmrs, old odoo)
mkdir -p "$TMP/seed-old"
printf 'CREATE TABLE person (x int);\n' | gzip > "$TMP/seed-old/openmrs.sql.gz"
printf 'CREATE TABLE product_uom (x int);\n' | gzip > "$TMP/seed-old/odoo.sql.gz"
printf 'x\n' | gzip > "$TMP/seed-old/openelis.sql.gz"
out="$(SEED_DIR_OVERRIDE="$TMP/seed-old" base bash "$T" 2>&1)"; rc=$?
assert_rc "old openmrs dump refused (rc)" "$rc" 1
assert_contains "old openmrs dump refused" "$out" "seed openmrs.sql.gz is not an iplit-1.2.0 dump (changeset 20251223-drop-default-value-from-column absent)"

# openmrs is 1.2.0 but odoo is still Odoo 10 -- refused for the odoo reason specifically
mkdir -p "$TMP/seed-mixed"
printf "INSERT INTO liquibasechangelog VALUES ('20251223-drop-default-value-from-column','iplit');\n" | gzip > "$TMP/seed-mixed/openmrs.sql.gz"
printf 'CREATE TABLE product_uom (x int);\n' | gzip > "$TMP/seed-mixed/odoo.sql.gz"
printf 'x\n' | gzip > "$TMP/seed-mixed/openelis.sql.gz"
out="$(SEED_DIR_OVERRIDE="$TMP/seed-mixed" base bash "$T" 2>&1)"; rc=$?
assert_rc "old odoo dump refused (rc)" "$rc" 1
assert_contains "old odoo dump refused" "$out" "seed odoo.sql.gz is not an Odoo 16 dump (no uom_uom)"

# a 1.2.0 / Odoo 16 seed passes the gate
mkdir -p "$TMP/seed-new"
printf "INSERT INTO liquibasechangelog VALUES ('20251223-drop-default-value-from-column','iplit');\n" | gzip > "$TMP/seed-new/openmrs.sql.gz"
printf 'CREATE TABLE uom_uom (x int);\n' | gzip > "$TMP/seed-new/odoo.sql.gz"
printf 'x\n' | gzip > "$TMP/seed-new/openelis.sql.gz"
out="$(SEED_DIR_OVERRIDE="$TMP/seed-new" base bash "$T" 2>&1)"; rc=$?
assert_rc "new seed passes the version gate (rc)" "$rc" 0
assert_contains "new seed passes the version gate" "$out" "seed shape: openmrs iplit-1.2.0, odoo 16"

# pipefail proof: the changeset line is the FIRST line of a large multi-line dump, so
# grep -m1 matches and closes its read end before gzip finishes writing -- gzip is
# killed by SIGPIPE (exit 141) while still mid-write. Under `set -o pipefail` that
# would poison a bare `gzip -dc f | grep -qm1 pat` pipeline's status to 141 even
# though grep found its match; the gate wraps gzip in `{ ... || true; }` precisely so
# this large-dump case still passes.
mkdir -p "$TMP/seed-big"
{ printf "INSERT INTO liquibasechangelog VALUES ('20251223-drop-default-value-from-column','iplit');\n"; seq 1 50000 | awk '{print "INSERT INTO filler VALUES (" $1 ");"}'; } | gzip > "$TMP/seed-big/openmrs.sql.gz"
printf 'CREATE TABLE uom_uom (x int);\n' | gzip > "$TMP/seed-big/odoo.sql.gz"
printf 'x\n' | gzip > "$TMP/seed-big/openelis.sql.gz"
out="$(SEED_DIR_OVERRIDE="$TMP/seed-big" base bash "$T" 2>&1)"; rc=$?
assert_rc "large multi-line seed passes despite early pipe close (rc)" "$rc" 0
assert_contains "large multi-line seed passes despite early pipe close" "$out" "seed shape: openmrs iplit-1.2.0, odoo 16"

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
