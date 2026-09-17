#!/usr/bin/env bash
# The hub installer's library: the clinic installer's helpers (logging, ERR trap,
# .env editing, runtime detection, waits) sourced with the hub as the compose dir,
# plus what only a hub needs. bash 3.2 compatible like its parent.
HUB_INSTALL_DIR="${HUB_INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HUB_DIR="${HUB_DIR:-$(cd "${HUB_INSTALL_DIR}/.." && pwd)}"
# Derived from HUB_INSTALL_DIR, not HUB_DIR: a test overrides HUB_DIR alone (to
# point hub_compose_env's OUT at a tmp dir instead of the real hub/), and a
# REPO_DIR computed from that override would resolve to the tmp dir's parent
# instead of this checkout -- the nested source below would then fail to find
# clinic/install/lib.sh. HUB_INSTALL_DIR is always this file's own real
# location, so REPO_DIR stays correct regardless of any HUB_DIR override.
REPO_DIR="${REPO_DIR:-$(cd "${HUB_INSTALL_DIR}/../.." && pwd)}"
# The clinic lib derives CLINIC_DIR from its own path and runs compose there with
# the clinic profiles; for the hub both are overridden before sourcing. Nothing
# clinic-specific it defines is called from hub tasks.
CLINIC_DIR="${HUB_DIR}" PROFILES="" INSTALL_DIR="${REPO_DIR}/clinic/install" . "${REPO_DIR}/clinic/install/lib.sh"
PROFILES=""
HUB_ENV="${HUB_ENV:-${REPO_DIR}/sync/hub.env}"
HUB_KEYS="KAFKA_CLUSTER_ID REMOTE_KAFKA_HOST KAFKA_BASE_NETWORK KAFKA_ADMIN_PASSWORD REMOTE_KAFKA_PASSWORD DEBEZIUM_DB_USER DEBEZIUM_DB_PASSWORD REMOTE_MYSQL_HOST REMOTE_MYSQL_PORT REMOTE_MYSQL_DATABASE REMOTE_MYSQL_USER REMOTE_MYSQL_PASSWORD REMOTE_MYSQL_USE_SSL ODOO_SINK_PASSWORD CLINLIMS_SINK_PASSWORD CLOUD_MYSQL_SERVER_NAME CLOUD_DEBEZIUM_SERVER_ID KAFKA_CONNECT_URL BASE_MYSQL_ROOT_PASSWORD BASE_PG_SUPERUSER BASE_PG_PASSWORD BASE_MYSQL_CONTAINER BASE_PG_CONTAINER BASE_ELIS_CONTAINER BASE_ELIS_SUPERUSER ODOO_DB_PASSWORD CLINLIMS_SOURCE_PASSWORD REMOTE_SERVER_NAME CLOUD_MYSQL_HOST CLOUD_MYSQL_PORT CLOUD_MYSQL_DATABASE KAFKA_UI_USER KAFKA_UI_PASSWORD"

# KAFKA_CONTAINER: the docker/podman container NAME hub tasks `exec` into for
# kafka-configs/kafka-topics calls (080-sources.sh, and
# clinic/scripts/set-schema-history-retention.sh, shared with the clinic).
# Always "kafka" in production -- hub/docker-compose.yml pins that exact
# container_name, and nothing about a real deployment ever needs it to
# differ. Deliberately NOT HUB_KEYS/hub/.env material: unlike
# KAFKA_CONNECT_URL, there is no per-deployment reason for this to vary.
# The one legitimate override is hub/install/tests/test_sources.sh, which
# must run these same tasks for real beside another real stack that already
# holds the bare name on this host's docker daemon, and so renames its own
# throwaway container and exports this before invoking the tasks.
#
# CONNECT_CONTAINER (its former sibling here) was removed (code review
# fold-in, Task 6/7 review): every hub task that talks to Kafka Connect does
# so over its REST API (CONNECT_URL), never `ct exec` into the container by
# name, so the variable was defined and exported but read by nothing.
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"

