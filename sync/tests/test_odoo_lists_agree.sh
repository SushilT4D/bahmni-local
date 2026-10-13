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

# The clinic sends every synced Odoo table up.
f="$REPO/clinic/connectors/odoo-source-connector.json"; label="$(basename "$f")"
got="$(include_set "$f")"
[ "$got" = "$want" ] && ok "$label table.include.list == subsystems.conf odoo: rows" || bad "$label table.include.list: [$got] != [$want]"
got="$(regex_set "$f")"
[ "$got" = "$want" ] && ok "$label transforms.agg.regex == subsystems.conf odoo: rows" || bad "$label transforms.agg.regex: [$got] != [$want]"

# The hub sends down only the down list, rendered into its source at registration
# (register-odoo.sh); the rendered config is compared, not the template.
down="$(bash "$REPO/sync/hub-down.sh" odoo | sort | tr '\n' ' ' | sed 's/ $//')"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hub/connectors" "$T/sync" "$T/bin"
cp "$REPO/hub/connectors/odoo-cloud-source.json" "$REPO/hub/connectors/register-odoo.sh" "$REPO/hub/connectors/_render_connector.py" "$T/hub/connectors/"
cp "$REPO/sync/hub-down.sh" "$REPO/sync/hub-down.conf" "$REPO/sync/subsystems.conf" "$T/sync/"
printf 'ODOO_DB_PASSWORD=x\nREMOTE_SERVER_NAME=bahmni-cloud\n' > "$T/hub/.env"
printf '#!/bin/sh\ncat > "%s/body"; printf "\\n201"\n' "$T" > "$T/bin/curl"; chmod +x "$T/bin/curl"
PATH="$T/bin:$PATH" NODE=cloud bash "$T/hub/connectors/register-odoo.sh" odoo-cloud-source >/dev/null 2>&1
printf '{"config":%s}' "$(cat "$T/body" 2>/dev/null)" > "$T/rendered.json"
got="$(include_set "$T/rendered.json")"
[ "$got" = "$down" ] && ok "rendered odoo-cloud-source table.include.list == sync/hub-down.conf" || bad "rendered odoo-cloud-source table.include.list: [$got] != [$down]"
got="$(regex_set "$T/rendered.json")"
[ "$got" = "$down" ] && ok "rendered odoo-cloud-source transforms.agg.regex == sync/hub-down.conf" || bad "rendered odoo-cloud-source transforms.agg.regex: [$got] != [$down]"

printf '%s failure(s)\n' "$fails"; exit $((fails>0))
