#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$TMP/hub"; mkdir -p "$HUB_DIR"
. "$HERE/../lib.sh"
OUT="$HUB_DIR/.env"
printf 'MYSQL_ROOT_PASSWORD=r00t\nOPENMRS_DB_NAME=openmrs\nODOO_DB_PASSWORD=od\nODOO_SINK_PASSWORD=os\nOPENELIS_DB_PASSWORD=oe\n' > "$TMP/base.env"
printf 'REMOTE_KAFKA_PASSWORD=fleetpw\n' > "$TMP/secrets.env"
printf 'REMOTE_KAFKA_BOOTSTRAP_SERVERS=kafka.example:9092\nREMOTE_KAFKA_USERNAME=mirrormaker\n' > "$TMP/hub.env"
HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT"
assert_eq "REMOTE_KAFKA_HOST from sync/hub.env" "$(env_get "$OUT" REMOTE_KAFKA_HOST)" "kafka.example"
assert_eq "fleet password from secrets" "$(env_get "$OUT" REMOTE_KAFKA_PASSWORD)" "fleetpw"
assert_eq "base root password carried" "$(env_get "$OUT" BASE_MYSQL_ROOT_PASSWORD)" "r00t"
assert_eq "existing sink password reused" "$(env_get "$OUT" ODOO_SINK_PASSWORD)" "os"
assert_eq "odoo db password carried" "$(env_get "$OUT" ODOO_DB_PASSWORD)" "od"
assert_eq "clinlims source password from base OPENELIS_DB_PASSWORD" "$(env_get "$OUT" CLINLIMS_SOURCE_PASSWORD)" "oe"
assert_eq "remote server name" "$(env_get "$OUT" REMOTE_SERVER_NAME)" "bahmni-cloud"
# Task 080: the down-source's connection triple. CLOUD_MYSQL_HOST has no base
# .env counterpart to copy -- it defaults to whatever BASE_MYSQL_CONTAINER was
# just set to (no override here, so the fixed fallback "cloud-openmrsdb-1"),
# since Docker resolves container names on the shared network.
assert_eq "CLOUD_MYSQL_HOST defaults to BASE_MYSQL_CONTAINER" "$(env_get "$OUT" CLOUD_MYSQL_HOST)" "cloud-openmrsdb-1"
assert_eq "CLOUD_MYSQL_PORT default" "$(env_get "$OUT" CLOUD_MYSQL_PORT)" "3306"
assert_eq "CLOUD_MYSQL_DATABASE default" "$(env_get "$OUT" CLOUD_MYSQL_DATABASE)" "openmrs"
assert_eq "clinlims sink password generated (32)" "$(env_get "$OUT" CLINLIMS_SINK_PASSWORD | wc -c | tr -d ' ')" "33"
assert_eq "cluster id generated (22)" "$(env_get "$OUT" KAFKA_CLUSTER_ID | wc -c | tr -d ' ')" "23"
assert_eq "mode 600" "$(stat -c %a "$OUT" 2>/dev/null || stat -f %Lp "$OUT")" "600"
before="$(cat "$OUT")"; HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT"
assert_eq "second compose keeps generated values" "$(cat "$OUT")" "$before"
# hub_base_container ROLE reads BASE_MYSQL_CONTAINER/BASE_PG_CONTAINER from
# ${HUB_DIR}/.env -- that is exactly $OUT above, so no separate fixture is
# needed; the defaults hub_compose_env wrote (no override in the environment)
# are asserted literally, not by re-reading $OUT through env_get, so a shared
# env_get bug couldn't mask a hub_base_container bug.
assert_eq "hub_base_container mysql" "$(hub_base_container mysql)" "cloud-openmrsdb-1"
assert_eq "hub_base_container pg" "$(hub_base_container pg)" "cloud-openelisdb-1"
( hub_base_container bogus ) >/dev/null 2>&1; rc=$?
assert_eq "hub_base_container rejects an unknown role" "$rc" "1"

