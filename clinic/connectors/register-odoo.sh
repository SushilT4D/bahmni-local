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
  body=$(ODOO_DB_PASSWORD="${ODOO_DB_PASSWORD:-}" ODOO_SINK_PASSWORD="${ODOO_SINK_PASSWORD:-}" CLINLIMS_SINK_PASSWORD="${CLINLIMS_SINK_PASSWORD:-}" CLINLIMS_SOURCE_PASSWORD="${CLINLIMS_SOURCE_PASSWORD:-}" NODE="${NODE:?set NODE=rawach|ghated|cloud}" MYSQL_SERVER_NAME="${MYSQL_SERVER_NAME:?set MYSQL_SERVER_NAME in .env}" REMOTE_SERVER_NAME="${REMOTE_SERVER_NAME:-bahmni-cloud}" TOPIC_PREFIX="${TOPIC_PREFIX:-$MYSQL_SERVER_NAME}" \
         python3 "$ROOT/connectors/_render_connector.py" "$f") || { echo "$body" >&2; exit 1; }
  # Connect's response echoes the connector config back, database.password and
  # connection.password included -- so the body is never written to disk (was
  # /tmp/.reg.out, a fixed, world-readable path: F-073). It's held only in this
  # shell's own memory, split on the trailing newline curl's -w appends, and on
  # a non-2xx it's printed with any password value masked before the human ever
  # sees it.
  resp=$(printf '%s' "$body" | curl -s -w '\n%{http_code}' \
         -X PUT -H 'Content-Type: application/json' \
         --data-binary @- "$CONNECT_URL/connectors/${name}/config")
  code="${resp##*$'\n'}"
  echo "  ${name}: HTTP ${code}"
  # The value group below must consume JSON escapes ([^"\\]|\\.)* rather than
  # stop at the first bare quote ([^"]*) -- a password containing an escaped
  # quote (\") would otherwise end the match early and leak everything after
  # it, e.g. "connection.password": "SEC\"RET" -> "connection.password":
  # "***"RET" with the naive pattern (F-073 review, round 1).
  [ "$code" -lt 300 ] || printf '%s\n' "${resp%$'\n'*}" \
    | sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*(")/\1***\4/g' \
    | sed 's/^/    /'
done
