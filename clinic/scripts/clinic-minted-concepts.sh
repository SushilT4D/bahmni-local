#!/usr/bin/env bash
# Before the concept dictionary's down sinks start on a clinic: finds the
# concept rows this clinic minted for itself, and with --rekey moves the ones
# the hub also holds to the hub's ids.
#
#   clinic/scripts/clinic-minted-concepts.sh --hub-query
#   clinic/scripts/clinic-minted-concepts.sh --hub-ids FILE [--rekey] [--container NAME] [--database DB]
#
# The tables are the rows hub/tables.conf marks `changes` (the concept
# dictionary): the hub writes them and sends changes only, so a clinic must
# already hold the hub's rows under the hub's ids. Three kinds of clinic row
# break that, and each would stop or corrupt a down sink:
#   twin       the hub holds the row's uuid under another id. OpenMRS mints
#              such rows at the first start of a new image on a clinic that
#              keeps its own database: module changesets create concepts,
#              names and sets with fixed uuids on the clinic's own counter. The
#              hub's first change to that concept arrives under the hub's id
#              and stops the sink on the duplicate uuid.
#   collision  the hub holds the row's id with another uuid, and the row is not
#              a twin being moved away: the hub's next change to that id would
#              overwrite a different concept here.
#   residue    the row's id is above the hub's last id on a residue other than
#              0 (the hub mints on residue 0 above it) and is not on 0, and the
#              hub does not hold the row: a concept made here alone.
#
# --hub-query prints the read-only query that reads the hub's side: every row's
# id and uuid, and per table the hub's last id on a residue other than 0. Run
# it against the hub's OpenMRS MySQL with `mysql -N -B` and save the output as
# FILE; the same query is run here against this clinic's MySQL.
#
# With --hub-ids FILE it prints one line per finding,
#   twin <table> <clinic id> <hub id> <uuid>
#   collision <table> <id> <clinic uuid> <hub uuid>
#   residue <table> <id> <uuid>
# and exits 0 when there is none, 1 when there is any, 2 when it cannot judge.
#
# --rekey moves every twin to the hub's id, in one transaction with binary
# logging off (the move is not captured and does not travel up), and rewrites
# every reference to it: the concept tables among themselves, every column the
# schema declares a foreign key to one of these tables, obs.concept_id,
# obs.value_coded and obs.value_coded_name_id, and a global property whose
# value is exactly a moved concept's id and whose name speaks of a concept.
# Each row is moved through a temporary negative id, so a row may move onto an
# id another moving row leaves. Before COMMIT it checks, and stops (rolling
# back) at the first that fails: each table's row count unchanged, each
# table's set of uuids unchanged, each moved row at the hub's id with its uuid,
# no negative id left, no reference left to an id that no longer exists, every
# reference to a moved row finding it. It refuses, changing nothing:
#   - with any collision (a row is in the way of a move, or would be
#     overwritten), or when OpenMRS is running (it caches these rows; stop it
#     first, and its next start rebuilds the search index);
#   - when a table this clinic sends up (sync/local/tables.conf, obs among
#     them) refers to a row that would move: its copy at the hub would keep the
#     old id;
#   - when another column whose name speaks of a concept, or a global property
#     other than an exact one named for a concept, holds a moving concept's id:
#     it is listed for a person to decide.
# After COMMIT it runs the check again; residue findings are not moved (the hub
# does not hold those rows) and keep the exit status 1.
#
# --container   the MySQL container (default <COMPOSE_PROJECT_NAME>-bahmni-mysql-1,
#               COMPOSE_PROJECT_NAME from clinic/.env)
# --database    the OpenMRS schema (default openmrs)
# RUNTIME=docker|podman overrides the platform's default runtime.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLINIC_DIR="${CLINIC_DIR:-$(cd "${HERE}/.." && pwd)}"; export CLINIC_DIR
REPO_DIR="${REPO_DIR:-$(cd "${HERE}/../.." && pwd)}"; export REPO_DIR
# shellcheck disable=SC1091
. "${HERE}/../install/lib.sh"
usage(){ sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
die2(){ printf '  FAIL %s\n' "$*" >&2; exit 2; }
MODE=check; HUBF=""; MY=""; DB=openmrs
while [ $# -gt 0 ]; do
  case "$1" in
    --hub-query) MODE=query; shift ;;
    --hub-ids) HUBF="${2:?--hub-ids needs a file}"; shift 2 ;;
    --rekey) MODE=rekey; shift ;;
    --container) MY="${2:?--container needs a name}"; shift 2 ;;
    --database) DB="${2:?--database needs a name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die2 "unknown argument: $1" ;;
  esac
