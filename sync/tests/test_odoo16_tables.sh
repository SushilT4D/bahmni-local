#!/usr/bin/env bash
set -u; REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
want="account_move account_move_line product_category product_product product_template res_partner sale_order sale_order_line stock_move stock_picking stock_quant uom_uom"
have="$(grep -E '^odoo:' "$REPO/sync/subsystems.conf" | grep -v ':all$' | cut -d: -f2 | sort | tr '\n' ' ' | sed 's/ $//')"
[ "$have" = "$want" ] && ok "subsystems.conf carries the Odoo 16 set" || bad "subsystems.conf odoo set is: $have"

# Ruling 2: the striding SQL no longer hard-codes any table name -- it takes the
# list from the caller (task 060, which reads subsystems.conf) via a psql
# variable, split with string_to_array. So instead of asserting each table
# NAME is present in the SQL, assert none of them are (the array literal is
# gone) and that the split mechanism is there.
STRIDE="$REPO/clinic/odoo/apply-odoo-sequence-striding.sql"
hit=""
for t in $want; do grep -qE "'${t}'" "$STRIDE" && hit="$hit $t"; done
[ -z "$hit" ] && ok "striding SQL no longer hard-codes table names" || bad "striding SQL still names:$hit"
grep -qE "string_to_array\(current_setting\('myvars.tables'\)" "$STRIDE" && ok "striding SQL splits the passed-in table list via string_to_array" || bad "striding SQL missing string_to_array(current_setting('myvars.tables'), ...)"

# Files marked HISTORICAL, FROZEN are completed one-time migrations that ran
# against the real Odoo 10 schema and are excluded on purpose (renaming their
# literal table names would misrepresent what actually executed -- see each
# file's own header). This test script's OWN source line below also contains
# the literal strings it searches for, so it excludes itself too.
old_name_files="$(grep -rlE "account_invoice|product_uom\b" "$REPO/sync" "$REPO/clinic/odoo" "$REPO/clinic/scripts" "$REPO/clinic/install" "$REPO/clinic/connectors" "$REPO/hub/connectors" "$REPO/hub/scripts" "$REPO/hub/odoo" 2>/dev/null || true)"
hits=""
for f in $old_name_files; do
  case "$f" in */test_odoo16_tables.sh) continue ;; esac
  grep -q 'HISTORICAL, FROZEN' "$f" && continue
  hits="$hits $f"
done
[ -z "$hits" ] && ok "no Odoo 10 table names left (outside HISTORICAL, FROZEN migrations)" || bad "Odoo 10 names remain:$hits"

grep -qE '^\s+odoodb:' "$REPO/clinic/docker-compose.override.yml" && bad "odoodb service still defined" || ok "no private odoodb"
grep -q 'bahmni/odoo-10' "$REPO/clinic/docker-compose.override.yml" && bad "override still pins bahmni/odoo-10" || ok "no bahmni/odoo-10 in override"
grep -qE '^\s+odoo:\s*$' "$REPO/clinic/docker-compose.override.yml" && bad "override still defines its own odoo: service (odoo-10 image/platform pin likely follows)" || ok "no odoo: override block -- base odoo-16 service runs unmodified"

# The removal comment is allowed to NAME the retired flag for context (it explains
# why 1.2.0 no longer needs it) -- what must actually be gone is the flag itself,
# functionally, off the OMRS_JAVA_SERVER_OPTS value the container reads.
grep -E '^OMRS_JAVA_SERVER_OPTS=' "$REPO/clinic/.env.example" | grep -q 'UseContainerSupport' \
  && bad "OMRS_JAVA_SERVER_OPTS still carries -XX:-UseContainerSupport" \
  || ok "container-support flag dropped from OMRS_JAVA_SERVER_OPTS"
printf '%s failure(s)\n' "$fails"; exit $((fails>0))
