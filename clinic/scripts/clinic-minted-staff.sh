#!/usr/bin/env bash
# Before the hub's staff come down to a clinic that keeps its own OpenMRS
# database: finds every row of this clinic that is in the way of the logins,
# roles, providers and people the hub created, and loads the hub's existing
# ones once, before the receivers start.
#
#   clinic/scripts/clinic-minted-staff.sh --derive-floors [--database DB]
#   clinic/scripts/clinic-minted-staff.sh --hub-query --floors FILE [--database DB]
#   clinic/scripts/clinic-minted-staff.sh --hub-dump --floors FILE [--database DB]
#   clinic/scripts/clinic-minted-staff.sh --hub-rows FILE [--container NAME] [--database DB]
#   clinic/scripts/clinic-minted-staff.sh --hub-rows FILE --print-floors | --print-properties
#   clinic/scripts/clinic-minted-staff.sh --hub-rows FILE --load DUMP [--container NAME] [--database DB]
#
# A hub-written row is one whose key is at or above the hub's floor for its
# table and ends in 0, the hub's residue. Below the floor this clinic's rows and
# the hub's are two histories that share ids, so only hub-written rows come
# down (clinic/scripts/generate-local-sink-connectors.sh, role `hub-written`).
# The floors: person and person_name use their base in sync/local/tables.conf,
# the value the hub's source filter uses; users and provider use the hub's
# recorded floors, a file of "<table> <floor>" lines kept on the hub.
#
# On the hub (each prints SQL or shell to run there, read-only):
#   --derive-floors  SQL that prints a floor for users and provider: the first
#                    multiple of 10 above the largest id not ending in 0. Only
#                    the hub writes these tables, so every id above it is the
#                    hub's. Run it once, `mysql -N -B`, and keep the output as
#                    the hub's floors file; a recorded floor is never changed.
#   --hub-query      SQL that reads the hub's side for the check (run it with
#                    `mysql -N -B`, save the output as the hub's rows file): its
#                    hub-written users, providers, people and names, its users'
#                    role grants and property names, and every role with its
#                    privileges and parents.
#   --hub-dump       a shell script to run inside the hub's MySQL container
#                    (`| <runtime> exec -i <container> sh`): mysqldump of the
#                    hub-written rows of person, person_name, users, provider,
#                    user_role and user_property (never a property name in
#                    sync/user-property-node-local.conf). Its output carries
#                    password hashes: keep it mode 600 and delete it after the
#                    load.
#
# On the clinic, with --hub-rows FILE (the --hub-query output):
#   the check prints one line per finding and exits 0 when there is none, 1
#   when there is any, 2 when it cannot judge:
#     collision <table> <id> <clinic uuid> <hub uuid>
#                    the hub's row's id holds another row here; the hub's
#                    changes would overwrite it
#     twin <table> <clinic id> <hub id> <uuid>
#                    the hub's row is here under another id; its arrival would
#                    stop the receiver on the duplicate uuid (for role: the
#                    same uuid under another name)
#     login-twin users <hub id> <clinic id> username|system_id <value>
#     login-twin provider <hub id> <clinic id> identifier <value>
#                    the same login or provider identifier under another id;
#                    two people would answer to one name
#     in-the-hub-range <table> <id> <uuid>
#                    a row of this clinic at or above the hub's floor ending in
#                    0 that the hub does not hold (made here before this clinic
#                    was strided); a hub row may later take its id
#     role-differs <role> privileges|parents
#                    both hold the role with another set of privileges or
#                    parent roles; the hub's grants would mean something else
#     role-missing <role> <hub user ids>
#                    a hub user holds a role this clinic does not have; made at
#                    this clinic, then the check is run again
#   Lines starting "info" decide nothing.
#   --print-floors     the "<table> <floor>" lines the receivers need for users
#                      and provider (HUB_STAFF_FLOORS)
#   --print-properties the property names the hub's users carry, less the
#                      node-local ones, comma-separated (USER_PROPERTY_KEEP)
#   --load DUMP        runs the check (refusing on any finding), then loads the
#                      --hub-dump output in one transaction with binary logging
#                      off (nothing travels up): the rows go first into
#                      temporary tables, each checked to be hub-written, then
#                      into the clinic's tables where their id is not taken.
#                      Before COMMIT it checks, and rolls everything back at the
#                      first that fails: every hub row in FILE is here under the
#                      hub's id and uuid, every role grant in FILE is here, and
#                      every hub-written user, provider, name, grant and
#                      property finds the person, user and role it names.
#                      users rows carry password hashes: loaded only with
#                      HUB_LINK_PER_SITE_TLS=yes, as for their receiver.
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
MODE=check; HUBF=""; FLOORS=""; DUMP=""; MY=""; DB=openmrs
while [ $# -gt 0 ]; do
  case "$1" in
    --derive-floors) MODE=derive; shift ;;
    --hub-query) MODE=query; shift ;;
    --hub-dump) MODE=dump; shift ;;
    --floors) FLOORS="${2:?--floors needs a file}"; shift 2 ;;
    --hub-rows) HUBF="${2:?--hub-rows needs a file}"; shift 2 ;;
    --print-floors) MODE=floors; shift ;;
    --print-properties) MODE=properties; shift ;;
    --load) MODE=load; DUMP="${2:?--load needs the --hub-dump output}"; shift 2 ;;
    --container) MY="${2:?--container needs a name}"; shift 2 ;;
    --database) DB="${2:?--database needs a name}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die2 "unknown argument: $1" ;;
  esac
