#!/usr/bin/env bash
# The hub publishes only the rows written at the hub. A clinic's Odoo and
# OpenELIS rows stop there: the hub up-sinks that write them claim that
# clinic's replication origin, and the hub's two Postgres sources decode with
# origin=none, so a row a sink applied is never published to the other clinics
# or back to its sender. This checks the sources, and that the sinks
# generate-sink-connectors.sh writes give every clinic an origin of its own:
# PostgreSQL lets one session at a time hold an origin, so two clinics sharing
# one would stop a sink.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
C="$R/cloud/scripts/templates"
cfg(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("config") or d).get(sys.argv[2], ""))' "$1" "$2"; }

# --- the source: decode only what was written at the hub --------------------
for n in odoo-cloud-source clinlims-cloud-source; do
  v="$(cfg "$C/$n.json.template" slot.stream.params)"
  [ "$v" = origin=none ] && ok_ "$n decodes with slot.stream.params=origin=none" || bad "$n: slot.stream.params is '${v}', want origin=none"
done
# --- the clinic's down sinks: each claims an origin of its own -----------------
# A row a clinic's down sink writes is tagged with the origin the sink claims,
# so the clinic's own Postgres sources (origin=none) never send it back up. An
# origin is held by one session at a time, so the two down sinks claim two.
CC="$R/clinic/scripts/templates"
for n in odoo-source-connector clinlims-source-connector; do
  v="$(cfg "$CC/$n.json" slot.stream.params)"
  [ "$v" = origin=none ] && ok_ "the clinic's $n decodes with origin=none" || bad "the clinic's $n: slot.stream.params is '${v}', want origin=none"
done
o1="$(cfg "$CC/odoo-clinic-sink-all.json" hibernate.agroal.initialSQL)"; o2="$(cfg "$CC/clinlims-clinic-sink-all.json" hibernate.agroal.initialSQL)"
case "$o1|$o2" in
  "SELECT pg_replication_origin_session_setup('hub_"*"')|SELECT pg_replication_origin_session_setup('hub_"*"')") [ "$o1" != "$o2" ] && ok_ "the clinic's Odoo and OpenELIS down sinks claim two different hub origins" || bad "both clinic down sinks claim one origin: $o1" ;;
  *) bad "a clinic down sink claims no hub origin: Odoo '$o1', OpenELIS '$o2'" ;;
esac
for n in odoo-clinic-sink-all clinlims-clinic-sink-all; do
  [ "$(cfg "$CC/$n.json" tasks.max)|$(cfg "$CC/$n.json" connection.pool.max_size)" = "1|1" ] && ok_ "$n: one task on one connection (the origin is held by one session)" || bad "$n: tasks.max/pool read $(cfg "$CC/$n.json" tasks.max)|$(cfg "$CC/$n.json" connection.pool.max_size)"
done
reg="$(grep -E '^[^#]*register-connectors.sh' "$R/clinic/install/tasks/090-local-sync.sh")"
printf '%s' "$reg" | grep -q 'odoo-clinic-sink-all' && printf '%s' "$reg" | grep -q 'clinlims-clinic-sink-all' \
  && grep -q '^export CLINLIMS_DOWN_CONDITION' "$R/clinic/scripts/generate/postgres.sh" \
  && grep -q '${CLINLIMS_DOWN_CONDITION}' "$CC/clinlims-clinic-sink-all.json" \
  && ok_ "the clinic installer registers its Odoo down sink, and its OpenELIS down sink with its filter" || bad "090 registers: $reg"