# hub_compose_env BASE_ENV SECRETS OUT : write hub/.env from the fleet pointer
# (sync/hub.env), the base stack's .env (root credentials, existing sink
# passwords) and the operator's secrets file (the fleet SASL password). Values
# already in OUT are kept, so a resume never regenerates a secret.
hub_compose_env(){
  local base="$1" secrets="$2" out="$3" k v
  [ -f "$base" ] || fail "base .env not found: $base"
  [ -f "$secrets" ] || fail "secrets file not found: $secrets"
  [ -f "$HUB_ENV" ] || fail "hub endpoint file missing: $HUB_ENV"
  ( umask 077; [ -f "$out" ] || : > "$out" ); chmod 600 "$out"
  # shellcheck disable=SC1090
  local bs="$(set -a; . "$HUB_ENV"; set +a; printf '%s' "${REMOTE_KAFKA_BOOTSTRAP_SERVERS:?}")"
  put(){ [ -n "$(env_get "$out" "$1")" ] || env_put "$out" "$1" "$2"; }
  put REMOTE_KAFKA_HOST "${bs%%:*}"
  put KAFKA_BASE_NETWORK "${KAFKA_BASE_NETWORK:-cloud_default}"
  put KAFKA_CLUSTER_ID "$(kafka_cluster_id)"
  put KAFKA_ADMIN_PASSWORD "$(gen_secret)"
  put REMOTE_KAFKA_PASSWORD "$(env_get "$secrets" REMOTE_KAFKA_PASSWORD)"
  put DEBEZIUM_DB_USER debezium
  put DEBEZIUM_DB_PASSWORD "$(v="$(env_get "$base" DEBEZIUM_DB_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put REMOTE_MYSQL_HOST "$(v="$(env_get "$base" REMOTE_MYSQL_HOST)"; printf '%s' "${v:-openmrsdb}")"
  put REMOTE_MYSQL_PORT "$(v="$(env_get "$base" REMOTE_MYSQL_PORT)"; printf '%s' "${v:-3306}")"
  put REMOTE_MYSQL_DATABASE "$(v="$(env_get "$base" OPENMRS_DB_NAME)"; printf '%s' "${v:-openmrs}")"
  put REMOTE_MYSQL_USER "$(v="$(env_get "$base" REMOTE_MYSQL_USER)"; printf '%s' "${v:-sink}")"
  put REMOTE_MYSQL_PASSWORD "$(v="$(env_get "$base" REMOTE_MYSQL_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put REMOTE_MYSQL_USE_SSL false
  put ODOO_SINK_PASSWORD "$(v="$(env_get "$base" ODOO_SINK_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put CLINLIMS_SINK_PASSWORD "$(v="$(env_get "$base" CLINLIMS_SINK_PASSWORD)"; printf '%s' "${v:-$(gen_secret)}")"
  put CLOUD_MYSQL_SERVER_NAME bahmni-cloud
  put CLOUD_DEBEZIUM_SERVER_ID 184060
  put KAFKA_CONNECT_URL http://localhost:8083
  put BASE_MYSQL_ROOT_PASSWORD "$(env_get "$base" MYSQL_ROOT_PASSWORD)"
  put BASE_PG_SUPERUSER "$(v="$(env_get "$base" POSTGRES_USER)"; printf '%s' "${v:-postgres}")"
  put BASE_PG_PASSWORD "$(env_get "$base" POSTGRES_PASSWORD)"
  put BASE_MYSQL_CONTAINER "${BASE_MYSQL_CONTAINER:-cloud-openmrsdb-1}"
  put BASE_PG_CONTAINER "${BASE_PG_CONTAINER:-cloud-openelisdb-1}"
  # BASE_ELIS_CONTAINER / BASE_ELIS_SUPERUSER: one container serves both
  # databases on the mini and every clinic, so these default straight from
  # the BASE_PG_* values just set above (read back from $out, same reason
  # CLOUD_MYSQL_HOST reads BASE_MYSQL_CONTAINER back below rather than the
  # shell variable -- a pre-existing value already in $out must win over a
  # fresh default). IPLIT's real hub base is the one deployment that differs:
  # it runs Odoo and OpenELIS in two separate Postgres containers with
  # different bootstrap superusers (iplit-base-odoodb-1/odoo,
  # iplit-base-openelisdb-1/clinlims -- docs/sync-core/runbooks/hub-build-and-
  # connect.md's container table), where an operator sets both keys
  # explicitly before running the installer.
  put BASE_ELIS_CONTAINER "$(env_get "$out" BASE_PG_CONTAINER)"
  put BASE_ELIS_SUPERUSER "$(env_get "$out" BASE_PG_SUPERUSER)"
  # The down-source dials the base stack's own MySQL by container name on the
  # shared KAFKA_BASE_NETWORK (Docker resolves it), so its default is simply
  # whatever BASE_MYSQL_CONTAINER was just set to above -- read back from $out,
  # not from the shell variable, so a pre-existing BASE_MYSQL_CONTAINER value
  # already in $out (not just an env override) is still picked up correctly.
  put CLOUD_MYSQL_HOST "$(env_get "$out" BASE_MYSQL_CONTAINER)"
  put CLOUD_MYSQL_PORT 3306
  put CLOUD_MYSQL_DATABASE openmrs
  put ODOO_DB_PASSWORD "$(env_get "$base" ODOO_DB_PASSWORD)"
  put CLINLIMS_SOURCE_PASSWORD "$(env_get "$base" OPENELIS_DB_PASSWORD)"
  put REMOTE_SERVER_NAME bahmni-cloud
  # kafka-ui (Ruling 3): a login the operator actually knows, not a bare
  # generated username -- "admin" is not a secret, so it is a fixed default
  # rather than something `put`'s already-set-wins guard needs to protect
  # from being clobbered on resume (it never generates a fresh one after the
  # first run either way, same as every other `put` here).
  put KAFKA_UI_USER admin
  put KAFKA_UI_PASSWORD "$(gen_secret)"
  versions_put "$out"   # every fleet pin from sync/versions.env (L-005: one place)
  for k in $HUB_KEYS; do [ -n "$(env_get "$out" "$k")" ] || [ "$k" = BASE_PG_PASSWORD ] || fail "hub .env is missing $k"; done
}

# hub_base_container ROLE : the base stack's container name for the given
# role, read back from hub/.env (hub_compose_env's OUT) -- for hub scripts
# that docker/podman exec into the base stack's MySQL or Postgres.
hub_base_container(){
  local v
  case "$1" in
    mysql) env_get "${HUB_DIR}/.env" BASE_MYSQL_CONTAINER ;;
    pg)    env_get "${HUB_DIR}/.env" BASE_PG_CONTAINER ;;
    # elis: BASE_ELIS_CONTAINER if hub/.env carries it (always true once
    # composed by hub_compose_env, which defaults it), falling back to
    # BASE_PG_CONTAINER for an .env written before this key pair existed.
    elis)
      v="$(env_get "${HUB_DIR}/.env" BASE_ELIS_CONTAINER)"
      printf '%s' "${v:-$(env_get "${HUB_DIR}/.env" BASE_PG_CONTAINER)}"
      ;;
    *) fail "hub_base_container: unknown role $1" ;;
  esac
}

