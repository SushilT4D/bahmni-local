#!/usr/bin/env bash
# Reads and checks a floors file ("<table> <floor>" lines) for the cloud server's Odoo or
# OpenELIS down publication, and prints the valid lines.
# Usage: down-floors.sh <floors file> [odoo|clinlims]
set -uf

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${1:?usage: down-floors.sh <floors file> [odoo|clinlims]}"
SUBSYS="${2:-odoo}"

die() { printf 'down-floors.sh: %s\n' "$*" >&2; exit 1; }


# ---- the floors file, and the [down] tables it may name (those with a floor filter)

case "$SUBSYS" in
  odoo)
    [ -f "$F" ] || die "no floors file at $F: the hub's floors are recorded by the run that strides its Odoo ids (cloud/scripts/stride.sh odoo)"
    down="$(bash "$HERE/../../sync/tables/tables.sh" odoo down)" \
      || die "the down list could not be read (reason above)"
    ;;
  clinlims)
    [ -f "$F" ] || die "no floors file at $F: the hub's OpenELIS floors are recorded just before its OpenELIS ids are strided (cloud/scripts/record-down-floors.sh openelis)"
    down="$(bash "$HERE/../../sync/tables/tables.sh" openelis unrouted)" \
      || die "the down list could not be read (reason above)"
    ;;
  *)
    die "unknown subsystem '$SUBSYS' (odoo or clinlims)"
    ;;
esac


# ---- each line: a [down] table, once, with a floor that is a multiple of 10 ----

out=""
seen=" "
n=0

while IFS= read -r raw || [ -n "$raw" ]; do
  n=$((n + 1))
  line="$(printf '%s' "$raw" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue

  set -- $line
  [ "$#" = 2 ] \
    || die "$F line $n: '$raw' is not '<table> <floor>'"
  printf '%s' "$1" | grep -qE '^[a-z_][a-z0-9_]*$' \
    || die "$F line $n: '$1' is not a table name"
  printf '%s' "$2" | grep -qE '^[1-9][0-9]*$' \
    || die "$F line $n: the floor of $1 is '$2', not a whole number without leading zeros"
  [ $(( $2 % 10 )) = 0 ] \
    || die "$F line $n: the floor of $1 is $2, not a multiple of 10 (the hub mints residue 0 from its floor)"
  printf '%s\n' "$down" | grep -qx "$1" \
    || die "$F line $n: $1 is not a table captured for clinics filtered on a floor (sync/tables/{odoo,openelis}.conf [down])"
  case "$seen" in
    *" $1 "*) die "$F line $n: $1 is listed twice" ;;
  esac

  seen="$seen$1 "
  out="$out$1 $2
"
done < "$F"

printf '%s' "$out"
