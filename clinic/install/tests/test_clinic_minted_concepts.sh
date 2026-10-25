#!/usr/bin/env bash
# clinic/scripts/clinic-minted-concepts.sh: finds the concept rows a clinic
# minted for itself before the concept dictionary's down sinks start, and moves
# the ones the hub also holds to the hub's ids.
#
# On a throwaway MySQL of the pinned image, with binary logging on, a hub schema
# and a clinic schema: the clinic's first start minted two concepts, two names
# and a set under its own ids with the hub's uuids, and holds two concepts under
# each other's ids. The check lists exactly those twins; a collision, a
# reference from a table the clinic sends up (obs), an unknown column holding a
# moving id, a global property listing one, and a running OpenMRS each refuse
# the move with nothing changed; a statement refused inside the move rolls all
# of it back; the move itself puts every row at the hub's id, rewrites the
# references (the concept tables among themselves, a declared foreign key, a
# concept global property), writes nothing to the binary log, and the check
# then passes once the one concept the hub does not hold is gone.
# Skipped (passing) without docker or the pinned MySQL image.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
S="${RP}/clinic/scripts/clinic-minted-concepts.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; CNAME=""; ONAME=""
trap '[ -n "$CNAME" ] && docker rm -f "$CNAME" >/dev/null 2>&1; [ -n "$ONAME" ] && docker rm -f "$ONAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
[ -f "$S" ] || { bad "no $S"; exit 1; }

# --- without a database ---------------------------------------------------------------
q="$(REPO_DIR="$RP" bash "$S" --hub-query 2>&1)"; rc=$?
n="$(printf '%s\n' "$q" | grep -c "^SELECT 'last-legacy'")"
[ "$rc" = 0 ] && [ "$n" = "$(grep -c ':changes$' "$RP/hub/tables.conf")" ] && [ "$n" = 10 ] && ok_ "--hub-query reads the ten tables hub/tables.conf marks changes" || bad "hub query: rc=$rc n=$n"
printf '%s\n' "$q" | grep -q '^SET SESSION TRANSACTION READ ONLY;$' && ! printf '%s\n' "$q" | grep -qiE '^(INSERT|UPDATE|DELETE|ALTER|DROP|CREATE)' \
  && ok_ "the hub query is one read-only transaction" || bad "hub query writes: $q"
printf '%s\n' "$q" | grep -q "SELECT 'row', 'concept_numeric', \`concept_id\`, ''" && ok_ "concept_numeric is read by its concept's id, with no uuid of its own" || bad "concept_numeric query"
mkdir -p "$TMP/node"; printf 'COMPOSE_PROJECT_NAME=cmtest%s\n' "$$" > "$TMP/node/.env"
printf 'not the hub file\n' > "$TMP/bad"
out="$(REPO_DIR="$RP" CLINIC_DIR="$TMP/node" CT=docker bash "$S" --hub-ids "$TMP/bad" --container none 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'is not the output of --hub-query' && ok_ "a hub file that is not --hub-query's output is refused" || bad "bad hub file: rc=$rc $out"

# --- a real MySQL ------------------------------------------------------------------------
IMG="$(sed -n 's/^MYSQL_IMAGE=\([^[:space:]#]*\).*/\1/p' "$RP/sync/versions.env")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime or no local ${IMG:-MySQL image}: the real-MySQL checks are skipped"
  exit "$fails"
fi
CNAME="cm-test-$$"
docker run -d --name "$CNAME" --tmpfs /var/lib/mysql -e MYSQL_ROOT_PASSWORD=t -e MYSQL_DATABASE=openmrs "$IMG" \
  --innodb-buffer-pool-size=16M --performance-schema=OFF >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
