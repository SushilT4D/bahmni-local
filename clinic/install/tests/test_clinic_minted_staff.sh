#!/usr/bin/env bash
# clinic/scripts/clinic-minted-staff.sh: before the hub's staff come down to a
# clinic that keeps its own OpenMRS database, finds every row of the clinic in
# the way of the hub's logins, providers, people and roles, and loads the hub's
# existing rows once.
#
# Without a database: the hub-side SQL is read-only and filters on the floors,
# the dump leaves the node-local property names out, a floors file off the
# grid or naming another table is refused.
# On a throwaway MySQL of the pinned image, with binary logging on, a hub schema
# and a clinic schema sharing their older rows: the floors derived on the hub
# are where its own rows begin; a role a hub user holds that the clinic lacks
# fails the check until the clinic has it; a planted collision, twin, login
# twin (username, system id, provider identifier), row in the hub's range and
# role with other privileges or parents each fire, and clear once removed; a
# hub floor below rows that do not end in 0 stops the check; the load refuses
# users without the link statement, a dump with any other statement, and a
# dump row that is not hub-written (rolled back, nothing loaded); the load
# itself puts every hub row here under the hub's id, leaves the node-local
# properties out, writes nothing to the binary log, and runs again unchanged.
# Skipped (passing) without docker or the pinned MySQL image.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
S="${RP}/clinic/scripts/clinic-minted-staff.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; CNAME=""
trap '[ -n "$CNAME" ] && docker rm -f "$CNAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
[ -f "$S" ] || { bad "no $S"; exit 1; }

# --- without a database ---------------------------------------------------------------
printf 'users 20\nprovider 10\n' > "$TMP/floors"
q="$(REPO_DIR="$RP" bash "$S" --hub-query --floors "$TMP/floors" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$q" | grep -q '^SET SESSION TRANSACTION READ ONLY;$' && ! printf '%s\n' "$q" | grep -qiE '^(INSERT|UPDATE|DELETE|ALTER|DROP|CREATE)' \
  && ok_ "the hub query is one read-only transaction" || bad "hub query: rc=$rc $q"
printf '%s\n' "$q" | grep -q "FROM \`openmrs\`.\`users\` WHERE \`user_id\` >= 20 AND \`user_id\` % 10 = 0" \
  && printf '%s\n' "$q" | grep -q "FROM \`openmrs\`.\`person\` WHERE \`person_id\` >= 230000 AND \`person_id\` % 10 = 0" \
  && ok_ "the hub query reads users on the recorded floor and person on its base in sync/local/tables.conf" || bad "hub query floors: $q"
d="$(REPO_DIR="$RP" bash "$S" --hub-dump --floors "$TMP/floors" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$d" | grep -q "user_property --where=\"user_id >= 20 AND user_id % 10 = 0 AND property NOT IN ('lastViewedPatients'," \
  && printf '%s\n' "$d" | grep -q "'loginAttempts'" && ok_ "the dump leaves every node-local property name out" || bad "hub dump: rc=$rc $d"
