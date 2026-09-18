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
# BASE_MYSQL_ROOT_PASSWORD and BASE_PG_PASSWORD are NOT composed any more
# (final review, Important 7): nothing read either one, so hub/.env no longer
# carries a copy of the base stack's root credentials. Asserted as an absence,
# so a future re-add has to come past this line.
assert_eq "base root password NOT copied into hub/.env (dropped: no reader)" "$(env_get "$OUT" BASE_MYSQL_ROOT_PASSWORD)" ""
assert_eq "base pg password NOT copied into hub/.env (dropped: no reader)" "$(env_get "$OUT" BASE_PG_PASSWORD)" ""
assert_eq "KAFKA_SASL_BIND defaults to the public 0.0.0.0" "$(env_get "$OUT" KAFKA_SASL_BIND)" "0.0.0.0"
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
# Fix round 1: env_get no longer appends an incidental trailing newline (the
# old implementation's last pipeline stage was `sed`, which adds one whether
# the input line had one or not; the new one ends in a bare `printf '%s'`) --
# so these now count bytes in the value itself, not value+1.
assert_eq "clinlims sink password generated (32)" "$(env_get "$OUT" CLINLIMS_SINK_PASSWORD | wc -c | tr -d ' ')" "32"
assert_eq "cluster id generated (22)" "$(env_get "$OUT" KAFKA_CLUSTER_ID | wc -c | tr -d ' ')" "22"
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

# --- CLINIC_DIR really survives the nested source ---------------------------
# (found live: `VAR=x . file` is a TEMPORARY assignment outside POSIX mode, so
# CLINIC_DIR reverted to unset the moment hub/install/lib.sh's nested source of
# clinic/install/lib.sh returned -- and every compose() call in tasks 040, 060
# and 070 then died on `cd "${CLINIC_DIR}"` under set -u.) compose() is what
# reads it, so the assertion is on the value, in this already-sourced shell.
assert_eq "CLINIC_DIR survives the nested source and equals HUB_DIR" "${CLINIC_DIR:-<unset>}" "$HUB_DIR"
assert_eq "INSTALL_DIR survives the nested source and points at clinic/install" "${INSTALL_DIR:-<unset>}" "${REPO_DIR}/clinic/install"
assert_eq "PROFILES is empty for the hub (never the clinic's --profile list)" "${PROFILES:-}" ""

