#!/usr/bin/env bash
# Records the hub's floor for each floor-filtered down table, checked against the database:
#   odoo      ./odoo-down-floors.local, from values captured at the first striding
#             (--from-file); written once, never rewritten
#   openelis  ./clinlims-down-floors.local: before the first striding (stride.sh calls it),
#             from a file (--from-file), or printed from the rows (--derive)
# usage: record-down-floors.sh odoo --from-file FILE [--out OUT] -- PSQL-COMMAND...
#        record-down-floors.sh openelis [--from-file FILE | --derive] [--out OUT] -- PSQL-COMMAND...
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$HERE/../.."
USAGE="usage: record-down-floors.sh odoo --from-file FILE [--out OUT] -- <psql command...>
       record-down-floors.sh openelis [--from-file FILE | --derive] [--out OUT] -- <psql command...>"

die() { printf 'record-down-floors.sh: %s\n' "$*" >&2; exit 1; }


# ---- arguments ---------------------------------------------------------------

DB="${1:-}"
shift || true
case "$DB" in
  odoo)     OUT="$PWD/odoo-down-floors.local" ;;
  openelis) OUT="$PWD/clinlims-down-floors.local" ;;
  *)        echo "$USAGE" >&2; exit 2 ;;
esac

SRC=""
DERIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from-file) SRC="${2:?--from-file needs a file}"; shift 2 ;;
    --derive)    DERIVE=1; shift ;;
    --out)       OUT="${2:?--out needs a file}"; shift 2 ;;
    --)          shift; break ;;
    *)           break ;;
  esac
done

[ "$#" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
[ -n "$SRC" ] && [ "$DERIVE" = 1 ] \
  && die "--from-file and --derive do not go together: --derive prints floors, --from-file records them"


# ==== Odoo ======================================================================

record_odoo() {
  [ "$DERIVE" = 0 ] || die "--derive is for openelis; odoo floors come from --from-file"
  [ -n "$SRC" ] || { echo "$USAGE" >&2; exit 2; }
  [ -e "$OUT" ] && die "$OUT already exists: it holds this hub's floors and is never rewritten"

  # ---- the floors given, and the down tables' current sequence state

  floors="$(bash "$HERE/down-floors.sh" "$SRC")" \
    || die "$SRC cannot be read as floors (reason above); nothing was written"

  down="$(bash "$R/sync/tables/tables.sh" odoo down)" \
    || die "the down list could not be read (reason above); nothing was written"

  state="$("$@" -v ON_ERROR_STOP=1 -qAt \
             -v tables="$(printf '%s\n' "$down" | paste -sd, -)" \
             -f /dev/stdin < "$R/cloud/odoo/down-sequence-state.sql" 2>&1)" \
    || die "the down sequences could not be read; nothing was written: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"

  # ---- every floor must name a down table that has an id column

  idtabs=" $(printf '%s\n' "$state" | cut -d'|' -f1 | tr '\n' ' ') "

  while read -r t f; do
    [ -n "$t" ] || continue
    case "$idtabs" in
      *" $t "*) ;;
      *) die "$SRC gives a floor for $t, which has no id column (it is captured unfiltered); nothing was written" ;;
    esac
  done <<EOF
$floors
EOF

  # ---- every id table needs a floor, a strided sequence (step 10), and a floor at or below its next id

  while IFS='|' read -r t _restart nxt inc; do
    [ -n "$t" ] || continue
    f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"

    [ -n "$f" ] \
      || die "$SRC gives no floor for $t; nothing was written"
    [ "$inc" = 10 ] \
      || die "$t's sequence steps by $inc, not 10: it has not been strided; nothing was written"
    [ "$f" -le "$nxt" ] \
      || die "the floor given for $t, $f, is above the id its sequence issues next ($nxt), so it cannot be where it restarted; nothing was written"
  done <<EOF
$state
EOF

  # ---- write the floors file

  ( umask 022; printf '%s\n' "$floors" > "$OUT" ) || die "could not write $OUT"

  printf '%s\n' "$floors" | sed 's/^/  floor /'
  echo "  wrote $OUT from $SRC ($(printf '%s\n' "$floors" | grep -c .) tables)"
}


