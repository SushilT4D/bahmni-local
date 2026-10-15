#!/usr/bin/env bash
# Registers the hub's Postgres CDC connectors (the Odoo and OpenELIS down
# sources and the per-clinic Odoo and OpenELIS up-sinks), substituting credentials from
# .env at registration time so no committed file holds a literal secret. The four
# clinlims connector JSONs predate this and DO carry literals -- see the note in
# f74613f; do not copy their pattern.
set -euo pipefail
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; . "$ROOT/.env"; set +a

# The hub's down sources take their table lists and aggregate regexes from the
# down list (sync/hub-down.conf): HUB_DOWN_ODOO_* for the Odoo source (schema
# public), HUB_DOWN_CLINLIMS_* for the OpenELIS source (schema clinlims). Read
# before anything is registered, and only when a template asks for that
# subsystem; a list it refuses stops every registration.
down_vars(){ # SUBSYSTEM PG_SCHEMA : exports HUB_DOWN_<SUB>_TABLES, _TABLE_INCLUDE_LIST, _ALTERNATION
  local sub="$1" schema="$2" up down
  up="$(printf '%s' "$sub" | tr '[:lower:]' '[:upper:]')"
  down="$(bash "$ROOT/../sync/hub-down.sh" "$sub")" || { echo "  the down list could not be read (reason above); nothing was registered" >&2; exit 1; }
  export "HUB_DOWN_${up}_TABLES=$(printf '%s\n' "$down" | paste -sd, -)"
  export "HUB_DOWN_${up}_TABLE_INCLUDE_LIST=$(printf '%s\n' "$down" | sed "s/^/${schema}./" | paste -sd, -)"
  export "HUB_DOWN_${up}_ALTERNATION=$(printf '%s\n' "$down" | paste -sd'|' -)"
}
want_odoo=0; want_clinlims=0
for name in "$@"; do
  grep -q '${HUB_DOWN_ODOO_' "$ROOT/connectors/${name}.json" 2>/dev/null && want_odoo=1
  grep -q '${HUB_DOWN_CLINLIMS_' "$ROOT/connectors/${name}.json" 2>/dev/null && want_clinlims=1
done
[ "$want_odoo" = 0 ] || down_vars odoo public
[ "$want_clinlims" = 0 ] || down_vars clinlims clinlims

for name in "$@"; do
  f="$ROOT/connectors/${name}.json"
  [ -f "$f" ] || { echo "  no such config: $f" >&2; exit 1; }
  body=$(ODOO_DB_PASSWORD="${ODOO_DB_PASSWORD:-}" ODOO_SINK_PASSWORD="${ODOO_SINK_PASSWORD:-}" CLINLIMS_SOURCE_PASSWORD="${CLINLIMS_SOURCE_PASSWORD:-}" NODE="${NODE:?set NODE=rawach|ghated|cloud}" TOPIC_PREFIX="${TOPIC_PREFIX:-bahmni-local}" \
         python3 "$ROOT/connectors/_render_connector.py" "$f") || {
    # _render_connector.py substitutes
    # every value (passwords included) into cfg BEFORE its own unresolved-
    # placeholder check, so on some future failure path $body could carry
    # the rendered config, passwords and all -- masked with the same
    # JSON-escape-aware pattern used below, on the chance it ever does.
    printf '%s\n' "$body" | sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*(")/\1***\4/g' >&2
    exit 1
  }
  # Connect's response echoes the connector config back, database.password and
  # connection.password included -- so the body is never written to disk (was
  # /tmp/.reg.out, a fixed, world-readable path -- the same fix as
  # clinic/connectors/register-odoo.sh). It's held
  # only in this shell's own memory, split on the trailing newline curl's -w
  # appends, and on a non-2xx it's printed with any password value masked
  # before the human ever sees it.
  resp=$(printf '%s' "$body" | curl -s -w '\n%{http_code}' \
         -X PUT -H 'Content-Type: application/json' \
         --data-binary @- "$CONNECT_URL/connectors/${name}/config")
  code="${resp##*$'\n'}"
  echo "  ${name}: HTTP ${code}"
  # The value group below must consume JSON escapes ([^"\\]|\\.)* rather than
  # stop at the first bare quote ([^"]*) -- a password containing an escaped
  # quote (\") would otherwise end the match early and leak everything after
  # it, e.g. "connection.password": "SEC\"RET" -> "connection.password":
  # "***"RET" with the naive pattern (d66aae8).
  [ "$code" -lt 300 ] || printf '%s\n' "${resp%$'\n'*}" \
    | sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*(")/\1***\4/g' \
    | sed 's/^/    /'
done