# --- the four base-stack coordinates come from the ENVIRONMENT first --------
# (final review, Important 6) A stock Bahmni base .env carries no POSTGRES_USER,
# so the old order silently produced "postgres" on IPLIT's real hub, where the
# superusers are odoo and clinlims -- with no way for an operator to say so.
# Composed into a SEPARATE file, since $OUT's values are already set and `put`
# keeps what is already there.
mkdir -p "$TMP/hub-env-first"
OUT2="$TMP/hub-env-first/.env"
( export BASE_PG_SUPERUSER=odoo BASE_ELIS_SUPERUSER=clinlims \
         BASE_MYSQL_CONTAINER=iplit-base-openmrsdb-1 BASE_PG_CONTAINER=iplit-base-odoodb-1 \
         BASE_ELIS_CONTAINER=iplit-base-openelisdb-1 KAFKA_SASL_BIND=127.0.0.1
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT2" >/dev/null )
assert_eq "BASE_PG_SUPERUSER from the install command's environment" "$(env_get "$OUT2" BASE_PG_SUPERUSER)" "odoo"
assert_eq "BASE_ELIS_SUPERUSER from the environment (not defaulted from BASE_PG_SUPERUSER)" "$(env_get "$OUT2" BASE_ELIS_SUPERUSER)" "clinlims"
assert_eq "BASE_PG_CONTAINER from the environment" "$(env_get "$OUT2" BASE_PG_CONTAINER)" "iplit-base-odoodb-1"
assert_eq "BASE_ELIS_CONTAINER from the environment" "$(env_get "$OUT2" BASE_ELIS_CONTAINER)" "iplit-base-openelisdb-1"
assert_eq "BASE_MYSQL_CONTAINER from the environment" "$(env_get "$OUT2" BASE_MYSQL_CONTAINER)" "iplit-base-openmrsdb-1"
assert_eq "CLOUD_MYSQL_HOST follows the environment's BASE_MYSQL_CONTAINER" "$(env_get "$OUT2" CLOUD_MYSQL_HOST)" "iplit-base-openmrsdb-1"
assert_eq "KAFKA_SASL_BIND from the environment (a lab hub behind a tunnel)" "$(env_get "$OUT2" KAFKA_SASL_BIND)" "127.0.0.1"
# The base .env's own POSTGRES_USER still wins over the fixed default when the
# environment says nothing -- the middle source of the three.
printf 'MYSQL_ROOT_PASSWORD=r00t\nOPENMRS_DB_NAME=openmrs\nPOSTGRES_USER=basefile\nODOO_DB_PASSWORD=od\nOPENELIS_DB_PASSWORD=oe\n' > "$TMP/base-pguser.env"
mkdir -p "$TMP/hub-base-second"; OUT3="$TMP/hub-base-second/.env"
( unset BASE_PG_SUPERUSER; HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base-pguser.env" "$TMP/secrets.env" "$OUT3" >/dev/null )
assert_eq "BASE_PG_SUPERUSER falls back to the base .env's POSTGRES_USER" "$(env_get "$OUT3" BASE_PG_SUPERUSER)" "basefile"

# --- residual fix item 1: the environment overrides on EVERY run, not just
# the first (final whole-branch re-review's New Important finding) ---------
# `put`'s own keep-existing guard used to make the "environment first"
# precedence above a dead letter after run 1: a first attempt that omitted
# BASE_PG_SUPERUSER baked "postgres" into hub/.env, and setting it and
# rerunning changed nothing -- put() saw an already-non-empty slot. put_coord
# (hub/install/lib.sh) fixes this for exactly the seven non-secret base
# coordinates. Three composes into ONE file, the shape a real resume
# exercises: run 1 with nothing in the environment, run 2 with all seven set
# (must override despite existing values), run 3 with the environment unset
# again (must KEEP run 2's values, not revert). A secret
# (KAFKA_ADMIN_PASSWORD, pure gen_secret, no base .env counterpart) rides
# along on all three runs to prove put_coord's refactor left secrets on the
# unchanged keep-existing path.
mkdir -p "$TMP/hub-resume"; OUT4="$TMP/hub-resume/.env"
coord_vars="KAFKA_BASE_NETWORK BASE_MYSQL_CONTAINER BASE_PG_CONTAINER BASE_PG_SUPERUSER BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER KAFKA_SASL_BIND"

# Run 1: nothing in the environment -- the same fixed defaults asserted
# against $OUT above land here too.
run1_from_env="$( ( unset $coord_vars
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT4" >/dev/null
  printf '%s' "$HUB_COMPOSE_ENV_FROM_ENV" ) )"
assert_eq "run 1 (no environment): HUB_COMPOSE_ENV_FROM_ENV is empty" "$run1_from_env" ""
assert_eq "run 1 (no environment): KAFKA_SASL_BIND default lands" "$(env_get "$OUT4" KAFKA_SASL_BIND)" "0.0.0.0"
assert_eq "run 1 (no environment): BASE_PG_SUPERUSER default lands" "$(env_get "$OUT4" BASE_PG_SUPERUSER)" "postgres"
assert_eq "run 1 (no environment): BASE_MYSQL_CONTAINER default lands" "$(env_get "$OUT4" BASE_MYSQL_CONTAINER)" "cloud-openmrsdb-1"
run1_admin_pw="$(env_get "$OUT4" KAFKA_ADMIN_PASSWORD)"
assert_eq "run 1: KAFKA_ADMIN_PASSWORD generated (32)" "$(printf '%s' "$run1_admin_pw" | wc -c | tr -d ' ')" "32"

# Run 2: all seven set in the environment -- every one overridden IN THE
# FILE even though $OUT4 already carries a DIFFERENT value for each from run
# 1. This is the exact scenario the finding named: a rerun after setting the
# environment must actually take effect, not silently no-op.
run2_from_env="$( ( export KAFKA_BASE_NETWORK=iplit-base_default BASE_MYSQL_CONTAINER=iplit-base-openmrsdb-1 \
         BASE_PG_CONTAINER=iplit-base-odoodb-1 BASE_PG_SUPERUSER=odoo \
         BASE_ELIS_CONTAINER=iplit-base-openelisdb-1 BASE_ELIS_SUPERUSER=clinlims \
         KAFKA_SASL_BIND=127.0.0.1
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT4" >/dev/null
  printf '%s' "$HUB_COMPOSE_ENV_FROM_ENV" ) )"