# pg_admin DB ARGS... : psql as the base Postgres superuser, for whichever
# container actually hosts DB -- "openelis" routes to BASE_ELIS_CONTAINER/
# BASE_ELIS_SUPERUSER (IPLIT's real hub base runs Odoo and OpenELIS in two
# separate Postgres containers with different bootstrap superusers), every
# other DB (odoo, and the bare "postgres" maintenance db some callers use)
# stays on BASE_PG_CONTAINER/BASE_PG_SUPERUSER. One contract, hoisted here
# (code review fold-in, Task 6/7 review): 050-base-db.sh and 080-sources.sh
# each used to define their own `pg_admin` with a DIFFERENT argument shape
# (050's took a db name and dispatched; 080's took a container+superuser
# directly), a naming collision waiting to bite the next person who greps for
# one and edits the other. Both tasks now call this one. ARGS are passed
# straight to psql -- a heredoc/pipe on stdin, or -Atc "SQL", or -f/-v as
# 050-base-db.sh already does -- with no masking here; a caller whose SQL
# carries a secret masks it the way 050-base-db.sh's own pg_admin_pw wraps
# this function for the two sink-role passwords. Reads BASE_PG_CONTAINER/
# BASE_PG_SUPERUSER/BASE_ELIS_CONTAINER/BASE_ELIS_SUPERUSER from the caller's
# already-sourced hub/.env; the BASE_ELIS_* fallback mirrors hub_compose_env's
# own default (an .env composed before that key pair existed).
pg_admin(){
  local db="$1" ct_name="${BASE_PG_CONTAINER:?pg_admin: BASE_PG_CONTAINER not set}" su="${BASE_PG_SUPERUSER:?pg_admin: BASE_PG_SUPERUSER not set}"
  if [ "$db" = openelis ]; then
    ct_name="${BASE_ELIS_CONTAINER:-$ct_name}"
    su="${BASE_ELIS_SUPERUSER:-$su}"
  fi
  shift
  ct exec -i "$ct_name" psql -U "$su" -d "$db" -v ON_ERROR_STOP=1 -q "$@"
}