done
printf '%s' "$DB" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || die2 "bad database name: $DB"
TAB="$(printf '\t')"
ID_TABLES="users provider person person_name"
pk_of(){ case "$1" in users) echo user_id ;; provider) echo provider_id ;; person) echo person_id ;; person_name) echo person_name_id ;; esac; }
NODE_LOCAL="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "${REPO_DIR}/sync/user-property-node-local.conf" | grep . || true)"
[ -n "$NODE_LOCAL" ] || die2 "sync/user-property-node-local.conf lists no property name"
sqlq(){ printf "'%s'" "$(printf '%s' "$1" | sed -e "s/\\\\/\\\\\\\\/g" -e "s/'/''/g")"; }
node_local_list(){ printf '%s\n' "$NODE_LOCAL" | while read -r p; do sqlq "$p"; printf ','; done | sed 's/,$//'; }
# person and person_name: their base in sync/local/tables.conf
base_of(){ awk -v t="$1" '{ sub(/#.*/, "") } NF { split($1, f, ":"); if (f[1] == t && f[3] ~ /^[0-9]+$/) { print f[3]; exit } }' "${REPO_DIR}/sync/local/tables.conf"; }
valid_floor(){ printf '%s' "$1" | grep -qE '^[1-9][0-9]*0$'; }

if [ "$MODE" = derive ]; then
  printf 'SET SESSION TRANSACTION READ ONLY;\nSTART TRANSACTION WITH CONSISTENT SNAPSHOT;\n'
  for t in users provider; do
    pk="$(pk_of "$t")"
    printf "SELECT '%s', (COALESCE(MAX(CASE WHEN \`%s\` %% 10 <> 0 THEN \`%s\` END), 0) DIV 10 + 1) * 10 FROM \`%s\`.\`%s\`;\n" "$t" "$pk" "$pk" "$DB" "$t"
  done
  printf 'COMMIT;\n'; exit 0
fi

# the floors: users and provider from a floors file (on the hub) or the hub's
# rows file (on the clinic); person and person_name from sync/local/tables.conf
F_users=""; F_provider=""; F_person=""; F_person_name=""
floor_of(){ eval "printf '%s' \"\${F_$1}\""; }
for t in person person_name; do
  b="$(base_of "$t")"; valid_floor "$b" || die2 "sync/local/tables.conf gives ${t} no base that is a multiple of 10 ('${b}'): its hub-written rows cannot be told apart"
  eval "F_$t=$b"
done
read_floors_file(){ # FILE: "<table> <floor>" lines for users and provider
  local f="$1" n t v
  [ -s "$f" ] || die2 "no floors file at ${f}: on the hub, record it once with --derive-floors"
  for t in $(awk '{ sub(/#.*/, "") } NF { print $1 }' "$f"); do
    case "$t" in users|provider) ;; *) die2 "${f}: '${t}' takes no floor here (only users and provider; person and person_name use sync/local/tables.conf)" ;; esac
  done
  for t in users provider; do
    n="$(awk -v t="$t" '{ sub(/#.*/, "") } NF && $1 == t' "$f" | grep -c . || true)"
    [ "$n" = 1 ] || die2 "${f}: ${t} has ${n} floor lines, not one"
    v="$(awk -v t="$t" '{ sub(/#.*/, "") } NF && $1 == t { print $2 }' "$f")"
    valid_floor "$v" || die2 "${f}: the floor of ${t} is '${v}', not a whole multiple of 10"
    eval "F_$t=$v"
  done
}