out="$(REPO_DIR="$RP" bash "$S" --hub-query 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q -- '--floors FILE is needed' && ok_ "the hub query needs the hub's recorded floors" || bad "no floors: rc=$rc $out"
printf 'users 25\nprovider 10\n' > "$TMP/f-odd"
out="$(REPO_DIR="$RP" bash "$S" --hub-query --floors "$TMP/f-odd" 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "the floor of users is '25', not a whole multiple of 10" && ok_ "a floor off the residue grid is refused" || bad "odd floor: rc=$rc $out"
printf 'users 20\nprovider 10\nperson 240000\n' > "$TMP/f-person"
out="$(REPO_DIR="$RP" bash "$S" --hub-query --floors "$TMP/f-person" 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "'person' takes no floor here" && ok_ "a floors file that gives person a floor is refused (its floor is the hub source filter's)" || bad "person floor: rc=$rc $out"
printf 'not the hub file\n' > "$TMP/bad"
out="$(REPO_DIR="$RP" CLINIC_DIR="$TMP" CT=docker bash "$S" --hub-rows "$TMP/bad" --container none 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'is not the output of --hub-query' && ok_ "a hub file that is not --hub-query's output is refused" || bad "bad hub file: rc=$rc $out"

# --- a real MySQL ------------------------------------------------------------------------
IMG="$(sed -n 's/^MYSQL_IMAGE=\([^[:space:]#]*\).*/\1/p' "$RP/sync/versions.env")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime or no local ${IMG:-MySQL image}: the real-MySQL checks are skipped"
  exit "$fails"
fi
CNAME="cs-test-$$"
docker run -d --name "$CNAME" --tmpfs /var/lib/mysql -e MYSQL_ROOT_PASSWORD=t -e MYSQL_DATABASE=openmrs "$IMG" \
  --innodb-buffer-pool-size=16M --performance-schema=OFF >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
sq(){ docker exec -i "$CNAME" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B'; }
up=0; for i in $(seq 1 120); do docker logs "$CNAME" 2>&1 | grep -q 'ready for connections.*port: 3306' && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "${IMG} was not ready within 120 s"; exit "$fails"; }
ddl(){ cat <<SQL
CREATE TABLE $1.person (person_id int PRIMARY KEY, gender varchar(50), uuid char(38) NOT NULL UNIQUE);
CREATE TABLE $1.person_name (person_name_id int PRIMARY KEY, person_id int NOT NULL, given_name varchar(50), uuid char(38) NOT NULL UNIQUE,
  FOREIGN KEY (person_id) REFERENCES $1.person (person_id));
CREATE TABLE $1.users (user_id int PRIMARY KEY, system_id varchar(50) NOT NULL, username varchar(50), password varchar(128), salt varchar(128),
  person_id int NOT NULL, uuid char(38) NOT NULL UNIQUE, FOREIGN KEY (person_id) REFERENCES $1.person (person_id));
CREATE TABLE $1.provider (provider_id int PRIMARY KEY, person_id int, identifier varchar(255), uuid char(38) NOT NULL UNIQUE);
CREATE TABLE $1.role (role varchar(50) PRIMARY KEY, description varchar(255), uuid char(38) NOT NULL UNIQUE);
CREATE TABLE $1.role_privilege (role varchar(50), privilege varchar(255), PRIMARY KEY (role, privilege));
CREATE TABLE $1.role_role (parent_role varchar(50), child_role varchar(50), PRIMARY KEY (parent_role, child_role));
CREATE TABLE $1.user_role (user_id int, role varchar(50), PRIMARY KEY (user_id, role), FOREIGN KEY (user_id) REFERENCES $1.users (user_id),
  FOREIGN KEY (role) REFERENCES $1.role (role));
CREATE TABLE $1.user_property (user_id int, property varchar(100), property_value varchar(255), PRIMARY KEY (user_id, property),
  FOREIGN KEY (user_id) REFERENCES $1.users (user_id));
SQL
}
seed(){ # SCHEMA : the rows both nodes share (older ids, every residue)
  cat <<SQL
INSERT INTO $1.person VALUES (1,'M','p-1'),(2,'F','p-2'),(3,'M','p-3'),(4,'F','p-4'),(5,'M','p-5');
INSERT INTO $1.person_name VALUES (1,1,'admin','pn-1'),(2,2,'nurse','pn-2');
INSERT INTO $1.users VALUES (1,'admin','admin','h','s',1,'u-1'),(2,'2-1','nurse1','h','s',2,'u-2'),(13,'13-1','clerk','h','s',3,'u-13');
INSERT INTO $1.provider VALUES (1,1,'PROV-1','v-1'),(7,2,'PROV-7','v-7');
INSERT INTO $1.role VALUES ('Doctor','',  'r-doc'),('Nurse','','r-nurse'),('Authenticated','','r-auth');
INSERT INTO $1.role_privilege VALUES ('Doctor','View Patients'),('Doctor','Add Orders'),('Nurse','View Patients');
INSERT INTO $1.role_role VALUES ('Authenticated','Doctor'),('Authenticated','Nurse');
INSERT INTO $1.user_role VALUES (2,'Nurse');
SQL
}
{
  echo 'CREATE DATABASE hubdb;'; ddl hubdb; seed hubdb
  # the hub's own staff: users 20 and 30, provider 10, their people and names above 230000 on residue 0
  cat <<'SQL'
INSERT INTO hubdb.role VALUES ('Lab','','r-lab');
INSERT INTO hubdb.role_privilege VALUES ('Lab','View Results');
INSERT INTO hubdb.person VALUES (230010,'F','p-230010'),(230020,'M','p-230020'),(230013,'M','p-clinic-up');
INSERT INTO hubdb.person_name VALUES (230010,230010,'asha','pn-230010'),(230020,230020,'ravi','pn-230020');
INSERT INTO hubdb.users VALUES (20,'20-0','asha','hash-a','salt-a',230010,'u-20'),(30,'30-0','ravi','hash-r','salt-r',230020,'u-30');
INSERT INTO hubdb.provider VALUES (10,230010,'PROV-ASHA','v-10');
INSERT INTO hubdb.user_role VALUES (20,'Doctor'),(30,'Lab'),(1,'Doctor');
INSERT INTO hubdb.user_property VALUES (20,'defaultLocale','hi'),(20,'loginAttempts','4'),(30,'lockoutTimestamp','1');
SQL
  ddl openmrs; seed openmrs
  # the clinic (residue 3): its own people and logins above the floor
  cat <<'SQL'
INSERT INTO openmrs.person VALUES (230003,'F','p-230003'),(230013,'M','p-230013');
INSERT INTO openmrs.users VALUES (23,'23-3','meena','h','s',230003,'u-23');
INSERT INTO openmrs.user_property VALUES (23,'loginAttempts','1');
SQL
} | sq 2>"$TMP/fx.err" || { bad "fixture refused: $(head -3 "$TMP/fx.err")"; exit "$fails"; }

# the floors, derived on the hub as the hub team records them
REPO_DIR="$RP" bash "$S" --derive-floors --database hubdb | sq > "$TMP/hub-floors"
[ "$(tr '\t' ' ' < "$TMP/hub-floors" | tr '\n' '|')" = "users 20|provider 10|" ] \
  && ok_ "the floors derived on the hub: users from 20, provider from 10 (the first multiple of 10 above every id not ending in 0)" || bad "derived floors: $(cat "$TMP/hub-floors")"
hubrows(){ REPO_DIR="$RP" bash "$S" --hub-query --floors "$1" --database hubdb | sq > "$TMP/hub.tsv"; }
hubrows "$TMP/hub-floors"
[ "$(head -1 "$TMP/hub.tsv")" = "format	staff-rows	1" ] && [ "$(grep -c '^users	' "$TMP/hub.tsv")" = 2 ] && [ "$(grep -c '^person	' "$TMP/hub.tsv")" = 2 ] \
  && ok_ "the hub file holds the hub's two users and two people, and not the person a clinic sent up" || bad "hub file: $(cat "$TMP/hub.tsv" | head -20 | tr '\n' '|')"
run(){ out="$(env PATH="$PATH" REPO_DIR="$RP" CLINIC_DIR="$TMP" CT=docker bash "$S" --hub-rows "$TMP/hub.tsv" --container "$CNAME" "$@" 2>&1)"; rc=$?; }
p="$(REPO_DIR="$RP" CLINIC_DIR="$TMP" bash "$S" --hub-rows "$TMP/hub.tsv" --print-properties 2>&1)"; f="$(REPO_DIR="$RP" CLINIC_DIR="$TMP" bash "$S" --hub-rows "$TMP/hub.tsv" --print-floors 2>&1 | tr '\n' '|')"
[ "$p" = defaultLocale ] && [ "$f" = "users 20|provider 10|" ] && ok_ "the receivers' inputs: the property names to keep (defaultLocale; loginAttempts and lockoutTimestamp stay) and the floors" || bad "print: '$p' '$f'"

run
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qx 'role-missing	Lab	30' && [ "$(printf '%s\n' "$out" | grep -cE '^(collision|twin|login-twin|in-the-hub-range|role-differs)')" = 0 ] \
  && printf '%s' "$out" | grep -q 'only missing roles' && printf '%s' "$out" | grep -q 'info users: 1 row(s) of this clinic at or above' \
  && ok_ "a role a hub user holds and the clinic lacks fails the check, alone (exit 1); the clinic's own users above the floor are information only" || bad "role missing: rc=$rc
$out"
echo "INSERT INTO openmrs.role VALUES ('Lab','','r-lab'); INSERT INTO openmrs.role_privilege VALUES ('Lab','View Results');" | sq
run
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q "no staff row at this clinic in the hub's way: 7 hub-written row(s)" && ok_ "once the clinic has the role the check passes" || bad "after role: rc=$rc $out"

# every finding, planted together; each must fire
cat <<'SQL' | sq
INSERT INTO openmrs.person VALUES (230010,'F','p-other');
INSERT INTO openmrs.person VALUES (230023,'M','p-230020');
INSERT INTO openmrs.users VALUES (33,'33-3','asha','h','s',230003,'u-33'), (43,'30-0','x43','h','s',230003,'u-43'), (40,'40-0','old','h','s',230003,'u-40');
INSERT INTO openmrs.provider VALUES (53,230003,'PROV-ASHA','v-53');
DELETE FROM openmrs.role_privilege WHERE role = 'Doctor' AND privilege = 'Add Orders';
DELETE FROM openmrs.role_role WHERE child_role = 'Nurse';
INSERT INTO openmrs.role VALUES ('Lab2','','r-auth-twin');
SQL
echo "UPDATE openmrs.role SET uuid='r-nurse2' WHERE role='Nurse'; UPDATE openmrs.role SET uuid='r-nurse' WHERE role='Lab2';" | sq
run
want="collision	person	230010	p-other	p-230010
in-the-hub-range	users	40	u-40
login-twin	provider	10	53	identifier	PROV-ASHA
login-twin	users	20	33	username	asha
login-twin	users	30	43	system_id	30-0
role-differs	Doctor	privileges
role-differs	Nurse	parents
twin	person	230023	230020	p-230020
twin	role	Lab2	Nurse	r-nurse"
got="$(printf '%s\n' "$out" | grep -E '^(collision|twin|login-twin|in-the-hub-range|role-differs|role-missing)	' | LC_ALL=C sort)"
[ "$rc" = 1 ] && [ "$got" = "$want" ] && ok_ "each planted finding fires: a collision, a person twin, a role twin, three login twins (username, system id, provider identifier), a row in the hub's range, a role with other privileges and one with other parents (exit 1)" || bad "findings: rc=$rc
got:
$got
want:
$want
$out"
cat <<'SQL' | sq
DELETE FROM openmrs.person WHERE person_id IN (230010, 230023);
DELETE FROM openmrs.users WHERE user_id IN (33, 43, 40);
DELETE FROM openmrs.provider WHERE provider_id = 53;
INSERT INTO openmrs.role_privilege VALUES ('Doctor','Add Orders');
INSERT INTO openmrs.role_role VALUES ('Authenticated','Nurse');
DELETE FROM openmrs.role WHERE role = 'Lab2';
UPDATE openmrs.role SET uuid='r-nurse' WHERE role='Nurse';
SQL
run
[ "$rc" = 0 ] && ok_ "with each removed the check passes again" || bad "after clearing: rc=$rc $out"

# a recorded floor below rows that do not end in 0
printf 'users 10\nprovider 10\n' > "$TMP/f-low"; hubrows "$TMP/f-low"
run
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "the hub holds 1 users row(s) at or above its recorded floor 10 that do not end in 0" && ok_ "a hub floor below rows that are not the hub's stops the check (exit 2)" || bad "low floor: rc=$rc $out"
hubrows "$TMP/hub-floors"

# --- the load ------------------------------------------------------------------------------
REPO_DIR="$RP" bash "$S" --hub-dump --floors "$TMP/hub-floors" --database hubdb | docker exec -i "$CNAME" sh > "$TMP/dump.sql" 2>"$TMP/dump.err"
[ "$(grep -c '^INSERT INTO' "$TMP/dump.sql")" = 10 ] && ! grep -q 'loginAttempts\|lockoutTimestamp' "$TMP/dump.sql" && ! grep -q "'p-clinic-up'" "$TMP/dump.sql" \
  && ok_ "the hub's dump: 10 hub-written rows, no node-local property, no person a clinic sent up" || bad "dump: $(cat "$TMP/dump.err") $(cat "$TMP/dump.sql")"
state(){ echo "SELECT GROUP_CONCAT(CONCAT(user_id, '=', uuid) ORDER BY user_id) FROM openmrs.users; SELECT GROUP_CONCAT(person_id ORDER BY person_id) FROM openmrs.person; SELECT GROUP_CONCAT(CONCAT(user_id, ':', role) ORDER BY user_id, role) FROM openmrs.user_role; SELECT GROUP_CONCAT(CONCAT(user_id, ':', property) ORDER BY user_id, property) FROM openmrs.user_property; SELECT GROUP_CONCAT(provider_id ORDER BY provider_id) FROM openmrs.provider;" | sq | tr '\n' ' '; }
S0="$(state)"
run --load "$TMP/dump.sql"
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'holds users rows, which carry password hashes' && [ "$(state)" = "$S0" ] \
  && ok_ "users rows are not loaded without the link statement; nothing loaded" || bad "load without link: rc=$rc $out"
{ cat "$TMP/dump.sql"; echo 'DROP TABLE users;'; } > "$TMP/dump-extra.sql"
HUB_LINK_PER_SITE_TLS=yes run --load "$TMP/dump-extra.sql"
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'is not --hub-dump'"'"'s output' && [ "$(state)" = "$S0" ] \
  && ok_ "a dump with any other statement is refused; nothing loaded" || bad "foreign statement: rc=$rc $out"
{ cat "$TMP/dump.sql"; echo "INSERT INTO \`person\` (\`person_id\`, \`gender\`, \`uuid\`) VALUES (230033,'F','p-230033');"; } > "$TMP/dump-foreign.sql"
HUB_LINK_PER_SITE_TLS=yes run --load "$TMP/dump-foreign.sql"
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'rolled back' && printf '%s' "$out" | grep -q 'person: every row loaded is a hub-written one' && [ "$(state)" = "$S0" ] \
  && ok_ "a dump row that is not hub-written rolls the whole load back" || bad "foreign row: rc=$rc $out | $(state)"
pos0="$(echo 'SHOW MASTER STATUS' | sq | cut -f1-2)"
HUB_LINK_PER_SITE_TLS=yes run --load "$TMP/dump.sql"
pos1="$(echo 'SHOW MASTER STATUS' | sq | cut -f1-2)"
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'loaded and committed; every check passed before the commit' && ok_ "the load commits" || bad "load: rc=$rc $out"
[ -n "$pos0" ] && [ "$pos0" = "$pos1" ] && ok_ "the load wrote nothing to the binary log ($pos0)" || bad "binary log moved: $pos0 -> $pos1"
case "$(state)" in "1=u-1,2=u-2,13=u-13,20=u-20,23=u-23,30=u-30 1,2,3,4,5,230003,230010,230013,230020 2:Nurse,20:Doctor,30:Lab 20:defaultLocale,23:loginAttempts 1,7,10 ") \
  ok_ "every hub row is here under the hub's id, with its role grants and its setting; the hub's grant to an older user, its node-local properties and the person a clinic sent up are not" ;;
  *) bad "after the load: $(state)" ;; esac
S1="$(state)"
HUB_LINK_PER_SITE_TLS=yes run --load "$TMP/dump.sql"
[ "$rc" = 0 ] && [ "$(state)" = "$S1" ] && ok_ "a second load changes nothing and passes" || bad "second load: rc=$rc $out"
run
[ "$rc" = 0 ] && ok_ "after the load the check still passes: the hub's rows here are the hub's" || bad "check after load: rc=$rc $out"
exit "$fails"
