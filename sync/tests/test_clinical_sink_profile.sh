#!/usr/bin/env bash
# The hub's up sinks for obs, orders and drug_order, one per clinic in
# hub/clinics.conf, upsert on the table's strided key, stop on an error, apply
# deletes and never change the hub's schema. The validator the generator runs
# refuses a config that breaks any of that. The other sinks keep their settings.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/hub" "$C/sync/local"
cp -R "$R/hub/scripts" "$R/hub/connectors" "$C/hub/"; cp "$R/hub/tables.conf" "$C/hub/"
# every clinic of hub/clinics.conf, each marked as sending the clinical tables
grep -vE '^[[:space:]]*(#|$)' "$R/hub/clinics.conf" | sed -E 's/^([^:]+:[^:]+:[^:]+:[^:]+).*/\1:clinical/' > "$C/hub/clinics.conf"
cp "$R/sync/local/tables-conf.sh" "$C/sync/local/"
printf 'REMOTE_MYSQL_HOST=h\nREMOTE_MYSQL_PORT=3306\nREMOTE_MYSQL_DATABASE=openmrs\nREMOTE_MYSQL_USER=u\nREMOTE_MYSQL_PASSWORD=p\n' > "$C/hub/.env"
{ grep -vE '^[[:space:]]*(#|$)' "$R/sync/local/tables.conf" | grep -vE '^(obs|orders|drug_order):'
  printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n'; } > "$C/sync/local/tables.conf"

out="$(bash "$C/hub/scripts/generate-sink-connectors.sh" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "the generator renders and validates every sink" || bad "generator rc=$rc: $(printf '%s' "$out" | tail -5)"

check(){ # FILE TABLE KEY -> one line per wrong setting
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
f, table, key = sys.argv[1:4]
c = json.load(open(f))["config"]
want = {"errors.tolerance": "none", "insert.mode": "upsert", "primary.key.mode": "record_key",
        "primary.key.fields": key, "delete.enabled": "true", "schema.evolution": "none",
        "table.name.format.default": "openmrs." + table}
for k, v in want.items():
    if c.get(k) != v:
        print(f"{k}={c.get(k)!r} want {v!r}")
for k in ("auto.create", "auto.evolve"):
    if k in c:
        print(f"{k} present")
PY
}
nclin=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac
  IFS=: read -r clinic prefix _mm _server <<EOF
$line
EOF
  nclin=$((nclin+1))
  for tk in obs:obs_id orders:order_id drug_order:order_id; do
    t="${tk%%:*}"; k="${tk#*:}"; f="$C/hub/connectors/${prefix}${t}.json"
    if [ ! -f "$f" ]; then bad "${clinic}: no sink ${prefix}${t}"; continue; fi
    d="$(check "$f" "$t" "$k")"
    [ -z "$d" ] && ok_ "${clinic}: ${prefix}${t} upserts on ${k}, errors none, deletes on, schema evolution none" || bad "${clinic} ${t}: $(printf '%s' "$d" | tr '\n' ';')"
  done
  f="$C/hub/connectors/${prefix}encounter.json"
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; sys.exit(not (c.get("auto.create")=="true" and c.get("auto.evolve")=="true" and "schema.evolution" not in c))' "$f" 2>/dev/null \
    && ok_ "${clinic}: the encounter sink keeps auto.create/auto.evolve and no schema.evolution" || bad "${clinic}: the encounter sink changed"
done < "$C/hub/clinics.conf"
[ "$nclin" -ge 1 ] && ok_ "${nclin} clinic(s) in hub/clinics.conf checked" || bad "no clinic in hub/clinics.conf"

# the validator refuses each way a clinical sink can be wrong
V="$C/hub/scripts/validate-sink-config.py"; K="$C/hub/connectors/known-good.json"
first="$(sed -n 's/^\([^#:][^:]*\):\([^:]*\):.*/\2/p' "$R/hub/clinics.conf" | head -1)"
src="$C/hub/connectors/${first}obs.json"
python3 "$V" "$src" --known-good "$K" --profile clinical >/dev/null 2>&1 && ok_ "validator: the rendered obs sink passes" || bad "validator rejects the rendered obs sink"
mutate(){ # KEY VALUE|-  -> a copy of the obs sink with KEY set (or removed with -)
  python3 - "$src" "$TMP/m.json" "$1" "$2" <<'PY'
import json, sys
src, dst, k, v = sys.argv[1:5]
d = json.load(open(src))
if v == "-": d["config"].pop(k, None)
else: d["config"][k] = v
json.dump(d, open(dst, "w"))
PY
}
for kv in errors.tolerance=all primary.key.mode=record_value primary.key.fields=uuid delete.enabled=false schema.evolution=basic schema.evolution=- auto.evolve=true errors.tolerance=-; do
  mutate "${kv%%=*}" "${kv#*=}"
  msg="$(python3 "$V" "$TMP/m.json" --known-good "$K" --profile clinical 2>&1)"
  [ $? -ne 0 ] && ok_ "validator refuses a clinical sink with ${kv}" || bad "validator accepts a clinical sink with ${kv}"
done
python3 "$V" "$src" --known-good "$K" >/dev/null 2>&1 && bad "validator accepts the obs sink under the default profile" || ok_ "validator refuses obs under the default profile"
python3 "$V" "$C/hub/connectors/${first}encounter.json" --known-good "$K" --profile clinical >/dev/null 2>&1 && bad "validator accepts the clinical profile for encounter" || ok_ "validator refuses the clinical profile for a non-clinical table"
exit $((fails > 0))
