#!/usr/bin/env bash
# Live test for inspect-old-node.sh against real MySQL 8.0 and Postgres
# containers (needs docker; not part of the runtime-free install suite).
#
# The fixture is built the way the old stack leaves a clinic: a starting copy
# with no stride (ids 1, 2, 3, ...), then the global stride and base floors
# set with SET PERSIST, then rows inserted by the clinic. The starting copy's
# top obs and allergy_reaction rows deliberately sit on the clinic's residue,
# so a naive "rows on my residue at the top" count would report rows the
# clinic never wrote.
#
#   B: the clinic wrote obs, orders and an Odoo invoice  -> verdict B, 7 rows
#   A: the clinic wrote only captured tables             -> verdict A, 0 rows
#   MySQL stopped                                        -> verdict UNKNOWN, exit 2
#
# Each scenario runs under bash and under /bin/bash (macOS's 3.2) when present.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../inspect-old-node.sh"
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || { echo "docker is not running"; exit 1; }
for p in 18083 18084; do
  if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then echo "port $p is busy; the Connect stub needs it"; exit 1; fi
done

P=inspecttest
MY="${P}-bahmni-mysql"; PG="${P}-bahmni-postgres"
T="$(mktemp -d "${TMPDIR:-/tmp}/inspect-live.XXXXXX")"
STUB_PIDS=""
cleanup(){
  docker rm -f "$MY" "$PG" >/dev/null 2>&1
  for s in $STUB_PIDS; do kill "$s" 2>/dev/null; done
  rm -rf "$T"
}
trap cleanup EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

# --- a fake old checkout ---------------------------------------------------
OLD="${T}/bahmni-local"
mkdir -p "${OLD}/debezium/local" "${OLD}/data/bahmni-document-images" "${OLD}/files/odoo"
: > "${OLD}/docker-compose.yml"
cat > "${OLD}/.env" <<'EOF'
BHS_LOCATION=rawach
MYSQL_SERVER_NAME=bahmni-local
MYSQL_ROOT_PASSWORD=testroot
OPENMRS_DB_NAME=openmrs
ODOO_DB_USER=odoo
ODOO_DB_PASSWORD=testodoo
ODOO_DB_NAME=odoo
OPENMRS_IMAGE_NAME=example/openmrs:old
REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.example:9093
EOF
cat > "${OLD}/debezium/local/tables.conf" <<'EOF'
# table:key:base
encounter:encounter_id:528000
person:person_id:230000
visit:visit_id:625000
EOF
printf 'old scan\n' > "${OLD}/data/bahmni-document-images/a.jpg"
touch -t 202501010000 "${OLD}/data/bahmni-document-images/a.jpg"

# --- Connect REST stubs on 18083 (Debezium) and 18084 (MirrorMaker) ----------
cat > "${T}/stub.py" <<'EOF'
import sys, http.server
body = open(sys.argv[2], 'rb').read()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
EOF
printf '%s' '{"src":{"info":{"config":{"table.include.list":"openmrs.person,openmrs.visit,openmrs.encounter"}},"status":{"connector":{"state":"RUNNING"},"tasks":[{"state":"RUNNING"}]}}}' > "${T}/src.json"
printf '%s' '{"mm":{"status":{"connector":{"state":"RUNNING"},"tasks":[{"state":"RUNNING"}]}}}' > "${T}/mm.json"
python3 "${T}/stub.py" 18083 "${T}/src.json" & STUB_PIDS="$!"
python3 "${T}/stub.py" 18084 "${T}/mm.json" & STUB_PIDS="${STUB_PIDS} $!"

# --- databases ---------------------------------------------------------------
docker rm -f "$MY" "$PG" >/dev/null 2>&1
docker run -d --name "$MY" --tmpfs /var/lib/mysql:rw,size=1g -e MYSQL_ROOT_PASSWORD=testroot -e MYSQL_DATABASE=openmrs mysql:8.0 >/dev/null
docker run -d --name "$PG" --tmpfs /var/lib/postgresql/data:rw,size=512m -e POSTGRES_USER=odoo -e POSTGRES_PASSWORD=testodoo -e POSTGRES_DB=odoo postgres:16 >/dev/null
# Ready means the final server, not the entrypoint's temporary one: wait for
# the log line the entrypoint prints after the temporary server has stopped.
for i in $(seq 1 90); do
  docker logs "$MY" 2>&1 | grep -q 'MySQL init process done' &&
    docker exec "$MY" mysql -uroot -ptestroot -e 'SELECT 1' >/dev/null 2>&1 && break
  sleep 2