# ==== OpenELIS ==================================================================

# first multiple of 10 above an id
derived() { echo $(( ($1 / 10 + 1) * 10 )); }

# clinic replication origins that show progress, as a count
progress() {
  local p
  p="$("$@" -v ON_ERROR_STOP=1 -qAt \
         -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" \
         < /dev/null 2>&1)" \
    || die "the replication origins could not be read; nothing was written: $p"
  printf '%s' "$p"
}

record_openelis() {
  # ---- the floor-filtered down tables, and the tables clinics send up

  down="$(bash "$R/sync/tables/tables.sh" openelis unrouted)" \
    || die "the down list could not be read (reason above); nothing was written"
  [ -n "$down" ] \
    || die "sync/tables/{odoo,openelis}.conf [down] lists no OpenELIS table captured with a floor filter; there is nothing to record"

  up=" $(bash "$R/sync/tables/tables.sh" openelis up | tr '\n' ' ') "
  is_up() { case "$up" in *" $1 "*) return 0 ;; esac; return 1; }

  # ---- floors OUT already holds; a recorded floor is never changed

  held=""
  if [ -e "$OUT" ]; then
    held="$(bash "$HERE/down-floors.sh" "$OUT" clinlims)" \
      || die "$OUT cannot be read as OpenELIS floors (reason above); nothing was written"
  fi
  held_floor() { printf '%s\n' "$held" | awk -v t="$1" '$1 == t { print $2 }'; }

  # ---- each table's sequence and id state, and the id tables that still need a floor

  state="$("$@" -v ON_ERROR_STOP=1 -qAt -v detail=1 \
             -v tables="$(printf '%s\n' "$down" | paste -sd, -)" \
             -f /dev/stdin < "$R/cloud/openelis/down-sequence-state.sql" 2>&1)" \
    || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"

  need="$(printf '%s\n' "$state" \
    | awk -F'|' 'NF == 7 && $7 == "id" { print $1 }' \
    | while read -r t; do [ -n "$(held_floor "$t")" ] || echo "$t"; done)"

  if [ -z "$need" ] && [ -z "$SRC" ]; then
    die "$OUT already exists and holds a floor for every OpenELIS table filtered on a floor; it is never rewritten"
  fi

  rows=""

  # ---- --derive: print floors read from the rows, writing nothing

  if [ "$DERIVE" = 1 ]; then
    p=""
    while IFS='|' read -r t _restart nxt inc mx _mxnz kind; do
      [ -n "$t" ] && [ "$kind" = id ] || continue
      printf '%s\n' "$need" | grep -qx "$t" || continue

      if is_up "$t"; then
        [ -n "$p" ] || p="$(progress "$@")"
        [ "$p" = 0 ] \
          || die "clinlims.$t is sent up by the clinics and $p clinic replication origin(s) show progress: a clinic's rows may be its largest ids, so its floor cannot be read from the rows. Its floor is the value its sequence restarted at when the hub's OpenELIS ids were strided; nothing was printed"
        f="$(derived "$mx")"
        [ "$inc" = 0 ] || [ "$f" -le "$nxt" ] \
          || die "clinlims.$t's sequence issues $nxt next, below its rows (largest id $mx): clinics send it up, so a floor read from the rows could let their rows down; nothing was printed"
      else
        f="$(derived "$mx")"
      fi

      rows="$rows$t $f
"
    done <<EOF
