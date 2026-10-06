#!/usr/bin/env bash
# Grant this clinic's sink database user what the down sinks need on every
# table hub/tables.conf lists: SELECT, INSERT, UPDATE and DELETE, table by
# table, then read the grants back. Seed task 050 does the same on a node it
# seeds; this is for a node seeded before a table joined that file, whose new
# down sink would otherwise be refused its first INSERT. Safe to re-run.
#
#   clinic/scripts/grant-down-tables.sh [--dry-run]
#
# --dry-run prints the grants and changes nothing.
#
# After it: regenerate and register the down sinks so the new table has one
#   cd clinic && bash scripts/generate-local-sink-connectors.sh && bash scripts/register-local-sink-connectors.sh
#
# Reads COMPOSE_PROJECT_NAME from clinic/.env and runs mysql as root inside
# <project>-bahmni-mysql-1. RUNTIME=docker|podman overrides the platform's
# default runtime, as for the installer.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
# hub/tables.conf is read from the checkout this script is in
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
. "${HERE}/../install/lib.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
DRYRUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "unknown argument: $1" ;;
  esac
done
begin_task "grant the sink user the down tables$( [ "$DRYRUN" = 1 ] && printf ' (dry run: nothing changes)')"
sql="$(sink_grant_sql)" || fail "could not build the grants from hub/tables.conf"
if [ "$DRYRUN" = 1 ]; then
  printf '%s\n' "$sql" | sed 's/^/    /'
  log "dry run: nothing changed."
  exit 0
fi
E="${CLINIC_DIR}/.env"
[ -f "$E" ] || fail "no ${E}: this is not an installed node"
COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
[ -n "${COMPOSE_PROJECT_NAME}" ] || fail "clinic/.env has no COMPOSE_PROJECT_NAME"
[ -n "${CT:-}" ] || setup_compose
MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
mysql_root(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N'; }
users="$(printf "select count(*) from mysql.user where User='sink' and Host='%%'\n" | mysql_root)" \
  || fail "could not query MySQL in ${MY}: is it running? (${COMPOSE_CMD:-compose} ps bahmni-mysql)"
[ "$users" = 1 ] || fail "MySQL in ${MY} has no sink user: this node has not been seeded (seed task 050 creates the user with its grants)"
have="$(printf "select table_name from information_schema.tables where table_schema='openmrs'\n" | mysql_root)"
absent=""
for t in $(down_tables); do printf '%s\n' "$have" | grep -qx "$t" || absent="${absent} ${t}"; done
[ -z "$absent" ] || fail "openmrs in ${MY} has no table:${absent}. hub/tables.conf names a table this database lacks; nothing was granted"
printf '%s\nFLUSH PRIVILEGES;\n' "$sql" | mysql_root || fail "the grants failed in ${MY}"
missing="$(printf '%s\n' "${SINK_GRANTS_READ_SQL}" | mysql_root | sink_grants_missing)" || fail "could not read back the sink user's grants"
[ -z "$missing" ] || fail "after granting, the sink user still lacks SELECT, INSERT, UPDATE or DELETE on: $(printf '%s' "$missing" | tr '\n' ' ')"
ok "sink user holds SELECT, INSERT, UPDATE, DELETE on every down table: $(down_tables | tr '\n' ' ')"
log "next: regenerate and register the down sinks (cd clinic && bash scripts/generate-local-sink-connectors.sh && bash scripts/register-local-sink-connectors.sh)"