sq(){ docker exec -i "$CNAME" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B'; }
up=0; for i in $(seq 1 120); do docker logs "$CNAME" 2>&1 | grep -q 'ready for connections.*port: 3306' && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "${IMG} was not ready within 120 s"; exit "$fails"; }
ddl(){ cat <<SQL
CREATE TABLE $1.concept_class (concept_class_id int PRIMARY KEY, uuid char(38) UNIQUE);
CREATE TABLE $1.concept_reference_source (concept_source_id int PRIMARY KEY, uuid char(38) UNIQUE);
CREATE TABLE $1.concept (concept_id int PRIMARY KEY, class_id int, uuid char(38) NOT NULL UNIQUE);
CREATE TABLE $1.concept_name (concept_name_id int PRIMARY KEY, concept_id int, name varchar(255), uuid char(38) NOT NULL UNIQUE);
CREATE TABLE $1.concept_description (concept_description_id int PRIMARY KEY, concept_id int, uuid char(38) UNIQUE);
CREATE TABLE $1.concept_numeric (concept_id int PRIMARY KEY, hi_absolute double);
CREATE TABLE $1.concept_answer (concept_answer_id int PRIMARY KEY, concept_id int, answer_concept int, uuid char(38) UNIQUE);
CREATE TABLE $1.concept_set (concept_set_id int PRIMARY KEY, concept_id int, concept_set int, uuid char(38) UNIQUE);
CREATE TABLE $1.concept_reference_term (concept_reference_term_id int PRIMARY KEY, concept_source_id int, uuid char(38) UNIQUE);
CREATE TABLE $1.concept_reference_map (concept_map_id int PRIMARY KEY, concept_id int, concept_reference_term_id int, uuid char(38) UNIQUE);
SQL
}
seed(){ # SCHEMA : the rows every node shares (legacy ids 1..37 on every residue)
  cat <<SQL
INSERT INTO $1.concept_class VALUES (1,'k-1'),(2,'k-2'),(3,'k-3');
INSERT INTO $1.concept_reference_source VALUES (1,'src-1'),(2,'src-2');
INSERT INTO $1.concept_reference_term VALUES (1,1,'t-1'),(2,1,'t-2');
SQL
  for i in $(seq 1 37); do printf "INSERT INTO %s.concept VALUES (%s, 1, 'c-%s'); INSERT INTO %s.concept_name VALUES (%s, %s, 'name %s', 'n-%s');\n" "$1" "$i" "$i" "$1" "$i" "$i" "$i" "$i"; done
  printf "INSERT INTO %s.concept_reference_map VALUES (1, 5, 1, 'm-1');\nINSERT INTO %s.concept_description VALUES (1, 5, 'd-1');\nINSERT INTO %s.concept_answer VALUES (1, 5, 6, 'a-1');\n" "$1" "$1" "$1"
}
{
  echo 'CREATE DATABASE hubdb;'; ddl hubdb; seed hubdb
  # the hub's own rows, on residue 0 above its last legacy id 37
  cat <<'SQL'
INSERT INTO hubdb.concept VALUES (40, 1, 'c-40'), (50, 1, 'c-50'), (60, 1, 'c-60'), (70, 1, 'c-70'), (90, 1, 'c-y');
INSERT INTO hubdb.concept_name VALUES (400, 40, 'module concept', 'n-40'), (500, 50, 'module set', 'n-50');
INSERT INTO hubdb.concept_set VALUES (600, 40, 50, 's-1');
INSERT INTO hubdb.concept_numeric VALUES (40, 9.5);
SQL
  ddl openmrs; seed openmrs
  # the clinic (residue 3): its first start minted the module's concepts under
  # its own ids; two concepts sit under each other's ids
  cat <<'SQL'
INSERT INTO openmrs.concept VALUES (43, 1, 'c-40'), (53, 1, 'c-50'), (60, 1, 'c-70'), (70, 1, 'c-60');
INSERT INTO openmrs.concept_name VALUES (63, 43, 'module concept', 'n-40'), (73, 53, 'module set', 'n-50');
INSERT INTO openmrs.concept_set VALUES (93, 43, 53, 's-1');
INSERT INTO openmrs.concept_numeric VALUES (43, 9.5);
CREATE TABLE openmrs.obs (obs_id int PRIMARY KEY, concept_id int, value_coded int, value_coded_name_id int);
INSERT INTO openmrs.obs VALUES (1, 5, NULL, NULL);
CREATE TABLE openmrs.drug (drug_id int PRIMARY KEY, concept_id int, FOREIGN KEY (concept_id) REFERENCES openmrs.concept (concept_id));
INSERT INTO openmrs.drug VALUES (1, 43), (2, 7);
CREATE TABLE openmrs.global_property (property varchar(255) PRIMARY KEY, property_value text);
INSERT INTO openmrs.global_property VALUES ('bahmni.lab.concept', '43'), ('unrelated.setting', '1');
CREATE TABLE openmrs.concept_proposal (concept_proposal_id int PRIMARY KEY, obs_concept_id int);
SQL
} | sq 2>"$TMP/fx.err" || { bad "fixture refused: $(head -3 "$TMP/fx.err")"; exit "$fails"; }
# the hub file, read exactly as the runbook reads it on the hub
REPO_DIR="$RP" bash "$S" --hub-query --database hubdb | sq > "$TMP/hub.tsv"
[ "$(head -1 "$TMP/hub.tsv" | cut -f1-3)" = "format	concept-ids	1" ] && grep -q '^last-legacy	concept	37' "$TMP/hub.tsv" \
  && ok_ "the hub file: format line, the hub's last legacy concept id 37" || bad "hub file: $(head -3 "$TMP/hub.tsv" | tr '\n' '|')"
