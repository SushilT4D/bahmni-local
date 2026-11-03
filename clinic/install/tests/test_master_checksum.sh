#!/usr/bin/env bash
# clinic/scripts/master-checksum.sh: a row count and a checksum over every
# column of every row, per down table, so a row edited in place with its id and
# uuid unchanged is seen. First against a fake MySQL that records the query;
# then, when a container runtime and the pinned MySQL image are already on this
# machine, against a real MySQL: an in-place edit changes the checksum while an
# (id, uuid) checksum of the same rows does not.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
S="${RP}/clinic/scripts/master-checksum.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; CNAME=""
trap '[ -n "$CNAME" ] && docker rm -f "$CNAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
[ -f "$S" ] || { bad "no $S"; exit 1; }
[ -f "$RP/hub/checksum-exclusions.conf" ] && ok_ "the excluded columns are listed in hub/checksum-exclusions.conf" || bad "no hub/checksum-exclusions.conf"
[ "$(awk '{ sub(/#.*/, "") } NF { print $1 }' "$RP/hub/checksum-exclusions.conf")" = privilege.uuid ] \
  && ok_ "the one excluded column is privilege.uuid" || bad "exclusions: $(awk '{ sub(/#.*/, "") } NF' "$RP/hub/checksum-exclusions.conf")"

# --- a fake MySQL: columns from a fixture, every statement logged ---------------------
R="$TMP/r"; mkdir -p "$R/hub" "$TMP/bin" "$TMP/node"
cp "$RP/hub/table-verdicts.conf" "$RP/hub/checksum-exclusions.conf" "$R/hub/"
printf 'form:form_id\nform_resource:form_resource_id\nprivilege:privilege\n' > "$R/hub/tables.conf"
printf 'COMPOSE_PROJECT_NAME=bahmni-t\n' > "$TMP/node/.env"
TAB="$(printf '\t')"
cat > "$TMP/cols" <<EOF
form${TAB}build${TAB}int
form${TAB}date_created${TAB}datetime
form${TAB}description${TAB}text
form${TAB}form_id${TAB}int
form${TAB}name${TAB}varchar
form${TAB}published${TAB}tinyint
form${TAB}uuid${TAB}char
form${TAB}version${TAB}varchar
form${TAB}xslt${TAB}mediumtext
privilege${TAB}description${TAB}text
privilege${TAB}privilege${TAB}varchar
privilege${TAB}uuid${TAB}char
concept_datatype${TAB}concept_datatype_id${TAB}int
concept_datatype${TAB}hl7_abbreviation${TAB}varchar
EOF
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
q="$(cat)"; printf '%s\n' "ct $*" "$q" >> "$FAKE_LOG"
case "$q" in
  *information_schema.COLUMNS*) cat "$FAKE_COLS" ;;
  *"SELECT 'form'"*) printf 'form\t3\t123\t9:abc\nform_resource\tabsent\nprivilege\t2\t456\t2:def\n' ;;
esac
SH
chmod +x "$TMP/bin/fakect"
mc(){ env PATH="$PATH" REPO_DIR="$R" CLINIC_DIR="$TMP/node" CT="$TMP/bin/fakect" FAKE_LOG="$TMP/log" FAKE_COLS="$TMP/cols" bash "$S" "$@" 2>&1; }
: > "$TMP/log"; out="$(mc)"; rc=$?
[ "$rc" -eq 0 ] && grep -q '^ct exec -i bahmni-t-bahmni-mysql-1 ' "$TMP/log" && ok_ "it reads the node's MySQL container" || bad "run: rc=$rc out=$out"
[ "$(printf '%s\n' "$out" | cut -f1 | tr '\n' ' ')" = "form form_resource privilege " ] && ok_ "one line per listed table, sorted" || bad "output: $out"
q="$(grep "^SELECT 'form'," "$TMP/log")"
miss=""; for c in build date_created description form_id name published uuid version xslt; do printf '%s' "$q" | grep -qF "\`${c}\`" || miss="$miss $c"; done
[ -n "$q" ] && [ -z "$miss" ] && ok_ "form's checksum covers every one of its columns, not only id and uuid" || bad "form query lacks:${miss} ($q)"
printf '%s' "$q" | grep -qF 'FROM `openmrs`.`form`' && printf '%s' "$q" | grep -qF "IFNULL(CONCAT(LENGTH(" && printf '%s' "$q" | grep -qF "SUM(" \
  && ok_ "each column is length-prefixed and NULL-marked, and rows are summed (order-free)" || bad "form query shape: $q"
q="$(grep "^SELECT 'privilege'," "$TMP/log")"
printf '%s' "$q" | grep -qF '`privilege`' && printf '%s' "$q" | grep -qF '`description`' && ! printf '%s' "$q" | grep -qF '`uuid`' \
  && ok_ "privilege.uuid is left out; its other columns are in" || bad "privilege query: $q"
