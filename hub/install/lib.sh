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
HUB_KEYS="KAFKA_CLUSTER_ID REMOTE_KAFKA_HOST KAFKA_BASE_NETWORK KAFKA_ADMIN_PASSWORD REMOTE_KAFKA_PASSWORD DEBEZIUM_DB_USER DEBEZIUM_DB_PASSWORD REMOTE_MYSQL_HOST REMOTE_MYSQL_PORT REMOTE_MYSQL_DATABASE REMOTE_MYSQL_USER REMOTE_MYSQL_PASSWORD REMOTE_MYSQL_USE_SSL ODOO_SINK_PASSWORD CLINLIMS_SINK_PASSWORD CLOUD_MYSQL_SERVER_NAME CLOUD_DEBEZIUM_SERVER_ID KAFKA_CONNECT_URL BASE_MYSQL_ROOT_PASSWORD BASE_PG_SUPERUSER BASE_PG_PASSWORD BASE_MYSQL_CONTAINER BASE_PG_CONTAINER ODOO_DB_PASSWORD CLINLIMS_SOURCE_PASSWORD REMOTE_SERVER_NAME"

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
  put ODOO_DB_PASSWORD "$(env_get "$base" ODOO_DB_PASSWORD)"
  put CLINLIMS_SOURCE_PASSWORD "$(env_get "$base" OPENELIS_DB_PASSWORD)"
  put REMOTE_SERVER_NAME bahmni-cloud
  versions_put "$out"   # every fleet pin from sync/versions.env (L-005: one place)
  for k in $HUB_KEYS; do [ -n "$(env_get "$out" "$k")" ] || [ "$k" = BASE_PG_PASSWORD ] || fail "hub .env is missing $k"; done
}

# hub_base_container ROLE : the base stack's container name for the given
# role, read back from hub/.env (hub_compose_env's OUT) -- for hub scripts
# that docker/podman exec into the base stack's MySQL or Postgres.
hub_base_container(){
  case "$1" in
    mysql) env_get "${HUB_DIR}/.env" BASE_MYSQL_CONTAINER ;;
    pg)    env_get "${HUB_DIR}/.env" BASE_PG_CONTAINER ;;
    *) fail "hub_base_container: unknown role $1" ;;
  esac
}

# jaas_escape STR : backslash-escapes a value for safe embedding inside a
# double-quoted JAAS/Java-properties string. Order matters -- backslashes
# first, then quotes -- so a literal backslash already in the input is never
# re-escaped by the quote pass (Fix round 1, code review Finding 1): an
# operator-typed REMOTE_KAFKA_PASSWORD containing a '"' or '\' would otherwise
# break the quoting of whatever file it lands in.
jaas_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

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
# what they are or vary by DB.
mysql_user_sql(){
  local ver="$1" user="$2" pw="$3" db="$4"
  case "$ver" in
    5.*)
      printf "GRANT USAGE ON %s.* TO '%s'@'%%' IDENTIFIED BY '%s';\nSET PASSWORD FOR '%s'@'%%' = PASSWORD('%s');\n" \
        "$db" "$user" "$pw" "$user" "$pw"
      ;;
    *)
      printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\nALTER USER '%s'@'%%' IDENTIFIED BY '%s';\n" \
        "$user" "$pw" "$user" "$pw"
      ;;
  esac
}