if [ "$MODE" = query ] || [ "$MODE" = dump ]; then
  [ -n "$FLOORS" ] || die2 "--floors FILE is needed (the hub's recorded floors for users and provider)"
  read_floors_file "$FLOORS"
fi

if [ "$MODE" = query ]; then
  q(){ printf '`%s`.`%s`' "$DB" "$1"; }
  hw(){ printf '`%s` >= %s AND `%s` %% 10 = 0' "$1" "$2" "$1"; }
  printf 'SET SESSION TRANSACTION READ ONLY;\nSTART TRANSACTION WITH CONSISTENT SNAPSHOT;\n'
  printf "SELECT 'format', 'staff-rows', '1';\n"
  for t in $ID_TABLES; do printf "SELECT 'floor', '%s', '%s';\n" "$t" "$(floor_of "$t")"; done
  for t in users provider; do
    printf "SELECT 'off-residue', '%s', COUNT(*) FROM %s WHERE \`%s\` >= %s AND \`%s\` %% 10 <> 0;\n" "$t" "$(q "$t")" "$(pk_of "$t")" "$(floor_of "$t")" "$(pk_of "$t")"
  done
  printf "SELECT 'users', user_id, uuid, IFNULL(username, ''), IFNULL(system_id, ''), IFNULL(person_id, '') FROM %s WHERE %s;\n" "$(q users)" "$(hw user_id "$F_users")"
  printf "SELECT 'provider', provider_id, uuid, IFNULL(identifier, ''), IFNULL(person_id, '') FROM %s WHERE %s;\n" "$(q provider)" "$(hw provider_id "$F_provider")"
  printf "SELECT 'person', person_id, uuid FROM %s WHERE %s;\n" "$(q person)" "$(hw person_id "$F_person")"
  printf "SELECT 'person_name', person_name_id, uuid, person_id FROM %s WHERE %s;\n" "$(q person_name)" "$(hw person_name_id "$F_person_name")"
  printf "SELECT 'user-role', user_id, role FROM %s WHERE %s;\n" "$(q user_role)" "$(hw user_id "$F_users")"
  printf "SELECT DISTINCT 'property', property FROM %s WHERE %s;\n" "$(q user_property)" "$(hw user_id "$F_users")"
  printf "SELECT 'role', role, uuid FROM %s;\n" "$(q role)"
  printf "SELECT 'role-privilege', role, privilege FROM %s;\n" "$(q role_privilege)"
  printf "SELECT 'role-role', parent_role, child_role FROM %s;\n" "$(q role_role)"
  printf 'COMMIT;\n'; exit 0
fi

