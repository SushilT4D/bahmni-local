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
# already stepping by 10 are left as they are, so a re-run moves nothing.
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
bad="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select coalesce(string_agg(format('%s (steps by %s from %s)', sequencename, increment_by, coalesce(last_value, start_value)), ', ' order by sequencename), '') from pg_sequences where schemaname = 'clinlims' and (increment_by not in (1, 10) or (increment_by = 10 and coalesce(last_value, start_value) % 10 <> 0))" 2>&1)" \
  || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$bad" | sed -n 's/^.*ERROR: *//p' | head -1)"
[ -z "$bad" ] || die "not the hub's striding (residue 0): ${bad}; nothing was written or strided"

if [ -e "$OUT" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$OUT" clinlims)" || die "$OUT cannot be read (reason above); nothing was strided"
  down="$(bash "$R/sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above); nothing was strided"
  if [ -n "$down" ]; then
    state="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/openelis/down-sequence-state.sql" 2>&1)" \
      || die "the OpenELIS sequences could not be read; nothing was strided: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
    while IFS='|' read -r t restart nxt inc; do
      [ -n "$t" ] || continue
      f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
      [ -n "$f" ] || die "$OUT records no floor for $t; nothing was strided. Its floor is the value its sequence restarted at when the hub's OpenELIS ids were first strided: add that line by hand from the striding record"
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
