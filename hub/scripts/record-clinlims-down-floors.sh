#!/usr/bin/env bash
# record-clinlims-down-floors.sh [--from-file FILE | --derive] [--out OUT] -- PSQL-COMMAND...
#
# Records the hub's floor of each OpenELIS down table its publication filters
# (sync/hub-down.sh --unrouted clinlims: the lab accounts and the lab test
# catalogue) in OUT, default hub/clinlims-down-floors.local, one
# "<table> <floor>" line each. The publication sends such a table's rows below
# the floor (the hub's, from before its ids were strided) or ending in 0 (the
# hub's since), and nothing a clinic minted. A table without an id column (a
# link table) takes no floor and has no line.
#
# A recorded line is never changed. When OUT already exists, only the tables it
# does not hold yet are added (a table that joined the down list after OUT was
# written); a value given for a table OUT already holds must equal it. With
# nothing to add, it refuses and changes nothing.
#
# Without --from-file or --derive it is run immediately BEFORE the hub's
# OpenELIS ids are strided, and records where each floor must lie: for the lab
# accounts, which clinics also write and send up, where the stride will restart
# the sequence, ((last_value / 10) + 1) * 10, the hub's OpenELIS striding's own
# restart; for a catalogue table, which only the hub writes, that or the first
# multiple of 10 above the largest id the table holds, whichever is higher (some
# catalogue sequences stand below the rows they hold; a floor below a row the
# hub owns would stop that row's changes from going down). Refused, writing
# nothing, when a sequence already steps by more than 1 (the hub was strided
# before: record the floors with --derive and --from-file), or when any
# clinic's replication origin (clinic_*) shows progress (clinics' rows may
# already sit above it).
#
# With --derive it writes nothing and prints, for each table OUT does not hold
# yet, a floor read from the rows: the first multiple of 10 above the table's
# largest id. That is the floor for a hub whose OpenELIS ids were strided
# before the table joined the down list. Refused for a table clinics send up
# (sync/subsystems.conf) once any clinic's replication origin shows progress:
# a clinic's rows may then be the largest ids, and a floor above them would
# send them to every clinic. Save the output and record it with --from-file.
#
# With --from-file FILE ("<table> <floor>" lines) it records values captured
# or derived elsewhere, after checking them against the database: each table
# listed once, its sequence stepping by 10 (a table without a sequence aside),
# the floor a multiple of 10; for a table clinics send up, not above the id
# the sequence issues next; for a catalogue table, above every id the table
# holds that does not end in 0 (those rows are the hub's, and must pass the
# filter) and not above the higher of the id its sequence issues next and the
# first multiple of 10 above its largest id.
#
# PSQL-COMMAND reaches the hub's openelis database as a superuser, for example:
#   hub/scripts/record-clinlims-down-floors.sh -- docker exec -i <openelis-db-container> psql -U postgres -d openelis
# On a hub strided before:
#   hub/scripts/record-clinlims-down-floors.sh --derive -- <psql command...> > /tmp/floors &&
#   hub/scripts/record-clinlims-down-floors.sh --from-file /tmp/floors -- <psql command...>
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
OUT="$HERE/../clinlims-down-floors.local"; SRC=""; DERIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from-file) SRC="${2:?--from-file needs a file}"; shift 2 ;;
    --derive) DERIVE=1; shift ;;
    --out) OUT="${2:?--out needs a file}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
die(){ printf 'record-clinlims-down-floors.sh: %s\n' "$*" >&2; exit 1; }
[ "$#" -gt 0 ] || { echo "usage: record-clinlims-down-floors.sh [--from-file FILE | --derive] [--out OUT] -- <psql command...>" >&2; exit 2; }
[ -n "$SRC" ] && [ "$DERIVE" = 1 ] && die "--from-file and --derive do not go together: --derive prints floors, --from-file records them"
down="$(bash "$R/sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above); nothing was written"
[ -n "$down" ] || die "sync/hub-down.conf sends no OpenELIS table down filtered on a floor; there is nothing to record"
# the tables clinics send up: their rows can reach this hub
up=" $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | sed -n 's/^clinlims://p' | grep -vx all | tr '\n' ' ') "
is_up(){ case "$up" in *" $1 "*) return 0 ;; esac; return 1; }
held=""
if [ -e "$OUT" ]; then
  held="$(bash "$HERE/down-floors.sh" "$OUT" clinlims)" || die "$OUT cannot be read as OpenELIS floors (reason above); nothing was written"
fi
held_floor(){ printf '%s\n' "$held" | awk -v t="$1" '$1 == t { print $2 }'; }
state="$("$@" -v ON_ERROR_STOP=1 -qAt -v detail=1 -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/openelis/down-sequence-state.sql" 2>&1)" \
  || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
# the id tables OUT does not hold yet
need="$(printf '%s\n' "$state" | awk -F'|' 'NF == 7 && $7 == "id" { print $1 }' | while read -r t; do [ -n "$(held_floor "$t")" ] || echo "$t"; done)"
if [ -z "$need" ] && [ -z "$SRC" ]; then
  die "$OUT already exists and holds a floor for every OpenELIS table filtered on a floor; it is never rewritten"
