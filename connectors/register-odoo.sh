#!/usr/bin/env bash
# ADDED 2026-09-04. Registers the Odoo CDC connectors, substituting credentials from
# .env at registration time so no committed file holds a literal secret. The four
# clinlims connector JSONs predate this and DO carry literals -- see the note in
# f74613f; do not copy their pattern.
set -euo pipefail
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; . "$ROOT/.env"; set +a

for name in "$@"; do
  f="$ROOT/connectors/${name}.json"
  [ -f "$f" ] || { echo "  no such config: $f" >&2; exit 1; }
  body=$(ODOO_DB_PASSWORD="${ODOO_DB_PASSWORD:-}" ODOO_SINK_PASSWORD="${ODOO_SINK_PASSWORD:-}" \
         python3 -c "
import json,os,sys,re
d=json.load(open(sys.argv[1]))
def sub(v):
    return re.sub(r'\\\$\{(\w+)\}', lambda m: os.environ.get(m.group(1),''), v) if isinstance(v,str) else v
cfg={k:sub(v) for k,v in d['config'].items()}
missing=[k for k,v in cfg.items() if 'password' in k.lower() and not v]
if missing: sys.exit('  unset env for: '+','.join(missing))
# PUT /connectors/<name>/config takes the CONFIG OBJECT ITSELF, not the
# {name, config} envelope that POST /connectors takes.
print(json.dumps(cfg))
" "$f")
  code=$(printf '%s' "$body" | curl -s -o /tmp/.reg.out -w '%{http_code}' \
         -X PUT -H 'Content-Type: application/json' \
         --data-binary @- "$CONNECT_URL/connectors/${name}/config")
  echo "  ${name}: HTTP ${code}"
  [ "$code" -lt 300 ] || sed 's/^/    /' /tmp/.reg.out
done
rm -f /tmp/.reg.out