# jaas_escape STR : backslash-escapes a value for safe embedding inside a
# double-quoted JAAS/Java-properties string. Order matters -- backslashes
# first, then quotes -- so a literal backslash already in the input is never
# re-escaped by the quote pass (Fix round 1, code review Finding 1): an
# operator-typed REMOTE_KAFKA_PASSWORD containing a '"' or '\' would otherwise
# break the quoting of whatever file it lands in.
jaas_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# pg_lit_escape STR : doubles every single quote, for safe embedding inside a
# single-quoted Postgres string literal ('...'). Postgres string literals do
# not treat backslash specially (standard_conforming_strings, the default
# since 9.1), so nothing else needs escaping -- an operator-typed
# ODOO_SINK_PASSWORD/CLINLIMS_SINK_PASSWORD containing a "'" would otherwise
# break out of the ALTER ROLE ... PASSWORD '...' literal it lands in
# (Fix round 2).
pg_lit_escape(){ printf '%s' "$1" | sed "s/'/''/g"; }

# mysql_lit_escape STR : backslash-escapes a value for safe embedding inside a
# single-quoted MySQL string literal ('...'). Unlike Postgres, MySQL string
# literals DO treat backslash as an escape character, so it needs the same
# two-pass order as jaas_escape above -- backslashes first, then quotes -- so
# a literal backslash already in the input is never re-escaped by the quote
# pass. An operator-typed REMOTE_MYSQL_PASSWORD/DEBEZIUM_DB_PASSWORD
# containing a "'" or "\" would otherwise break the IDENTIFIED BY '...'
# clause mysql_user_sql builds below (Fix round 2).
mysql_lit_escape(){ printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }

# mask_env_secrets NAME... : reads stdin, replaces the CURRENT value of each
# named environment variable with <hidden> -- a literal substring replace
# (Python's str.replace, not a sed regex), so a password containing any
# sed/regex-special character (., *, [, ], ^, $, \, or the delimiter itself,
# "/") can never break the mask or leak past it the way
# `sed "s/${SECRET}/<hidden>/g"` did (Fix round 2, code review: that pattern
# breaks -- or silently mis-substitutes -- the moment a secret contains a "/"
# or a regex metacharacter). Only variable NAMES are ever passed as
# arguments (never secret values); mask_env_secrets reads the actual values
# from its own inherited environment, so a secret never touches this
# process's own argv either. A name that is unset or empty is skipped, not
# replaced -- Python's str.replace(data, "", "<hidden>") would otherwise
# insert "<hidden>" between every character.
mask_env_secrets(){
  python3 -c '
import os, sys
data = sys.stdin.read()
for name in sys.argv[1:]:
    val = os.environ.get(name, "")
    if val:
        data = data.replace(val, "<hidden>")
sys.stdout.write(data)
' "$@"
}

