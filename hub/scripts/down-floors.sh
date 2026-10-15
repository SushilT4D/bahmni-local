#!/usr/bin/env bash
# down-floors.sh FILE [clinlims] : prints FILE's "<table> <floor>" lines,
# validated, one per line. FILE is a hub's own record of its down-table floors
# (hub/odoo-down-floors.local, written once by stride-odoo.sh in the run that
# strides the hub's Odoo ids; with clinlims, hub/clinlims-down-floors.local,
# written once by record-clinlims-down-floors.sh before the hub's OpenELIS ids
# are strided; never committed, because each hub has its own).
#
# Refuses (exit 1, naming the line) a line that is not "<table> <floor>", a
# floor that is not a whole multiple of 10, a table listed twice, and a table
# that is not a down table (sync/hub-down.sh odoo; with clinlims, an OpenELIS
# down table the publication filters: sync/hub-down.sh --unrouted clinlims).
# Blank lines and "#"
# comments are skipped.
set -uf
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${1:?usage: down-floors.sh <floors file> [clinlims]}"; SUBSYS="${2:-odoo}"
die(){ printf 'down-floors.sh: %s\n' "$*" >&2; exit 1; }
case "$SUBSYS" in
  odoo) [ -f "$F" ] || die "no floors file at $F: the hub's floors are recorded by the run that strides its Odoo ids (hub/scripts/stride-odoo.sh)"
        down="$(bash "$HERE/../../sync/hub-down.sh" odoo)" || die "the down list could not be read (reason above)" ;;
  clinlims) [ -f "$F" ] || die "no floors file at $F: the hub's OpenELIS floors are recorded just before its OpenELIS ids are strided (hub/scripts/record-clinlims-down-floors.sh)"
        down="$(bash "$HERE/../../sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above)" ;;
  *) die "unknown subsystem '$SUBSYS' (odoo or clinlims)" ;;
esac
out=""; seen=" "; n=0
while IFS= read -r raw || [ -n "$raw" ]; do
  n=$((n+1))
  line="$(printf '%s' "$raw" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$line" ] || continue
  set -- $line
  [ "$#" = 2 ] || die "$F line $n: '$raw' is not '<table> <floor>'"
  printf '%s' "$1" | grep -qE '^[a-z_][a-z0-9_]*$' || die "$F line $n: '$1' is not a table name"
  printf '%s' "$2" | grep -qE '^[1-9][0-9]*$' || die "$F line $n: the floor of $1 is '$2', not a whole number without leading zeros"
  [ $(( $2 % 10 )) = 0 ] || die "$F line $n: the floor of $1 is $2, not a multiple of 10 (the hub mints residue 0 from its floor)"
  printf '%s\n' "$down" | grep -qx "$1" || die "$F line $n: $1 is not a table the hub sends down filtered on a floor (sync/hub-down.conf)"
  case "$seen" in *" $1 "*) die "$F line $n: $1 is listed twice" ;; esac
  seen="$seen$1 "; out="$out$1 $2
"
done < "$F"
printf '%s' "$out"
