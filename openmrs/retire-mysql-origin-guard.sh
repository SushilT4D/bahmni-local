#!/bin/bash
# sync-core, 2026-09-09: MySQL engine loop guard on a CLINIC node — replaces the Groovy
# publish filter, the sinks' accept filter and the person/person_name stamping triggers
# installed by apply-mysql-origin-filter.sh / apply-sync-origin.sh (sync-core F-047).
#
# Mechanism (Sushil's proposal, 7 Sep; Module 30 T3 proved it 27 Aug): every clinic
# JDBC sink connects with sessionVariables=sql_log_bin=0, so the rows it applies never
# enter the clinic binlog and Debezium, which reads that binlog, never re-publishes
# them. Needs SYSTEM_VARIABLES_ADMIN for the sink user (server-wide; MySQL cannot scope
# it) on MySQL 8.0 — the clinics run 8.0, so this does not wait on production's 5.6.
# Consequence (BL-066): the clinic binlog no longer describes replicated rows, so backups
# of a clinic must be logical dumps, not binlog PITR. NEVER run this on the hub: the cloud
# must republish what its sinks write in order to relay clinic to clinic.
# Idempotent. Run on the clinic host with the Connect REST API on localhost:8083 and the
# MySQL container name as $1 (docker) — pass RT=podman for a podman node.
set -eu; MY=${1:?mysql container name}; RT=${RT:-docker}
my() { $RT exec "$MY" sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -N -e \"$1\" 2>/dev/null"; }
echo "1. grant"; my "GRANT SYSTEM_VARIABLES_ADMIN ON *.* TO 'sink'@'%'; FLUSH PRIVILEGES"
echo "2. sink URLs"; for c in $(curl -s localhost:8083/connectors | python3 -c "import sys,json; print(' '.join(k for k in json.load(sys.stdin) if k.startswith('mysql-local-sink-')))"); do
  curl -s localhost:8083/connectors/$c/config | python3 -c "
import sys,json; c=json.load(sys.stdin); u=c['connection.url']
if 'sql_log_bin' not in u: c['connection.url']=u+'&sessionVariables=sql_log_bin=0'
if c.get('transforms','').startswith('filterOrigin'): c['transforms']='dropPrefix'; c={k:v for k,v in c.items() if not k.startswith('transforms.filterOrigin')}
json.dump(c, open('/tmp/$c.json','w'))"; curl -s -o /dev/null -w "$c=%{http_code} " -X PUT -H 'Content-Type: application/json' --data @/tmp/$c.json localhost:8083/connectors/$c/config; done; echo
echo "3. source: drop the publish filter"; curl -s localhost:8083/connectors/mysql-source-connector/config | python3 -c "
import sys,json; c=json.load(sys.stdin); c.pop('transforms',None); c={k:v for k,v in c.items() if not k.startswith('transforms.')}; json.dump(c, open('/tmp/mysql-source-connector.json','w'))"; curl -s -o /dev/null -w "source=%{http_code}\n" -X PUT -H 'Content-Type: application/json' --data @/tmp/mysql-source-connector.json localhost:8083/connectors/mysql-source-connector/config
echo "4. triggers"; my "DROP TRIGGER IF EXISTS openmrs.person_origin_ins; DROP TRIGGER IF EXISTS openmrs.person_origin_upd; DROP TRIGGER IF EXISTS openmrs.person_name_origin_ins; DROP TRIGGER IF EXISTS openmrs.person_name_origin_upd; SELECT CONCAT('openmrs triggers left: ', COUNT(*)) FROM information_schema.triggers WHERE trigger_schema='openmrs'"
