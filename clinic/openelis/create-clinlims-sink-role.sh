#!/usr/bin/env bash
# Derived from the verified odoo_sink role script (sync-core, 2026-09-04).
#
# Creates the clinlims_sink login role. The JDBC sinks MUST connect as a role the
# OpenELIS application itself never uses: it is the role that claims a replication
# origin (openelis/apply-replication-origin.sql grants the origin functions to it and
# to nobody else), which is what stops a replicated write from being republished.
#
# PASSWORD HANDLING. The DDL is written to a file inside the container and run with -f,
# never passed with -c and never interpolated into a logged command. This is not
# theoretical caution: on 2026-09-03 a generated password leaked into a PostgreSQL ERROR
# CONTEXT line, because a failing statement echoes its own text -- including the literal
# -- back to the client. With -f, the error cites a file and line, not the statement.
# The value is written once to .env (gitignored) and never printed.
set -euo pipefail

NODE="${1:?usage: create-clinlims-sink-role.sh <node>   e.g. rawach}"
CTR="${PG_CONTAINER:-bahmni-local-bahmni-postgres-1}"
PG_ADMIN="${PG_ADMIN:-postgres}"
# Some nodes have podman only, not docker.
CTR_RT="${CTR_RT:-}"
if [ -z "$CTR_RT" ]; then
  if command -v docker >/dev/null 2>&1; then CTR_RT=docker
  elif command -v podman >/dev/null 2>&1; then CTR_RT=podman
  else echo "no docker or podman on PATH" >&2; exit 2; fi
fi
ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.env"

# READ .env BY SOURCING IT, NOT BY CUTTING THE LINE. Bahmni's .env files carry inline
# comments -- OPENELIS_DB_SERVER=bahmni-postgres       # [OK] -- and `cut -d= -f2-` keeps
# the padding and the comment as part of the value. On the cloud that produced a 76-char
# "password" where the real one is 4 chars: the role was created with the polluted string
# while every consumer sources .env and gets the clean one, so Debezium failed with
# "password authentication failed for user clinlims_sink" against a role that had just been
# created successfully. Source it the same way the consumers do.
if grep -q '^CLINLIMS_SINK_PASSWORD=' "$ENV_FILE" 2>/dev/null; then
  echo "  CLINLIMS_SINK_PASSWORD already present in .env -- reusing, not regenerating"
  PW="$(set -a; . "$ENV_FILE" >/dev/null 2>&1; set +a; printf '%s' "$CLINLIMS_SINK_PASSWORD")"
else
  # Bounded input on purpose: `tr </dev/urandom | head -c 32` never lets tr
  # finish, so head's exit sends it SIGPIPE and under pipefail the assignment
  # fails with 141 on Linux AND macOS -- every fresh node died here, before the
  # append (first live clinic, manpur, 2026-09-17). 512 bytes give ~124 [A-Za-z0-9].
  PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"
  [ "${#PW}" -eq 32 ] || { echo "  password generation produced ${#PW} chars, not 32" >&2; exit 1; }
  printf 'CLINLIMS_SINK_PASSWORD=%s\n' "$PW" >> "$ENV_FILE"
  echo "  generated CLINLIMS_SINK_PASSWORD and appended to .env (gitignored)"
fi

# umask so the DDL file is not world-readable even for the moment it exists
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

"$CTR_RT" cp "$TMP" "$CTR":/tmp/.clinlims_sink.sql >/dev/null
"$CTR_RT" exec "$CTR" chmod 600 /tmp/.clinlims_sink.sql
# -f, not -c: on failure psql cites the file and line, not the statement text
"$CTR_RT" exec "$CTR" psql -U "$PG_ADMIN" -d openelis -v ON_ERROR_STOP=1 -q -f /tmp/.clinlims_sink.sql
"$CTR_RT" exec "$CTR" rm -f /tmp/.clinlims_sink.sql

echo "  clinlims_sink role ready on ${CTR} (node ${NODE})"
"$CTR_RT" exec "$CTR" psql -U "$PG_ADMIN" -d openelis -t -A \
  -c "SELECT '  verified: role=' || rolname || ' canlogin=' || rolcanlogin FROM pg_roles WHERE rolname='clinlims_sink';"