if [ "$MODE" = dump ]; then
  # one mysqldump per table, parents first; INSERT statements only, one row per line
  printf '#!/bin/sh\nset -e\n'
  printf 'd(){ MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --no-create-info --skip-triggers --compact --complete-insert --skip-extended-insert --single-transaction --skip-tz-utc --set-gtid-purged=OFF --default-character-set=utf8mb4 "$@"; }\n'
  printf "d %s person --where='person_id >= %s AND person_id %% 10 = 0'\n" "$DB" "$F_person"
  printf "d %s person_name --where='person_name_id >= %s AND person_name_id %% 10 = 0'\n" "$DB" "$F_person_name"
  printf "d %s users --where='user_id >= %s AND user_id %% 10 = 0'\n" "$DB" "$F_users"
  printf "d %s provider --where='provider_id >= %s AND provider_id %% 10 = 0'\n" "$DB" "$F_provider"
  printf "d %s user_role --where='user_id >= %s AND user_id %% 10 = 0'\n" "$DB" "$F_users"
  # the property names go inside a double-quoted shell word: none may carry a shell or SQL quote
  ! printf '%s\n' "$NODE_LOCAL" | grep -qvE '^[A-Za-z0-9_.:-]+$' || die2 "sync/user-property-node-local.conf holds a name with a character other than letters, digits and _ . : -"
  printf 'd %s user_property --where="user_id >= %s AND user_id %% 10 = 0 AND property NOT IN (%s)"\n' "$DB" "$F_users" "$(node_local_list)"
  exit 0
fi

# --- the clinic side: the hub's rows file ------------------------------------------------
[ -n "$HUBF" ] || { usage >&2; die2 "--hub-rows FILE is needed (the hub's side, read with --hub-query)"; }
[ -s "$HUBF" ] || die2 "no hub file at ${HUBF} (or it is empty): read it on the hub with --hub-query"
head -1 "$HUBF" | grep -qE '^format	staff-rows	1$' || die2 "${HUBF} is not the output of --hub-query (its first line is not the format line)"
for t in $ID_TABLES; do
  v="$(awk -F'\t' -v t="$t" '$1 == "floor" && $2 == t { print $3 }' "$HUBF")"
  valid_floor "$v" || die2 "${HUBF} has no floor line for ${t}: read it again with this checkout's --hub-query"
  case "$t" in
    person|person_name) [ "$v" = "$(floor_of "$t")" ] || die2 "${HUBF} reads ${t} from ${v}, and this checkout's sync/local/tables.conf from $(floor_of "$t"): the two checkouts disagree on the floor the hub's source filter uses" ;;
    *) eval "F_$t=$v" ;;
  esac
done
for t in users provider; do
  n="$(awk -F'\t' -v t="$t" '$1 == "off-residue" && $2 == t { print $3 }' "$HUBF")"
  [ -n "$n" ] || die2 "${HUBF} has no off-residue line for ${t}: read it again with this checkout's --hub-query"
  [ "$n" = 0 ] || die2 "the hub holds ${n} ${t} row(s) at or above its recorded floor $(floor_of "$t") that do not end in 0: that floor is not where the hub's own ${t} rows begin; record the floors again on the hub before anything comes down"
done
grep -q "^role	" "$HUBF" || die2 "${HUBF} lists no role: read it again with --hub-query"

if [ "$MODE" = floors ]; then
  printf 'users %s\nprovider %s\n' "$F_users" "$F_provider"; exit 0
fi
if [ "$MODE" = properties ]; then
  awk -F'\t' '$1 == "property" { print $2 }' "$HUBF" | LC_ALL=C sort -u | grep -vxF -f <(printf '%s\n' "$NODE_LOCAL") | paste -sd, - || true
  exit 0
fi

E="${CLINIC_DIR}/.env"
[ ! -f "$E" ] || COMPOSE_PROJECT_NAME="$(env_get "$E" COMPOSE_PROJECT_NAME)"
if [ -z "$MY" ]; then
  [ -f "$E" ] || die2 "no ${E}: name the MySQL container with --container"
  [ -n "${COMPOSE_PROJECT_NAME:-}" ] || die2 "clinic/.env has no COMPOSE_PROJECT_NAME: name the MySQL container with --container"
  MY="${COMPOSE_PROJECT_NAME}-bahmni-mysql-1"
