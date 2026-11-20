#!/usr/bin/env bash
# Creates the odoo_sink role the Odoo down sinks log in as, storing its password in .env.
# Odoo never uses this role, so the write-origin guard can tell a replicated write by session_user.
set -euo pipefail

CTR="${PG_CONTAINER:-bahmni-local-bahmni-postgres-1}"
PG_ADMIN="${PG_ADMIN:-postgres}"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"

# Reuse the password in .env, or generate one and write it there.
[ -f "$ENV_FILE" ] || { echo "  no .env at $ENV_FILE" >&2; exit 1; }
PW="$(set -a; . "$ENV_FILE" >/dev/null 2>&1; set +a; printf '%s' "${ODOO_SINK_PASSWORD:-}")"
if [ -n "$PW" ]; then
  echo "  reusing ODOO_SINK_PASSWORD from .env"
else
  PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"
  [ "${#PW}" -eq 32 ] || { echo "  password generation produced ${#PW} chars, not 32" >&2; exit 1; }
  tmp="$(mktemp)"; grep -v '^ODOO_SINK_PASSWORD=' "$ENV_FILE" > "$tmp" || true
  printf 'ODOO_SINK_PASSWORD=%s\n' "$PW" >> "$tmp"; cat "$tmp" > "$ENV_FILE"; rm -f "$tmp"
  echo "  generated ODOO_SINK_PASSWORD into .env"
fi

# Create or update the role. The SQL runs from a file so an error never echoes the password.
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
podman cp "$TMP" "$CTR":/tmp/.odoo_sink.sql >/dev/null
podman exec "$CTR" chmod 600 /tmp/.odoo_sink.sql
podman exec "$CTR" psql -U "$PG_ADMIN" -d odoo -v ON_ERROR_STOP=1 -q -f /tmp/.odoo_sink.sql
podman exec "$CTR" rm -f /tmp/.odoo_sink.sql
echo "  odoo_sink role ready on ${CTR}"