done
printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || die2 "bad database name: $DB"

# concept_numeric rows extend a concept row under the concept's own id and
# carry no uuid of their own.
NO_UUID=" concept_numeric "
SPECS="$(awk '{ sub(/#.*/, ""); gsub(/[ \t]/, "") } NF { n = split($0, f, ":"); if (n == 3 && f[3] == "changes") print f[1], f[2] }' "${REPO_DIR}/hub/tables.conf")"
[ -n "$SPECS" ] || die2 "hub/tables.conf marks no table \`changes\`: there is no concept table to check"
while read -r t pk; do
  printf '%s %s' "$t" "$pk" | grep -qE '^[a-z_][a-z0-9_]* [a-z_][a-z0-9_]*$' || die2 "hub/tables.conf: '$t:$pk:changes' needs a single-column key"
done <<EOF
$SPECS
EOF
TABLES="$(printf '%s\n' "$SPECS" | awk '{ print $1 }')"
pk_of(){ printf '%s\n' "$SPECS" | awk -v t="$1" '$1 == t { print $2 }'; }
is_no_uuid(){ case "$NO_UUID" in *" $1 "*) return 0 ;; esac; return 1; }

# One read, run alike on the hub and here: "row <table> <id> <uuid>" and
# "last-legacy <table> <id>" lines, tab-separated, from one consistent snapshot.
ids_query(){
  printf 'SET SESSION TRANSACTION READ ONLY;\nSTART TRANSACTION WITH CONSISTENT SNAPSHOT;\n'
  printf "SELECT 'format', 'concept-ids', '1', '';\n"
  while read -r t pk; do
    printf "SELECT 'last-legacy', '%s', COALESCE(MAX(CASE WHEN \`%s\` %% 10 <> 0 THEN \`%s\` END), 0), '' FROM \`%s\`.\`%s\`;\n" "$t" "$pk" "$pk" "$DB" "$t"
    if is_no_uuid "$t"; then printf "SELECT 'row', '%s', \`%s\`, '' FROM \`%s\`.\`%s\`;\n" "$t" "$pk" "$DB" "$t"
    else printf "SELECT 'row', '%s', \`%s\`, uuid FROM \`%s\`.\`%s\`;\n" "$t" "$pk" "$DB" "$t"; fi
  done <<EOF
$SPECS
EOF
  printf 'COMMIT;\n'
}
if [ "$MODE" = query ]; then ids_query; exit 0; fi

[ -n "$HUBF" ] || { usage >&2; die2 "--hub-ids FILE is needed (the hub's side, read with --hub-query)"; }
[ -s "$HUBF" ] || die2 "no hub file at ${HUBF} (or it is empty): read it on the hub with --hub-query"
head -1 "$HUBF" | grep -qE '^format	concept-ids	1	?$' || die2 "${HUBF} is not the output of --hub-query (its first line is not the format line)"
for t in $TABLES; do
  grep -qE "^last-legacy	${t}	[0-9]+	?$" "$HUBF" || die2 "${HUBF} has no line for ${t}: read it again with this checkout's --hub-query"
done

E="${CLINIC_DIR}/.env"
[ ! -f "$E" ] || COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
if [ -z "$MY" ]; then
  [ -f "$E" ] || die2 "no ${E}: name the MySQL container with --container"
  [ -n "${COMPOSE_PROJECT_NAME}" ] || die2 "clinic/.env has no COMPOSE_PROJECT_NAME: name the MySQL container with --container"
  MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
