#!/usr/bin/env bash
# The hub publishes only the rows written at the hub. A clinic's Odoo and
# OpenELIS rows stop there: the hub up-sinks that write them claim that
# clinic's replication origin, and the hub's two Postgres sources decode with
# origin=none, so a row a sink applied is never published to the other clinics
# or back to its sender. This checks both halves in the tracked templates, and
# that the per-clinic render a join makes (the ghated template with the slug
# swapped) gives every clinic an origin of its own: PostgreSQL lets one session
# at a time hold an origin, so two clinics sharing one would stop a sink.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
C="$R/hub/connectors"
cfg(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("config") or d).get(sys.argv[2], ""))' "$1" "$2"; }

# --- the source: decode only what was written at the hub --------------------
for n in odoo-cloud-source clinlims-cloud-source; do
  v="$(cfg "$C/$n.json" slot.stream.params)"
  [ "$v" = origin=none ] && ok_ "$n decodes with slot.stream.params=origin=none" || bad "$n: slot.stream.params is '${v}', want origin=none"
done
# --- the clinic's down sinks: each claims an origin of its own -----------------
# A row a clinic's down sink writes is tagged with the origin the sink claims,
# so the clinic's own Postgres sources (origin=none) never send it back up. An
# origin is held by one session at a time, so the two down sinks claim two.
CC="$R/clinic/connectors"
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
reg="$(grep -E '^[^#]*register-odoo\.sh' "$R/clinic/install/tasks/090-local-sync.sh")"
printf '%s' "$reg" | grep -q 'odoo-clinic-sink-all' && printf '%s' "$reg" | grep -q 'CLINLIMS_DOWN_CONDITION=.*clinlims-clinic-sink-all' \
  && ok_ "the clinic installer registers its Odoo down sink, and its OpenELIS down sink with its filter" || bad "090 registers: $reg"

# --- the up-sinks: each claims its own clinic's origin, on one connection ----
# check_sinks DIR CLINICS_CONF : every Postgres JDBC sink in DIR claims
# clinic_<slug>_<odoo|clinlims>, where <slug> is the clinics.conf row whose
# "<mm_prefix>.<server_name>." starts the sink's topic and the suffix follows
# the database the sink writes; one task, a pool of one; no origin shared.
check_sinks(){
  python3 - "$1" "$2" <<'PY'
import glob, json, os, re, sys
d, conf = sys.argv[1], sys.argv[2]
rows = []
for line in open(conf):
    line = line.split('#', 1)[0].strip()
    if not line:
        continue
    f = line.split(':')
    if len(f) >= 4:
        rows.append((f[0], f[2] + '.' + f[3] + '.'))
seen, bad, n = {}, 0, 0
for p in sorted(glob.glob(os.path.join(d, '*-sink-all.json'))):
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
        msgs.append('topic %r belongs to %d clinics.conf rows, want 1' % (topic, len(slug)))
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
    print('  FAIL only %d Postgres up-sink templates found in %s' % (n, d)); bad += 1
sys.exit(1 if bad else 0)
PY
}
CL="$(mktemp)"; cat "$R"/hub/clinics.*.conf > "$CL"   # every hub's clinics
check_sinks "$C" "$CL" || fails=$((fails+1))

# --- a join renders the ghated template for its own slug ---------------------
T="$(mktemp -d)"; trap 'rm -rf "$T" "$CL"' EXIT
for slug in manpur bedawal; do
  for k in odoo clinlims; do sed "s/ghated/$slug/g" "$C/$k-ghated-sink-all.json" > "$T/$k-$slug-sink-all.json"; done
done
{ cat "$CL"; printf 'bedawal:mysql-sink-bedawal-:bedawal:bahmni-bedawal\n'; } > "$T/clinics.conf"
out="$(check_sinks "$T" "$T/clinics.conf")"; rc=$?
printf '%s\n' "$out" | sed 's/^  /  render: /'
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "clinic_manpur_odoo" && printf '%s\n' "$out" | grep -q "clinic_bedawal_clinlims" \
  && ok_ "two clinics rendered from the template claim four distinct origins" || bad "the per-clinic render does not give each clinic its own origins"

# --- the negative: a sink without the claim, or sharing one, is caught --------
mkdir -p "$T/neg"; cp "$C/odoo-ghated-sink-all.json" "$T/neg/"
python3 - "$T/neg/odoo-ghated-sink-all.json" "$T/neg/odoo-manpur-sink-all.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d['config'].pop('hibernate.agroal.initialSQL', None)
json.dump(d, open(sys.argv[1], 'w'))
d['config']['topics'] = 'manpur.bahmni-manpur.odoo.all'
d['config']['hibernate.agroal.initialSQL'] = "SELECT pg_replication_origin_session_setup('clinic_ghated_odoo')"
json.dump(d, open(sys.argv[2], 'w'))
PY
out="$(check_sinks "$T/neg" "$CL")"; rc=$?
[ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q 'odoo-ghated-sink-all.json: hibernate.agroal.initialSQL is' \
  && printf '%s\n' "$out" | grep -q "odoo-manpur-sink-all.json: hibernate.agroal.initialSQL is \"SELECT pg_replication_origin_session_setup('clinic_ghated_odoo')\"" \
  && ok_ "a sink with no claim, and a sink claiming another clinic's origin, both fail" || bad "the check passes a sink without its own claim: rc=$rc $out"

# --- the README states the rule now in force -----------------------------------
grep -q 'relays everything' "$R/hub/README.md" && bad "hub/README.md still says the hub relays everything" || ok_ "hub/README.md no longer says the hub relays everything"
grep -q 'origin=none' "$R/hub/README.md" && grep -q 'clinic_<slug>_odoo' "$R/hub/README.md" \
  && ok_ "hub/README.md names origin=none and the per-clinic origins" || bad "hub/README.md does not describe the origin guard"
exit "$fails"
