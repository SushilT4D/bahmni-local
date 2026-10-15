#!/usr/bin/env bash
# hub-down.sh SUBSYSTEM : prints the tables of SUBSYSTEM the hub sends down to
# clinics, one per line, in sync/hub-down.conf's order.
# hub-down.sh --subsystems : prints each subsystem that sends anything down, once.
# hub-down.sh --unrouted SUBSYSTEM : prints the tables of SUBSYSTEM that go to
#   every clinic (no clinic=<column>), which the hub's publication filters on
#   its own floor: (id < floor OR id % 10 = 0).
# hub-down.sh --routes SUBSYSTEM : prints "<table> <column> <floor table>" for
#   each routed row of SUBSYSTEM (a row ending in :clinic=<column>): the column
#   a clinic reads to keep the row, and the table whose clinic floor that
#   column's value is compared with (the table itself for `id`, table t for
#   `t_id`).
#
# The one reader of that list: the hub publications, the hub sources' table
# lists and aggregate regexes, the clinic MirrorMaker's down topics and the
# clinic's OpenELIS down filter all come from what this prints.
#
# Refuses (exit 1, naming the row) when a row is malformed, names a table that
# is not a synced table of its subsystem in sync/subsystems.conf, repeats a
# table, or names a table that is written at the clinics and must never go down
# (Odoo partners, sales, invoices and stock levels; any OpenELIS table other
# than the three a hub lab user completes and the lab accounts they name). An
# OpenELIS result, analysis or sample row must say which column routes it to
# its clinic; an OpenELIS system_user row and every Odoo row must not (they go
# to every clinic, chosen by the publication's floor filter). Nothing is
# printed when it refuses, so a caller never renders from half a list.
#
# HUB_DOWN_CONF and SUBSYSTEMS_CONF override the two files (tests).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=tables
case "${1:-}" in
  --routes) MODE=routes; SUB="${2:?usage: hub-down.sh --routes <subsystem>}" ;;
  --unrouted) MODE=unrouted; SUB="${2:?usage: hub-down.sh --unrouted <subsystem>}" ;;
  *) SUB="${1:?usage: hub-down.sh <subsystem>}" ;;
esac
CONF="${HUB_DOWN_CONF:-$HERE/hub-down.conf}"
SUBS="${SUBSYSTEMS_CONF:-$HERE/subsystems.conf}"
die(){ printf 'hub-down.sh: %s\n' "$*" >&2; exit 1; }
[ -f "$CONF" ] || die "no such file: $CONF"
[ -f "$SUBS" ] || die "no such file: $SUBS"

# Written at the clinics: never sent down, whatever the list says.
UP_ONLY_ODOO=" res_partner res_partner_attributes sale_order sale_order_line account_move account_move_line stock_quant "
# The OpenELIS rows a hub lab user writes for a clinic's sample: the result
# entered against the clinic's analysis, and the status the hub gives that
# analysis and its sample. Every other OpenELIS table is written at the
# clinics only and is refused by name.
DOWN_CLINLIMS=" result analysis sample "
# The lab accounts the hub's lab users write: a sample the hub moves on names
# the account that did it (sample.sys_user_id, a foreign key), so every clinic
# takes the hub's accounts, filtered on the hub's floor like an Odoo master row.
DOWN_CLINLIMS_ALL=" system_user "