fi
[ -n "${CT:-}" ] || setup_compose
my(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B'; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
TAB="$(printf '\t')"

# the clinic's columns: every concept table must be here, with a uuid where the hub has one
printf "SELECT table_name, column_name, data_type, column_type, column_key FROM information_schema.columns WHERE table_schema = '%s';\n" "$DB" | my > "$W/cols" \
  || die2 "could not read information_schema in ${MY}: is MySQL running?"
for t in $TABLES; do
  awk -F'\t' -v t="$t" -v c="$(pk_of "$t")" '$1 == t && $2 == c { f = 1 } END { exit !f }' "$W/cols" || die2 "${DB}.${t} has no column $(pk_of "$t") on this clinic"
  if is_no_uuid "$t"; then :; else awk -F'\t' -v t="$t" '$1 == t && $2 == "uuid" { f = 1 } END { exit !f }' "$W/cols" || die2 "${DB}.${t} has no uuid column on this clinic"; fi
done
ids_query | my > "$W/clinic" || die2 "the concept tables could not be read in ${MY}"

# --- the findings -----------------------------------------------------------------
findings(){ # HUBFILE CLINICFILE -> finding lines on stdout
  local h="$1" c="$2"
  awk -F'\t' '$1 == "row" && $4 != "" { print $2 "|" $4 "\t" $3 }' "$h" | LC_ALL=C sort > "$W/hu"
  awk -F'\t' '$1 == "row" && $4 != "" { print $2 "|" $4 "\t" $3 }' "$c" | LC_ALL=C sort > "$W/cu"
  # twins: the same uuid under two ids -> table uuid clinic-id hub-id
  LC_ALL=C join -t "$TAB" "$W/hu" "$W/cu" | awk -F'\t' '$2 != $3 { split($1, k, "|"); print k[1] "\t" k[2] "\t" $3 "\t" $2 }' > "$W/twins"
  awk -F'\t' '$1 == "row" && $4 != "" { print $2 "|" $3 "\t" $4 }' "$h" | LC_ALL=C sort > "$W/hi"
  awk -F'\t' '$1 == "row" && $4 != "" { print $2 "|" $3 "\t" $4 }' "$c" | LC_ALL=C sort > "$W/ci"
  # collisions: one id, two uuids, the clinic's row not moving away
  LC_ALL=C join -t "$TAB" "$W/hi" "$W/ci" | awk -F'\t' -v tw="$W/twins" '
    BEGIN { while ((getline l < tw) > 0) { split(l, f, "\t"); mv[f[1] "|" f[2]] = 1 } }
    $2 != $3 { split($1, k, "|"); if (!((k[1] "|" $3) in mv)) print "collision\t" k[1] "\t" k[2] "\t" $3 "\t" $2 }'
  awk -F'\t' '{ print "twin\t" $1 "\t" $3 "\t" $4 "\t" $2 }' "$W/twins"
  # residue: above the hub's last legacy id, not on 0, not moving, the hub not holding it
  awk -F'\t' -v tw="$W/twins" -v hf="$h" '
    BEGIN { while ((getline l < tw) > 0) { split(l, f, "\t"); mv[f[1] "|" f[2]] = 1; if (f[1] == "concept") cmv[f[3]] = 1 }
            while ((getline l < hf) > 0) { split(l, f, "\t"); if (f[1] == "last-legacy") wm[f[2]] = f[3] + 0 } }
    $1 == "row" && ($2 in wm) && $3 + 0 > wm[$2] && $3 % 10 != 0 {
      if ($4 != "" && (($2 "|" $4) in mv)) next
      if ($4 == "" && ($3 in cmv)) next
      print "residue\t" $2 "\t" $3 "\t" $4 }' "$c"
}
findings "$HUBF" "$W/clinic" > "$W/found"
nrows="$(grep -c '^row' "$W/clinic" || true)"
if [ "$MODE" = check ] || [ ! -s "$W/found" ] || ! grep -q '^twin' "$W/found"; then
  cat "$W/found"
  if [ -s "$W/found" ]; then
    printf '  FAIL %s concept row(s) this clinic minted for itself (twin %s, collision %s, residue %s): the concept down sinks must not start until each is resolved\n' \
      "$(grep -c . "$W/found")" "$(grep -c '^twin' "$W/found" || true)" "$(grep -c '^collision' "$W/found" || true)" "$(grep -c '^residue' "$W/found" || true)" >&2
    [ "$MODE" = check ] || printf '  (nothing to move: --rekey moves twins only)\n' >&2
    exit 1
  fi
  ok "no concept row minted at this clinic: ${nrows} rows of $(printf '%s\n' "$TABLES" | grep -c .) tables match the hub's ids, none on another residue above the hub's"
  exit 0
fi

# --- the re-key ----------------------------------------------------------------------
cat "$W/found"
grep -q '^collision' "$W/found" && die2 "$(grep -c '^collision' "$W/found") collision(s) above: a row is in the way of a move or would be overwritten by the hub; nothing was changed"
OM="${COMPOSE_PROJECT_NAME:-x}-openmrs-1"
[ "$(ct inspect --format '{{.State.Running}}' "$OM" 2>/dev/null || printf false)" != true ] || die2 "OpenMRS (${OM}) is running: stop it first (it caches the concept rows); nothing was changed"
awk -F'\t' '$1 == "twin" { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$W/found" > "$W/moves"   # table old new uuid
olds_of(){ awk -F'\t' -v t="$1" '$1 == t { printf "%s%s", (n++ ? "," : ""), $2 }' "$W/moves"; }
news_of(){ awk -F'\t' -v t="$1" '$1 == t { printf "%s%s", (n++ ? "," : ""), $3 }' "$W/moves"; }
moved_tables="$(cut -f1 "$W/moves" | sort -u)"
# references: built-in logical links, and every foreign key the schema declares
cat > "$W/builtin" <<'EOF'
concept_name concept_id concept
concept_description concept_id concept
concept_answer concept_id concept
concept_answer answer_concept concept
concept_set concept_id concept
concept_set concept_set concept
concept_numeric concept_id concept
concept_complex concept_id concept
concept_reference_map concept_id concept
concept_attribute concept_id concept
obs concept_id concept
obs value_coded concept
obs value_coded_name_id concept_name
concept_name_tag_map concept_name_id concept_name
concept class_id concept_class
concept_reference_term concept_source_id concept_reference_source
concept_reference_map concept_reference_term_id concept_reference_term
concept_reference_term_map term_a_id concept_reference_term
concept_reference_term_map term_b_id concept_reference_term
EOF
inlist="$(printf '%s\n' "$TABLES" | sed "s/.*/'&'/" | paste -sd, -)"
printf "SELECT table_name, column_name, referenced_table_name, referenced_column_name FROM information_schema.key_column_usage WHERE table_schema = '%s' AND referenced_table_schema = '%s' AND referenced_table_name IN (%s);\n" "$DB" "$DB" "$inlist" | my > "$W/fks" \
  || die2 "could not read the foreign keys in ${MY}"
{ awk -F'\t' -v specs="$(printf '%s\n' "$SPECS" | tr '\n' ';')" 'BEGIN { n = split(specs, s, ";"); for (i = 1; i <= n; i++) { split(s[i], f, " "); if (f[1] != "") pk[f[1]] = f[2] } }
    ($3 in pk) && $4 == pk[$3] { print $1, $2, $3 }' "$W/fks"
  cat "$W/builtin"; } | awk -v cols="$W/cols" 'BEGIN { while ((getline l < cols) > 0) { split(l, f, "\t"); have[f[1] " " f[2]] = 1 } }
    (($1 " " $2) in have) && !seen[$0]++' > "$W/refs"   # child column parent, only those that exist here, once
# only references to a table with moves matter
awk -v mt=" $(printf '%s' "$moved_tables" | tr '\n' ' ') " 'index(mt, " " $3 " ")' "$W/refs" > "$W/mrefs"
# columns that are signed integers: a temporary negative id must fit
for spec in $(awk '{ print $1 ":" $2 }' "$W/mrefs") $(for t in $moved_tables; do printf '%s:%s\n' "$t" "$(pk_of "$t")"; done); do
  t="${spec%%:*}"; c="${spec#*:}"
  awk -F'\t' -v t="$t" -v c="$c" '$1 == t && $2 == c && $4 !~ /unsigned/ && $3 ~ /int$/ { f = 1 } END { exit !f }' "$W/cols" \
    || die2 "${t}.${c} is not a signed integer column; the move through a temporary negative id cannot be used; nothing was changed"
done
UP_TABLES=" $(sed -e 's/#.*//' "${REPO_DIR}/sync/local/tables.conf" | awk -F: 'NF { gsub(/[ \t]/, "", $1); if ($1 != "") print $1 }' | tr '\n' ' ') "
# what refers to a moving row now, and from where
refusals=""
while read -r ch col par; do
  [ -n "$ch" ] || continue
  n="$(printf 'SELECT COUNT(*) FROM `%s`.`%s` WHERE `%s` IN (%s);\n' "$DB" "$ch" "$col" "$(olds_of "$par")" | my)" || die2 "could not read ${ch}.${col}"
  if [ "${n:-0}" != 0 ]; then
    case "$UP_TABLES" in *" $ch "*) refusals="${refusals}
  ${ch}.${col}: ${n} row(s) refer to a moving ${par} row, and this clinic sends ${ch} up: the hub's copy would keep the old id" ;; esac
  fi