assert_eq "run 2: HUB_COMPOSE_ENV_FROM_ENV names all seven, in call order (020-env.sh's read-back line)" \
  "$run2_from_env" "KAFKA_SASL_BIND KAFKA_BASE_NETWORK BASE_PG_SUPERUSER BASE_MYSQL_CONTAINER BASE_PG_CONTAINER BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER"
assert_eq "run 2: KAFKA_BASE_NETWORK overridden despite an existing value" "$(env_get "$OUT4" KAFKA_BASE_NETWORK)" "iplit-base_default"
assert_eq "run 2: BASE_MYSQL_CONTAINER overridden despite an existing value" "$(env_get "$OUT4" BASE_MYSQL_CONTAINER)" "iplit-base-openmrsdb-1"
assert_eq "run 2: BASE_PG_CONTAINER overridden despite an existing value" "$(env_get "$OUT4" BASE_PG_CONTAINER)" "iplit-base-odoodb-1"
assert_eq "run 2: BASE_PG_SUPERUSER overridden despite an existing value (the exact Azure-hub scenario)" "$(env_get "$OUT4" BASE_PG_SUPERUSER)" "odoo"
assert_eq "run 2: BASE_ELIS_CONTAINER overridden despite an existing value" "$(env_get "$OUT4" BASE_ELIS_CONTAINER)" "iplit-base-openelisdb-1"
assert_eq "run 2: BASE_ELIS_SUPERUSER overridden despite an existing value" "$(env_get "$OUT4" BASE_ELIS_SUPERUSER)" "clinlims"
assert_eq "run 2: KAFKA_SASL_BIND overridden despite an existing value" "$(env_get "$OUT4" KAFKA_SASL_BIND)" "127.0.0.1"
assert_eq "run 2: a secret key (KAFKA_ADMIN_PASSWORD) composed twice keeps its first value" "$(env_get "$OUT4" KAFKA_ADMIN_PASSWORD)" "$run1_admin_pw"

# Run 3: environment unset again -- run 2's values are KEPT, not reverted to
# the run-1/fixed defaults (put_coord falls through to put()'s own
# keep-existing rule when the environment says nothing this run).
run3_from_env="$( ( unset $coord_vars
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT4" >/dev/null
  printf '%s' "$HUB_COMPOSE_ENV_FROM_ENV" ) )"
assert_eq "run 3 (environment unset again): HUB_COMPOSE_ENV_FROM_ENV is empty" "$run3_from_env" ""
assert_eq "run 3: KAFKA_BASE_NETWORK keeps run 2's value, not reverted" "$(env_get "$OUT4" KAFKA_BASE_NETWORK)" "iplit-base_default"
assert_eq "run 3: BASE_MYSQL_CONTAINER keeps run 2's value, not reverted" "$(env_get "$OUT4" BASE_MYSQL_CONTAINER)" "iplit-base-openmrsdb-1"
assert_eq "run 3: BASE_PG_CONTAINER keeps run 2's value, not reverted" "$(env_get "$OUT4" BASE_PG_CONTAINER)" "iplit-base-odoodb-1"
assert_eq "run 3: BASE_PG_SUPERUSER keeps run 2's value, not reverted" "$(env_get "$OUT4" BASE_PG_SUPERUSER)" "odoo"
assert_eq "run 3: BASE_ELIS_CONTAINER keeps run 2's value, not reverted" "$(env_get "$OUT4" BASE_ELIS_CONTAINER)" "iplit-base-openelisdb-1"
assert_eq "run 3: BASE_ELIS_SUPERUSER keeps run 2's value, not reverted" "$(env_get "$OUT4" BASE_ELIS_SUPERUSER)" "clinlims"
assert_eq "run 3: KAFKA_SASL_BIND keeps run 2's value, not reverted" "$(env_get "$OUT4" KAFKA_SASL_BIND)" "127.0.0.1"
assert_eq "run 3: KAFKA_ADMIN_PASSWORD still keeps run 1's first value" "$(env_get "$OUT4" KAFKA_ADMIN_PASSWORD)" "$run1_admin_pw"

# --- residual fix round 2: the env-wins rewrite must be TRANSITIVE ----------
# The re-review's displaced Important: round 1's put_coord only made a
# coordinate's OWN environment variable win every run. CLOUD_MYSQL_HOST had
# no such treatment at all (plain put, deriving from whatever
# BASE_MYSQL_CONTAINER happened to be STORED in $out) and BASE_ELIS_CONTAINER/
# BASE_ELIS_SUPERUSER's own put_coord fallback (no ELIS override given) also
# read the STORED BASE_PG_* rather than this run's possibly-new one.
# put_derived (hub/install/lib.sh) fixes both. Three scenarios below, kept
# separate rather than folded into the run1/run2/run3 block above so each
# maps onto exactly one sentence of the ruling.

