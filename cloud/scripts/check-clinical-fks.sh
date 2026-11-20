#!/usr/bin/env bash
# Checks the foreign keys on obs, orders, drug_order and test_order in the hub's OpenMRS schema. Read-only.
#   OUT: no foreign key out of them to a table a clinic writes (one would stop an up sink).
#   IN:  the foreign keys into them match cloud/scripts/clinical-fks-in.conf.
# usage: check-clinical-fks.sh --container NAME [--database DB] | --from FILE
# Exit: 0 both pass; 1 an FK out (or the read failed); 2 the FKs in differ. RUNTIME picks docker or podman.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd "${HERE}/.." && pwd)"
BASELINE="${CLINICAL_FKS_IN:-${HERE}/clinical-fks-in.conf}"
VERDICTS="${CLINICAL_FK_VERDICTS:-${HUB_DIR}/table-verdicts.conf}"

# the clinical tables, as a list, as SQL, and their count
CLINICAL="obs orders drug_order test_order"
CLINICAL_SQL="$(printf "'%s', " $CLINICAL | sed 's/, $//')"
NCLINICAL="$(printf '%s\n' $CLINICAL | grep -c .)"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
die()   { printf 'FAIL %s\n' "$*"; exit 1; }


# ---- arguments ---------------------------------------------------------------

MY=""
DB=openmrs
FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --container) MY="${2:?--container needs a name}"; shift 2 ;;
    --database)  DB="${2:?--database needs a name}"; shift 2 ;;
    --from)      FROM="${2:?--from needs a file}"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown argument: $1" ;;
  esac
done

printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || die "bad database name: $DB"
[ -f "$BASELINE" ] || die "no ${BASELINE}: the recorded FKs into the clinical tables are required"
[ -f "$VERDICTS" ] || die "no ${VERDICTS}: the table verdicts are required to tell a hub-written parent from a clinic-written one"

# tables only the hub writes (DOWN) or only changesets and the seed write (RESEED)
HUB_WRITTEN=" $(awk '{ sub(/#.*/, "") } NF >= 2 && ($2 == "DOWN" || $2 == "RESEED") { print $1 }' "$VERDICTS" | tr '\n' ' ') "


# ---- read the foreign keys from information_schema, or from --from -------------

SQL="SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME, CONSTRAINT_NAME
  FROM information_schema.KEY_COLUMN_USAGE
  WHERE TABLE_SCHEMA = '${DB}'
    AND REFERENCED_TABLE_NAME IS NOT NULL
    AND (TABLE_NAME IN (${CLINICAL_SQL}) OR REFERENCED_TABLE_NAME IN (${CLINICAL_SQL}))
  ORDER BY 1, 2;
SELECT 'schema', COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '${DB}' AND TABLE_NAME IN (${CLINICAL_SQL});"

if [ -n "$FROM" ]; then
  [ -f "$FROM" ] || die "no such file: $FROM"
  rows="$(cat "$FROM")"
else
  [ -n "$MY" ] || { usage >&2; die "--container or --from is required"; }

  CT="${RUNTIME:-}"
  if [ -z "$CT" ]; then
    for c in docker podman; do
      command -v "$c" >/dev/null 2>&1 && "$c" ps >/dev/null 2>&1 && { CT="$c"; break; }
    done
  fi
  [ -n "$CT" ] || die "no working container engine (tried docker, podman)"

  rows="$(printf '%s\n' "$SQL" | "$CT" exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B' 2>/dev/null)" \
    || die "could not read information_schema in ${MY}; nothing was checked"
fi

# every clinical table must exist, or the checks would check nothing
n="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="schema" {print $2}')"
[ "${n:-}" = "$NCLINICAL" ] \
  || die "${DB} does not hold all ${NCLINICAL} of $(printf '%s' "$CLINICAL" | sed 's/ /, /g') (found ${n:-no answer}); nothing was checked"
rows="$(printf '%s\n' "$rows" | awk -F'\t' 'NF >= 4 && $1 != "schema"')"


# ---- OUT: foreign keys out of each clinical table -------------------------------

rc=0
for t in $CLINICAL; do
  out="$(printf '%s\n' "$rows" | awk -F'\t' -v t="$t" -v hw="$HUB_WRITTEN" \
    '$1==t && index(hw, " " $3 " ") == 0 {print $1 "." $2 " -> " $3 "." $4 " (" $5 ")"}')"
  hub="$(printf '%s\n' "$rows" | awk -F'\t' -v t="$t" -v hw="$HUB_WRITTEN" \
    '$1==t && index(hw, " " $3 " ") > 0 {print $1 "." $2 " -> " $3 "." $4 " (" $5 ")"}')"

  if [ -n "$out" ]; then
    printf 'FAIL %s has %s foreign key(s) out of it to a table a clinic writes; an early-arriving row would stop its up sink:\n' \
      "$t" "$(printf '%s\n' "$out" | grep -c .)"
    printf '%s\n' "$out" | sed 's/^/       /'
    rc=1
  elif [ -n "$hub" ]; then
    printf 'ok   %s: no foreign key out to a table a clinic writes; %s to a table only the hub writes: %s\n' \
      "$t" "$(printf '%s\n' "$hub" | grep -c .)" "$(printf '%s\n' "$hub" | paste -sd';' - | sed 's/;/; /g')"
  else
    printf 'ok   %s: no foreign key out\n' "$t"
  fi
done


# ---- IN: foreign keys into the clinical tables, against the recorded list -------

want="$(awk '{ sub(/#.*/, "") } NF == 4 { print $1, $2, $3, $4 }' "$BASELINE" | LC_ALL=C sort)"
got="$(printf '%s\n' "$rows" | awk -F'\t' -v c=" $CLINICAL " 'index(c, " " $3 " ") {print $1, $2, $3, $4}' | LC_ALL=C sort)"

# lines of $2 that are not in $1
lines_not_in() {
  { printf '%s\n' "$1"; printf '\001\n'; printf '%s\n' "$2"; } \
    | awk '$0 == "\001" { s = 1; next } !s { a[$0] = 1; next } $0 != "" && !($0 in a) { print }'
}
added="$(lines_not_in "$want" "$got")"
gone="$(lines_not_in "$got" "$want")"

if [ -z "$added" ] && [ -z "$gone" ]; then
  printf 'ok   %s foreign key(s) into the clinical tables, as recorded in %s\n' \
    "$(printf '%s\n' "$got" | grep -c . || true)" "${BASELINE##*/}"
else
  if [ -n "$added" ]; then
    printf 'CHANGED foreign key(s) into the clinical tables not in %s (a clinic'"'"'s delete of a row they reference would stop that sink):\n' "${BASELINE##*/}"
    printf '%s\n' "$added" | awk '{print "       + " $1 "." $2 " -> " $3 "." $4}'
  fi
  if [ -n "$gone" ]; then
    printf 'CHANGED foreign key(s) into the clinical tables recorded in %s but no longer on this hub:\n' "${BASELINE##*/}"
    printf '%s\n' "$gone" | awk '{print "       - " $1 "." $2 " -> " $3 "." $4}'
  fi
  [ "$rc" = 1 ] || rc=2
fi

exit "$rc"
