#!/usr/bin/env bash
# Creates (or resets) the odoo_sink Postgres role that the Odoo sinks write as.
# Usage: odoo/create-odoo-sink-role.sh <node>   (PG_CONTAINER overrides the container)
set -euo pipefail

NODE="${1:?usage: create-odoo-sink-role.sh <node>   e.g. rawach}"
CTR="${PG_CONTAINER:-bahmni-local-bahmni-postgres-1}"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"


# Reuse ODOO_SINK_PASSWORD from .env, or generate one and save it there.
[ -f "$ENV_FILE" ] || { echo "  no .env at $ENV_FILE" >&2; exit 1; }
PW="$(set -a; . "$ENV_FILE" >/dev/null 2>&1; set +a; printf '%s' "${ODOO_SINK_PASSWORD:-}")"
if [ -n "$PW" ]; then
  echo "  ODOO_SINK_PASSWORD already present in .env -- reusing, not regenerating"
else
  PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"
  [ "${#PW}" -eq 32 ] || { echo "  password generation produced ${#PW} chars, not 32" >&2; exit 1; }
  if grep -q '^ODOO_SINK_PASSWORD=' "$ENV_FILE" 2>/dev/null; then
    tmp="$(mktemp)"; grep -v '^ODOO_SINK_PASSWORD=' "$ENV_FILE" > "$tmp" || true
    printf 'ODOO_SINK_PASSWORD=%s\n' "$PW" >> "$tmp"; cat "$tmp" > "$ENV_FILE"; rm -f "$tmp"
    echo "  ODOO_SINK_PASSWORD was blank in .env -- generated and set (gitignored)"
  else
    printf 'ODOO_SINK_PASSWORD=%s\n' "$PW" >> "$ENV_FILE"
    echo "  generated ODOO_SINK_PASSWORD and appended to .env (gitignored)"
  fi
fi

# Create or update the role and grant it read/write on the odoo public schema.
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

# Run the SQL inside the container from a private file, then remove it.
docker cp "$TMP" "$CTR":/tmp/.odoo_sink.sql >/dev/null
docker exec "$CTR" chmod 600 /tmp/.odoo_sink.sql
docker exec "$CTR" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q -f /tmp/.odoo_sink.sql
docker exec "$CTR" rm -f /tmp/.odoo_sink.sql

# Read the role back.
echo "  odoo_sink role ready on ${CTR} (node ${NODE})"
docker exec "$CTR" psql -U postgres -d odoo -t -A \
  -c "SELECT '  verified: role=' || rolname || ' canlogin=' || rolcanlogin FROM pg_roles WHERE rolname='odoo_sink';"
