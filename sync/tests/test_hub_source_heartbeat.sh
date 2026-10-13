#!/usr/bin/env bash
# Every hub source heartbeats, so each one's liveness can be read on its own: the
# MySQL source's committed offset moves every minute even when no captured table
# changes, and each Postgres source upserts its dbz_heartbeat row every minute and
# confirms it through its own slot. The MySQL source is rendered by the real
# generator here, against a throwaway hub dir, so a key the template carries but
# the render drops is caught too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/hub/connectors"
cp "$R/hub/connectors/mysql-cloud-source-connector.json.template" "$T/hub/connectors/"
printf 'DEBEZIUM_DB_PASSWORD=test-only\n' > "$T/hub/.env"
if HUB_DIR="$T/hub" REPO_DIR="$R" bash "$R/hub/scripts/generate-cloud-source-connector.sh" "$T/out.json" >"$T/gen.log" 2>&1; then
  v="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("config") or d).get("heartbeat.interval.ms",""))' "$T/out.json")"
  [ "$v" = 60000 ] && ok_ "the rendered MySQL source heartbeats every 60000 ms" || bad "the rendered MySQL source has heartbeat.interval.ms '${v}', want 60000"
else
  bad "the MySQL source did not render: $(tail -3 "$T/gen.log")"
fi
for s in odoo-cloud-source:public clinlims-cloud-source:clinlims; do
  n="${s%%:*}"; sch="${s#*:}"
  r="$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print("%s|%s|%s" % (c.get("heartbeat.interval.ms",""), sys.argv[2] + ".dbz_heartbeat" in c.get("heartbeat.action.query",""), sys.argv[2] + ".dbz_heartbeat" in c.get("table.include.list","").split(",")))' "$R/hub/connectors/$n.json" "$sch")"
  [ "$r" = "60000|True|True" ] && ok_ "$n heartbeats every 60000 ms into ${sch}.dbz_heartbeat and captures it" || bad "$n heartbeat interval|action query|capture read '$r', want 60000|True|True"
done
exit "$fails"
