#!/usr/bin/env bash
# The clinic's OpenELIS source is a hand-written config with its own
# table.include.list and transforms.agg.regex, beside sync/subsystems.conf's
# clinlims: rows, which the clinic's publication, MirrorMaker's topics and the
# hub's grant read-back are built from. A table added to one and not the other
# is published with no topic, or given a topic nothing writes. This checks:
#   - subsystems.conf's clinlims: rows (the aggregate aside) equal, as a set,
#     the source's include list (dbz_heartbeat and the schema prefix aside) and
#     the alternation of its aggregate regex;
#   - the lab signature and the lab account are among them, the account listed
#     before the signature that names it;
#   - neither is still given an unsynced verdict in sync/unsynced-allowlist.conf
#     (a table is either synced or has a verdict, never both).
set -u; REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

rows(){ sed 's/#.*//' "$REPO/sync/subsystems.conf" | tr -d ' \t' | grep -E '^clinlims:' | grep -v ':all$' | cut -d: -f2; }
want="$(rows | sort | tr '\n' ' ' | sed 's/ $//')"
[ -n "$want" ] || bad "sync/subsystems.conf has no clinlims: rows"

f="$REPO/clinic/connectors/clinlims-source-connector.json"
inc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$f" \
  | tr ',' '\n' | sed 's/^clinlims\.//' | grep -v '^dbz_heartbeat$' | sort | tr '\n' ' ' | sed 's/ $//')"
[ "$inc" = "$want" ] && ok "clinlims-source-connector table.include.list == subsystems.conf clinlims: rows" || bad "clinlims-source-connector table.include.list: [$inc] != [$want]"
agg="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["transforms.agg.regex"])' "$f" \
  | sed -E 's/^.*\(([^)]*)\)\$?$/\1/' | tr '|' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
[ "$agg" = "$want" ] && ok "clinlims-source-connector transforms.agg.regex == subsystems.conf clinlims: rows" || bad "clinlims-source-connector transforms.agg.regex: [$agg] != [$want]"

nu="$(rows | grep -nx system_user | cut -d: -f1)"; ns="$(rows | grep -nx result_signature | cut -d: -f1)"
[ -n "$nu" ] && [ -n "$ns" ] && [ "$nu" -lt "$ns" ] && ok "system_user and result_signature go up, the account listed before the signature" \
  || bad "system_user at row '${nu:-absent}', result_signature at row '${ns:-absent}' (both wanted, system_user first)"

for t in $(rows); do
  grep -qE "^openelis:${t}[[:space:]]" "$REPO/sync/unsynced-allowlist.conf" && bad "openelis:${t} is synced and still has an unsynced verdict in sync/unsynced-allowlist.conf"
done
grep -qE '^openelis:(system_user|result_signature)[[:space:]]' "$REPO/sync/unsynced-allowlist.conf" || ok "sync/unsynced-allowlist.conf gives neither system_user nor result_signature an unsynced verdict"
exit $((fails > 0))
