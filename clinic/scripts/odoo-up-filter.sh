#!/usr/bin/env bash
# Prints the condition of this clinic's Odoo own-rows filter: the Groovy
# expression that keeps a change captured by the clinic's Odoo source unless
# it is to a row of a hub table that this clinic did not mint.
#
#   clinic/scripts/odoo-up-filter.sh
#
# The hub sends its products, units, addresses, stock structure, shops and
# price lists down to every clinic (sync/hub-down.conf). A clinic's own rows of
# those tables go up; an edit a clinic makes to the hub's row, or to another
# clinic's, stays at the clinic, so no row has two writers at the hub. A row is
# this clinic's when its id is at or above the clinic's floor for the table
# and ends in the clinic's residue. Below the floor every id was handed out
# before this clinic's sequences were strided, and none of them is its own.
#
# The condition is evaluated on the record key and the topic, so it judges a
# delete and its tombstone the same way as an insert or an update. Changes to
# every other table pass: the clinic's partners, sales, invoices and stock
# levels, the link tables (sync/local/tables-conf.sh UP_ODOO_LINK_TABLES), and
# the transfer tables (UP_ODOO_SHARED_ROWS), which the clinic completes for the
# hub. The topic the step sees is <server>.public.<table>, before the step that
# routes every table into the one ordered topic.
#
# The residue is RESIDUE (environment, else clinic/.env). The floor of table t
# is ODOO_FLOOR_<T> (for example ODOO_FLOOR_PRODUCT_TEMPLATE), a multiple of 10,
# from the environment, else clinic/.env, else SEED_MANIFEST, else the floors
# installer task 060 recorded on this machine (clinic/.install-state). Without
# the residue or any floor it prints nothing, names what is missing on stderr
# and exits 1: the source is then not registered, rather than registered on a
# guessed floor.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"
die(){ printf 'odoo-up-filter: %s\n' "$*" >&2; exit 1; }
file_get(){ # FILE KEY -> the last value of KEY in FILE, quotes and blanks trimmed
  [ -f "$1" ] || return 0
  { grep -E "^$2=" "$1" || true; } | tail -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//' | tr -d "\"' "
}
value_of(){ # KEY -> environment, else clinic/.env, else SEED_MANIFEST, else .install-state
  local k="$1" v="${!1:-}"
  [ -n "$v" ] || v="$(file_get "${CLINIC_DIR}/.env" "$k")"
  [ -n "$v" ] || [ -z "${SEED_MANIFEST:-}" ] || v="$(file_get "${SEED_MANIFEST}" "$k")"
  [ -n "$v" ] || v="$(file_get "${CLINIC_DIR}/.install-state" "$k")"
  printf '%s' "$v"
}

r="$(value_of RESIDUE)"
case "$r" in [1-9]) ;; *) die "this clinic's residue (RESIDUE, 1-9) is not set (read '${r}'): the Odoo own-rows filter keeps only this clinic's rows and is not written without it" ;; esac
. "${REPO_DIR}/sync/local/tables-conf.sh"
down="$(bash "${REPO_DIR}/sync/hub-down.sh" odoo)" || die "the hub's down list could not be read (reason above); no filter was written"
entries=""; missing=""
for t in $down; do
  case " ${UP_ODOO_SHARED_ROWS} ${UP_ODOO_LINK_TABLES} " in *" $t "*) continue ;; esac
  key="ODOO_FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
  f="$(value_of "$key")"
  [ -n "$f" ] || { missing="${missing} ${key}"; continue; }
  case "$f" in *[!0-9]*|0*) die "${key} is '${f}', not a whole number above 0" ;; esac
  [ $(( f % 10 )) = 0 ] || die "${key} is ${f}, not a multiple of 10: floor + residue would not be on this clinic's residue"
  entries="${entries}${entries:+, }'${t}': ${f}L"
done
[ -z "$missing" ] || die "no Odoo floor for this clinic:${missing} (looked in the environment, clinic/.env, SEED_MANIFEST and clinic/.install-state). Each is the id below which every row of that table came from the seed; installer task 060 records them before it strides. Without them the Odoo source is not registered, because it could not tell this clinic's rows from the hub's."
[ -n "$entries" ] || die "the hub's down list sends no Odoo table down that this clinic publishes only for its own rows; there is nothing to filter"
printf "%s\n" "def t = topic.substring(topic.lastIndexOf('.') + 1); def f = [${entries}]; !f.containsKey(t) || (key != null && key.get('id') instanceof Number && key.get('id').longValue() >= f[t] && key.get('id').longValue() % 10 == ${r})"