# --- the up-sinks: each claims its own clinic's origin, on one connection ----
# check_sinks DIR SLUGS : every Postgres JDBC sink in DIR claims
# clinic_<slug>_<odoo|clinlims>, where <slug> is the clinic whose
# "<slug>.bahmni-<slug>." starts the sink's topic and the suffix follows
# the database the sink writes; one task, a pool of one; no origin shared.
check_sinks(){
  python3 - "$1" "$2" <<'PY'
import glob, json, os, re, sys
d, slugs = sys.argv[1], sys.argv[2].split()
rows = [(s, f"{s}.bahmni-{s}.") for s in slugs]
seen, bad, n = {}, 0, 0
for p in sorted(glob.glob(os.path.join(d, '*-sink.json'))):
    c = json.load(open(p)); c = c.get('config') or c
    url = c.get('connection.url', '')
    if not url.startswith('jdbc:postgresql:'):
        continue
    n += 1
    name = os.path.basename(p)
    db = url.rsplit('/', 1)[-1].split('?')[0]
    sfx = {'odoo': 'odoo', 'openelis': 'clinlims'}.get(db)
    topic = c.get('topics', '')
    slug = [s for s, pre in rows if topic.startswith(pre)]
    msgs = []
    if not sfx:
        msgs.append('writes database %r, not odoo or openelis' % db)
    if len(slug) != 1:
        msgs.append('topic %r belongs to %d clinics, want 1' % (topic, len(slug)))
    want = "SELECT pg_replication_origin_session_setup('clinic_%s_%s')" % (slug[0] if len(slug) == 1 else '?', sfx)
    got = c.get('hibernate.agroal.initialSQL', '')
    if got != want:
        msgs.append('hibernate.agroal.initialSQL is %r, want %r' % (got, want))
    for k in ('tasks.max', 'connection.pool.min_size', 'connection.pool.max_size'):
        if str(c.get(k, '')) != '1':
            msgs.append('%s is %r, want 1' % (k, c.get(k, '')))
    m = re.search(r"session_setup\('([^']*)'\)", got)
    if m:
        if m.group(1) in seen:
            msgs.append('origin %s is also claimed by %s' % (m.group(1), seen[m.group(1)]))
        seen[m.group(1)] = name
    if msgs:
        bad += 1
        print('  FAIL %s: %s' % (name, '; '.join(msgs)))
    else:
        print('  ok   %s claims %s, one task, a pool of one' % (name, m.group(1)))
if n < 2:
    print('  FAIL only %d Postgres up-sinks found in %s' % (n, d)); bad += 1
sys.exit(1 if bad else 0)
PY
}
# --- the generated sinks: two clinics, four distinct origins ---------------------
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf 'manpur:1\nbedawal:2\ncloud:10\n' > "$T/clinics.txt"
printf 'OPENMRS_DB_HOST=h\nOPENMRS_DB_NAME=openmrs\nDEBEZIUM_DB_PASSWORD=x\nODOO_DB_HOST=o\nODOO_DB_NAME=odoo\nODOO_SINK_PASSWORD=x\nOPENELIS_DB_HOST=e\nCLINLIMS_SINK_PASSWORD=x\n' > "$T/.env"
CLINICS_FILE="$T/clinics.txt" ENV_FILE="$T/.env" OUT_DIR="$T/gen" bash "$R/cloud/scripts/generate-sink-connectors.sh" > "$T/gen.log" 2>&1 \
  || bad "generate-sink-connectors.sh failed: $(tail -3 "$T/gen.log")"
out="$(check_sinks "$T/gen" "manpur bedawal")"; rc=$?
printf '%s\n' "$out" | sed 's/^  /  render: /'
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "clinic_manpur_odoo" && printf '%s\n' "$out" | grep -q "clinic_bedawal_clinlims" \
  && ok_ "two clinics generated from sync/clinics.txt claim four distinct origins" || bad "the generated sinks do not give each clinic its own origins"
[ ! -e "$T/gen/odoo-cloud-sink.json" ] && ok_ "the cloud's own row gets no sinks" || bad "a sink was generated for the cloud itself"

# --- the negative: a sink without the claim, or sharing one, is caught --------
mkdir -p "$T/neg"; cp "$T/gen/odoo-manpur-sink.json" "$T/neg/"
python3 - "$T/neg/odoo-manpur-sink.json" "$T/neg/odoo-bedawal-sink.json" <<'NEG'
import json, sys
d = json.load(open(sys.argv[1])); d['config'].pop('hibernate.agroal.initialSQL', None)
json.dump(d, open(sys.argv[1], 'w'))
d['config']['topics'] = 'bedawal.bahmni-bedawal.odoo.all'
d['config']['hibernate.agroal.initialSQL'] = "SELECT pg_replication_origin_session_setup('clinic_manpur_odoo')"
json.dump(d, open(sys.argv[2], 'w'))
NEG
out="$(check_sinks "$T/neg" "manpur bedawal")"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'odoo-manpur-sink.json: hibernate.agroal.initialSQL is' \
  && printf '%s\n' "$out" | grep -q "odoo-bedawal-sink.json: hibernate.agroal.initialSQL is \"SELECT pg_replication_origin_session_setup('clinic_manpur_odoo')\"" \
  && ok_ "a sink with no claim, and a sink claiming another clinic's origin, both fail" || bad "the check passes a sink without its own claim: rc=$rc $out"

# --- the README states the rule now in force -----------------------------------
grep -q 'relays everything' "$R/cloud/README.md" && bad "cloud/README.md still says the hub relays everything" || ok_ "cloud/README.md no longer says the hub relays everything"
grep -q 'origin=none' "$R/cloud/README.md" && grep -q 'clinic_<slug>_odoo' "$R/cloud/README.md" \
  && ok_ "cloud/README.md names origin=none and the per-clinic origins" || bad "cloud/README.md does not describe the origin guard"
exit "$fails"
