#!/usr/bin/env bash
# F-043: heartbeat table + publication membership in both PG databases, then heartbeat settings
# on both PG source connectors of this node. Usage: scripts/apply-slot-heartbeat.sh <docker|podman> <pg-container> <pg-superuser> <odoo-source-name> <clinlims-source-name> [connect-url]
set -euo pipefail
T=$1; PG=$2; SU=$3; OSRC=$4; CSRC=$5; C=${6:-http://localhost:8083}
here=$(cd "$(dirname "$0")/.." && pwd)
$T cp "$here/odoo/apply-slot-heartbeat.sql" "$PG:/tmp/hb.sql"
$T exec "$PG" psql -U "$SU" -d odoo     -v ON_ERROR_STOP=1 -v s=public   -v r=odoo     -v p=dbz_odoo_owned     -f /tmp/hb.sql | grep 'carries'
$T exec "$PG" psql -U "$SU" -d openelis -v ON_ERROR_STOP=1 -v s=clinlims -v r=clinlims -v p=dbz_clinlims_owned -f /tmp/hb.sql | grep 'carries'
patch() { # name schema
  curl -s "$C/connectors/$1/config" | python3 -c "
import json,sys; c=json.load(sys.stdin); s=sys.argv[1]
t=c['table.include.list'].split(','); [t.append(f'{s}.dbz_heartbeat') for _ in [0] if f'{s}.dbz_heartbeat' not in t]; c['table.include.list']=','.join(t)
c['heartbeat.interval.ms']='60000'; c['heartbeat.action.query']=f'INSERT INTO {s}.dbz_heartbeat (id, ts) VALUES (1, now()) ON CONFLICT (id) DO UPDATE SET ts = EXCLUDED.ts'
print(json.dumps(c))" "$2" > /tmp/src-hb.json
  curl -s -o /dev/null -w "$1: %{http_code}\n" -X PUT -H 'Content-Type: application/json' --data @/tmp/src-hb.json "$C/connectors/$1/config"
}
patch "$OSRC" public; patch "$CSRC" clinlims
sleep 30; for n in "$OSRC" "$CSRC"; do curl -s "$C/connectors/$n/status" | python3 -c "import json,sys; d=json.load(sys.stdin); print(sys.argv[1], d['connector']['state'], [t['state'] for t in d['tasks']])" "$n"; done
