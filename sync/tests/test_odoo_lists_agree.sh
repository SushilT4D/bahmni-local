#!/usr/bin/env bash
# the two hand-written Odoo connector configs (clinic and hub) each
# carry their OWN table.include.list and transforms.agg.regex, independent of
# sync/subsystems.conf and of each other -- FOUR copies of "which Odoo tables
# are synced" that a table can be added to some of and not others. That is
# exactly the near-miss res_country_state's own header warns about
# (subsystems.conf existed only after a regenerate silently dropped two whole
# subsystems from replication). This test is the tripwire: subsystems.conf's
# odoo: rows must equal, as a SET, both files' table.include.list (minus
# dbz_heartbeat, minus the public. prefix) and both files' transforms.agg.regex
# alternation.
set -u; REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

conf_set(){ grep -E '^odoo:' "$REPO/sync/subsystems.conf" | grep -v ':all$' | cut -d: -f2 | sort | tr '\n' ' ' | sed 's/ $//'; }

include_set(){ # FILE
  jq -r '.config."table.include.list"' "$1" \
    | tr ',' '\n' | sed -e 's/^public\.//' | grep -v '^dbz_heartbeat$' \
    | sort | tr '\n' ' ' | sed 's/ $//'
}
regex_set(){ # FILE : the alternation inside \.odoo\.( ... )$ -- there is only
  # one "(" in this regex, so a greedy .*\( always lands on it.
  jq -r '.config."transforms.agg.regex"' "$1" \
    | sed -E 's/^.*\(([^)]*)\)\$?$/\1/' \
    | tr '|' '\n' | sort | tr '\n' ' ' | sed 's/ $//'
}

want="$(conf_set)"
[ -n "$want" ] || bad "sync/subsystems.conf has no odoo: rows"

for f in "$REPO/clinic/connectors/odoo-source-connector.json" "$REPO/hub/connectors/odoo-cloud-source.json"; do
  label="$(basename "$f")"
  got="$(include_set "$f")"
  [ "$got" = "$want" ] && ok "$label table.include.list == subsystems.conf odoo: rows" || bad "$label table.include.list: [$got] != [$want]"
  got="$(regex_set "$f")"
  [ "$got" = "$want" ] && ok "$label transforms.agg.regex == subsystems.conf odoo: rows" || bad "$label transforms.agg.regex: [$got] != [$want]"
done

printf '%s failure(s)\n' "$fails"; exit $((fails>0))
