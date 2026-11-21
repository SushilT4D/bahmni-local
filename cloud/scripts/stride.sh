#!/usr/bin/env bash
# Strides the hub's Odoo or OpenELIS ids (residue 0) and, when no floors are recorded yet, records
# the floors of the floor-filtered down tables in the working directory:
#   odoo      odoo-down-floors.local, from where each sequence restarted
#   openelis  clinlims-down-floors.local, recorded just before striding
# usage: stride.sh <odoo|openelis> [--floors FILE] -- PSQL-COMMAND...
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$HERE/../.."
USAGE="usage: stride.sh <odoo|openelis> [--floors FILE] -- <psql command...>"

die() { printf 'stride.sh: %s\n' "$*" >&2; exit 1; }


# ---- arguments ---------------------------------------------------------------

DB="${1:-}"
shift || true
case "$DB" in
  odoo)     OUT="$PWD/odoo-down-floors.local" ;;
  openelis) OUT="$PWD/clinlims-down-floors.local" ;;
  *)        echo "$USAGE" >&2; exit 2 ;;
esac

if [ "${1:-}" = --floors ]; then
  OUT="${2:?--floors needs a file}"
  shift 2
fi
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }


# ==== Odoo ======================================================================

stride_odoo() {
  # ---- the down and synced table lists, and the down sequences' current state

  down="$(bash "$R/sync/tables/tables.sh" odoo down)" \
    || die "the down list could not be read (reason above); nothing was strided"

  synced="$(bash "$R/sync/tables/tables.sh" odoo up | paste -sd, -)"
  [ -n "$synced" ] || die "sync/tables/odoo.conf has no [up] tables; nothing was strided"

  state="$("$@" -v ON_ERROR_STOP=1 -qAt \
             -v tables="$(printf '%s\n' "$down" | paste -sd, -)" \
             -f /dev/stdin < "$R/cloud/odoo/down-sequence-state.sql" 2>&1)" \
    || die "the down sequences could not be read; nothing was strided: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"

  idtabs="$(printf '%s\n' "$state" | cut -d'|' -f1)"

  # ---- safety checks before striding

  if [ -e "$OUT" ]; then
    # floors already recorded: refuse a sequence that would restart below its floor
    floors="$(bash "$HERE/down-floors.sh" "$OUT")" \
      || die "$OUT cannot be read (reason above); nothing was strided"

    while IFS='|' read -r t restart _nxt _inc; do
      [ -n "$t" ] || continue
      f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"

      [ -n "$f" ] \
        || die "$OUT records no floor for $t; nothing was strided. Its floor is the value its sequence restarted at when the hub's ids were first strided: add that line by hand from the striding record"
      [ "$restart" -ge "$f" ] \
        || die "$t would restart at $restart, below its recorded floor $f (the database holds fewer rows than when it was strided); nothing was strided"
    done <<EOF
$state
EOF

  else
    # no floors yet: only before any clinic's rows have arrived. Striding restarts every
    # sequence above its rows (also one strided before), and each restart becomes the floor.
    p="$("$@" -v ON_ERROR_STOP=1 -qAt \
           -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" 2>&1)" \
      || die "the replication origins could not be read; nothing was strided: $p"
    [ "$p" = 0 ] \
      || die "$p clinic replication origin(s) show progress: clinics' rows have reached this hub, so a floor read now could sit above them; nothing was strided. Record the floors captured when the hub was first strided: cloud/scripts/record-down-floors.sh odoo --from-file <file> -- <psql command>"
  fi

  # ---- stride the synced tables, then the master tables

  o1="$("$@" -v ON_ERROR_STOP=1 -q -v residue=0 -v tables="$synced" \
          -f /dev/stdin < "$R/clinic/scripts/sql/odoo/apply-odoo-sequence-striding.sql" 2>&1)" \
    || { printf '%s\n' "$o1" >&2; die "apply-odoo-sequence-striding.sql failed (above)"; }

  o2="$("$@" -v ON_ERROR_STOP=1 -qAt \
          -f /dev/stdin < "$R/clinic/scripts/sql/odoo/apply-master-sequence-striding.sql" 2>&1)" \
    || { printf '%s\n' "$o1" "$o2" >&2; die "apply-master-sequence-striding.sql failed (above)"; }

  printf '%s\n' "$o1" "$o2" | grep -E 'NOTICE|next=' | sed 's/^/  /'

  # ---- record each id table's restart value as its floor

  if [ -e "$OUT" ]; then
    echo "  floors kept: $OUT is unchanged"
    return 0
  fi

  # the last restart reported for a table wins
  rows=""
  for t in $idtabs; do
    n="$(printf '%s\n' "$o1" "$o2" | sed -nE "s/^.*NOTICE: +${t} : .*-> next=([0-9]+) .*$/\\1/p" | tail -1)"
    [ -n "$n" ] \
      || die "the striding run reported no restart for $t; the hub was strided but no floors were written. Record them from the restart values above: cloud/scripts/record-down-floors.sh odoo --from-file <file> -- <psql command>"
    rows="$rows$t $n
"
  done

  # validate, then write the floors file
  tmp="$OUT.tmp.$$"
  printf '%s' "$rows" > "$tmp" || die "could not write $tmp"
  bash "$HERE/down-floors.sh" "$tmp" >/dev/null \
    || { rm -f "$tmp"; die "the restart values do not validate as floors (above); the hub was strided but no floors were written"; }
  mv "$tmp" "$OUT"

  printf '%s' "$rows" | sed 's/^/  floor /'
  echo "  wrote $OUT ($(printf '%s' "$rows" | grep -c .) tables)"
}


