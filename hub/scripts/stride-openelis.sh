#!/usr/bin/env bash
# stride-openelis.sh [--floors FILE] -- PSQL-COMMAND...
#
# Strides the hub's OpenELIS ids (residue 0) with hub/openelis/apply-sequence-striding.sql
# and, on the first striding, records the floor of each down table the hub's
# OpenELIS publication filters (sync/hub-down.sh --unrouted clinlims; today
# system_user) just before it: record-clinlims-down-floors.sh, which reads where
# the striding is about to restart each sequence. FILE defaults to
# hub/clinlims-down-floors.local, one "<table> <floor>" line per table.
#
# The floors are recorded once. When FILE already exists, a re-run never
# changes it: it refuses, before striding, when a filtered table's sequence
# would restart (or already issues) below its recorded floor, which means the
# database went back, or when a filtered table has no recorded floor. Sequences
# already stepping by 10 are left as they are, unless one would issue an id at
# or below the largest id of its tables: a re-run lifts that one above them.
#
# A first recording is allowed only on a first striding, and only while no
# clinic's replication origin shows progress (record-clinlims-down-floors.sh
# refuses otherwise and names --from-file). Nothing is strided when the floors
# cannot be recorded.
#
# PSQL-COMMAND reaches the hub's openelis database as a superuser, for example:
#   hub/scripts/stride-openelis.sh -- docker exec -i <openelis-db-container> psql -U postgres -d openelis
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
OUT="$HERE/../clinlims-down-floors.local"
[ "${1:-}" = --floors ] && { OUT="${2:?--floors needs a file}"; shift 2; }
[ "${1:-}" = -- ] && shift
[ "$#" -gt 0 ] || { echo "usage: stride-openelis.sh [--floors FILE] -- <psql command...>" >&2; exit 2; }
die(){ printf 'stride-openelis.sh: %s\n' "$*" >&2; exit 1; }

# Another node's striding (a sequence stepping by something other than 1 or 10,
# or by 10 off a multiple of 10) is refused before anything is recorded or
# strided. apply-sequence-striding.sql refuses the same sequences itself.
# Each last value is read from the sequence itself: pg_sequences shows none for
# a sequence restarted and not used since, and its start value says nothing
# about where the striding left it.
bad="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select coalesce(string_agg(format('%s (steps by %s from %s)', s.sequencename, s.increment_by, x.lv), ', ' order by s.sequencename), '') from pg_sequences s cross join lateral (select (xpath('/row/lv/text()', query_to_xml(format('select last_value as lv from %I.%I', s.schemaname, s.sequencename), false, true, '')))[1]::text::bigint as lv) x where s.schemaname = 'clinlims' and (s.increment_by not in (1, 10) or (s.increment_by = 10 and x.lv % 10 <> 0))" < /dev/null 2>&1)" \
  || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$bad" | sed -n 's/^.*ERROR: *//p' | head -1)"
[ -z "$bad" ] || die "not the hub's striding (residue 0): ${bad}; nothing was written or strided"

if [ -e "$OUT" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$OUT" clinlims)" || die "$OUT cannot be read (reason above); nothing was strided"
  down="$(bash "$R/sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above); nothing was strided"
  if [ -n "$down" ]; then
    state="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/openelis/down-sequence-state.sql" 2>&1)" \
      || die "the OpenELIS sequences could not be read; nothing was strided: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
    # The tables clinics also write and send up (sync/subsystems.conf). Only for
    # those does an id issued below the floor matter; the lab test catalogue is
    # written at the hub alone, and its floor may stand above its sequence (some
    # catalogue sequences stand below the rows they hold).
    up=" $(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$R/sync/subsystems.conf" | sed -n 's/^clinlims://p' | grep -vx all | tr '\n' ' ') "
    while IFS='|' read -r t restart nxt inc; do
      [ -n "$t" ] || continue
      f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
      [ -n "$f" ] || die "$OUT records no floor for $t; nothing was strided. Its floor is the value its sequence restarted at when the hub's OpenELIS ids were first strided: add that line by hand from the striding record"
      case "$up" in *" $t "*) ;; *) continue ;; esac
      if [ "$inc" = 10 ]; then at="$nxt"; else at="$restart"; fi
      [ "$at" -ge "$f" ] || die "clinlims.$t would issue $at, below its recorded floor $f (the database holds fewer rows than when it was strided); nothing was strided"
    done <<EOF
$state
EOF
  fi
  kept=1
else
  rec="$(bash "$HERE/record-clinlims-down-floors.sh" --out "$OUT" -- "$@" 2>&1)" \
    || { printf '%s\n' "$rec" >&2; die "the floors could not be recorded (above); nothing was strided"; }
  printf '%s\n' "$rec"
  kept=0
fi

o="$("$@" -v ON_ERROR_STOP=1 -qAt -f /dev/stdin < "$R/hub/openelis/apply-sequence-striding.sql" 2>&1)" \
  || { printf '%s\n' "$o" >&2; die "apply-sequence-striding.sql failed (above)"; }
printf '%s\n' "$o" | sed -n -E 's/^.*NOTICE: +//p; /^sequences step 10: /p' | sed 's/^/  /'
[ "$kept" = 0 ] || echo "  floors kept: $OUT is unchanged"