# write_jaas OUT ADMIN_PW FLEET_PW : the broker's SASL/PLAIN users. Generated from
# hub/.env at install time -- cloud/kafka_server_jaas.conf was TRACKED with literal
# passwords since the repo's first commit (public repo), hence F-071. Both
# passwords are escaped before interpolation (Fix round 1).
write_jaas(){
  local out="$1" adm fleet
  adm="$(jaas_escape "$2")"; fleet="$(jaas_escape "$3")"
  ( umask 077; printf 'KafkaServer {\n    org.apache.kafka.common.security.plain.PlainLoginModule required\n    username="admin"\n    password="%s"\n    user_admin="%s"\n    user_mirrormaker="%s";\n};\n' "$adm" "$adm" "$fleet" > "$out" )
  chmod 600 "$out"
}

# sasl_listener_ok : proves the broker's published SASL_PLAINTEXT listener
# authenticates the mirrormaker user, dialed from the HOST network on the
# PUBLISHED port -- never by dialing REMOTE_KAFKA_HOST from inside the
# broker's own container (an Azure VM cannot reach its own public IP).
# Extracted here (code review fold-in, Task 6/7 review) so task 060 (right
# after the broker first comes up) and task 090 (the exit checks, proving it
# is STILL true at the end) share one definition instead of two copies
# drifting apart. Same ok-or-named-reason contract as binlog_ok above: prints
# nothing and returns 0 on success, prints the reason and returns 1
# otherwise. Reads KAFKA_IMAGE/REMOTE_KAFKA_HOST/REMOTE_KAFKA_PASSWORD from
# the caller's already-sourced hub/.env; requires setup_compose to have run
# (uses ct). The check's own password never touches a command line, a log, or
# a tracked file: written by the printf builtin (no subprocess ever sees it
# in argv) to a mode-600 temp file under HUB_DIR, removed before this
# function returns on every path.
#
# SASL_LISTENER_PORT overrides which published host port is dialed (default
# 9092, production's real value): hub/install/tests/test_sources.sh's
# throwaway broker cannot publish 9092 itself (this host may already run a
# real hub bound to it), so it republishes the same internal SASL listener on
# a throwaway host port instead and sets this to match -- the one legitimate
# override, the same shape as KAFKA_CONTAINER/CONNECT_URL.
sasl_listener_ok(){
  local tmp esc_pw rc=0 port="${SASL_LISTENER_PORT:-9092}"
  tmp="$(mktemp "${HUB_DIR}/.sasl-check.XXXXXX")"
  chmod 600 "$tmp"
  esc_pw="$(jaas_escape "${REMOTE_KAFKA_PASSWORD:?sasl_listener_ok: REMOTE_KAFKA_PASSWORD not set}")"
  printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=PLAIN\nsasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="mirrormaker" password="%s";\n' "$esc_pw" > "$tmp"
  ct run --rm --network host -v "${tmp}:/tmp/c.properties:ro" "${KAFKA_IMAGE:?sasl_listener_ok: KAFKA_IMAGE not set}" kafka-broker-api-versions --bootstrap-server "127.0.0.1:${port}" --command-config /tmp/c.properties >/dev/null 2>&1 || rc=$?
  rm -f "$tmp"
  [ "$rc" = 0 ] && return 0
  printf 'SASL listener did not answer on 127.0.0.1:%s as mirrormaker (image %s)\n' "$port" "${KAFKA_IMAGE}"
  return 1
}

# binlog_ok FORMAT IMAGE RETENTION_S SERVER_ID INCREMENT OFFSET CONNECTOR_ID : the
# base MySQL is fit for a Debezium source and the hub's striding (residue 0).
binlog_ok(){
  local f="$1" i="$2" r="$3" s="$4" inc="$5" off="$6" cid="$7" bad=''
  [ "$f" = ROW ] || bad="$bad binlog_format=$f"
  [ "$i" = FULL ] || bad="$bad binlog_row_image=$i"
  [ "${r:-0}" -ge 604800 ] || bad="$bad retention=${r}s(<7d)"
  [ "$s" != "$cid" ] || bad="$bad server_id=$s(equals the connector id, F-059)"
  [ "$inc" = 10 ] || bad="$bad auto_increment_increment=$inc"
  [ "$off" = 10 ] || bad="$bad auto_increment_offset=$off(the hub is residue 0)"
  [ -z "$bad" ] && return 0; printf '%s\n' "$bad"; return 1
}

