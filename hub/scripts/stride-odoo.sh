#!/usr/bin/env bash
# stride-odoo.sh [--floors FILE] -- PSQL-COMMAND...
#
# Strides the hub's Odoo ids (residue 0) and records the floor of each down
# table in the same run: clinic/odoo/apply-odoo-sequence-striding.sql over every
# synced Odoo table, then clinic/odoo/apply-master-sequence-striding.sql. A
# table's floor is the value its sequence restarts at, read from the striding
# scripts' own report of each restart, at the moment it happens. FILE defaults
# to hub/odoo-down-floors.local, one "<table> <floor>" line per down table with
# an id (sync/hub-down.conf).
#
# The floors are recorded once. When FILE already exists, a re-run strides
# again (forward only) and never changes it: it refuses, before striding, when a
# sequence would restart below its recorded floor (the database went back), or
# when a down table with an id has no recorded floor.
#
# A first recording is refused, before striding, when any clinic's replication
# origin (clinic_*) shows progress: clinics' rows have reached this hub, and a
# floor read now could sit above them. Record the values captured when the hub
# was first strided instead: record-down-floors.sh --from-file.
#
# PSQL-COMMAND reaches the hub's Odoo database as its owner, for example:
#   hub/scripts/stride-odoo.sh -- docker exec -i <odoo-db-container> psql -U odoo -d odoo
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
OUT="$HERE/../odoo-down-floors.local"
[ "${1:-}" = --floors ] && { OUT="${2:?--floors needs a file}"; shift 2; }
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: stride-odoo.sh [--floors FILE] -- <psql command...>" >&2; exit 2; }
die(){ printf 'stride-odoo.sh: %s\n' "$*" >&2; exit 1; }
down="$(bash "$R/sync/hub-down.sh" odoo)" || die "the down list could not be read (reason above); nothing was strided"
synced="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | sed -n 's/^odoo://p' | grep -vx all | paste -sd, -)"
[ -n "$synced" ] || die "sync/subsystems.conf has no odoo: tables; nothing was strided"
state="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/odoo/down-sequence-state.sql" 2>&1)" \
  || die "the down sequences could not be read; nothing was strided: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
idtabs="$(printf '%s\n' "$state" | cut -d'|' -f1)"

if [ -e "$OUT" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$OUT")" || die "$OUT cannot be read (reason above); nothing was strided"
  while IFS='|' read -r t restart _nxt _inc; do
    [ -n "$t" ] || continue
    f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
    [ -n "$f" ] || die "$OUT records no floor for $t; nothing was strided. Its floor is the value its sequence restarted at when the hub's ids were first strided: add that line by hand from the striding record"
    [ "$restart" -ge "$f" ] || die "$t would restart at $restart, below its recorded floor $f (the database holds fewer rows than when it was strided); nothing was strided"
  done <<EOF2
$state
EOF2
else
  p="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" 2>&1)" \
    || die "the replication origins could not be read; nothing was strided: $p"
  [ "$p" = 0 ] || die "$p clinic replication origin(s) show progress: clinics' rows have reached this hub, so a floor read now could sit above them; nothing was strided. Record the floors captured when the hub was first strided: hub/scripts/record-down-floors.sh --from-file <file> -- <psql command>"
fi

o1="$("$@" -v ON_ERROR_STOP=1 -q -v residue=0 -v tables="$synced" -f /dev/stdin < "$R/clinic/odoo/apply-odoo-sequence-striding.sql" 2>&1)" \
  || { printf '%s\n' "$o1" >&2; die "apply-odoo-sequence-striding.sql failed (above)"; }
o2="$("$@" -v ON_ERROR_STOP=1 -qAt -f /dev/stdin < "$R/clinic/odoo/apply-master-sequence-striding.sql" 2>&1)" \
  || { printf '%s\n' "$o1" "$o2" >&2; die "apply-master-sequence-striding.sql failed (above)"; }
printf '%s\n' "$o1" "$o2" | grep -E 'NOTICE|next=' | sed 's/^/  /'

if [ -e "$OUT" ]; then
  echo "  floors kept: $OUT is unchanged"
  exit 0
fi
# the last restart each table reported wins: the master script runs second
rows=""
for t in $idtabs; do
  n="$(printf '%s\n' "$o1" "$o2" | sed -nE "s/^.*NOTICE: +${t} : .*-> next=([0-9]+) .*$/\\1/p" | tail -1)"
  [ -n "$n" ] || die "the striding run reported no restart for $t; the hub was strided but no floors were written. Record them from the restart values above: hub/scripts/record-down-floors.sh --from-file <file> -- <psql command>"
  rows="$rows$t $n
"
done
tmp="$OUT.tmp.$$"
printf '%s' "$rows" > "$tmp" || die "could not write $tmp"
bash "$HERE/down-floors.sh" "$tmp" >/dev/null || { rm -f "$tmp"; die "the restart values do not validate as floors (above); the hub was strided but no floors were written"; }
mv "$tmp" "$OUT"
printf '%s' "$rows" | sed 's/^/  floor /'
echo "  wrote $OUT ($(printf '%s' "$rows" | grep -c .) tables)"