done
docker exec "$MY" mysql -uroot -ptestroot -e 'SELECT 1' >/dev/null 2>&1 || { echo "MySQL did not start:"; docker logs "$MY" 2>&1 | tail -5; exit 1; }
for i in $(seq 1 30); do docker exec "$PG" pg_isready -U odoo >/dev/null 2>&1 && break; sleep 1; done
my(){ docker exec -i "$MY" mysql -uroot -ptestroot openmrs 2>&1 | grep -v 'Using a password' >&2; }
pg(){ docker exec -i "$PG" psql -q -U odoo -d odoo -v ON_ERROR_STOP=1 >/dev/null; }

reset_db(){ # the starting copy: no stride; its top person (104), obs (1004) and
  # allergy_reaction (14) rows sit on residue 4. Dating the start from the top
  # person row would put it inside the copy and count the copy's obs.
  my <<'SQL'
SET PERSIST auto_increment_increment = 1; SET PERSIST auto_increment_offset = 1;
SET SESSION auto_increment_increment = 1; SET SESSION auto_increment_offset = 1;
DROP TABLE IF EXISTS person, visit, encounter, obs, orders, allergy_reaction, event_records;
CREATE TABLE person (person_id INT AUTO_INCREMENT PRIMARY KEY, date_created DATETIME);
CREATE TABLE visit (visit_id INT AUTO_INCREMENT PRIMARY KEY, date_created DATETIME);
CREATE TABLE encounter (encounter_id INT AUTO_INCREMENT PRIMARY KEY, date_created DATETIME);
CREATE TABLE obs (obs_id INT AUTO_INCREMENT PRIMARY KEY, date_created DATETIME);
CREATE TABLE orders (order_id INT AUTO_INCREMENT PRIMARY KEY, date_created DATETIME);
CREATE TABLE allergy_reaction (allergy_reaction_id INT AUTO_INCREMENT PRIMARY KEY, reaction INT);
CREATE TABLE event_records (id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(20));
SET SESSION cte_max_recursion_depth = 5000;
INSERT INTO person (date_created) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<104) SELECT '2025-01-10' FROM s;
INSERT INTO visit (date_created) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<100) SELECT '2025-01-10' FROM s;
INSERT INTO encounter (date_created) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<100) SELECT '2025-01-10' FROM s;
INSERT INTO obs (date_created) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<1004) SELECT '2025-06-01' FROM s;
INSERT INTO orders (date_created) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<50) SELECT '2025-06-01' FROM s;
INSERT INTO allergy_reaction (reaction) WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM s WHERE n<14) SELECT 1 FROM s;
INSERT INTO event_records (title) VALUES ('a'),('b');
-- what the old stack's offsets script does for clinic residue 4
SET PERSIST auto_increment_increment = 10; SET PERSIST auto_increment_offset = 4;
ALTER TABLE person AUTO_INCREMENT = 230004;
ALTER TABLE visit AUTO_INCREMENT = 625004;
ALTER TABLE encounter AUTO_INCREMENT = 528004;
SQL
  pg <<'SQL'
DROP TABLE IF EXISTS ir_module_module, account_invoice, sale_order, res_partner;
CREATE TABLE ir_module_module (name text, latest_version text);
INSERT INTO ir_module_module VALUES ('base', '10.0.1.3');
CREATE TABLE account_invoice (id serial PRIMARY KEY, create_date timestamp);
CREATE TABLE sale_order (id serial PRIMARY KEY, create_date timestamp);
CREATE TABLE res_partner (id serial PRIMARY KEY, create_date timestamp);
INSERT INTO account_invoice (create_date) VALUES ('2025-02-01'), ('2025-02-02');
INSERT INTO res_partner (create_date) VALUES ('2025-02-01');
SQL
}