run(){ out="$(env PATH="$PATH" REPO_DIR="$RP" CLINIC_DIR="$TMP/node" CT=docker bash "$S" --hub-ids "$TMP/hub.tsv" --container "$CNAME" "$@" 2>&1)"; rc=$?; }
state(){ echo "SELECT GROUP_CONCAT(CONCAT(concept_id, '=', uuid) ORDER BY uuid) FROM openmrs.concept WHERE concept_id > 37; SELECT GROUP_CONCAT(CONCAT(concept_name_id, ':', concept_id) ORDER BY concept_name_id) FROM openmrs.concept_name WHERE concept_name_id > 37; SELECT GROUP_CONCAT(CONCAT(concept_set_id, ':', concept_id, ':', concept_set)) FROM openmrs.concept_set; SELECT GROUP_CONCAT(concept_id) FROM openmrs.concept_numeric; SELECT GROUP_CONCAT(CONCAT(drug_id, ':', concept_id) ORDER BY drug_id) FROM openmrs.drug; SELECT GROUP_CONCAT(CONCAT(property, '=', property_value) ORDER BY property) FROM openmrs.global_property;" | sq | tr '\n' ' '; }
S0="$(state)"
# the guard each check uses: a broken condition ends the session with an error
# (so COMMIT is never reached), a sound one passes quietly
g="$(printf "SELECT (SELECT z.n FROM (SELECT 1 AS n UNION ALL SELECT 2) z WHERE (SELECT 0) = 1);\nSELECT 'after';\n" | sq 2>&1)"; g1=$?
b2="$(printf "START TRANSACTION; UPDATE openmrs.concept SET class_id = 2 WHERE concept_id = 1;\nSELECT (SELECT z.n FROM (SELECT 1 AS n UNION ALL SELECT 2) z WHERE (SELECT 1) = 1);\nCOMMIT;\n" | sq 2>&1)"; g2=$?
[ "$g1" = 0 ] && [ "$(printf '%s' "$g" | tr '\n' ' ')" = "NULL after" ] && [ "$g2" != 0 ] && printf '%s' "$b2" | grep -q 'ERROR 1242' \
  && [ "$(echo 'SELECT class_id FROM openmrs.concept WHERE concept_id = 1' | sq)" = 1 ] \
  && ok_ "the check idiom: a sound condition passes, a broken one stops the session (error 1242) before COMMIT and the change is rolled back" || bad "check idiom: $g / $b2"

run
want="twin	concept	43	40	c-40
twin	concept	53	50	c-50
twin	concept	60	70	c-70
twin	concept	70	60	c-60
twin	concept_name	63	400	n-40
twin	concept_name	73	500	n-50
twin	concept_set	93	600	s-1"
got="$(printf '%s\n' "$out" | grep '^twin' | LC_ALL=C sort)"
[ "$rc" = 1 ] && [ "$got" = "$want" ] && ! printf '%s' "$out" | grep -qE '^(collision|residue)' && printf '%s' "$out" | grep -q 'FAIL 7 concept row(s) this clinic minted' \
  && ok_ "the check lists exactly the seven twins (two concepts, two names, a set, and the two concepts under each other's ids), exit 1" || bad "check: rc=$rc
$out"
[ "$(state)" = "$S0" ] && ok_ "the check changed nothing" || bad "the check changed rows"

echo "INSERT INTO openmrs.concept VALUES (90, 1, 'c-x');" | sq
SP="$(state)"; run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q '^collision	concept	90	c-x	c-y' && printf '%s' "$out" | grep -q 'nothing was changed' && [ "$(state)" = "$SP" ] \
  && ok_ "a clinic concept under an id the hub uses for another (a collision) refuses the move, nothing changed" || bad "collision: rc=$rc $out"
echo "DELETE FROM openmrs.concept WHERE concept_id = 90;" | sq

echo "INSERT INTO openmrs.obs VALUES (2, 43, NULL, NULL);" | sq
run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'obs.concept_id: 1 row(s) refer to a moving concept row, and this clinic sends obs up' && [ "$(state)" = "$S0" ] \
  && ok_ "an observation recorded against a moving concept refuses the move (obs travels up; the hub's copy would keep the old id), nothing changed" || bad "obs reference: rc=$rc $out"
