#!/usr/bin/env bash
# Node preflight for the three-node lab (F-007, F-017, F-022): reachability, disk, memory,
# MySQL wait_timeout floor, PG slot WAL retention, Kafka reachable, connector task states.
# Exit 1 if any floor is breached. Usage: scripts/preflight.sh [rawach|ghated|cloud ...]
set -u
NODES=${*:-"rawach ghated cloud"}
DISK_FLOOR_GB=${DISK_FLOOR_GB:-5}; MEM_FLOOR_MB=${MEM_FLOOR_MB:-1024}; WAIT_FLOOR=${WAIT_FLOOR:-28800}; SLOT_FLOOR_MB=${SLOT_FLOOR_MB:-2048}
MINI="samyoga@samyogas-mac-mini.tailca2651.ts.net"; MINI_KEY="/Users/nithun/Documents/dev/keys/mini"
GH_PRE='export DOCKER_HOST=$(grep -o "DOCKER_HOST=[^ ]*" ~/.zprofile | head -1 | cut -d= -f2- | tr -d "\"'"'"'"); export PATH=$PATH:/opt/homebrew/bin:/usr/local/bin; '
rc=0; bad(){ echo "  FAIL $*"; rc=1; }; ok(){ echo "  ok   $*"; }
run(){ case $1 in rawach) bash -c "$2";; ghated) ssh -o ConnectTimeout=15 ghated "$GH_PRE$2";; cloud) ssh -i "$MINI_KEY" -o ConnectTimeout=15 "$MINI" "export PATH=/opt/homebrew/bin:\$PATH; $2";; esac 2>/dev/null; }
for n in $NODES; do
  echo "== $n =="
  case $n in rawach) T=docker; MY=bahmni-local-bahmni-mysql-1; PG=bahmni-local-bahmni-postgres-1; PU=odoo; BS=localhost:9092;;
              ghated) T=podman; MY=bahmni-ghated-bahmni-mysql-1; PG=bahmni-ghated-bahmni-postgres-1; PU=odoo; BS=localhost:9092;;
              cloud)  T=docker; MY=cloud-openmrsdb-1; PG=cloud-openelisdb-1; PU=postgres; BS=kafka:29092;; esac
  if [ -z "$(run $n 'echo up')" ]; then bad "unreachable (mesh down or host asleep, F-017/F-054)"; continue; fi; ok "reachable"
  read -r disk mem <<< "$(run $n "$T run --rm --privileged --pid=host alpine:3.20 nsenter -t 1 -m -u -n -i sh -c 'echo \$(df -m /var/lib/docker 2>/dev/null | tail -1 | awk \"{print \\\$4}\") \$(free -m | awk \"NR==2{print \\\$7}\")' 2>/dev/null")"
  case $n in cloud) disk=$(run $n "$T run --rm -v /:/host alpine:3.20 df -m /host/mnt/lima-colima | tail -1 | awk '{print \$4}'");; esac
  [ -n "$disk" ] && { [ "$disk" -ge $((DISK_FLOOR_GB*1024)) ] && ok "vm disk free ${disk} MB" || bad "vm disk free ${disk} MB < ${DISK_FLOOR_GB} GB (F-022)"; }
  [ -n "$mem" ] && { [ "$mem" -ge "$MEM_FLOOR_MB" ] && ok "vm memory available ${mem} MB" || bad "vm memory available ${mem} MB < ${MEM_FLOOR_MB} MB (F-050)"; }
  wt=$(run $n "$T exec $MY sh -c 'mysql -N -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"select @@global.wait_timeout\" 2>/dev/null'"); [ -n "$wt" ] && { [ "$wt" -ge "$WAIT_FLOOR" ] && ok "mysql wait_timeout $wt" || bad "mysql wait_timeout $wt < $WAIT_FLOOR (F-007/BL-039)"; }
  slots=$(run $n "$T exec $PG psql -U $PU -d openelis -tAc \"select slot_name||' '||active||' '||(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)/1048576)::int from pg_replication_slots\"")
  while read -r s a mb; do [ -z "$s" ] && continue; case "$a" in t|true) :;; *) bad "slot $s inactive ($a)";; esac; [ "${mb:-0}" -le "$SLOT_FLOOR_MB" ] && ok "slot $s retains ${mb} MB" || bad "slot $s retains ${mb} MB > ${SLOT_FLOOR_MB} MB (F-043)"; done <<< "$slots"
  kt=$(run $n "$T exec kafka kafka-topics --bootstrap-server $BS --list 2>/dev/null | wc -l | tr -d ' '"); [ "${kt:-0}" -gt 0 ] && ok "kafka reachable ($kt topics)" || bad "kafka not answering on $BS"
  st=$(run $n "curl -s 'localhost:8083/connectors?expand=status'" | python3 -c "import json,sys
try: d=json.load(sys.stdin)
except Exception: print('connect-unreachable'); sys.exit()
bad=[k for k,v in d.items() if v['status']['connector']['state']!='RUNNING' or any(t['state']!='RUNNING' for t in v['status']['tasks'])]; print(f'{len(d)} connectors; not RUNNING: {bad}')")
  case "$st" in *"not RUNNING: []") ok "$st";; *) bad "$st";; esac
done
exit $rc
