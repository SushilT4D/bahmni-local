#!/usr/bin/env bash
# Unit test for hub/install/tasks/100-join.sh. No docker, no network -- the
# task only reads hub/.env and prints text, so it runs directly against a
# fixture .env, the same way test_jaas.sh and test_preflight.sh exercise
# their own tasks/functions without a live stack.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_contains(){ if printf '%s' "$2" | grep -qF "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: expected output to contain %q\n' "$1" "$3"; fails=$((fails+1)); fi; }
TASK="${HERE}/../tasks/100-join.sh"

# DRY: prints a "would:" line and nothing else, exits 0.
out="$(DRY=1 HUB_DIR="$TMP" bash "$TASK" 2>&1)"; rc=$?
assert_rc "DRY exits 0" "$rc" 0
assert_contains "DRY prints a would: line" "$out" "would:"

# A real .env, values distinct from any real hub's (never copy a live one
# into a fixture) -- exercises the two-container identity and the
# public-listener line, all read from hub/.env, none hardcoded.
printf 'KAFKA_BASE_NETWORK=test-base_default\nBASE_MYSQL_CONTAINER=test-base-openmrsdb-1\nBASE_PG_CONTAINER=test-base-odoodb-1\nBASE_PG_SUPERUSER=odoo\nBASE_ELIS_CONTAINER=test-base-openelisdb-1\nBASE_ELIS_SUPERUSER=clinlims\nREMOTE_KAFKA_HOST=198.51.100.7\n' > "$TMP/.env"
chmod 600 "$TMP/.env"
out="$(DRY=0 HUB_DIR="$TMP" bash "$TASK" 2>&1)"; rc=$?
assert_rc "real run exits 0" "$rc" 0
assert_contains "prints the exact join command" "$out" "skills/install-clinic.sh join <slug>"
assert_contains "prints the exact leave command" "$out" "skills/install-clinic.sh leave <slug>"
assert_contains "HUB_GIT is the fixed pull literal (a real hub fetches GitHub itself)" "$out" "HUB_GIT=pull"
assert_contains "HUB_SSH host comes from REMOTE_KAFKA_HOST" "$out" "@198.51.100.7"
assert_contains "HUB_KEY is a placeholder, never invented" "$out" "HUB_KEY=<path to this hub's operator SSH private key>"
assert_contains "prints KAFKA_BASE_NETWORK" "$out" "test-base_default"
assert_contains "prints BASE_MYSQL_CONTAINER" "$out" "test-base-openmrsdb-1"
assert_contains "prints BASE_PG_CONTAINER and its superuser" "$out" "test-base-odoodb-1  (superuser: odoo)"
assert_contains "prints BASE_ELIS_CONTAINER and its superuser" "$out" "test-base-openelisdb-1  (superuser: clinlims)"
assert_contains "prints the public listener" "$out" "SASL_PLAINTEXT://198.51.100.7:9092"
assert_contains "prints the mTLS/ACL caveat" "$out" "mTLS and per-site broker"
assert_contains "ends with the printed marker" "$out" "printed"

# BASE_ELIS_CONTAINER/SUPERUSER absent (an .env composed before that pair
# existed, or the common single-container case) -- falls back to BASE_PG_*,
# same convention as hub_base_container/pg_admin.
printf 'KAFKA_BASE_NETWORK=test-base_default\nBASE_MYSQL_CONTAINER=test-base-openmrsdb-1\nBASE_PG_CONTAINER=test-base-pg-1\nBASE_PG_SUPERUSER=postgres\nREMOTE_KAFKA_HOST=198.51.100.7\n' > "$TMP/.env"
chmod 600 "$TMP/.env"
out="$(DRY=0 HUB_DIR="$TMP" bash "$TASK" 2>&1)"
assert_contains "BASE_ELIS_CONTAINER falls back to BASE_PG_CONTAINER when absent" "$out" "test-base-pg-1  (superuser: postgres)"

# A hub/.env with no REMOTE_KAFKA_HOST at all must refuse, not print a
# printout with a blank host baked into it.
printf 'KAFKA_BASE_NETWORK=test-base_default\nBASE_MYSQL_CONTAINER=test-base-openmrsdb-1\nBASE_PG_CONTAINER=test-base-pg-1\nBASE_PG_SUPERUSER=postgres\n' > "$TMP/.env"
chmod 600 "$TMP/.env"
( DRY=0 HUB_DIR="$TMP" bash "$TASK" ) >/dev/null 2>&1; rc=$?
assert_rc "refuses when REMOTE_KAFKA_HOST is empty, rather than printing a blank host" "$rc" 1

printf '%s\n' "$fails failure(s)"
exit $((fails>0))