$state
EOF

    [ -n "$rows" ] || die "every OpenELIS table filtered on a floor already has one in $OUT; there is nothing to derive"
    printf '%s' "$rows"
    return 0
  fi

  if [ -n "$SRC" ]; then
    # ---- --from-file: check the given floors against the database

    floors="$(bash "$HERE/down-floors.sh" "$SRC" clinlims)" \
      || die "$SRC cannot be read as OpenELIS floors (reason above); nothing was written"

    while IFS='|' read -r t _restart nxt inc mx mxnz kind; do
      [ -n "$t" ] || continue
      f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"

      if [ "$kind" = noid ]; then
        [ -z "$f" ] \
          || die "$SRC gives a floor for $t, which has no id column (a link table: it is published whole); nothing was written"
        continue
      fi

      h="$(held_floor "$t")"
      if [ -n "$h" ]; then
        [ -z "$f" ] || [ "$f" = "$h" ] \
          || die "$SRC gives $t the floor $f, but $OUT holds $h for it, and a recorded floor is never changed; nothing was written"
        continue
      fi

      [ -n "$f" ] \
        || die "$SRC gives no floor for $t; nothing was written"
      [ "$inc" = 10 ] || [ "$inc" = 0 ] \
        || die "clinlims.$t's sequence steps by $inc, not 10: it has not been strided; nothing was written"

      if is_up "$t"; then
        [ "$f" -le "$nxt" ] \
          || die "the floor given for $t, $f, is above the id its sequence issues next ($nxt), so it cannot be where it restarted; nothing was written"
      else
        [ "$f" -gt "$mxnz" ] \
          || die "the floor given for $t, $f, is not above its row $mxnz, which does not end in 0 and is the hub's: the publication would stop capturing that row's changes; nothing was written"
        top="$(derived "$mx")"
        [ "$nxt" -gt "$top" ] && top="$nxt"
        [ "$f" -le "$top" ] \
          || die "the floor given for $t, $f, is above both the id its sequence issues next ($nxt) and its rows (largest id $mx); nothing was written"
      fi

      rows="$rows$t $f
"
    done <<EOF
$state
EOF

    [ -n "$rows" ] || die "$SRC adds nothing: $OUT already holds every floor it gives; nothing was written"

  else
    # ---- default: before a first striding, record where each sequence will restart

    strided="$(printf '%s\n' "$state" \
      | awk -F'|' 'NF == 7 && $7 == "id" && $4 != 1 && $4 != 0 { printf "%s%s (steps by %s)", (n++ ? ", " : ""), $1, $4 }')"
    [ -z "$strided" ] \
      || die "this hub's OpenELIS ids were strided before: ${strided}. Their floors are the values the sequences restarted at then; nothing was written. Derive them with --derive and record them with --from-file <file>"

    p="$(progress "$@")"
    [ "$p" = 0 ] \
      || die "$p clinic replication origin(s) show progress: clinics' rows may have reached this hub, so a floor read now could sit above them; nothing was written. Record the floors with --from-file <file>"

    while IFS='|' read -r t restart _nxt _inc mx _mxnz kind; do
      [ -n "$t" ] && [ "$kind" = id ] || continue
      printf '%s\n' "$need" | grep -qx "$t" || continue

      f="$restart"
      if ! is_up "$t"; then
        d="$(derived "$mx")"
        [ "$d" -gt "$f" ] && f="$d"
      fi

      rows="$rows$t $f
"
    done <<EOF
$state
EOF
  fi

  # ---- validate, then write OUT (keeping the floors it already held)

  tmp="$OUT.tmp.$$"
  { [ ! -e "$OUT" ] || cat "$OUT"; printf '%s' "$rows"; } > "$tmp" || die "could not write $tmp"
  bash "$HERE/down-floors.sh" "$tmp" clinlims >/dev/null \
    || { rm -f "$tmp"; die "the values do not validate as floors (above); nothing was written"; }

  existed=0
  [ -e "$OUT" ] && existed=1
  mv "$tmp" "$OUT"

  printf '%s' "$rows" | sed 's/^/  floor /'
  if [ "$existed" = 1 ]; then
    echo "  added $(printf '%s' "$rows" | grep -c .) table(s) to $OUT; the floors it held are unchanged"
  else
    echo "  wrote $OUT ($(printf '%s' "$rows" | grep -c .) tables)"
  fi
}


# ==== run =======================================================================

case "$DB" in
  odoo)     record_odoo "$@" ;;
  openelis) record_openelis "$@" ;;
esac
