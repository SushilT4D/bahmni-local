#!/usr/bin/env bash
# apply-clinlims-down-publication.sh -- PSQL-COMMAND...
#
# Converges the hub's OpenELIS down publication, dbz_clinlims_owned, to exactly
# the OpenELIS rows of the down list (sync/hub-down.conf through
# sync/hub-down.sh clinlims), with no row filter, plus clinlims.dbz_heartbeat.
# hub/openelis/apply-down-publication.sql does the work and refuses, naming the
# table, a missing table or one without a replica identity. Prints
# "<table> <row filter>" per published table on success ("-": none).
#
# PSQL-COMMAND reaches the hub's OpenELIS database as a role that may alter the
# publication, for example: docker exec -i <openelis-db-container> psql -U clinlims -d openelis
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: apply-clinlims-down-publication.sh -- <psql command...>" >&2; exit 2; }
die(){ printf 'apply-clinlims-down-publication.sh: %s\n' "$*" >&2; exit 1; }
tables="$(bash "$HERE/../../sync/hub-down.sh" clinlims)" || die "the down list could not be read (reason above); the publication was not touched"
tables="$(printf '%s\n' "$tables" | paste -sd, -)"
out="$("$@" -v ON_ERROR_STOP=1 -qAt -v pub=dbz_clinlims_owned -v tables="$tables" -f /dev/stdin < "$HERE/../openelis/apply-down-publication.sql" 2>&1)" \
  || die "dbz_clinlims_owned was refused: $(printf '%s\n' "$out" | sed -n 's/^.*ERROR: *//p' | head -1)"
printf '%s\n' "$out"