grep -qF "SELECT 'form_resource', 'absent';" "$TMP/log" && ok_ "a listed table missing from the schema is reported absent" || bad "absent table not reported"
grep -qx 'SET SESSION TRANSACTION READ ONLY;' "$TMP/log" && grep -qx 'START TRANSACTION WITH CONSISTENT SNAPSHOT;' "$TMP/log" \
  && ! grep -qiE '^[[:space:]]*(INSERT|UPDATE|DELETE|REPLACE|ALTER|DROP|CREATE|GRANT|TRUNCATE)[[:space:]]' "$TMP/log" \
  && ok_ "read-only: one READ ONLY transaction, no statement that writes" || bad "statements: $(grep -v '^ct ' "$TMP/log" | cut -c1-60 | tr '\n' '|')"
grep -q "concept_datatype" "$TMP/log" && bad "a RESEED table was read without --reseed" || ok_ "RESEED tables only with --reseed"
tz="$(grep -n "^SET SESSION time_zone = '+00:00';\$" "$TMP/log" | head -1 | cut -d: -f1)"; tx="$(grep -n '^START TRANSACTION' "$TMP/log" | head -1 | cut -d: -f1)"
[ -n "$tz" ] && [ -n "$tx" ] && [ "$tz" -lt "$tx" ] && ok_ "the session reads in UTC, set before the snapshot is taken" || bad "no UTC session time zone before the transaction: $(grep -v '^ct ' "$TMP/log" | head -3 | tr '\n' '|')"
: > "$TMP/log"; mc --reseed >/dev/null
grep -q "^SELECT 'concept_datatype'," "$TMP/log" && grep -q "'care_setting'" "$TMP/log" && ok_ "--reseed adds the tables hub/table-verdicts.conf marks RESEED" || bad "--reseed: $(grep -c . "$TMP/log")"
printf 'form.xslt\n' >> "$R/hub/checksum-exclusions.conf"; : > "$TMP/log"; mc >/dev/null
q="$(grep "^SELECT 'form'," "$TMP/log")"
! printf '%s' "$q" | grep -qF '`xslt`' && printf '%s' "$q" | grep -qF '`name`' && ok_ "a column is excluded by a line in hub/checksum-exclusions.conf, and only then" || bad "exclusion not read: $q"
printf 'not a column\n' >> "$R/hub/checksum-exclusions.conf"; out="$(mc)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "is not <table>.<column>" && ok_ "a malformed exclusion is refused" || bad "malformed exclusion: rc=$rc $out"
cp "$RP/hub/checksum-exclusions.conf" "$R/hub/"
out="$(env PATH="$PATH" REPO_DIR="$R" CLINIC_DIR="$TMP/node" CT="$TMP/bin/fakect" FAKE_LOG="$TMP/log" FAKE_COLS="$TMP/cols" bash "$S" --container hub-db 2>&1)"
grep -q '^ct exec -i hub-db ' "$TMP/log" && ok_ "--container names another MySQL (the hub's)" || bad "--container: $out"

# --- a real MySQL, when one can be started without a download ---------------------------
IMG="$(sed -n 's/^MYSQL_IMAGE=\([^[:space:]#]*\).*/\1/p' "$RP/sync/versions.env")"
if [ "${TEST_NO_CONTAINERS:-0}" = 1 ] || ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  ok_ "no container runtime or no local ${IMG:-MySQL image}: the real-MySQL checks are skipped"
  exit "$fails"
fi
CNAME="mc-test-$$"
# a throwaway server: data in memory, no binlog, a small buffer pool
docker run -d --name "$CNAME" --tmpfs /var/lib/mysql -e MYSQL_ROOT_PASSWORD=t -e MYSQL_DATABASE=openmrs "$IMG" \
  --skip-log-bin --innodb-buffer-pool-size=16M --performance-schema=OFF >/dev/null 2>&1 || { bad "could not start ${IMG}"; exit "$fails"; }
