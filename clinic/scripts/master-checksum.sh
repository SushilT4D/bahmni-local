#!/usr/bin/env bash
# Print a row count and a content checksum for every table hub/tables.conf
# lists, from one OpenMRS MySQL. Run it on the hub and on a clinic seeded from
# that hub and compare the two outputs line by line: a table whose line differs
# holds different rows.
#
#   clinic/scripts/master-checksum.sh [--reseed] [--container NAME] [--database DB]
#
# --reseed      also the tables hub/table-verdicts.conf marks RESEED (delivered
#               by the seed only), whose checksum must stay equal to the hub's
# --container   the MySQL container (default <COMPOSE_PROJECT_NAME>-bahmni-mysql-1,
#               COMPOSE_PROJECT_NAME from clinic/.env); needed on the hub
# --database    the OpenMRS schema (default openmrs)
#
# The checksum covers every column of every row, read from
# information_schema.COLUMNS, except the columns hub/checksum-exclusions.conf
# lists: a row edited in place keeps its id and uuid but changes the checksum.
# Each column is hashed with its length and a NULL marker, so a NULL never
# collides with an empty string or with a value moved to the next column, and
# the per-row hashes are summed, so row order does not matter. The session
# reads in UTC: MySQL renders a TIMESTAMP column in the session's time zone,
# so two servers with different default zones would otherwise hash the same
# stored instant differently.
#
# Output, sorted by table, tab-separated:
#   <table>  <rows>  <checksum>  <column count>:<hash of the column names>
#   <table>  absent
# Read-only: one READ ONLY transaction with a consistent snapshot, run as root
# inside the container. RUNTIME=docker|podman overrides the platform's default.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
RESEED=0; MY=""; DB=openmrs
while [ $# -gt 0 ]; do
  case "$1" in
    --reseed) RESEED=1; shift ;;
    --container) MY="${2:?--container needs a name}"; shift 2 ;;
    --database) DB="${2:?--database needs a name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; fail "unknown argument: $1" ;;
  esac
done
printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || fail "bad database name: $DB"

tables="$(down_tables)" || fail "could not read hub/tables.conf"
if [ "$RESEED" = 1 ]; then
  V="${REPO_DIR}/hub/table-verdicts.conf"
  [ -f "$V" ] || fail "no ${V}"
  tables="${tables}
$(awk '{ sub(/#.*/, "") } $2 == "RESEED" { print $1 }' "$V")"
fi
tables="$(printf '%s\n' "$tables" | grep -E '^[a-z_][a-z0-9_]*$' | sort -u)"
[ -n "$tables" ] || fail "no tables to checksum"

X="${REPO_DIR}/hub/checksum-exclusions.conf"
[ -f "$X" ] || fail "no ${X}: the list of excluded columns is required, even when it is empty"
excl="$(awk '{ sub(/#.*/, "") } NF { print $1 }' "$X")"
for e in $excl; do
  printf '%s' "$e" | grep -qE '^[a-z_][a-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$' || fail "${X}: '${e}' is not <table>.<column>"
done

if [ -z "$MY" ]; then
  E="${CLINIC_DIR}/.env"
  [ -f "$E" ] || fail "no ${E}: name the MySQL container with --container"
  COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
  [ -n "${COMPOSE_PROJECT_NAME}" ] || fail "clinic/.env has no COMPOSE_PROJECT_NAME: name the MySQL container with --container"
  MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
fi
[ -n "${CT:-}" ] || setup_compose
mysql_ro(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B'; }

inlist="$(printf '%s\n' "$tables" | sed "s/.*/'&'/" | paste -sd, -)"
cols="$(printf "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='%s' AND TABLE_NAME IN (%s) ORDER BY TABLE_NAME, COLUMN_NAME;\n" "$DB" "$inlist" | mysql_ro)" \
  || fail "could not read information_schema.COLUMNS in ${MY}: is MySQL running?"

# One SELECT per table present; a listed table with no columns is absent.
sql="$(printf '%s\n' "$cols" | awk -F'\t' -v q="'" -v db="$DB" -v tables="$(printf '%s' "$tables" | tr '\n' ' ')" -v excl="$(printf '%s' "$excl" | tr '\n' ' ')" '
  BEGIN {
    n = split(excl, ex, / +/); for (i = 1; i <= n; i++) if (ex[i] != "") skip[ex[i]] = 1
    print "SET SESSION time_zone = " q "+00:00" q ";"
    print "SET SESSION TRANSACTION READ ONLY;"
    print "START TRANSACTION WITH CONSISTENT SNAPSHOT;"
  }
  NF >= 3 && !(($1 "." $2) in skip) {
    t = $1; c = $2; ty = tolower($3)
    if (ty ~ /^(binary|varbinary|tinyblob|blob|mediumblob|longblob|bit|geometry|point|linestring|polygon|multipoint|multilinestring|multipolygon|geometrycollection)$/)
      v = "HEX(`" c "`)"
    else
      v = "CAST(`" c "` AS CHAR CHARACTER SET utf8mb4)"
    e = "IFNULL(CONCAT(LENGTH(" v "), " q ":" q ", " v "), " q "N" q ")"
    expr[t] = (t in expr) ? expr[t] ", " e : e
    names[t] = (t in names) ? names[t] "," c : c
    ncol[t]++
  }
  END {
    m = split(tables, ts, / +/)
    for (i = 1; i <= m; i++) {
      t = ts[i]; if (t == "") continue
      if (!(t in expr)) { print "SELECT " q t q ", " q "absent" q ";"; continue }
      printf "SELECT %s%s%s, COUNT(*), COALESCE(SUM(CAST(CONV(LEFT(MD5(CONCAT(%s)), 16), 16, 10) AS UNSIGNED)), 0), CONCAT(%s%d:%s, LEFT(MD5(%s%s%s), 12)) FROM `%s`.`%s`;\n", q, t, q, expr[t], q, ncol[t], q, q, names[t], q, db, t
    }
    print "COMMIT;"
  }')"
out="$(printf '%s\n' "$sql" | mysql_ro)" || fail "the checksum query failed in ${MY}"
printf '%s\n' "$out" | grep -v '^$' | LC_ALL=C sort
