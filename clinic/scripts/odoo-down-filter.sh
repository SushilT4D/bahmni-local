#!/usr/bin/env bash
# Prints the condition of this clinic's Odoo down filter: the Groovy expression
# that keeps a record of the hub's Odoo down stream unless it is a stock
# transfer going to another clinic's warehouse.
#
#   clinic/scripts/odoo-down-filter.sh -- PSQL-COMMAND...
#
# Every clinic receives the same stream (sync/hub-down.conf). Most of it is for
# every clinic: products, prices, shops, addresses and the stock structure. A
# transfer is for one clinic: the hub makes it, from its warehouse to the
# clinic's, and the clinic receives and completes it. Each clinic has its own
# warehouse in Odoo, made at the hub and named here by its short name
# (ODOO_WAREHOUSE, from the environment, else clinic/.env). A row of
# stock_picking, stock_move or stock_move_line is kept only when its
# destination (location_dest_id) is one of that warehouse's locations, so a
# transfer, its moves and its move lines are kept or dropped together. Every
# other record is kept, and so is every delete: a delete of a row this clinic
# never received changes nothing here.
#
# The warehouse's locations are read from this clinic's Odoo database
# (stock_location.warehouse_id) when the condition is written. A location
# added to the warehouse later is not in it until the down sink is registered
# again with a new condition.
#
# Without ODOO_WAREHOUSE no transfer is kept, and a note says so on stderr.
# With a name that is not a warehouse in this clinic's Odoo, it prints nothing,
# names the warehouse on stderr and exits 1: the warehouse is made at the hub
# and reaches the clinic before its transfers can.
#
# PSQL-COMMAND reaches this clinic's Odoo database, for example:
#   clinic/scripts/odoo-down-filter.sh -- docker exec -i <odoo-db-container> psql -U postgres -d odoo
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
die(){ printf 'odoo-down-filter: %s\n' "$*" >&2; exit 1; }
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: odoo-down-filter.sh -- <psql command...>" >&2; exit 2; }
file_get(){ # FILE KEY -> the last value of KEY in FILE, quotes and blanks trimmed
  [ -f "$1" ] || return 0
  { grep -E "^$2=" "$1" || true; } | tail -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}
wh="${ODOO_WAREHOUSE:-}"; [ -n "$wh" ] || wh="$(file_get "${CLINIC_DIR}/.env" ODOO_WAREHOUSE)"
ids=""
if [ -z "$wh" ]; then
  printf 'odoo-down-filter: ODOO_WAREHOUSE is not set, so this clinic has no warehouse and keeps no stock transfer from the hub\n' >&2
else
  printf '%s' "$wh" | grep -qE '^[A-Za-z0-9_-]{1,5}$' || die "ODOO_WAREHOUSE is '${wh}': a warehouse short name is 1 to 5 letters, digits, - or _"
  got="$(printf "select 'n|' || count(*) from stock_warehouse where code = :'code';\nselect 'l|' || l.id from stock_location l join stock_warehouse w on w.id = l.warehouse_id where w.code = :'code' order by l.id;\n" \
    | "$@" -v ON_ERROR_STOP=1 -v code="$wh" -qAt -f /dev/stdin 2>&1)" || die "the warehouse's locations could not be read from this clinic's Odoo: $(printf '%s\n' "$got" | sed -n 's/^.*ERROR: *//p' | head -1)"
  n="$(printf '%s\n' "$got" | sed -n 's/^n|//p')"
  case "$n" in
    1) ;;
    0) die "this clinic's Odoo has no warehouse with the short name ${wh} (ODOO_WAREHOUSE). It is made at the hub and comes down; once it is here, write the condition again." ;;
    *) die "this clinic's Odoo has '${n:-no answer}' warehouses with the short name ${wh}; it must have exactly one" ;;
  esac
  ids="$(printf '%s\n' "$got" | sed -n 's/^l|\([0-9][0-9]*\)$/\1L/p' | paste -sd, - | sed 's/,/, /g')"
  [ -n "$ids" ] || die "warehouse ${wh} has no locations in this clinic's Odoo"
fi
printf "%s\n" "value == null || value.get('op') == 'd' || !(['stock_picking', 'stock_move', 'stock_move_line'].contains(value.get('source').get('table'))) || (value.get('after') != null && value.get('after').get('location_dest_id') instanceof Number && [${ids}].contains(value.get('after').get('location_dest_id').longValue()))"