sq(){ docker exec -i "$CNAME" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -N -B openmrs'; }
# the image's first start runs a temporary server on the socket only (port 0)
# and then restarts: ready means the server listening on 3306
up=0; for i in $(seq 1 120); do docker logs "$CNAME" 2>&1 | grep -q 'ready for connections.*port: 3306' && { up=1; break; }; sleep 1; done
[ "$up" = 1 ] || { bad "${IMG} was not ready within 120 s"; exit "$fails"; }
sq <<'SQL'
CREATE TABLE form (form_id int PRIMARY KEY, name varchar(255) NOT NULL, version varchar(50), published tinyint(1), description text, uuid char(38));
CREATE TABLE form_resource (form_resource_id int PRIMARY KEY, form_id int, name varchar(255), value_reference text, uuid char(38));
CREATE TABLE privilege (privilege varchar(255) PRIMARY KEY, description text, uuid char(38));
INSERT INTO form VALUES (454, 'Vitals', '1', 1, NULL, 'u-454'), (457, 'History', '2', 1, '', 'u-457'), (460, 'Plan', '1', 0, 'x', 'u-460');
INSERT INTO form_resource VALUES (1, 454, 'Vitals', '/home/bahmni/clinical_forms/a.json', 'r-1');
INSERT INTO privilege VALUES ('Get Concepts', 'Able to get concepts', 'p-1');
SQL
printf 'form:form_id\nform_resource:form_resource_id\nprivilege:privilege\n' > "$R/hub/tables.conf"
real(){ env PATH="$PATH" REPO_DIR="$R" CLINIC_DIR="$TMP/node" CT=docker bash "$S" --container "$CNAME" 2>&1; }
idsum(){ echo "SELECT COALESCE(SUM(CAST(CONV(LEFT(MD5(CONCAT(form_id, ':', uuid)), 16), 16, 10) AS UNSIGNED)), 0) FROM form;" | sq; }
a="$(real)"; rc=$?; ia="$(idsum)"
[ "$rc" -eq 0 ] && printf '%s\n' "$a" | grep -q "^form${TAB}3${TAB}[0-9][0-9]*${TAB}6:" && ok_ "real MySQL: form, 3 rows, a checksum, 6 columns" || bad "real run: rc=$rc $a"
echo "UPDATE form SET published = 1 WHERE form_id = 460;" | sq
b="$(real)"; ib="$(idsum)"
[ "$(printf '%s\n' "$a" | grep '^form	')" != "$(printf '%s\n' "$b" | grep '^form	')" ] && ok_ "an in-place edit (id and uuid unchanged) changes form's checksum" || bad "in-place edit not seen: $a / $b"
[ "$ia" = "$ib" ] && ok_ "while an (id, uuid) checksum of the same rows does not change" || bad "(id, uuid) checksum moved: $ia / $ib"
[ "$(printf '%s\n' "$a" | grep -v '^form	')" = "$(printf '%s\n' "$b" | grep -v '^form	')" ] && ok_ "the other tables' lines are unchanged" || bad "other tables moved: $a / $b"
echo "UPDATE form SET published = 0 WHERE form_id = 460;" | sq
[ "$(real)" = "$a" ] && ok_ "undoing the edit restores the checksum" || bad "not restored"
echo "UPDATE form SET description = '' WHERE form_id = 454; UPDATE form SET description = NULL WHERE form_id = 457;" | sq
[ "$(real | grep '^form	')" != "$(printf '%s\n' "$a" | grep '^form	')" ] && ok_ "NULL and an empty string are told apart, even when two rows swap them" || bad "NULL/empty swap not seen"
echo "UPDATE form SET description = NULL WHERE form_id = 454; UPDATE form SET description = '' WHERE form_id = 457;" | sq
echo "UPDATE privilege SET uuid = 'p-node-local';" | sq
[ "$(real)" = "$a" ] && ok_ "a node-local privilege uuid does not change the checksum (excluded)" || bad "privilege.uuid counted"
echo "DELETE FROM form; INSERT INTO form VALUES (460, 'Plan', '1', 0, 'x', 'u-460'), (457, 'History', '2', 1, '', 'u-457'), (454, 'Vitals', '1', 1, NULL, 'u-454');" | sq
[ "$(real)" = "$a" ] && ok_ "the same rows written in another order give the same checksum" || bad "row order changed the checksum"
echo "UPDATE form SET name = 'Vital', version = 's1' WHERE form_id = 454;" | sq
[ "$(real | grep '^form	')" != "$(printf '%s\n' "$a" | grep '^form	')" ] && ok_ "text moved from one column into the next is seen" || bad "column-boundary shift not seen"
# MySQL renders a TIMESTAMP in the session's time zone: the same stored instant
# must hash alike whatever zone the server hands a new session
echo "ALTER TABLE privilege ADD COLUMN date_changed TIMESTAMP NULL; UPDATE privilege SET date_changed = FROM_UNIXTIME(1000000000);" | sq
echo "SET GLOBAL time_zone = '+00:00';" | sq; ru="$(echo "SELECT CAST(date_changed AS CHAR) FROM privilege;" | sq)"; u="$(real)"
echo "SET GLOBAL time_zone = '+05:30';" | sq; rk="$(echo "SELECT CAST(date_changed AS CHAR) FROM privilege;" | sq)"; k="$(real)"
echo "SET GLOBAL time_zone = 'SYSTEM';" | sq
[ -n "$ru" ] && [ "$ru" != "$rk" ] && ok_ "the stored instant renders differently in the two zones (${ru} / ${rk})" || bad "zones did not change the rendering: '${ru}' / '${rk}'"
[ -n "$u" ] && [ "$u" = "$k" ] && printf '%s\n' "$u" | grep -q "^privilege${TAB}1${TAB}" && ok_ "a row with a TIMESTAMP hashes alike under two session time zones" || bad "the checksum follows the session time zone: $u / $k"
exit "$fails"
