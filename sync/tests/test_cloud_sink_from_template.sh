#!/usr/bin/env bash
# The hub's Odoo and OpenELIS up-sinks for a clinic the installer made are made
# from the Ghated files by cloud/connectors/register-odoo.sh:
#   - with no file for the clinic, both are made, mode 600, named for the
#     clinic, reading <slug>.bahmni-<slug>.<subsystem>.all under the clinic's
#     own replication origin, and both are registered;
#   - a file that exists is used as it is;
#   - a clinic that clinics.<HUB_NAME>.conf lists under other topic names is
#     refused, naming the file to write by hand, and nothing is made or registered.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
C="$T/repo"; mkdir -p "$C/cloud/connectors" "$T/bin"
cp "$R/cloud/connectors/register-odoo.sh" "$R/cloud/connectors/_render_connector.py" \
   "$R/cloud/connectors/odoo-ghated-sink-all.json" "$R/cloud/connectors/clinlims-ghated-sink-all.json" "$C/cloud/connectors/"
cat > "$T/bin/curl" <<'SH'
#!/bin/sh
cat >> "$FAKE_LOG"; echo >> "$FAKE_LOG"; printf '\n200'
SH
chmod +x "$T/bin/curl"
printf 'HUB_NAME=test\nODOO_SINK_PASSWORD=x\nCLINLIMS_SINK_PASSWORD=x\nBASE_PG_CONTAINER=pg\nBASE_ELIS_CONTAINER=elis\n' > "$C/cloud/.env"
printf 'other:mysql-sink-:source:bahmni-local\n' > "$C/cloud/clinics.test.conf"
reg2(){ rm -f "$T/log"; out="$(PATH="$T/bin:$PATH" FAKE_LOG="$T/log" NODE="$1" bash "$C/cloud/connectors/register-odoo.sh" "odoo-$1-sink-all" "clinlims-$1-sink-all" 2>&1)"; rc=$?; }
field(){ python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c=c.get("config",c); print(c.get(sys.argv[2],""))' "$1" "$2"; }

reg2 newclinic
for k in odoo clinlims; do
  f="$C/cloud/connectors/$k-newclinic-sink-all.json"
  [ -f "$f" ] || { bad "$k: no file made (rc=$rc) $out"; continue; }
  [ "$(field "$f" topics)" = "newclinic.bahmni-newclinic.$k.all" ] && ok_ "$k: reads newclinic.bahmni-newclinic.$k.all" || bad "$k: topics $(field "$f" topics)"
  [ "$(field "$f" hibernate.agroal.initialSQL)" = "SELECT pg_replication_origin_session_setup('clinic_newclinic_$k')" ] && ok_ "$k: holds origin clinic_newclinic_$k" || bad "$k: initialSQL $(field "$f" hibernate.agroal.initialSQL)"
  python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["name"] != sys.argv[2])' "$f" "$k-newclinic-sink-all" && ok_ "$k: named $k-newclinic-sink-all" || bad "$k: wrong name"
  grep -q ghated "$f" && bad "$k: still names ghated" || ok_ "$k: names no other clinic"
  [ "$(ls -l "$f" | cut -c1-10)" = "-rw-------" ] && ok_ "$k: mode 600" || bad "$k: mode $(ls -l "$f" | cut -c1-10)"
done
[ "$rc" = 0 ] && [ "$(grep -c . "$T/log" 2>/dev/null)" = 2 ] && ok_ "both registered" || bad "registered: rc=$rc $(grep -c . "$T/log" 2>/dev/null) $out"

before="$(cat "$C/cloud/connectors/odoo-ghated-sink-all.json")"
reg2 ghated
[ "$rc" = 0 ] && [ "$(cat "$C/cloud/connectors/odoo-ghated-sink-all.json")" = "$before" ] && ok_ "an existing file is used as it is" || bad "ghated: rc=$rc $out"

reg2 other
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q 'write connectors/odoo-other-sink-all.json by hand' \
  && ok_ "a clinic listed under other topic names is refused, naming the file" || bad "other: rc=$rc $out"
[ ! -e "$C/cloud/connectors/odoo-other-sink-all.json" ] && [ ! -s "$T/log" ] && ok_ "nothing made or registered for it" || bad "other: a file was made or a sink registered"
exit $((fails > 0))
