#!/usr/bin/env bash
# hub-down.sh SUBSYSTEM : prints the tables of SUBSYSTEM the hub sends down to
# clinics, one per line, in sync/hub-down.conf's order.
# hub-down.sh --subsystems : prints each subsystem that sends anything down, once.
#
# The one reader of that list: the hub publication, the hub source's table list
# and aggregate regex, and the clinic MirrorMaker's down topics all come from
# what this prints.
#
# Refuses (exit 1, naming the row) when a row is malformed, names a table that
# is not a synced table of its subsystem in sync/subsystems.conf, repeats a
# table, or names a table that is written at the clinics and must never go down
# (any OpenELIS table; Odoo partners, sales, invoices and stock levels). Nothing is
# printed when it refuses, so a caller never renders from half a list.
#
# HUB_DOWN_CONF and SUBSYSTEMS_CONF override the two files (tests).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUB="${1:?usage: hub-down.sh <subsystem>}"
CONF="${HUB_DOWN_CONF:-$HERE/hub-down.conf}"
SUBS="${SUBSYSTEMS_CONF:-$HERE/subsystems.conf}"
die(){ printf 'hub-down.sh: %s\n' "$*" >&2; exit 1; }
[ -f "$CONF" ] || die "no such file: $CONF"
[ -f "$SUBS" ] || die "no such file: $SUBS"

# Written at the clinics: never sent down, whatever the list says.
UP_ONLY_ODOO=" res_partner res_partner_attributes sale_order sale_order_line account_move account_move_line stock_quant "

strip(){ sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1"; }
SYNCED=" $(strip "$SUBS" | grep . | tr '\n' ' ') "

out=""; seen=" "
ROWS="$(strip "$CONF")"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  case "$row" in *:*) ;; *) die "$CONF: row '$row' is not <subsystem>:<table>" ;; esac
  s="${row%%:*}"; t="${row#*:}"
  case "$s:$t" in *[!a-z0-9_:]*|:*|*:) die "$CONF: row '$row' is not <subsystem>:<table> with bare lowercase names" ;; esac
  case "$t" in *:*) die "$CONF: row '$row' is not <subsystem>:<table> with bare lowercase names" ;; esac
  [ "$s" = clinlims ] && die "$CONF: clinlims:$t: no OpenELIS table goes down; lab rows are written at the clinics"
  if [ "$s" = odoo ]; then
    case "$UP_ONLY_ODOO" in *" $t "*) die "$CONF: odoo:$t is written at the clinics and never goes down (a hub write to it would reach every clinic)" ;; esac
  fi
  [ "$t" = all ] && die "$CONF: $s:all is the aggregate topic, not a table"
  case "$SYNCED" in *" $s:$t "*) ;; *) die "$CONF: $s:$t is not a synced table ($SUBS has no row $s:$t)" ;; esac
  case "$seen" in *" $s:$t "*) die "$CONF: $s:$t is listed twice" ;; esac
  seen="$seen$s:$t "
  if [ "$SUB" = --subsystems ]; then
    case " $(printf '%s' "$out" | tr '\n' ' ') " in *" $s "*) ;; *) out="$out$s
" ;; esac
  elif [ "$s" = "$SUB" ]; then out="$out$t
"; fi
done <<EOF
$ROWS
EOF
[ -n "$out" ] || die "$CONF has no ${SUB#--} rows"
printf '%s' "$out"
