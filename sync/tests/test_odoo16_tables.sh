#!/usr/bin/env bash
set -u; REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
want="account_move account_move_line product_category product_product product_template res_country_state res_partner sale_order sale_order_line stock_move stock_picking stock_quant uom_uom"
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
# The override's odoo: block is gone (image/HOST/volumes/depends_on all come from the
# base compose now) EXCEPT one line: `platform: linux/amd64`. The probe (this Mac,
# arm64) proved that line is still load-bearing -- `docker manifest inspect
# bahmni/odoo-16:1.0.0` carries no arm64 manifest, so a pull with no pin fails
# outright ("no matching manifest for linux/arm64/v8"), same disease the odoo-10
# image had. So: no odoo-10 image/HOST override, but the platform pin stays.
odoo_block="$(awk '/^  odoo:$/{flag=1;next}/^  [a-zA-Z_-]+:$/{flag=0}flag' "$REPO/clinic/docker-compose.override.yml")"
echo "$odoo_block" | grep -qE 'image:|HOST:|volumes:|depends_on:' && bad "override's odoo: block still carries image/HOST/volumes/depends_on (should be platform-only)" || ok "override's odoo: block is platform-only -- image/HOST/volumes/depends_on come from the base compose"
echo "$odoo_block" | grep -q 'platform: linux/amd64' && ok "odoo: platform: linux/amd64 kept (bahmni/odoo-16:1.0.0 has no arm64 manifest -- proven by the probe)" || bad "override's odoo: block is missing platform: linux/amd64"

# The removal comment is allowed to NAME the retired flag for context (it explains
# why 1.2.0 no longer needs it) -- what must actually be gone is the flag itself,
# functionally, off the OMRS_JAVA_SERVER_OPTS value the container reads.
grep -E '^OMRS_JAVA_SERVER_OPTS=' "$REPO/clinic/.env.example" | grep -q 'UseContainerSupport' \
  && bad "OMRS_JAVA_SERVER_OPTS still carries -XX:-UseContainerSupport" \
  || ok "container-support flag dropped from OMRS_JAVA_SERVER_OPTS"
printf '%s failure(s)\n' "$fails"; exit $((fails>0))