fi
[ -n "${CT:-}" ] || setup_compose
my(){ ct exec -i "$MY" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B'; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# this clinic's side: every row of the four id tables (the findings need the
# rows below the floor too: a twin or a login twin can sit anywhere) and every role
clinic_query(){
  printf 'SET SESSION TRANSACTION READ ONLY;\nSTART TRANSACTION WITH CONSISTENT SNAPSHOT;\n'
  printf "SELECT 'users', user_id, uuid, IFNULL(username, ''), IFNULL(system_id, ''), IFNULL(person_id, '') FROM \`%s\`.users;\n" "$DB"
  printf "SELECT 'provider', provider_id, uuid, IFNULL(identifier, ''), IFNULL(person_id, '') FROM \`%s\`.provider;\n" "$DB"
  printf "SELECT 'person', person_id, uuid FROM \`%s\`.person;\n" "$DB"
  printf "SELECT 'person_name', person_name_id, uuid, person_id FROM \`%s\`.person_name;\n" "$DB"
  printf "SELECT 'role', role, uuid FROM \`%s\`.role;\n" "$DB"
  printf "SELECT 'role-privilege', role, privilege FROM \`%s\`.role_privilege;\n" "$DB"
  printf "SELECT 'role-role', parent_role, child_role FROM \`%s\`.role_role;\n" "$DB"
  printf 'COMMIT;\n'
}
clinic_query | my > "$W/clinic" || die2 "the staff tables could not be read in ${MY}: is MySQL running?"

findings(){ # HUBFILE CLINICFILE -> finding lines, then info lines
  awk -F'\t' -v OFS='\t' \
      -v fu="$F_users" -v fp="$F_provider" -v fpe="$F_person" -v fpn="$F_person_name" '
    BEGIN { fl["users"] = fu + 0; fl["provider"] = fp + 0; fl["person"] = fpe + 0; fl["person_name"] = fpn + 0 }
    function idt(t) { return t == "users" || t == "provider" || t == "person" || t == "person_name" }
    FNR == NR {
      if (idt($1)) {
        hid[$1 SUBSEP $2] = $3; huu[$1 SUBSEP $3] = $2
        if ($1 == "users") { hname[$2] = $4; hsys[$2] = $5 }
        if ($1 == "provider") hident[$2] = $4
      }
      else if ($1 == "user-role") { if (!(($3) in rmiss)) rmiss[$3] = ""; rmiss[$3] = rmiss[$3] (rmiss[$3] == "" ? "" : ",") $2 }
      else if ($1 == "role") { hr[$2] = $3; hru[$3] = $2 }
      else if ($1 == "role-privilege") { hrp[$2 SUBSEP $3] = 1 }
      else if ($1 == "role-role") { hrr[$3 SUBSEP $2] = 1 }
      next
    }
    idt($1) {
      t = $1; id = $2 + 0
      cid[t SUBSEP $2] = $3; if (!((t SUBSEP $3) in cuu)) cuu[t SUBSEP $3] = $2
      if (t == "users") { if ($4 != "") cname[$4] = cname[$4] " " $2; if ($5 != "") csys[$5] = csys[$5] " " $2 }
      if (t == "provider" && $4 != "") cident[$4] = cident[$4] " " $2
      if (id >= fl[t] && id % 10 == 0 && !((t SUBSEP $2) in hid)) print "in-the-hub-range", t, $2, $3
      if (id >= fl[t] && id % 10 != 0) { own[t]++; if (!(t in omin) || id < omin[t]) omin[t] = id; if (id > omax[t]) omax[t] = id }
      next
    }
    $1 == "role" { cr[$2] = $3; cru[$3] = $2; next }
    $1 == "role-privilege" { crp[$2 SUBSEP $3] = 1; next }
    $1 == "role-role" { crr[$3 SUBSEP $2] = 1; next }
    END {
      for (k in hid) {
        split(k, a, SUBSEP)
        if ((k in cid) && cid[k] != hid[k]) print "collision", a[1], a[2], cid[k], hid[k]
      }
      for (k in huu) {
        split(k, a, SUBSEP)
        if ((k in cuu) && cuu[k] != huu[k]) print "twin", a[1], cuu[k], huu[k], a[2]
      }
      for (k in hid) {
        split(k, a, SUBSEP); id = a[2]
        if (a[1] == "users") {
          if (hname[id] != "" && (hname[id] in cname)) { n = split(cname[hname[id]], ids, " "); for (i = 1; i <= n; i++) if (ids[i] != "" && ids[i] != id) print "login-twin", "users", id, ids[i], "username", hname[id] }
          if (hsys[id] != "" && (hsys[id] in csys)) { n = split(csys[hsys[id]], ids, " "); for (i = 1; i <= n; i++) if (ids[i] != "" && ids[i] != id) print "login-twin", "users", id, ids[i], "system_id", hsys[id] }
        }
        if (a[1] == "provider" && hident[id] != "" && (hident[id] in cident)) {
          n = split(cident[hident[id]], ids, " "); for (i = 1; i <= n; i++) if (ids[i] != "" && ids[i] != id) print "login-twin", "provider", id, ids[i], "identifier", hident[id]
        }
      }
      for (r in hr) {
        if (!(r in cr)) continue
        dp = 0; for (k in hrp) { split(k, a, SUBSEP); if (a[1] == r && !(k in crp)) dp = 1 }
        for (k in crp) { split(k, a, SUBSEP); if (a[1] == r && !(k in hrp)) dp = 1 }
        if (dp) print "role-differs", r, "privileges"
        dq = 0; for (k in hrr) { split(k, a, SUBSEP); if (a[1] == r && !(k in crr)) dq = 1 }
        for (k in crr) { split(k, a, SUBSEP); if (a[1] == r && !(k in hrr)) dq = 1 }
        if (dq) print "role-differs", r, "parents"
      }
      for (u in hru) if ((u in cru) && cru[u] != hru[u]) print "twin", "role", cru[u], hru[u], u
      for (r in rmiss) if (!(r in cr)) print "role-missing", r, rmiss[r]
      for (r in hr) if ((r in cr) && cr[r] != hr[r]) print "info", "role " r ": the hub holds it under another uuid; the hub'"'"'s next change to it writes the hub'"'"'s uuid here"
      for (t in own) print "info", t ": " own[t] " row(s) of this clinic at or above the hub'"'"'s floor " fl[t] " on its own residue, ids " omin[t] " to " omax[t] " (they stay here and never meet the hub'"'"'s)"
    }' "$1" "$2" | LC_ALL=C sort
}
findings "$HUBF" "$W/clinic" > "$W/all"
grep -v '^info	' "$W/all" > "$W/found" || true
grep '^info	' "$W/all" | cut -f2- | sed 's/^/  info /' || true
nhub="$(grep -cE '^(users|provider|person|person_name)	' "$HUBF" || true)"

if [ -s "$W/found" ]; then
  cat "$W/found"
  count(){ grep -c "^$1	" "$W/found" || true; }
  printf '  FAIL %s staff row(s) in the hub'"'"'s way (collision %s, twin %s, login-twin %s, in-the-hub-range %s, role-differs %s, role-missing %s): no staff receiver may start on this clinic; the lines go to the hub team\n' \
    "$(grep -c . "$W/found")" "$(count collision)" "$(count twin)" "$(count login-twin)" "$(count in-the-hub-range)" "$(count role-differs)" "$(count role-missing)" >&2
  if [ "$(grep -vc '^role-missing	' "$W/found" || true)" = 0 ]; then
    printf '  (only missing roles: once the hub team makes each at this clinic, with the hub'"'"'s privileges and parents, run the check again)\n' >&2
  fi
  [ "$MODE" = load ] && printf '  nothing was loaded\n' >&2
  exit 1
fi
if [ "$MODE" = check ]; then
  ok "no staff row at this clinic in the hub's way: ${nhub} hub-written row(s) of users, provider, person and person_name checked, $(grep -c '^role	' "$W/clinic" || true) role(s) agree"
  exit 0
fi

# --- the load ------------------------------------------------------------------------------
[ -s "$DUMP" ] || die2 "no dump at ${DUMP}: read it on the hub with --hub-dump"
STAFF_DUMP_TABLES="person person_name users provider user_role user_property"
bad_line="$(grep -vE '^$' "$DUMP" | grep -vnE '^INSERT INTO `(person|person_name|users|provider|user_role|user_property)` \(' | head -1 || true)"
[ -z "$bad_line" ] || die2 "${DUMP} is not --hub-dump's output: line ${bad_line%%:*} is not an INSERT into one of the staff tables; nothing was loaded"
if grep -q '^INSERT INTO `users` ' "$DUMP" && [ "${HUB_LINK_PER_SITE_TLS:-}" != yes ]; then
  die2 "${DUMP} holds users rows, which carry password hashes: they are loaded only for a clinic whose link to the hub is TLS with plaintext refused and logs in with a login of its own (then HUB_LINK_PER_SITE_TLS=yes); nothing was loaded"
fi
q(){ printf '`%s`.`%s`' "$DB" "$1"; }
check(){ # NAME CONDITION-THAT-IS-1-WHEN-BROKEN : stops the session (error 1242) when broken
  printf "SELECT 'check: %s';\n" "$(printf '%s' "$1" | sed "s/'/''/g")"
  printf "SELECT (SELECT z.n FROM (SELECT 1 AS n UNION ALL SELECT 2) z WHERE (%s) = 1);\n" "$2"
}
hwc(){ printf '%s`%s` >= %s AND %s`%s` %% 10 = 0' "${3:+$3.}" "$1" "$2" "${3:+$3.}" "$1"; }  # COLUMN FLOOR [TABLE-ALIAS]
key_floor(){ case "$1" in users|user_role|user_property) printf 'user_id %s' "$F_users" ;; provider) printf 'provider_id %s' "$F_provider" ;; person) printf 'person_id %s' "$F_person" ;; person_name) printf 'person_name_id %s' "$F_person_name" ;; esac; }
# the hub's rows from FILE, for the checks: ids and uuids are digits and uuid characters only
awk -F'\t' '($1 == "users" || $1 == "provider" || $1 == "person" || $1 == "person_name") && ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9A-Za-z-]+$/) { bad = 1 } END { exit bad }' "$HUBF" \
  || die2 "${HUBF} holds an id or uuid that is not one; nothing was loaded"
{
  printf 'SET SESSION sql_log_bin = 0;\nSET SESSION foreign_key_checks = 0;\nUSE `%s`;\nSTART TRANSACTION;\n' "$DB"
  for t in $STAFF_DUMP_TABLES; do printf 'CREATE TEMPORARY TABLE `staff_in_%s` LIKE %s;\n' "$t" "$(q "$t")"; done
  sed -nE 's/^INSERT INTO `(person|person_name|users|provider|user_role|user_property)` \(/INSERT INTO `staff_in_\1` (/p' "$DUMP"
  for t in $STAFF_DUMP_TABLES; do
    set -- $(key_floor "$t")
    cond="NOT ($(hwc "$1" "$2"))"
    [ "$t" != user_property ] || cond="${cond} OR property IN ($(node_local_list))"
    check "${t}: every row loaded is a hub-written one" "(SELECT COUNT(*) > 0 FROM \`staff_in_${t}\` WHERE ${cond})"
  done
  for t in $STAFF_DUMP_TABLES; do printf 'INSERT IGNORE INTO %s SELECT * FROM `staff_in_%s`;\n' "$(q "$t")" "$t"; done
  printf 'CREATE TEMPORARY TABLE `staff_hub` (t varchar(32) NOT NULL, id int NOT NULL, uuid varchar(38) NOT NULL);\n'
  awk -F'\t' '$1 == "users" || $1 == "provider" || $1 == "person" || $1 == "person_name" { printf "INSERT INTO `staff_hub` VALUES ('\''%s'\'', %s, '\''%s'\'');\n", $1, $2, $3 }' "$HUBF"
  printf 'CREATE TEMPORARY TABLE `staff_hub_grant` (user_id int NOT NULL, role varchar(255) NOT NULL);\n'
  awk -F'\t' '$1 == "user-role"' "$HUBF" | while IFS="$TAB" read -r _x uid role; do
    printf 'INSERT INTO `staff_hub_grant` VALUES (%s, %s);\n' "$uid" "$(sqlq "$role")"
  done
  for t in $ID_TABLES; do
    pk="$(pk_of "$t")"
    check "${t}: every hub row is here under the hub's id and uuid" "(SELECT COUNT(*) > 0 FROM \`staff_hub\` h LEFT JOIN $(q "$t") x ON x.\`${pk}\` = h.id AND x.uuid = h.uuid WHERE h.t = '${t}' AND x.\`${pk}\` IS NULL)"
  done
  check "user_role: every role grant of a hub user is here" "(SELECT COUNT(*) > 0 FROM \`staff_hub_grant\` g LEFT JOIN $(q user_role) x ON x.user_id = g.user_id AND x.role = g.role WHERE x.user_id IS NULL)"
  check "users: every hub user finds its person" "(SELECT COUNT(*) > 0 FROM $(q users) u LEFT JOIN $(q person) p ON p.person_id = u.person_id WHERE $(hwc user_id "$F_users" u) AND p.person_id IS NULL)"
  check "provider: every hub provider with a person finds it" "(SELECT COUNT(*) > 0 FROM $(q provider) v LEFT JOIN $(q person) p ON p.person_id = v.person_id WHERE $(hwc provider_id "$F_provider" v) AND v.person_id IS NOT NULL AND p.person_id IS NULL)"
  check "person_name: every hub name finds its person" "(SELECT COUNT(*) > 0 FROM $(q person_name) n LEFT JOIN $(q person) p ON p.person_id = n.person_id WHERE $(hwc person_name_id "$F_person_name" n) AND p.person_id IS NULL)"
  check "user_role: every grant of a hub user finds its user and its role" "(SELECT COUNT(*) > 0 FROM $(q user_role) g LEFT JOIN $(q users) u ON u.user_id = g.user_id LEFT JOIN $(q role) r ON r.role = g.role WHERE $(hwc user_id "$F_users" g) AND (u.user_id IS NULL OR r.role IS NULL))"
  check "user_property: every property of a hub user finds its user" "(SELECT COUNT(*) > 0 FROM $(q user_property) x LEFT JOIN $(q users) u ON u.user_id = x.user_id WHERE $(hwc user_id "$F_users" x) AND u.user_id IS NULL)"
  printf "SET SESSION foreign_key_checks = 1;\nCOMMIT;\nSELECT 'committed';\n"
} > "$W/load.sql"
loaded="$(grep -cE '^INSERT INTO `' "$DUMP" || true)"
info "loading ${loaded} hub-written row(s) ($(sed -nE 's/^INSERT INTO `([a-z_]+)` .*/\1/p' "$DUMP" | uniq -c | awk '{ printf "%s%s %s", (n++ ? ", " : ""), $2, $1 }')) in one transaction with binary logging off"
out="$(my < "$W/load.sql" 2>&1)" || {
  printf '%s\n' "$out" | grep -E "^check: |ERROR" | tail -2 | sed 's/^/    /' >&2
  die2 "the load was rolled back (the last check named above failed, or a statement was refused); nothing was loaded"
}
printf '%s\n' "$out" | tail -1 | grep -qx committed || die2 "the load did not report its commit: $(printf '%s\n' "$out" | tail -1)"
ok "loaded and committed; every check passed before the commit: the hub's ${nhub} row(s) of users, provider, person and person_name are here, with their role grants"