# ==== OpenELIS ==================================================================

stride_openelis() {
  # ---- refuse sequences another node has strided (a step other than 1 or 10, or off residue 0)

  local foreign_strides_sql="select coalesce(string_agg(format('%s (steps by %s from %s)', s.sequencename, s.increment_by, x.lv), ', ' order by s.sequencename), '')
    from pg_sequences s
    cross join lateral (
      select (xpath('/row/lv/text()', query_to_xml(format('select last_value as lv from %I.%I', s.schemaname, s.sequencename), false, true, '')))[1]::text::bigint as lv
    ) x
    where s.schemaname = 'clinlims'
      and (s.increment_by not in (1, 10) or (s.increment_by = 10 and x.lv % 10 <> 0))"

  bad="$("$@" -v ON_ERROR_STOP=1 -qAt -c "$foreign_strides_sql" < /dev/null 2>&1)" \
    || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$bad" | sed -n 's/^.*ERROR: *//p' | head -1)"
  [ -z "$bad" ] || die "not the hub's striding (residue 0): ${bad}; nothing was written or strided"

  # ---- floors: check the recorded ones, or record them on the first striding

  if [ -e "$OUT" ]; then
    # refuse a clinic-written table whose sequence would issue below its floor
    floors="$(bash "$HERE/down-floors.sh" "$OUT" clinlims)" \
      || die "$OUT cannot be read (reason above); nothing was strided"
    down="$(bash "$R/sync/tables/tables.sh" openelis unrouted)" \
      || die "the down list could not be read (reason above); nothing was strided"

    if [ -n "$down" ]; then
      state="$("$@" -v ON_ERROR_STOP=1 -qAt \
                 -v tables="$(printf '%s\n' "$down" | paste -sd, -)" \
                 -f /dev/stdin < "$R/cloud/openelis/down-sequence-state.sql" 2>&1)" \
        || die "the OpenELIS sequences could not be read; nothing was strided: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"

      up=" $(bash "$R/sync/tables/tables.sh" openelis up | tr '\n' ' ') "

      while IFS='|' read -r t restart nxt inc; do
        [ -n "$t" ] || continue
        f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
        [ -n "$f" ] \
          || die "$OUT records no floor for $t; nothing was strided. Its floor is the value its sequence restarted at when the hub's OpenELIS ids were first strided: add that line by hand from the striding record"

        case "$up" in *" $t "*) ;; *) continue ;; esac

        if [ "$inc" = 10 ]; then at="$nxt"; else at="$restart"; fi
        [ "$at" -ge "$f" ] \
          || die "clinlims.$t would issue $at, below its recorded floor $f (the database holds fewer rows than when it was strided); nothing was strided"
      done <<EOF
$state
EOF
    fi
    kept=1

  else
    # no floors yet: on a first striding, record them before anything is strided; on a hub
    # strided before, stride (lifting sequences behind their rows), then record them from the rows
    kept=0
    late=0
    if ! rec="$(bash "$HERE/record-down-floors.sh" openelis --out "$OUT" -- "$@" 2>&1)"; then
      case "$rec" in
        *"were strided before"*)
          p="$("$@" -v ON_ERROR_STOP=1 -qAt \
                 -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" \
                 < /dev/null 2>&1)" \
            || die "the replication origins could not be read; nothing was strided: $p"
          [ "$p" = 0 ] \
            || die "no floors file at $OUT, and $p clinic replication origin(s) show progress: a floor read from the rows could sit above clinics' rows; nothing was strided. Record the floors captured when the hub was first strided: cloud/scripts/record-down-floors.sh openelis --from-file <file> -- <psql command>"
          late=1
          ;;
        *)
          printf '%s\n' "$rec" >&2
          die "the floors could not be recorded (above); nothing was strided"
          ;;
      esac
    else
      printf '%s\n' "$rec"
    fi
  fi

  # ---- stride

  o="$("$@" -v ON_ERROR_STOP=1 -qAt -f /dev/stdin < "$R/cloud/openelis/apply-sequence-striding.sql" 2>&1)" \
    || { printf '%s\n' "$o" >&2; die "apply-sequence-striding.sql failed (above)"; }

  printf '%s\n' "$o" | sed -n -E 's/^.*NOTICE: +//p; /^sequences step 10: /p' | sed 's/^/  /'
  [ "$kept" = 0 ] || echo "  floors kept: $OUT is unchanged"

  # ---- a hub strided before: its floors, read from the rows now that every sequence is clear of them

  if [ "${late:-0}" = 1 ]; then
    tmp="$OUT.derived.$$"
    bash "$HERE/record-down-floors.sh" openelis --derive --out "$OUT" -- "$@" > "$tmp" \
      || { rm -f "$tmp"; die "the hub was strided but its floors could not be derived (above); no floors were written"; }
    bash "$HERE/record-down-floors.sh" openelis --from-file "$tmp" --out "$OUT" -- "$@" \
      || { rm -f "$tmp"; die "the hub was strided but its floors could not be recorded (above); no floors were written"; }
    rm -f "$tmp"
  fi
}


# ==== run =======================================================================

case "$DB" in
  odoo)     stride_odoo "$@" ;;
  openelis) stride_openelis "$@" ;;
esac