# mysql_major_ok VERSION : true (rc 0) iff VERSION's major component is a fit
# for Debezium 3.6.2 (MySQL 8.0.x only -- 5.6/5.7 are not, though task 000's
# own binlog-fitness checks tolerate them). VERSION is whatever `select
# version()` returned, e.g. "8.0.39" or "5.7.44-log". Prints the reason and
# returns 1 when it is not a fit, same ok-or-named-reason contract as
# binlog_ok above. Extracted from 080-sources.sh (code review fold-in, Task 6
# review: this comparison used to be inlined there with no test of its own) --
# pure text logic, no docker, so it is testable directly.
mysql_major_ok(){
  local ver="$1" major="${1%%.*}"
  case "$major" in
    ''|*[!0-9]*) printf 'could not read a numeric MySQL major version (got %s)\n' "$ver"; return 1 ;;
  esac
  [ "$major" -ge 8 ] && return 0
  printf 'mysql %s is below major version 8 -- Debezium 3.6.2 supports MySQL 8.0.x only\n' "$ver"
  return 1
}

# slot_wait_state ROW SLOT : classifies a psql read-back ROW (the exact
# "<slot_name>|<active>" text a `select slot_name || '|' || active from
# pg_replication_slots where slot_name = '<slot>'` -At query produces) against
# SLOT -- "active" (the slot exists and is active), "inactive" (exists, not
# yet active) or "missing" (no such row, including an empty ROW: the slot not
# created yet). Extracted from 080-sources.sh's wait_slot (code review
# fold-in, Task 6 review) -- pure and side-effect free, so it is testable
# directly against the real shapes psql -At produces: dbz_odoo_down|true,
# dbz_odoo_down|false, empty.
slot_wait_state(){
  case "$1" in
    "${2}|true")  printf 'active\n' ;;
    "${2}|false") printf 'inactive\n' ;;
    *)            printf 'missing\n' ;;
  esac
}

# mysql_user_sql VERSION USER PASSWORD DB : SQL text (on stdout) that creates
# the MySQL account named USER if it does not already exist, and converges
# its password to PASSWORD either way -- version-branched because MySQL 8.0
# removed `GRANT ... IDENTIFIED BY`, which is 5.x's idiom (still needed for the
# Azure hub's MySQL 5.6 base image) for creating an account with a password in
# one statement. DB scopes the placeholder grant 5.x needs to create an
# account at all; USAGE is MySQL's "no real privilege" grant, so this carries
# none of the privileges the caller actually wants -- the caller issues those
# itself, in its own GRANT (identical syntax on 5.x and 8.0 once IDENTIFIED BY
# is out of it), once per privilege set, so this function never needs to know
# what they are or vary by DB. PASSWORD is escaped (mysql_lit_escape) before
# it is interpolated into either IDENTIFIED BY literal, not used raw (Fix
# round 2) -- interpolating it raw would let an operator-typed password
# containing "'" break out of the literal it lands in.
mysql_user_sql(){
  local ver="$1" user="$2" db="$4" esc_pw
  esc_pw="$(mysql_lit_escape "$3")"
  case "$ver" in
    5.*)
      printf "GRANT USAGE ON %s.* TO '%s'@'%%' IDENTIFIED BY '%s';\nSET PASSWORD FOR '%s'@'%%' = PASSWORD('%s');\n" \
        "$db" "$user" "$esc_pw" "$user" "$esc_pw"
      ;;
    *)
      printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\nALTER USER '%s'@'%%' IDENTIFIED BY '%s';\n" \
        "$user" "$esc_pw" "$user" "$esc_pw"
      ;;
  esac
}