# Ruling 11 (two-container Postgres base): BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER
# default from BASE_PG_CONTAINER/BASE_PG_SUPERUSER in hub_compose_env -- no
# override was given above, so both collapse to the same one-container values
# every other assertion in this file already exercises.
assert_eq "BASE_ELIS_CONTAINER defaults from BASE_PG_CONTAINER" "$(env_get "$OUT" BASE_ELIS_CONTAINER)" "cloud-openelisdb-1"
assert_eq "BASE_ELIS_SUPERUSER defaults from BASE_PG_SUPERUSER" "$(env_get "$OUT" BASE_ELIS_SUPERUSER)" "postgres"
assert_eq "hub_base_container elis (populated by hub_compose_env)" "$(hub_base_container elis)" "cloud-openelisdb-1"
# hub_base_container's OWN fallback: an hub/.env written before this key pair
# existed has no BASE_ELIS_CONTAINER line at all (not just an empty one) --
# a separate fixture, since $OUT above always has the key populated by
# hub_compose_env and so never exercises this function's own default branch.
mkdir -p "$TMP/hub-noelis"
printf 'BASE_PG_CONTAINER=legacy-pg-container\n' > "$TMP/hub-noelis/.env"
assert_eq "hub_base_container elis falls back to BASE_PG_CONTAINER when absent" "$(HUB_DIR="$TMP/hub-noelis" hub_base_container elis)" "legacy-pg-container"

# hub/.env.example must declare exactly the keys HUB_KEYS lists -- a key added
# to one and not the other is exactly how CLOUD_MYSQL_HOST/PORT/DATABASE went
# missing from .env.example in the first place (task 080). Word-count first
# (a quick, readable failure), then the full set (names every drift exactly).
example_file="$HERE/../../.env.example"
example_count="$(grep -cE '^[A-Z_0-9]+=' "$example_file")"
hub_keys_count="$(printf '%s\n' $HUB_KEYS | wc -l | tr -d ' ')"
assert_eq "hub/.env.example key count matches HUB_KEYS (${hub_keys_count})" "$example_count" "$hub_keys_count"
example_sorted="$(grep -oE '^[A-Z_0-9]+=' "$example_file" | sed 's/=$//' | sort)"
hub_keys_sorted="$(printf '%s\n' $HUB_KEYS | sort)"
assert_eq "hub/.env.example key set is exactly HUB_KEYS" "$example_sorted" "$hub_keys_sorted"

# mysql_user_sql VERSION USER PASSWORD DB -- pure text generation, no docker
# needed. 5.6.51 stands in for the Azure hub's base image, 8.0.39 for every
# other target (sync/versions.env's MYSQL_IMAGE).
assert_has(){ if printf '%s' "$2" | grep -qF "$3"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: %q does not contain %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_lacks(){ if printf '%s' "$2" | grep -qF "$3"; then printf '  FAIL %s: %q unexpectedly contains %q\n' "$1" "$2" "$3"; fails=$((fails+1)); else printf '  ok   %s\n' "$1"; fi; }
out56="$(mysql_user_sql 5.6.51 sink 's3kret' openmrs)"
out80="$(mysql_user_sql 8.0.39 sink 's3kret' openmrs)"
assert_lacks "5.6.51: no CREATE USER IF NOT EXISTS" "$out56" 'CREATE USER IF NOT EXISTS'
assert_has  "5.6.51: has IDENTIFIED BY"             "$out56" 'IDENTIFIED BY'
assert_has  "5.6.51: has SET PASSWORD"              "$out56" 'SET PASSWORD'
assert_has  "8.0.39: has CREATE USER IF NOT EXISTS" "$out80" 'CREATE USER IF NOT EXISTS'
assert_has  "8.0.39: has IDENTIFIED BY"             "$out80" 'IDENTIFIED BY'
assert_has  "8.0.39: has ALTER USER"                "$out80" 'ALTER USER'
# pg_lit_escape / mysql_lit_escape (Fix round 2): exact escaped SQL text for
# a value carrying both a quote and a backslash. This is a fixed test value,
# never a real secret -- the whole point of the assertion is that the exact
# output is knowable and stable.
raw_pw="a'b\\c"                    # 5 chars: a ' b \ c
assert_eq "pg_lit_escape doubles the quote, leaves backslash alone" "$(pg_lit_escape "$raw_pw")" "a''b\\c"
assert_eq "mysql_lit_escape backslash-escapes the backslash, then the quote" "$(mysql_lit_escape "$raw_pw")" "a\\'b\\\\c"

# mask_env_secrets (Fix round 2): a literal substring replace, not a sed
# pattern -- so a value containing sed/regex-special characters (here all of
# / \ ' & at once) must still be found and replaced whole, not break the
# mask or leak through it the way `sed "s/${SECRET}/.../g"` would. Built via
# variable interpolation on both the export and the expected input/output so
# the value is written out once, not re-escaped by hand in two places.
secret_val="a/b\\c'd&e"
export TESTVAR_MASK_SECRET="$secret_val"
got="$(printf '%s' "prefix ${secret_val} suffix" | mask_env_secrets TESTVAR_MASK_SECRET)"
assert_eq "mask_env_secrets replaces a value containing / \\ ' & intact" "$got" "prefix <hidden> suffix"
unset TESTVAR_MASK_SECRET

# Regression (Fix round 2, code review): `for t in $(gen); do` only checks
# the exit status of the SUBSHELL command substitution forks to run gen --
# word-splitting a $(...) into a for-list is not a context `set -e` inspects
# -- so a fail() partway through gen is swallowed: the loop still runs on
# whatever gen printed before it died, and the caller reaches code after the
# loop with exit 0. Capturing gen's output into a variable FIRST turns that
# into a plain assignment, whose exit status IS what `set -e` checks; this is
# the exact shape hub/install/tasks/050-base-db.sh and
# hub/install/tests/test_base_db.sh now use everywhere a fail()-capable
# generator (subsystem_tables) feeds a for-list. Both shapes are run inside
# their own `( set -e; ... )` subshell here so their exit -- or lack of it --
# never ends this test script.
fake_gen(){ printf 'one\ntwo\n'; fail 'boom'; }

swallow_out="$( ( set -e
  for t in $(fake_gen 2>/dev/null); do :; done
  echo REACHED_END
) 2>/dev/null )"
assert_eq "swallowing shape (for t in \$(gen)) still reaches past the mid-generator fail" "$swallow_out" "REACHED_END"

