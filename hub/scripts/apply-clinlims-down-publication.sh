#!/usr/bin/env bash
# apply-clinlims-down-publication.sh FLOORS-FILE -- PSQL-COMMAND...
#
# Converges the hub's OpenELIS down publication, dbz_clinlims_owned, to exactly
# the OpenELIS rows of the down list (sync/hub-down.conf through
# sync/hub-down.sh clinlims), plus clinlims.dbz_heartbeat: the rows routed to
# one clinic with no row filter, the rows that go to every clinic
# (sync/hub-down.sh --unrouted clinlims: the lab accounts and the lab test
# catalogue) with (id < <floor> OR id % 10 = 0) on this hub's floor from
# FLOORS-FILE (hub/clinlims-down-floors.local), each of those without an id
# column (a link table) with no row filter.
# hub/openelis/apply-down-publication.sql does the work and refuses, naming the
# table, a missing table, one without a replica identity (covering id, when
# filtered), or a missing floor. Prints "<table> <row filter>" per published
# table on success ("-": none).
#
# PSQL-COMMAND reaches the hub's OpenELIS database as a role that may alter the
# publication, for example: docker exec -i <openelis-db-container> psql -U clinlims -d openelis
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${1:?usage: apply-clinlims-down-publication.sh <floors file> -- <psql command...>}"; shift
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: apply-clinlims-down-publication.sh <floors file> -- <psql command...>" >&2; exit 2; }
die(){ printf 'apply-clinlims-down-publication.sh: %s\n' "$*" >&2; exit 1; }
tables="$(bash "$HERE/../../sync/hub-down.sh" clinlims)" || die "the down list could not be read (reason above); the publication was not touched"
filtered="$(bash "$HERE/../../sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above); the publication was not touched"
floors=""
if [ -n "$filtered" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$F" clinlims)" || die "this hub's OpenELIS floors could not be read (reason above); the publication was not touched"
fi
tables="$(printf '%s\n' "$tables" | paste -sd, -)"
filtered="$(printf '%s\n' "$filtered" | grep . | paste -sd, -)"
floors="$(printf '%s\n' "$floors" | awk 'NF == 2 { printf "%s%s:%s", (n++ ? "," : ""), $1, $2 }')"
out="$("$@" -v ON_ERROR_STOP=1 -qAt -v pub=dbz_clinlims_owned -v tables="$tables" -v filtered="$filtered" -v floors="$floors" -f /dev/stdin < "$HERE/../openelis/apply-down-publication.sql" 2>&1)" \
  || die "dbz_clinlims_owned was refused: $(printf '%s\n' "$out" | sed -n 's/^.*ERROR: *//p' | head -1)"
printf '%s\n' "$out"