echo "DELETE FROM openmrs.obs WHERE obs_id = 2;" | sq

echo "INSERT INTO openmrs.concept_proposal VALUES (1, 53);" | sq
run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'concept_proposal.obs_concept_id: 1 row(s) hold a moving concept' && [ "$(state)" = "$S0" ] \
  && ok_ "a column the script does not know as a reference, holding a moving concept's id, refuses the move" || bad "unknown column: rc=$rc $out"
echo "DELETE FROM openmrs.concept_proposal;" | sq

echo "INSERT INTO openmrs.global_property VALUES ('some.list', '5,43');" | sq
SP="$(state)"; run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "global property some.list = '5,43'" && [ "$(state)" = "$SP" ] \
  && ok_ "a global property listing a moving concept's id among others refuses the move" || bad "listed property: rc=$rc $out"
echo "DELETE FROM openmrs.global_property WHERE property = 'some.list';" | sq

ONAME="cmtest$$-openmrs-1"
docker run -d --name "$ONAME" --entrypoint sleep "$IMG" 120 >/dev/null 2>&1
run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q "OpenMRS (${ONAME}) is running" && [ "$(state)" = "$S0" ] \
  && ok_ "a running OpenMRS refuses the move" || bad "running OpenMRS: rc=$rc $out"
docker rm -f "$ONAME" >/dev/null 2>&1; ONAME=""

# a statement refused inside the move: everything before it is rolled back
echo "SET foreign_key_checks = 0; INSERT INTO openmrs.drug VALUES (3, 40); ALTER TABLE openmrs.drug ADD UNIQUE KEY one_drug_per_concept (concept_id);" | sq
S1="$(state)"
run --rekey
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q 'rolled back' && [ "$(state)" = "$S1" ] \
  && ok_ "a statement refused part-way through (a unique key on drug.concept_id) rolls the whole move back" || bad "rollback: rc=$rc $out | $(state)"
echo "DELETE FROM openmrs.drug WHERE drug_id = 3; ALTER TABLE openmrs.drug DROP INDEX one_drug_per_concept;" | sq
[ "$(state)" = "$S0" ] && ok_ "the fixture is back as it was before the refusals" || bad "fixture not restored: $(state)"

# the move, with one concept the hub does not hold (a residue finding) still here
echo "INSERT INTO openmrs.concept VALUES (83, 1, 'c-local');" | sq
pos0="$(echo 'SHOW MASTER STATUS' | sq | cut -f1-2)"
run --rekey
pos1="$(echo 'SHOW MASTER STATUS' | sq | cut -f1-2)"
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'moved and committed; every check passed before the commit' && printf '%s' "$out" | grep -q '^residue	concept	83	c-local' \
  && printf '%s' "$out" | grep -q 'after the move, 1 finding(s) remain (twin 0, residue 1)' && ok_ "the move commits; the concept the hub does not hold is reported, not moved (exit 1)" || bad "rekey: rc=$rc $out"
[ -n "$pos0" ] && [ "$pos0" = "$pos1" ] && ok_ "the move wrote nothing to the binary log ($pos0)" || bad "binary log moved: $pos0 -> $pos1"
got="$(state)"
case "$got" in "40=c-40,50=c-50,60=c-60,70=c-70,83=c-local 400:40,500:50 600:40:50 40 1:40,2:7 bahmni.lab.concept=40,unrelated.setting=1 ") ok_ "every row at the hub's id and every reference with it: names point at 40 and 50, the set is 600 (40 holds 50), concept_numeric at 40, drug 1 at 40, the concept property 40, the swapped pair each at its hub id" ;;
  *) bad "after the move: $got" ;; esac
[ "$(echo 'SELECT COUNT(*) FROM openmrs.concept; SELECT COUNT(*) FROM openmrs.concept_name;' | sq | tr '\n' ' ')" = "42 39 " ] && ok_ "row counts unchanged (42 concepts, 39 names)" || bad "counts: $(echo 'SELECT COUNT(*) FROM openmrs.concept; SELECT COUNT(*) FROM openmrs.concept_name;' | sq | tr '\n' ' ')"
echo "DELETE FROM openmrs.concept WHERE concept_id = 83;" | sq
run
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'no concept row minted at this clinic' && ok_ "then the check passes: the concept down sinks may start" || bad "final check: rc=$rc $out"
run --rekey
[ "$rc" = 0 ] && ok_ "a second --rekey has nothing to move and passes" || bad "second rekey: rc=$rc $out"
exit "$fails"
