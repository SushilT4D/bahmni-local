#!/usr/bin/env bash
# record-clinlims-down-floors.sh [--from-file FILE] [--out OUT] -- PSQL-COMMAND...
#
# Records the hub's floor of each OpenELIS down table its publication filters
# (sync/hub-down.sh --unrouted clinlims; today system_user) in OUT, default
# hub/clinlims-down-floors.local, one "<table> <floor>" line each. The
# publication sends such a table's rows below the floor (the hub's, from before
# its ids were strided) or ending in 0 (the hub's since), and nothing a clinic
# minted. OUT is written once and never rewritten.
#
# Without --from-file it is run immediately BEFORE the hub's OpenELIS ids are
# strided, and records where the stride will restart each sequence:
# ((last_value / 10) + 1) * 10, the hub's OpenELIS striding's own restart.
# Refused, writing nothing, when a sequence already steps by more than 1 (the
# hub was strided before: its restart values are gone; record those captured
# then, or derive them, with --from-file), or when any clinic's replication
# origin (clinic_*) shows progress (clinics' rows may already sit above it).
#
# With --from-file FILE ("<table> <floor>" lines) it records values captured
# or derived elsewhere, after checking them against the database: each table
# listed once, the sequence stepping by 10, the floor a multiple of 10 and not
# above the id the sequence issues next.
#
# PSQL-COMMAND reaches the hub's openelis database as a superuser, for example:
#   hub/scripts/record-clinlims-down-floors.sh -- docker exec -i <openelis-db-container> psql -U postgres -d openelis
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$HERE/../.."
OUT="$HERE/../clinlims-down-floors.local"; SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from-file) SRC="${2:?--from-file needs a file}"; shift 2 ;;
    --out) OUT="${2:?--out needs a file}"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
die(){ printf 'record-clinlims-down-floors.sh: %s\n' "$*" >&2; exit 1; }
[ "$#" -gt 0 ] || { echo "usage: record-clinlims-down-floors.sh [--from-file FILE] [--out OUT] -- <psql command...>" >&2; exit 2; }
[ -e "$OUT" ] && die "$OUT already exists: it holds this hub's OpenELIS floors and is never rewritten"
down="$(bash "$R/sync/hub-down.sh" --unrouted clinlims)" || die "the down list could not be read (reason above); nothing was written"
[ -n "$down" ] || die "sync/hub-down.conf sends no OpenELIS table down filtered on a floor; there is nothing to record"
state="$("$@" -v ON_ERROR_STOP=1 -qAt -v tables="$(printf '%s\n' "$down" | paste -sd, -)" -f /dev/stdin < "$R/hub/openelis/down-sequence-state.sql" 2>&1)" \
  || die "the OpenELIS sequences could not be read; nothing was written: $(printf '%s\n' "$state" | sed -n 's/^.*ERROR: *//p' | head -1)"
rows=""
if [ -n "$SRC" ]; then
  floors="$(bash "$HERE/down-floors.sh" "$SRC" clinlims)" || die "$SRC cannot be read as OpenELIS floors (reason above); nothing was written"
  while IFS='|' read -r t _restart nxt inc; do
    [ -n "$t" ] || continue
    f="$(printf '%s\n' "$floors" | awk -v t="$t" '$1 == t { print $2 }')"
    [ -n "$f" ] || die "$SRC gives no floor for $t; nothing was written"
    [ "$inc" = 10 ] || die "clinlims.$t's sequence steps by $inc, not 10: it has not been strided; nothing was written"
    [ "$f" -le "$nxt" ] || die "the floor given for $t, $f, is above the id its sequence issues next ($nxt), so it cannot be where it restarted; nothing was written"
    rows="$rows$t $f
"
  done <<EOF
$state
EOF
else
  strided="$(printf '%s\n' "$state" | awk -F'|' 'NF == 4 && $4 != 1 { printf "%s%s (steps by %s)", (n++ ? ", " : ""), $1, $4 }')"
  [ -z "$strided" ] || die "this hub's OpenELIS ids were strided before: ${strided}. Their floors are the values the sequences restarted at then; nothing was written. Record them with --from-file <file>"
  p="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select count(*) from pg_replication_origin_status where external_id like 'clinic\_%' and (remote_lsn <> '0/0' or local_lsn <> '0/0')" 2>&1)" \
    || die "the replication origins could not be read; nothing was written: $p"
  [ "$p" = 0 ] || die "$p clinic replication origin(s) show progress: clinics' rows may have reached this hub, so a floor read now could sit above them; nothing was written. Record the floors with --from-file <file>"
  rows="$(printf '%s\n' "$state" | awk -F'|' 'NF == 4 { print $1, $2 }')
"
fi
tmp="$OUT.tmp.$$"
printf '%s' "$rows" > "$tmp" || die "could not write $tmp"
bash "$HERE/down-floors.sh" "$tmp" clinlims >/dev/null || { rm -f "$tmp"; die "the values do not validate as floors (above); nothing was written"; }
mv "$tmp" "$OUT"
printf '%s' "$rows" | sed 's/^/  floor /'
echo "  wrote $OUT ($(printf '%s' "$rows" | grep -c .) tables)"