capture_out="$( ( set -e
  tables="$(fake_gen 2>/dev/null)"
  for t in $tables; do :; done
  echo REACHED_END
) 2>/dev/null )"
capture_rc=$?
assert_eq "capture-then-loop shape (this task's pattern) exits non-zero" "$capture_rc" "1"
assert_eq "capture-then-loop shape never reaches the marker after the fail" "$capture_out" ""

# pg_admin DB ARGS... (code review fold-in, Task 6/7 review: hoisted here so
# 050-base-db.sh and 080-sources.sh stop each defining their own, differently
# -shaped, same-named function). Dispatch only -- CT is faked to `echo` so
# this runs with no real docker/podman, and just proves which container and
# superuser pg_admin chose to `exec` into for a given db name.
export BASE_PG_CONTAINER=pg-c BASE_PG_SUPERUSER=pgsu BASE_ELIS_CONTAINER=elis-c BASE_ELIS_SUPERUSER=elissu
CT=echo
got="$(pg_admin odoo -Atc 'select 1')"
assert_eq "pg_admin odoo execs into BASE_PG_CONTAINER as BASE_PG_SUPERUSER" "$got" "exec -i pg-c psql -U pgsu -d odoo -v ON_ERROR_STOP=1 -q -Atc select 1"
got="$(pg_admin openelis -Atc 'select 1')"
assert_eq "pg_admin openelis execs into BASE_ELIS_CONTAINER as BASE_ELIS_SUPERUSER" "$got" "exec -i elis-c psql -U elissu -d openelis -v ON_ERROR_STOP=1 -q -Atc select 1"
got="$(pg_admin postgres -Atc 'select 1')"
assert_eq "pg_admin postgres (the maintenance db, not \"openelis\") stays on BASE_PG_CONTAINER" "$got" "exec -i pg-c psql -U pgsu -d postgres -v ON_ERROR_STOP=1 -q -Atc select 1"
# The ELIS fallback (an .env composed before BASE_ELIS_CONTAINER/SUPERUSER
# existed): unset both and confirm pg_admin collapses back onto BASE_PG_*,
# same as hub_compose_env's own default and hub_base_container's.
unset BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER
got="$(pg_admin openelis -Atc 'select 1')"
assert_eq "pg_admin openelis falls back to BASE_PG_CONTAINER/SUPERUSER when the ELIS pair is unset" "$got" "exec -i pg-c psql -U pgsu -d openelis -v ON_ERROR_STOP=1 -q -Atc select 1"
unset CT BASE_PG_CONTAINER BASE_PG_SUPERUSER

printf '%s\n' "$fails failure(s)"; exit $((fails>0))
