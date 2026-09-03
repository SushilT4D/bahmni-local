#!/usr/bin/env bash
# ADDED 2026-09-04 (sync-core, D7 Odoo full-replication build).
#
# Creates the odoo_sink login role -- the prerequisite that makes the write-origin guard
# possible at all. The trigger distinguishes a replicated write from a local one by
# session_user, so the sink MUST connect as a role the Odoo application never uses.
# This is the same prerequisite that blocked the OpenELIS guard until clinlims_sink
# existed (F-015).
#
# PASSWORD HANDLING. The DDL is written to a file inside the container and run with -f,
# never passed with -c and never interpolated into a logged command. This is not
# theoretical caution: on 2026-09-03 a generated password leaked into a PostgreSQL ERROR
# CONTEXT line, because a failing statement echoes its own text -- including the literal
# -- back to the client. With -f, the error cites a file and line, not the statement.
# The value is written once to .env (gitignored) and never printed.
set -euo pipefail

NODE="${1:?usage: create-odoo-sink-role.sh <node>   e.g. rawach}"
CTR="${PG_CONTAINER:-bahmni-local-bahmni-postgres-1}"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"

if grep -q '^ODOO_SINK_PASSWORD=' "$ENV_FILE" 2>/dev/null; then
  echo "  ODOO_SINK_PASSWORD already present in .env -- reusing, not regenerating"
  PW="$(grep '^ODOO_SINK_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
else
  PW="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
  printf 'ODOO_SINK_PASSWORD=%s\n' "$PW" >> "$ENV_FILE"
  echo "  generated ODOO_SINK_PASSWORD and appended to .env (gitignored)"
fi

# umask so the DDL file is not world-readable even for the moment it exists
TMP="$(mktemp)"; chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<SQL
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'odoo_sink') THEN
    ALTER ROLE odoo_sink WITH LOGIN PASSWORD '${PW}';
  ELSE
    CREATE ROLE odoo_sink WITH LOGIN PASSWORD '${PW}';
  END IF;
END \$\$;
GRANT USAGE ON SCHEMA public TO odoo_sink;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO odoo_sink;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO odoo_sink;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO odoo_sink;
SQL

docker cp "$TMP" "$CTR":/tmp/.odoo_sink.sql >/dev/null
docker exec "$CTR" chmod 600 /tmp/.odoo_sink.sql
# -f, not -c: on failure psql cites the file and line, not the statement text
docker exec "$CTR" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q -f /tmp/.odoo_sink.sql
docker exec "$CTR" rm -f /tmp/.odoo_sink.sql

echo "  odoo_sink role ready on ${CTR} (node ${NODE})"
docker exec "$CTR" psql -U postgres -d odoo -t -A \
  -c "SELECT '  verified: role=' || rolname || ' canlogin=' || rolcanlogin FROM pg_roles WHERE rolname='odoo_sink';"
