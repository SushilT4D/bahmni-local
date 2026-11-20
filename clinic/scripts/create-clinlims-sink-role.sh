#!/usr/bin/env bash
# Creates the clinlims_sink role the OpenELIS down sinks log in as, and checks its grants on the [down] tables.
# OpenELIS never uses this role, so its writes can be marked as replicated and not captured again.
set -euo pipefail

CTR="${PG_CONTAINER:-bahmni-local-bahmni-postgres-1}"
PG_ADMIN="${PG_ADMIN:-postgres}"
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"
TABLES_SH="$(cd "$(dirname "$0")/../.." && pwd)/sync/tables/tables.sh"
psql_admin(){ podman exec "$CTR" psql -U "$PG_ADMIN" -d openelis "$@"; }

# Reuse the password in .env, or generate one and write it there.
[ -f "$ENV_FILE" ] || { echo "  no .env at $ENV_FILE" >&2; exit 1; }
PW="$(set -a; . "$ENV_FILE" >/dev/null 2>&1; set +a; printf '%s' "${CLINLIMS_SINK_PASSWORD:-}")"
if [ -n "$PW" ]; then
  echo "  reusing CLINLIMS_SINK_PASSWORD from .env"
else
  PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"
  [ "${#PW}" -eq 32 ] || { echo "  password generation produced ${#PW} chars, not 32" >&2; exit 1; }
  tmp="$(mktemp)"; grep -v '^CLINLIMS_SINK_PASSWORD=' "$ENV_FILE" > "$tmp" || true
  printf 'CLINLIMS_SINK_PASSWORD=%s\n' "$PW" >> "$tmp"; cat "$tmp" > "$ENV_FILE"; rm -f "$tmp"
  echo "  generated CLINLIMS_SINK_PASSWORD into .env"
fi

# Create or update the role. The SQL runs from a file so an error never echoes the password.
TMP="$(mktemp)"; chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<SQL
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'clinlims_sink') THEN
    ALTER ROLE clinlims_sink WITH LOGIN PASSWORD '${PW}';
  ELSE
    CREATE ROLE clinlims_sink WITH LOGIN PASSWORD '${PW}';
  END IF;
END \$\$;
GRANT USAGE ON SCHEMA clinlims TO clinlims_sink;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA clinlims TO clinlims_sink;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA clinlims TO clinlims_sink;
ALTER DEFAULT PRIVILEGES IN SCHEMA clinlims
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO clinlims_sink;
SQL
podman cp "$TMP" "$CTR":/tmp/.clinlims_sink.sql >/dev/null
podman exec "$CTR" chmod 600 /tmp/.clinlims_sink.sql
psql_admin -v ON_ERROR_STOP=1 -q -f /tmp/.clinlims_sink.sql
podman exec "$CTR" rm -f /tmp/.clinlims_sink.sql
echo "  clinlims_sink role ready on ${CTR}"

# Check the role can SELECT, INSERT and UPDATE every OpenELIS [down] table.
DOWN="$(bash "$TABLES_SH" openelis down | cut -d: -f1)" || { echo "  could not read the OpenELIS [down] list" >&2; exit 1; }
lacking=""
for t in $DOWN; do
  got="$(psql_admin -t -A -c "SELECT has_table_privilege('clinlims_sink', 'clinlims.${t}', 'SELECT') AND has_table_privilege('clinlims_sink', 'clinlims.${t}', 'INSERT') AND has_table_privilege('clinlims_sink', 'clinlims.${t}', 'UPDATE')")" || got=""
  [ "$got" = t ] || lacking="${lacking} ${t}(${got:-unreadable})"
done
[ -z "$lacking" ] || { echo "  clinlims_sink lacks SELECT, INSERT or UPDATE on:${lacking}" >&2; exit 1; }
echo "  verified: clinlims_sink may SELECT, INSERT, UPDATE the OpenELIS [down] tables"
