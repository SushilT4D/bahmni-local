#!/usr/bin/env bash
# Sets the cloud server's down publication to the [down] tables of sync/tables/<db>.conf:
#   odoo      dbz_odoo_owned, every table with its floor filter
#   openelis  dbz_clinlims_owned, the floor filter on the tables every clinic keeps
# Usage: apply-down-publication.sh <odoo|openelis> <floors file> -- <psql command...>
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLES="$HERE/../../sync/tables/tables.sh"
USAGE="usage: apply-down-publication.sh <odoo|openelis> <floors file> -- <psql command...>"

die() { printf 'apply-down-publication.sh: %s\n' "$*" >&2; exit 1; }


# ---- arguments ---------------------------------------------------------------

DB="${1:?$USAGE}"
F="${2:?$USAGE}"
shift 2
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }


# ---- the [down] tables, the floor-filtered ones, and their floors ---------------

case "$DB" in
  odoo)
    PUB=dbz_odoo_owned
    SQL="$HERE/../odoo/apply-down-publication.sql"
    tables="$(bash "$TABLES" odoo down)" \
      || die "the down list could not be read (reason above); the publication was not touched"
    floors="$(bash "$HERE/down-floors.sh" "$F")" \
      || die "the floors could not be read (reason above); the publication was not touched"
    filtered=""
    ;;
  openelis)
    PUB=dbz_clinlims_owned
    SQL="$HERE/../openelis/apply-down-publication.sql"
    tables="$(bash "$TABLES" openelis down)" \
      || die "the down list could not be read (reason above); the publication was not touched"
    tables="$(printf '%s\n' "$tables" | cut -d: -f1)"
    filtered="$(bash "$TABLES" openelis unrouted)" \
      || die "the down list could not be read (reason above); the publication was not touched"
    floors=""
    if [ -n "$filtered" ]; then
      floors="$(bash "$HERE/down-floors.sh" "$F" clinlims)" \
        || die "this hub's OpenELIS floors could not be read (reason above); the publication was not touched"
    fi
    ;;
  *)
    echo "$USAGE" >&2
    exit 2
    ;;
esac


# ---- pass the lists to the SQL as comma-separated psql variables ---------------

tables="$(printf '%s\n' "$tables" | paste -sd, -)"
filtered="$(printf '%s\n' "$filtered" | grep . | paste -sd, -)"
floors="$(printf '%s\n' "$floors" | awk 'NF == 2 { printf "%s%s:%s", (n++ ? "," : ""), $1, $2 }')"

vars=(-v pub="$PUB" -v tables="$tables" -v floors="$floors")
[ "$DB" = openelis ] && vars+=(-v filtered="$filtered")

out="$("$@" -v ON_ERROR_STOP=1 -qAt "${vars[@]}" -f /dev/stdin < "$SQL" 2>&1)" \
  || die "$PUB was refused: $(printf '%s\n' "$out" | sed -n 's/^.*ERROR: *//p' | head -1)"

printf '%s\n' "$out"
