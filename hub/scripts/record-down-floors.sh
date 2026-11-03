#!/usr/bin/env bash
# record-down-floors.sh --from-file FILE [--out OUT] -- PSQL-COMMAND...
#
# Records this hub's down-table floors from values captured when its Odoo ids
# were strided, for a hub whose striding ran before stride-odoo.sh recorded
# them itself. FILE holds "<table> <floor>" lines: each down table with an id
# (sync/hub-down.conf) and the value its sequence restarted at. OUT defaults to
# hub/odoo-down-floors.local and is never rewritten.
#
# Floors are never read from the sequences now: once a hub has issued ids, or
# been strided again, its sequences no longer show where they restarted. The
# values are checked against the database instead, and refused, naming the
# table, when a down table with an id has no floor, a floor names a table
# without one, a sequence does not step by 10, or a floor is above the id the
# sequence issues next (it cannot be where that sequence restarted).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
OUT="$HERE/../odoo-down-floors.local"; SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from-file) SRC="${2:?--from-file needs a file}"; shift 2 ;;
    --out) OUT="${2:?--out needs a file}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
die(){ printf 'record-down-floors.sh: %s\n' "$*" >&2; exit 1; }
[ -n "$SRC" ] && [ "$#" -gt 0 ] || { echo "usage: record-down-floors.sh --from-file FILE [--out OUT] -- <psql command...>" >&2; exit 2; }
[ -e "$OUT" ] && die "$OUT already exists: it holds this hub's floors and is never rewritten"
floors="$(bash "$HERE/down-floors.sh" "$SRC")" || die "$SRC cannot be read as floors (reason above); nothing was written"
down="$(bash "$R/sync/hub-down.sh" odoo)" || die "the down list could not be read (reason above); nothing was written"
state="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/odoo/down-sequence-state.sql" 2>&1)" \
  || die "the down sequences could not be read; nothing was written: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
idtabs=" $(printf '%s\n' "$state" | cut -d'|' -f1 | tr '\n' ' ') "
while read -r t f; do
  [ -n "$t" ] || continue
  case "$idtabs" in *" $t "*) ;; *) die "$SRC gives a floor for $t, which has no id column (it is sent down unfiltered); nothing was written" ;; esac
done <<EOF2
$floors
EOF2
while IFS='|' read -r t _restart nxt inc; do
  [ -n "$t" ] || continue
  f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
  [ -n "$f" ] || die "$SRC gives no floor for $t; nothing was written"
  [ "$inc" = 10 ] || die "$t's sequence steps by $inc, not 10: it has not been strided; nothing was written"
  [ "$f" -le "$nxt" ] || die "the floor given for $t, $f, is above the id its sequence issues next ($nxt), so it cannot be where it restarted; nothing was written"
done <<EOF2
$state
EOF2
( umask 022; printf '%s\n' "$floors" > "$OUT" ) || die "could not write $OUT"
printf '%s\n' "$floors" | sed 's/^/  floor /'
echo "  wrote $OUT from $SRC ($(printf '%s\n' "$floors" | grep -c .) tables)"