# Scenario A -- the re-review's own worked example, verbatim: the documented
# Azure recovery is two attempts (hub/README.md's Install section), and
# CLOUD_MYSQL_HOST is never part of that documented command at all (nothing
# ever sets it directly) -- it must still follow BASE_MYSQL_CONTAINER on
# attempt 2, not keep attempt 1's now-wrong value.
mkdir -p "$TMP/hub-azure-recovery"; OUT5="$TMP/hub-azure-recovery/.env"
( unset $coord_vars CLOUD_MYSQL_HOST
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT5" >/dev/null )
assert_eq "azure recovery, attempt 1 (no environment): BASE_MYSQL_CONTAINER default" "$(env_get "$OUT5" BASE_MYSQL_CONTAINER)" "cloud-openmrsdb-1"
assert_eq "azure recovery, attempt 1: CLOUD_MYSQL_HOST follows the default" "$(env_get "$OUT5" CLOUD_MYSQL_HOST)" "cloud-openmrsdb-1"
attempt2_from_env="$( ( export KAFKA_BASE_NETWORK=iplit-base_default BASE_MYSQL_CONTAINER=iplit-base-openmrsdb-1 \
         BASE_PG_CONTAINER=iplit-base-odoodb-1 BASE_PG_SUPERUSER=odoo \
         BASE_ELIS_CONTAINER=iplit-base-openelisdb-1 BASE_ELIS_SUPERUSER=clinlims
  unset CLOUD_MYSQL_HOST
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT5" >/dev/null
  printf '%s' "$HUB_COMPOSE_ENV_FROM_ENV" ) )"
assert_eq "azure recovery, attempt 2 (the documented full command): BASE_MYSQL_CONTAINER moves to the real container" "$(env_get "$OUT5" BASE_MYSQL_CONTAINER)" "iplit-base-openmrsdb-1"
assert_eq "azure recovery, attempt 2: CLOUD_MYSQL_HOST follows it -- the re-review's exact bug (was: stuck on cloud-openmrsdb-1, a container that does not exist on this hub)" \
  "$(env_get "$OUT5" CLOUD_MYSQL_HOST)" "iplit-base-openmrsdb-1"
assert_eq "azure recovery, attempt 2: CLOUD_MYSQL_HOST's rewrite is NOT listed as environment-sourced (only BASE_MYSQL_CONTAINER's own name is -- CLOUD_MYSQL_HOST was derived, not itself overridden)" \
  "$(case " $attempt2_from_env " in *' CLOUD_MYSQL_HOST '*) echo present ;; *) echo absent ;; esac)" "absent"
assert_eq "azure recovery, attempt 2: BASE_MYSQL_CONTAINER IS listed as environment-sourced" \
  "$(case " $attempt2_from_env " in *' BASE_MYSQL_CONTAINER '*) echo present ;; *) echo absent ;; esac)" "present"