done < "$W/mrefs"
# other columns that speak of a concept and hold a moving concept's id
if grep -q '^concept	' "$W/moves"; then
  awk -F'\t' -v refs="$W/refs" 'BEGIN { while ((getline l < refs) > 0) { split(l, f, " "); r[f[1] " " f[2]] = 1 } }
      tolower($2) ~ /concept/ && $3 ~ /int$/ && $5 != "PRI" && !(($1 " " $2) in r) { print $1, $2 }' "$W/cols" | sort -u > "$W/other"
  while read -r ch col; do
    [ -n "$ch" ] || continue
    n="$(printf 'SELECT COUNT(*) FROM `%s`.`%s` WHERE `%s` IN (%s);\n' "$DB" "$ch" "$col" "$(olds_of concept)" | my 2>/dev/null)" || n=0
    [ "${n:-0}" = 0 ] || refusals="${refusals}
  ${ch}.${col}: ${n} row(s) hold a moving concept's id, and this script does not know that column as a reference"
  done < "$W/other"
  re="$(olds_of concept | sed 's/,/|/g')"
  printf "SELECT property, property_value FROM \`%s\`.global_property WHERE property_value REGEXP '(^|[^0-9])(%s)([^0-9]|\$)';\n" "$DB" "$re" | my > "$W/gp" 2>/dev/null || : > "$W/gp"
  while IFS="$TAB" read -r prop val; do
    [ -n "$prop" ] || continue
    if printf ',%s,' "$(olds_of concept)" | grep -qF ",${val}," && printf '%s' "$prop" | grep -qi concept; then :
    else refusals="${refusals}
  global property ${prop} = '${val}' holds a moving concept's id and is not exactly one id under a concept property's name"; fi
  done < "$W/gp"
