#!/usr/bin/env bash
# Unsynced-table check (ADR-005, F-085): clinic/scripts/preflight.sh's WARN
# section for tables outside the synced set that touch it by FK and have
# rows. Exercises the SQL-building and allowlist/subsystems parsing without a
# database -- pulled out via the unsynced-check:begin/:end markers, the same
# technique test_boot_budget.sh uses for the cpu-budget block. Does not try to
# run psql.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
PF="${HERE}/../../scripts/preflight.sh"

blk="$(sed -n '/# unsynced-check:begin/,/# unsynced-check:end/p' "$PF")"
[ -n "$blk" ] || bad "preflight.sh has no unsynced-check:begin/:end block"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
run(){ bash -c "${blk}
$1"; } # runs one command against the extracted function defs, nothing else

# --- subsystems_conf_tables --------------------------------------------------
cat > "$TMP/subsystems.conf" <<'CONF'
clinlims:all
odoo:all

clinlims:sample
clinlims:sample_item

odoo:res_partner
odoo:village_village   # trailing comment
CONF
out="$(run "subsystems_conf_tables odoo '$TMP/subsystems.conf'")"
[ "$out" = "$(printf 'res_partner\nvillage_village')" ] \
  && ok_ "subsystems_conf_tables odoo: rows, :all/comment/blank handled" \
  || bad "subsystems_conf_tables odoo: got [$out]"
out="$(run "subsystems_conf_tables clinlims '$TMP/subsystems.conf'")"
[ "$out" = "$(printf 'sample\nsample_item')" ] \
  && ok_ "subsystems_conf_tables clinlims: rows" \
  || bad "subsystems_conf_tables clinlims: got [$out]"
out="$(run "subsystems_conf_tables odoo '$TMP/no-such-file.conf'")"
[ -z "$out" ] && ok_ "subsystems_conf_tables: missing conf file returns nothing, does not error" || bad "subsystems_conf_tables: missing conf file gave [$out]"

# --- unsynced_check_sql -------------------------------------------------------
sql="$(run "unsynced_check_sql public res_partner village_village")"
printf '%s' "$sql" | grep -q "FK->synced" && printf '%s' "$sql" | grep -q "synced->FK" \
  && ok_ "unsynced_check_sql mentions both FK directions" \
  || bad "unsynced_check_sql missing a direction: $sql"
printf '%s' "$sql" | grep -q "n_live_tup" && ok_ "unsynced_check_sql mentions n_live_tup" || bad "unsynced_check_sql missing n_live_tup"
printf '%s' "$sql" | grep -q "'res_partner'" && printf '%s' "$sql" | grep -q "'village_village'" \
  && ok_ "unsynced_check_sql names the synced tables" \
  || bad "unsynced_check_sql missing table names: $sql"

# --- filter_unsynced_allowlist -----------------------------------------------
cat > "$TMP/allow.conf" <<'ALLOW'
odoo:res_country  # static: reference list
openelis:test  # master: lab catalogue
ALLOW
cat > "$TMP/lines.txt" <<'EOF'
res_country|synced->FK|250
mystery_table|FK->synced|12
test|synced->FK|635
EOF
out="$(run "cat '$TMP/lines.txt' | filter_unsynced_allowlist odoo '$TMP/allow.conf'")"
printf '%s\n' "$out" | grep -q '^res_country|' && bad "filter_unsynced_allowlist: allowlisted odoo:res_country was NOT filtered out"
printf '%s\n' "$out" | grep -q '^mystery_table|' && ok_ "filter_unsynced_allowlist: kept a table with no allowlist entry" || bad "filter_unsynced_allowlist: dropped mystery_table (should have kept it)"
printf '%s\n' "$out" | grep -q '^test|' && ok_ "filter_unsynced_allowlist: db-scoped -- openelis:test does not suppress odoo's own 'test' row" || bad "filter_unsynced_allowlist: dropped 'test' under db=odoo though only openelis:test is allowlisted"

out="$(run "cat '$TMP/lines.txt' | filter_unsynced_allowlist openelis '$TMP/allow.conf'")"
printf '%s\n' "$out" | grep -q '^test|' && bad "filter_unsynced_allowlist: openelis:test should have been filtered out under db=openelis"
printf '%s\n' "$out" | grep -q '^mystery_table|' && ok_ "filter_unsynced_allowlist: kept mystery_table under db=openelis too" || bad "filter_unsynced_allowlist: dropped mystery_table under db=openelis"

out="$(run "cat '$TMP/lines.txt' | filter_unsynced_allowlist odoo '$TMP/no-such-allow.conf'")"
n="$(printf '%s\n' "$out" | grep -c '.')"
[ "$n" -eq 3 ] && ok_ "filter_unsynced_allowlist: missing allowlist file allowlists nothing (keeps all 3)" || bad "filter_unsynced_allowlist: missing allowlist file changed the count ($n)"

# the compose project runs from <repo>/clinic; the repo root, where sync/ lives, is its parent
blk="$(sed -n '/^# The compose project lives in <repo>\/clinic/,/^if \[ -n "\$REPO" \].*then REPO=.*fi$/p' "$PF")"
[ -n "$blk" ] || bad "preflight has no compose-dir -> repo-root step"
R="$TMP/repo"; mkdir -p "$R/clinic" "$R/sync"
out="$(REPO="$R/clinic" bash -c "$blk; printf '%s' \"\$REPO\"")"
[ "$out" = "$R" ] && ok_ "REPO climbs from clinic/ to the repo root" || bad "REPO stayed at [$out]"
out="$(REPO="$R" bash -c "$blk; printf '%s' \"\$REPO\"")"
[ "$out" = "$R" ] && ok_ "a repo root is left alone" || bad "repo root became [$out]"

printf '%s failure(s)\n' "$fails"; exit $((fails>0))