# Scenario B -- isolates the BASE_ELIS_* transitivity fix on its own, in the
# one shape where it is not masked by an explicit ELIS override: the
# operator moves BASE_PG_CONTAINER/BASE_PG_SUPERUSER via the environment on a
# resume (e.g. correcting only the Odoo side) but does NOT also give
# BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER -- as the one-container default
# implies they need not. A stale ELIS pair from an earlier run must move
# WITH BASE_PG_*, not stay put.
mkdir -p "$TMP/hub-elis-transitive"; OUT6="$TMP/hub-elis-transitive/.env"
( unset $coord_vars
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT6" >/dev/null )
assert_eq "elis transitivity, attempt 1: BASE_ELIS_CONTAINER defaults from BASE_PG_CONTAINER" "$(env_get "$OUT6" BASE_ELIS_CONTAINER)" "cloud-openelisdb-1"
( export BASE_PG_CONTAINER=iplit-base-odoodb-1 BASE_PG_SUPERUSER=odoo
  unset BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT6" >/dev/null )
assert_eq "elis transitivity, attempt 2: BASE_PG_CONTAINER moves via the environment" "$(env_get "$OUT6" BASE_PG_CONTAINER)" "iplit-base-odoodb-1"
assert_eq "elis transitivity, attempt 2: BASE_ELIS_CONTAINER follows it, not the stale value (the displaced Important, generalized)" "$(env_get "$OUT6" BASE_ELIS_CONTAINER)" "iplit-base-odoodb-1"
assert_eq "elis transitivity, attempt 2: BASE_ELIS_SUPERUSER follows BASE_PG_SUPERUSER, not the stale value" "$(env_get "$OUT6" BASE_ELIS_SUPERUSER)" "odoo"

# Scenario C -- CLOUD_MYSQL_HOST given explicitly in the environment wins
# over the derivation, even when BASE_MYSQL_CONTAINER also moves the same
# run (own-environment precedence, same rule as every put_coord key).
mkdir -p "$TMP/hub-cloudhost-explicit"; OUT7="$TMP/hub-cloudhost-explicit/.env"
( export BASE_MYSQL_CONTAINER=iplit-base-openmrsdb-1 CLOUD_MYSQL_HOST=explicit-down-source-host
  HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base.env" "$TMP/secrets.env" "$OUT7" >/dev/null )
assert_eq "CLOUD_MYSQL_HOST given explicitly wins over the BASE_MYSQL_CONTAINER-derived value" "$(env_get "$OUT7" CLOUD_MYSQL_HOST)" "explicit-down-source-host"

# --- git_dirty_hub_paths (final review, Minor 10): pure classifier ----------
# Task 090 passes `git status --porcelain` through this and fails only on what
# it prints, so that a hub host's own deliberate edits to the BASE stack's
# files do not read as "the hub install left its tree dirty".
porcelain=' M hub/install/lib.sh
 M cloud/docker-compose.override.yml
?? docs/notes.md
R  hub/old.sh -> hub/new.sh
 M sync/versions.env'
assert_eq "git_dirty_hub_paths keeps only the hub/ paths" "$(printf '%s\n' "$porcelain" | git_dirty_hub_paths | tr '\n' ' ')" "hub/install/lib.sh hub/new.sh "
assert_eq "git_dirty_hub_paths prints nothing when the dirt is all outside hub/" "$(printf ' M cloud/docker-compose.override.yml\n?? docs/notes.md\n' | git_dirty_hub_paths)" ""
assert_eq "git_dirty_hub_paths on an empty status prints nothing" "$(printf '' | git_dirty_hub_paths)" ""

# --- env_put never puts a VALUE on argv (final review, Critical 1) ----------
# A static guard over clinic/install/lib.sh's env_put, the one function every
# secret this fleet writes passes through -- hub/.env's eleven, every clinic
# answer file's four. argv is world-readable for the life of the process
# (`ps -ef`, /proc/<pid>/cmdline), so the value goes through the environment
# instead. Proving the class, not one call: the python3 substep must read the
# value from os.environ, and must never read a third sys.argv element (the
# file and the key, neither secret, are argv 1 and 2).
env_put_src="$(awk '/^env_put\(\)\{/{f=1} f{print} f && /^}/{exit}' "${REPO_DIR}/clinic/install/lib.sh")"
assert_eq "env_put's python3 substep reads the value from the environment" "$(printf '%s' "$env_put_src" | grep -c 'os\.environ\["ENV_PUT_VALUE"\]')" "1"
assert_eq "env_put's python3 substep never reads a third argv element" "$(printf '%s' "$env_put_src" | grep -c 'sys\.argv\[3\]')" "0"
assert_eq "env_put passes only the file and the key on the command line" "$(printf '%s' "$env_put_src" | grep -c 'python3 - "\$f" "\$k" "\$v"')" "0"
assert_eq "env_put hands the value over as ENV_PUT_VALUE" "$(printf '%s' "$env_put_src" | grep -c 'ENV_PUT_VALUE="\$v" python3 - "\$f" "\$k"')" "1"
# ...and it still round-trips a value with shell metacharacters, and still
# refuses a single quote outright (the quoting contract is unchanged).
rt="$TMP/roundtrip.env"; : > "$rt"
env_put "$rt" TRICKY 'a b"c$d`e;f#g'
assert_eq "env_put round-trips a value full of shell metacharacters" "$(env_get "$rt" TRICKY)" 'a b"c$d`e;f#g'
assert_eq "the written line is single-quoted" "$(grep '^TRICKY=' "$rt")" "TRICKY='a b\"c\$d\`e;f#g'"
( env_put "$rt" QUOTED "it's" ) >/dev/null 2>&1; rc=$?
assert_eq "env_put still refuses a value containing a single quote" "$rc" "1"

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

# kafka_ui_login_ok (Fix round 1, code review Critical 1): a static guard
# over its own source in hub/install/lib.sh, not a live call (the live smoke
# is the real proof) -- the whole point of the fix was that
# KAFKA_UI_USER/KAFKA_UI_PASSWORD must never be visible in any process's own
# argv (`ps -ef` / /proc/<pid>/cmdline) for as long as it runs, and the
# previous shape passed both as positional arguments to `python3 -c`. Proving
# the class: the function's python3 substep must read os.environ, and must
# never reference sys.argv at all (there is nothing for it to read there --
# the shell function itself takes only URL as an argument).
fn_src="$(awk '/^kafka_ui_login_ok\(\)\{/{f=1} f{print} f && /^}/{exit}' "$HERE/../lib.sh")"
assert_eq "kafka_ui_login_ok's python3 substep never references sys.argv" "$(printf '%s' "$fn_src" | grep -c 'sys\.argv')" "0"
assert_eq "kafka_ui_login_ok's python3 substep reads os.environ instead (once for the user, once for the password)" "$(printf '%s' "$fn_src" | grep -c 'os\.environ')" "2"
pat_url_arg='local url="$1"'
assert_eq "kafka_ui_login_ok takes only URL as its own argument (no user/password params)" "$(printf '%s' "$fn_src" | grep -Fc "$pat_url_arg")" "1"
pat_chmod='chmod 600 "$body" "$cookie_jar"'
assert_eq "kafka_ui_login_ok's temp files are mode 600" "$(printf '%s' "$fn_src" | grep -Fc "$pat_chmod")" "1"
pat_trap='trap '"'"'rm -f "$body" "$cookie_jar"'"'"' EXIT'
assert_eq "kafka_ui_login_ok cleans up in a subshell-scoped trap (not a function-level one, which would replace the caller's own trap)" "$(printf '%s' "$fn_src" | grep -Fc "$pat_trap")" "1"


# --- Azure rehearsal stop 4 (2026-09-18): the hub's REMOTE_MYSQL_* never inherit
# the clinic package's placeholders from the base .env (they described the
# hub's OWN MySQL for the up-sinks), and placeholder values are refused.
mkdir -p "$TMP/hub-ph"; OUTP="$TMP/hub-ph/.env"
cp "$TMP/base.env" "$TMP/base-ph.env"
printf 'REMOTE_MYSQL_HOST=unused.invalid\nREMOTE_MYSQL_USER=unused\nREMOTE_MYSQL_PASSWORD=unused\n' >> "$TMP/base-ph.env"
( unset REMOTE_MYSQL_HOST REMOTE_MYSQL_USER REMOTE_MYSQL_PASSWORD; HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base-ph.env" "$TMP/secrets.env" "$OUTP" >/dev/null )
assert_eq "REMOTE_MYSQL_HOST derives from BASE_MYSQL_CONTAINER, not the base .env placeholder" "$(env_get "$OUTP" REMOTE_MYSQL_HOST)" "$(env_get "$OUTP" BASE_MYSQL_CONTAINER)"
assert_eq "REMOTE_MYSQL_USER defaults to the fleet user, not the base .env placeholder" "$(env_get "$OUTP" REMOTE_MYSQL_USER)" "sink"
pwv="$(env_get "$OUTP" REMOTE_MYSQL_PASSWORD)"
[ -n "$pwv" ] && [ "$pwv" != unused ] && ok "REMOTE_MYSQL_PASSWORD is generated, never the base .env placeholder" || { bad "REMOTE_MYSQL_PASSWORD inherited a placeholder or is empty"; fails=$((fails+1)); }
( REMOTE_MYSQL_USER=custom_sink HUB_ENV="$TMP/hub.env" hub_compose_env "$TMP/base-ph.env" "$TMP/secrets.env" "$OUTP" >/dev/null )
assert_eq "REMOTE_MYSQL_USER from the install command's environment wins on a rerun" "$(env_get "$OUTP" REMOTE_MYSQL_USER)" "custom_sink"
for v in unused unused.invalid db.example.com XXXX changeme; do placeholder_value "$v" && ok "placeholder_value rejects '$v'" || { bad "placeholder_value accepted '$v'"; fails=$((fails+1)); }; done
for v in sink iplit-base-openmrsdb-1 openmrs 3306; do placeholder_value "$v" && { bad "placeholder_value rejected the real value '$v'"; fails=$((fails+1)); } || ok "placeholder_value accepts '$v'"; done

printf '%s\n' "$fails failure(s)"; exit $((fails>0))
