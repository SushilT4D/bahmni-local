#!/usr/bin/env bash
# Renders the cloud server's Odoo and OpenELIS sources from scripts/templates/<name>.json.template
# into ./connectors/<name>.json, filling passwords and [down] table lists from ./.env,
# and registers each with Kafka Connect.
# Usage: scripts/register-odoo.sh [odoo-cloud-source] [clinlims-cloud-source]   (default: both)
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$ROOT/scripts/templates"
OUT="${OUT_DIR:-$PWD/connectors}"

set -a
. "${ENV_FILE:-$PWD/.env}"
set +a

[ "$#" -gt 0 ] || set -- odoo-cloud-source clinlims-cloud-source

# the configs hold database passwords: written mode 600
umask 077
mkdir -p "$OUT"


# ---- the [down] table list of one database, in the three forms the templates use ----

down_vars() { # SUBSYSTEM PG_SCHEMA : exports HUB_DOWN_<SUB>_TABLES, _TABLE_INCLUDE_LIST, _ALTERNATION
  local sub="$1" schema="$2" up down
  up="$(printf '%s' "$sub" | tr '[:lower:]' '[:upper:]')"
  down="$(bash "$ROOT/../sync/tables/tables.sh" "$sub" down)" \
    || { echo "  the down list could not be read (reason above); nothing was registered" >&2; exit 1; }
  down="$(printf '%s\n' "$down" | cut -d: -f1)"
  export "HUB_DOWN_${up}_TABLES=$(printf '%s\n' "$down" | paste -sd, -)"
  export "HUB_DOWN_${up}_TABLE_INCLUDE_LIST=$(printf '%s\n' "$down" | sed "s/^/${schema}./" | paste -sd, -)"
  export "HUB_DOWN_${up}_ALTERNATION=$(printf '%s\n' "$down" | paste -sd'|' -)"
}

down_vars odoo public
down_vars clinlims clinlims


# ---- render each config into ./connectors/, then PUT it ----------------------------

mask() { sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*(")/\1***\4/g'; }

for name in "$@"; do
  tpl="$TEMPLATES/${name}.json.template"
  [ -f "$tpl" ] || { echo "  no such template: $tpl" >&2; exit 1; }

  body=$(python3 "$ROOT/scripts/_render_connector.py" "$tpl") \
    || { printf '%s\n' "$body" | mask >&2; exit 1; }
  printf '{"name": "%s", "config": %s}\n' "$name" "$body" > "$OUT/${name}.json"

  resp=$(printf '%s' "$body" | curl -s -w '\n%{http_code}' \
         -X PUT -H 'Content-Type: application/json' \
         --data-binary @- "$CONNECT_URL/connectors/${name}/config")
  code="${resp##*$'\n'}"
  echo "  ${name}: HTTP ${code} (rendered to connectors/${name}.json)"
  [ "$code" -lt 300 ] || printf '%s\n' "${resp%$'\n'*}" | mask | sed 's/^/    /'
done