fi
derived(){ echo $(( ($1 / 10 + 1) * 10 )); }
progress(){ # clinic replication origins that show progress, as a count
  local p
  p="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" 2>&1)" \
    || die "the replication origins could not be read; nothing was written: $p"
  printf '%s' "$p"
}
rows=""
if [ "$DERIVE" = 1 ]; then
  p=""
  while IFS='|' read -r t _restart nxt inc mx _mxnz kind; do
    [ -n "$t" ] && [ "$kind" = id ] || continue
    printf '%s\n' "$need" | grep -qx "$t" || continue
    if is_up "$t"; then
      [ -n "$p" ] || p="$(progress "$@")"
      [ "$p" = 0 ] || die "clinlims.$t is sent up by the clinics and $p clinic replication origin(s) show progress: a clinic's rows may be its largest ids, so its floor cannot be read from the rows. Its floor is the value its sequence restarted at when the hub's OpenELIS ids were strided; nothing was printed"
      f="$(derived "$mx")"
      [ "$inc" = 0 ] || [ "$f" -le "$nxt" ] || die "clinlims.$t's sequence issues $nxt next, below its rows (largest id $mx): clinics send it up, so a floor read from the rows could let their rows down; nothing was printed"
    else
      f="$(derived "$mx")"
    fi
    rows="$rows$t $f
"
  done <<EOF
$state
EOF
  [ -n "$rows" ] || die "every OpenELIS table filtered on a floor already has one in $OUT; there is nothing to derive"
  printf '%s' "$rows"; exit 0
fi
if [ -n "$SRC" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$SRC" clinlims)" || die "$SRC cannot be read as OpenELIS floors (reason above); nothing was written"
  while IFS='|' read -r t _restart nxt inc mx mxnz kind; do
    [ -n "$t" ] || continue
    f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
    if [ "$kind" = noid ]; then
      [ -z "$f" ] || die "$SRC gives a floor for $t, which has no id column (a link table: it is published whole); nothing was written"
      continue
    fi
    h="$(held_floor "$t")"
    if [ -n "$h" ]; then
      [ -z "$f" ] || [ "$f" = "$h" ] || die "$SRC gives $t the floor $f, but $OUT holds $h for it, and a recorded floor is never changed; nothing was written"
      continue
    fi
    [ -n "$f" ] || die "$SRC gives no floor for $t; nothing was written"
    [ "$inc" = 10 ] || [ "$inc" = 0 ] || die "clinlims.$t's sequence steps by $inc, not 10: it has not been strided; nothing was written"
    if is_up "$t"; then
      [ "$f" -le "$nxt" ] || die "the floor given for $t, $f, is above the id its sequence issues next ($nxt), so it cannot be where it restarted; nothing was written"
    else
      [ "$f" -gt "$mxnz" ] || die "the floor given for $t, $f, is not above its row $mxnz, which does not end in 0 and is the hub's: the publication would stop sending that row's changes; nothing was written"
      top="$(derived "$mx")"; [ "$nxt" -gt "$top" ] && top="$nxt"
      [ "$f" -le "$top" ] || die "the floor given for $t, $f, is above both the id its sequence issues next ($nxt) and its rows (largest id $mx); nothing was written"
    fi
    rows="$rows$t $f
"
  done <<EOF
$state
EOF
  [ -n "$rows" ] || die "$SRC adds nothing: $OUT already holds every floor it gives; nothing was written"
else
  strided="$(printf '%s\n' "$state" | awk -F'|' 'NF == 7 && $7 == "id" && $4 != 1 && $4 != 0 { printf "%s%s (steps by %s)", (n++ ? ", " : ""), $1, $4 }')"
  [ -z "$strided" ] || die "this hub's OpenELIS ids were strided before: ${strided}. Their floors are the values the sequences restarted at then; nothing was written. Derive them with --derive and record them with --from-file <file>"
  p="$(progress "$@")"
  [ "$p" = 0 ] || die "$p clinic replication origin(s) show progress: clinics' rows may have reached this hub, so a floor read now could sit above them; nothing was written. Record the floors with --from-file <file>"
  while IFS='|' read -r t restart _nxt _inc mx _mxnz kind; do
    [ -n "$t" ] && [ "$kind" = id ] || continue
    printf '%s\n' "$need" | grep -qx "$t" || continue
    f="$restart"
    if ! is_up "$t"; then d="$(derived "$mx")"; [ "$d" -gt "$f" ] && f="$d"; fi
    rows="$rows$t $f
"
  done <<EOF
$state
EOF
fi
tmp="$OUT.tmp.$$"
{ [ ! -e "$OUT" ] || cat "$OUT"; printf '%s' "$rows"; } > "$tmp" || die "could not write $tmp"
bash "$HERE/down-floors.sh" "$tmp" clinlims >/dev/null || { rm -f "$tmp"; die "the values do not validate as floors (above); nothing was written"; }
existed=0; [ -e "$OUT" ] && existed=1
mv "$tmp" "$OUT"
printf '%s' "$rows" | sed 's/^/  floor /'
if [ "$existed" = 1 ]; then echo "  added $(printf '%s' "$rows" | grep -c .) table(s) to $OUT; the floors it held are unchanged"
else echo "  wrote $OUT ($(printf '%s' "$rows" | grep -c .) tables)"; fi