fi
[ -z "$refusals" ] || die2 "the move would leave references behind; nothing was changed:${refusals}"

# the transaction
q(){ printf '`%s`.`%s`' "$DB" "$1"; }
check(){ # NAME CONDITION-THAT-IS-1-WHEN-BROKEN : stops the session (error 1242) when broken
  printf "SELECT 'check: %s';\n" "$(printf '%s' "$1" | sed "s/'/''/g")"
  printf "SELECT (SELECT z.n FROM (SELECT 1 AS n UNION ALL SELECT 2) z WHERE (%s) = 1);\n" "$2"
}
{
  printf 'SET SESSION sql_log_bin = 0;\nSET SESSION foreign_key_checks = 0;\nSTART TRANSACTION;\n'
  i=0; done_tables=""
  for t in $TABLES $(awk '{ print $1 }' "$W/mrefs" | sort -u); do
    case " $done_tables " in *" $t "*) continue ;; esac; done_tables="$done_tables $t"; i=$((i+1))
    if printf '%s\n' "$TABLES" | grep -qx "$t" && ! is_no_uuid "$t"; then
      printf 'SELECT COUNT(*), COALESCE(BIT_XOR(CRC32(uuid)), 0) INTO @n%s, @x%s FROM %s;\n' "$i" "$i" "$(q "$t")"
    else
      printf 'SELECT COUNT(*) INTO @n%s FROM %s;\n' "$i" "$(q "$t")"
    fi
  done
  for phase in 1 2; do
    while IFS="$TAB" read -r t old new _u; do
      [ -n "$t" ] || continue
      pk="$(pk_of "$t")"
      if [ "$phase" = 1 ]; then from="$old"; to="-$old"; else from="-$old"; to="$new"; fi
      printf 'UPDATE %s SET `%s` = %s WHERE `%s` = %s;\n' "$(q "$t")" "$pk" "$to" "$pk" "$from"
      awk -v p="$t" '$3 == p { print $1, $2 }' "$W/mrefs" | while read -r ch col; do
        printf 'UPDATE %s SET `%s` = %s WHERE `%s` = %s;\n' "$(q "$ch")" "$col" "$to" "$col" "$from"
      done
      if [ "$t" = concept ]; then
        printf "UPDATE %s SET property_value = '%s' WHERE property_value = '%s' AND LOWER(property) LIKE '%%concept%%';\n" "$(q global_property)" "$to" "$from"
      fi
    done < "$W/moves"
  done
  i=0; done_tables=""
  for t in $TABLES $(awk '{ print $1 }' "$W/mrefs" | sort -u); do
    case " $done_tables " in *" $t "*) continue ;; esac; done_tables="$done_tables $t"; i=$((i+1))
    if printf '%s\n' "$TABLES" | grep -qx "$t" && ! is_no_uuid "$t"; then
      check "${t}: row count and uuid set unchanged" "(SELECT COUNT(*) <> @n${i} OR COALESCE(BIT_XOR(CRC32(uuid)), 0) <> @x${i} FROM $(q "$t"))"
    else
      check "${t}: row count unchanged" "(SELECT COUNT(*) <> @n${i} FROM $(q "$t"))"
    fi
  done
  while IFS="$TAB" read -r t old new u; do
    [ -n "$t" ] || continue
    check "${t} ${u} at the hub's id ${new}" "(SELECT COUNT(*) <> 1 FROM $(q "$t") WHERE \`$(pk_of "$t")\` = ${new} AND uuid = '${u}')"
  done < "$W/moves"
  for t in $moved_tables; do
    pk="$(pk_of "$t")"
    gone="$(awk -F'\t' -v t="$t" 'NR == FNR { if ($1 == t) n[$3] = 1; next } $1 == t && !($2 in n) { printf "%s%s", (c++ ? "," : ""), $2 }' "$W/moves" "$W/moves")"
    check "${t}: no negative id left" "(SELECT COUNT(*) > 0 FROM $(q "$t") WHERE \`${pk}\` < 0)"
    [ -z "$gone" ] || check "${t}: no row left at an id it moved from" "(SELECT COUNT(*) > 0 FROM $(q "$t") WHERE \`${pk}\` IN (${gone}))"
    awk -v p="$t" '$3 == p { print $1, $2 }' "$W/mrefs" | while read -r ch col; do
      check "${ch}.${col}: no negative id left" "(SELECT COUNT(*) > 0 FROM $(q "$ch") WHERE \`${col}\` < 0)"
      [ -z "$gone" ] || check "${ch}.${col}: no reference to an id ${t} moved from" "(SELECT COUNT(*) > 0 FROM $(q "$ch") WHERE \`${col}\` IN (${gone}))"
      check "${ch}.${col}: every reference to a moved ${t} row finds it" "(SELECT COUNT(*) > 0 FROM $(q "$ch") c LEFT JOIN $(q "$t") p ON p.\`${pk}\` = c.\`${col}\` WHERE c.\`${col}\` IN ($(news_of "$t")) AND p.\`${pk}\` IS NULL)"
    done
  done
  check "global properties: no temporary value left" "(SELECT COUNT(*) > 0 FROM $(q global_property) WHERE property_value REGEXP '^-[0-9]+\$' AND LOWER(property) LIKE '%concept%')"
  printf "SET SESSION foreign_key_checks = 1;\nCOMMIT;\nSELECT 'committed';\n"
} > "$W/rekey.sql"
info "moving $(grep -c . "$W/moves") row(s) to the hub's ids ($(cut -f1 "$W/moves" | sort | uniq -c | awk '{ printf "%s%s %s", (n++ ? ", " : ""), $2, $1 }')), rewriting $(grep -c . "$W/mrefs") reference column(s), in one transaction with binary logging off"
out="$(my < "$W/rekey.sql" 2>&1)" || {
  printf '%s\n' "$out" | grep -E "^check: |ERROR" | tail -2 | sed 's/^/    /' >&2
  die2 "the move was rolled back (the last check named above failed, or a statement was refused); nothing was changed"
}
printf '%s\n' "$out" | tail -1 | grep -qx committed || die2 "the move did not report its commit: $(printf '%s\n' "$out" | tail -1)"
ok "moved and committed; every check passed before the commit"
ids_query | my > "$W/clinic2" || die2 "the concept tables could not be read again in ${MY}"
findings "$HUBF" "$W/clinic2" > "$W/found2"
if [ -s "$W/found2" ]; then
  cat "$W/found2"
  printf '  FAIL after the move, %s finding(s) remain (twin %s, residue %s): the concept down sinks must not start yet\n' "$(grep -c . "$W/found2")" "$(grep -c '^twin' "$W/found2" || true)" "$(grep -c '^residue' "$W/found2" || true)" >&2
  exit 1
fi
ok "no concept row minted at this clinic remains: the concept down sinks may start"
