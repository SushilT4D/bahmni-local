#!/usr/bin/env bash
# Validates every connector config against a LIVE Connect (a config that
# was never submitted to the plugin is a guess). Usage: validate-connectors.sh http://localhost:8083
set -euo pipefail
URL="${1:?connect url}"; REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fails=0
render(){ sed -E 's/\$\{[A-Z_]+\}/placeholder/g; s/\$\{[A-Z_]+:-[^}]*\}/placeholder/g' "$1"; }
for f in "$REPO"/clinic/connectors/*.json "$REPO"/hub/connectors/*.json "$REPO"/hub/connectors/*.template; do
  [ -f "$f" ] || continue
  cls="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("config") or d)["connector.class"])' < <(render "$f") 2>/dev/null || true)"
  [ -n "$cls" ] || { printf '  skip %s (no connector.class)\n' "${f#$REPO/}"; continue; }
  body="$(python3 -c 'import json,sys; d=json.load(sys.stdin); c=d.get("config") or d; c.setdefault("name", d.get("name","probe")); print(json.dumps(c))' < <(render "$f"))"
  n="$(curl -s -X PUT -H 'Content-Type: application/json' "$URL/connector-plugins/${cls}/config/validate" -d "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); errs=[(c["value"]["name"],c["value"]["errors"]) for c in d.get("configs",[]) if c["value"]["errors"]]; print(d.get("error_count","?")); [print("      ",n,e) for n,e in errs]')"
  if [ "${n%%$'\n'*}" = 0 ]; then printf '  ok   %s\n' "${f#$REPO/}"; else printf '  FAIL %s error_count=%s\n' "${f#$REPO/}" "$n"; fails=$((fails+1)); fi
done
printf '%s failure(s)\n' "$fails"; exit $((fails>0))
