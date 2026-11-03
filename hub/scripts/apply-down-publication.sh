#!/usr/bin/env bash
# apply-down-publication.sh FLOORS-FILE -- PSQL-COMMAND...
#
# Converges the hub's Odoo down publication, dbz_odoo_owned, to exactly the down
# list (sync/hub-down.conf through sync/hub-down.sh), each table with an `id`
# filtered with (id < <floor> OR id % 10 = 0) from FLOORS-FILE (the hub's
# hub/odoo-down-floors.local), plus public.dbz_heartbeat. hub/odoo/
# apply-down-publication.sql does the work and refuses, naming the table, a
# missing floor, a missing table, or a replica identity that does not cover
# `id`. Prints "<table> <row filter>" per published table on success.
#
# PSQL-COMMAND reaches the hub's Odoo database as a role that may alter the
# publication, for example: docker exec -i <odoo-db-container> psql -U odoo -d odoo
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${1:?usage: apply-down-publication.sh <floors file> -- <psql command...>}"; shift
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: apply-down-publication.sh <floors file> -- <psql command...>" >&2; exit 2; }
die(){ printf 'apply-down-publication.sh: %s\n' "$*" >&2; exit 1; }
tables="$(bash "$HERE/../../sync/hub-down.sh" odoo)" || die "the down list could not be read (reason above); the publication was not touched"
floors="$(bash "$HERE/down-floors.sh" "$F")" || die "the floors could not be read (reason above); the publication was not touched"
tables="$(printf '%s\n' "$tables" | paste -sd, -)"
floors="$(printf '%s\n' "$floors" | awk 'NF == 2 { printf "%s%s:%s", (n++ ? "," : ""), $1, $2 }')"
out="$("$@" -v ON_ERROR_STOP=1 -qAt -v pub=dbz_odoo_owned -v tables="$tables" -v floors="$floors" -f /dev/stdin < "$HERE/../odoo/apply-down-publication.sql" 2>&1)" \
  || die "dbz_odoo_owned was refused: $(printf '%s\n' "$out" | sed -n 's/^.*ERROR: *//p' | head -1)"
printf '%s\n' "$out"