strip(){ sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1"; }
SYNCED=" $(strip "$SUBS" | grep . | tr '\n' ' ') "

out=""; seen=" "; routes=""
ROWS="$(strip "$CONF")"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  case "$row" in *:*) ;; *) die "$CONF: row '$row' is not <subsystem>:<table>" ;; esac
  s="${row%%:*}"; rest="${row#*:}"; t="${rest%%:*}"; third=""
  [ "$rest" = "$t" ] || third="${rest#*:}"
  case "$s:$t" in *[!a-z0-9_:]*|:*|*:) die "$CONF: row '$row' is not <subsystem>:<table> with bare lowercase names" ;; esac
  col=""
  case "$third" in
    '') ;;
    clinic=*) col="${third#clinic=}"
      case "$col" in ''|*[!a-z0-9_]*|[0-9]*) die "$CONF: row '$row': clinic=<column> needs a bare lowercase column name" ;; esac ;;
    *) die "$CONF: row '$row': the third field is clinic=<column> or nothing" ;;
  esac
  if [ "$s" = clinlims ]; then
    case "$DOWN_CLINLIMS $DOWN_CLINLIMS_ALL" in
      *" $t "*) ;;
      *) die "$CONF: clinlims:$t is written at the clinics and never goes down; only result, analysis and sample, completed by a hub lab user, and the lab accounts (system_user) go down" ;;
    esac
    case "$DOWN_CLINLIMS" in
      *" $t "*) [ -n "$col" ] || die "$CONF: clinlims:$t goes to one clinic, so the row must name the column that routes it (clinlims:$t:clinic=<column>)" ;;
      *) [ -z "$col" ] || die "$CONF: clinlims:$t goes to every clinic, filtered on the hub's floor; it takes no clinic=<column>" ;;
    esac
  else
    [ -z "$col" ] || die "$CONF: $s:$t: only an OpenELIS row is routed by clinic=<column>; an $s row goes to every clinic, chosen by the publication's filter"
  fi
  if [ "$s" = odoo ]; then
    case "$UP_ONLY_ODOO" in *" $t "*) die "$CONF: odoo:$t is written at the clinics and never goes down (a hub write to it would reach every clinic)" ;; esac
  fi
  [ "$t" = all ] && die "$CONF: $s:all is the aggregate topic, not a table"
  case "$SYNCED" in *" $s:$t "*) ;; *) die "$CONF: $s:$t is not a synced table ($SUBS has no row $s:$t)" ;; esac
  case "$seen" in *" $s:$t "*) die "$CONF: $s:$t is listed twice" ;; esac
  seen="$seen$s:$t "
  [ -n "$col" ] && routes="$routes$s $t $col
"
  if [ "$MODE" = unrouted ] && [ "$s" = "$SUB" ] && [ -z "$col" ]; then out="$out$t
"; fi
  if [ "$MODE" = tables ] && [ "$SUB" = --subsystems ]; then
    case " $(printf '%s' "$out" | tr '\n' ' ') " in *" $s "*) ;; *) out="$out$s
" ;; esac
  elif [ "$MODE" = tables ] && [ "$s" = "$SUB" ]; then out="$out$t
"; fi
done <<EOF
$ROWS
EOF

# A routing column is the row's own id, or <table>_id naming another routed row
# of the same subsystem: the clinic compares its value with that table's floor.
rout=""
while read -r s t col; do
  [ -n "$s" ] || continue
  if [ "$col" = id ]; then ft="$t"
  else
    case "$col" in *_id) ft="${col%_id}" ;; *) die "$CONF: $s:$t:clinic=$col: the column is id or <table>_id, naming the table whose clinic floor the value is compared with" ;; esac
    printf '%s' "$routes" | awk -v s="$s" -v t="$ft" '$1==s && $2==t {f=1} END {exit !f}' \
      || die "$CONF: $s:$t:clinic=$col: $s:$ft is not a routed down row here, so a clinic has no floor to compare $col with"
  fi
  [ "$MODE" = routes ] && [ "$s" = "$SUB" ] && rout="$rout$t $col $ft
"
done <<EOF
$routes
EOF

if [ "$MODE" = routes ]; then
  [ -n "$rout" ] || die "$CONF has no routed ${SUB} rows"
  printf '%s' "$rout"; exit 0
fi
if [ "$MODE" = unrouted ]; then printf '%s' "$out"; exit 0; fi
[ -n "$out" ] || die "$CONF has no ${SUB#--} rows"
printf '%s' "$out"
