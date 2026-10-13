#!/usr/bin/env bash
# Registers the Odoo CDC connectors, substituting credentials from
# .env at registration time so no committed file holds a literal secret. The four
# clinlims connector JSONs predate this and DO carry literals -- see the note in
# f74613f; do not copy their pattern.
set -euo pipefail
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
set -a; . "$ROOT/.env"; set +a

# The hub's down source takes its table list and aggregate regex from the down
# list (sync/hub-down.conf). Read before anything is registered, and only when
# a template asks for it; a list it refuses stops every registration.
for name in "$@"; do
  if grep -q '${HUB_DOWN_' "$ROOT/connectors/${name}.json" 2>/dev/null; then
    down="$(bash "$ROOT/../sync/hub-down.sh" odoo)" || { echo "  the down list could not be read (reason above); nothing was registered" >&2; exit 1; }
    HUB_DOWN_ODOO_TABLES="$(printf '%s\n' "$down" | paste -sd, -)"
    HUB_DOWN_ODOO_TABLE_INCLUDE_LIST="$(printf '%s\n' "$down" | sed 's/^/public./' | paste -sd, -)"
    HUB_DOWN_ODOO_ALTERNATION="$(printf '%s\n' "$down" | paste -sd'|' -)"
    export HUB_DOWN_ODOO_TABLES HUB_DOWN_ODOO_TABLE_INCLUDE_LIST HUB_DOWN_ODOO_ALTERNATION
    break
  fi
done

for name in "$@"; do
  f="$ROOT/connectors/${name}.json"
  [ -f "$f" ] || { echo "  no such config: $f" >&2; exit 1; }
  body=$(ODOO_DB_PASSWORD="${ODOO_DB_PASSWORD:-}" ODOO_SINK_PASSWORD="${ODOO_SINK_PASSWORD:-}" NODE="${NODE:?set NODE=rawach|ghated|cloud}" TOPIC_PREFIX="${TOPIC_PREFIX:-bahmni-local}" \
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