clinic_registers(){ # rows the clinic writes in captured tables (a new session picks up the stride)
  my <<'SQL'
INSERT INTO person (date_created) VALUES ('2026-03-05 09:00:00'), ('2026-03-06 10:00:00'), ('2026-04-01 11:00:00');
INSERT INTO visit (date_created) VALUES ('2026-03-05 09:05:00');
INSERT INTO encounter (date_created) VALUES ('2026-03-05 09:10:00'), ('2026-04-01 11:10:00');
INSERT INTO event_records (title) VALUES ('c');
SQL
}
clinic_records_care(){ # rows the old stack never sends
  my <<'SQL'
INSERT INTO obs (date_created) VALUES ('2026-03-05 09:11:00'), ('2026-03-05 09:12:00'), ('2026-03-06 10:11:00'), ('2026-04-01 11:11:00'), ('2026-04-01 11:12:00');
INSERT INTO orders (date_created) VALUES ('2026-03-05 09:13:00'), ('2026-04-01 11:13:00');
SQL
  pg <<'SQL'
INSERT INTO account_invoice (create_date) VALUES ('2026-03-05 09:20:00');
SQL
  printf 'new scan\n' > "${OLD}/data/bahmni-document-images/b.jpg"
}

val(){ grep -E "^$1=" "$2/summary.env" | cut -d= -f2-; }
shells="bash"; [ -x /bin/bash ] && [ "$(uname -s)" = Darwin ] && shells="bash /bin/bash"

run_inspect(){ # SHELL OUT -> exit code
  ( cd "$OLD" && CONNECT_PORT=18083 MM_CONNECT_PORT=18084 "$1" "$SCRIPT" --out "$2" > "$2.log" 2>&1 ); echo $?
}

for sh in $shells; do
  printf '\n== scenario B (%s) ==\n' "$sh"
  reset_db; clinic_registers; clinic_records_care
  o="${T}/b-$(basename "$sh")"; rc="$(run_inspect "$sh" "$o")"
  [ "$rc" = 0 ] && ok_ "exit 0" || { bad "exit ${rc}"; tail -20 "$o.log"; }
  [ "$(val verdict "$o")" = B ] && ok_ "verdict B" || bad "verdict $(val verdict "$o")"
  [ "$(val patient_record_rows_unsent "$o")" = 7 ] && ok_ "7 patient-record rows (5 obs, 2 orders), the copy's residue-4 obs row not counted" \
    || bad "patient_record_rows_unsent=$(val patient_record_rows_unsent "$o")"
  [ "$(val clinic_start "$o")" = "2026-03-05 09:00:00" ] && ok_ "start dated from the first person above its base" \
    || bad "clinic_start=$(val clinic_start "$o")"
  [ "$(val odoo_business_rows_since_start "$o")" = 1 ] && ok_ "1 Odoo invoice since the start" || bad "odoo=$(val odoo_business_rows_since_start "$o")"
  [ "$(val patient_files_since_start "$o")" = 1 ] && ok_ "1 new patient file" || bad "files=$(val patient_files_since_start "$o")"
  grep -qE '^allergy_reaction.*undated' "$o/clinic-rows.tsv" && ok_ "undated residue row listed, not counted" || bad "allergy_reaction not marked undated"
  grep -q 'testroot\|testodoo' -r "$o" && bad "a password reached the report" || ok_ "no password in the report"
  [ -n "${SHOW:-}" ] && cat "$o/report.txt"
  rm -f "${OLD}/data/bahmni-document-images/b.jpg"

  printf '\n== scenario A (%s) ==\n' "$sh"
  reset_db; clinic_registers
  o="${T}/a-$(basename "$sh")"; rc="$(run_inspect "$sh" "$o")"
  [ "$rc" = 0 ] && ok_ "exit 0" || { bad "exit ${rc}"; tail -20 "$o.log"; }
  [ "$(val verdict "$o")" = A ] && ok_ "verdict A" || { bad "verdict $(val verdict "$o")"; grep -E 'GAP|NOTE' "$o/report.txt"; }
  [ "$(val patient_record_rows_unsent "$o")" = 0 ] && ok_ "0 patient-record rows" || bad "patient_record_rows_unsent=$(val patient_record_rows_unsent "$o")"
done

printf '\n== MySQL stopped ==\n'
docker stop "$MY" >/dev/null
o="${T}/unknown"; rc="$(run_inspect bash "$o")"
[ "$rc" = 2 ] && ok_ "exit 2" || bad "exit ${rc}"
[ "$(val verdict "$o")" = UNKNOWN ] && ok_ "verdict UNKNOWN" || bad "verdict $(val verdict "$o")"

printf '\n%s failure(s)\n' "$fails"
[ "$fails" -eq 0 ]
