#!/usr/bin/env bash
# hub/tables.conf is the one list of what travels hub -> clinic. Each reader is
# run on a copy of the repo files it needs (no node's .env is read): the hub's
# capture list, the clinic's down sinks and MirrorMaker's down topics all carry
# the observation form tables, and the sinks for them are configured exactly
# like the down sinks already running.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"
for f in hub/tables.conf sync/local/tables.conf sync/subsystems.conf \
         clinic/scripts/generate-table-config.sh clinic/scripts/generate-local-sink-connectors.sh clinic/scripts/setup-mirrormaker.sh \
         clinic/config/mirrormaker/mm2.properties.template \
         sync/local/connectors/mysql-local-sink-connector.json.template \
         hub/scripts/generate-cloud-source-connector.sh hub/connectors/mysql-cloud-source-connector.json.template; do
  mkdir -p "$C/$(dirname "$f")"; cp "$RP/$f" "$C/$f" || bad "fixture: copy $f"
done

# --- the file ----------------------------------------------------------------
lines="$(grep -vE '^[[:space:]]*(#|$)' "$RP/hub/tables.conf")"
printf '%s\n' "$lines" | grep -qx 'form:form_id' && ok_ "hub/tables.conf lists form:form_id" || bad "hub/tables.conf has no form:form_id line"
printf '%s\n' "$lines" | grep -qx 'form_resource:form_resource_id' && ok_ "hub/tables.conf lists form_resource:form_resource_id (no role: the hub authors it)" || bad "hub/tables.conf has no form_resource:form_resource_id line"
nf="$(printf '%s\n' "$lines" | grep -n '^form:' | cut -d: -f1)"; nr="$(printf '%s\n' "$lines" | grep -n '^form_resource:' | cut -d: -f1)"
[ -n "$nf" ] && [ -n "$nr" ] && [ "$nf" -lt "$nr" ] && ok_ "form is listed before form_resource" || bad "form (line ${nf:-none}) is not before form_resource (line ${nr:-none})"
grep -qE '^[[:space:]]*form(_resource)?:' "$RP/sync/local/tables.conf" && bad "a form table is also in the clinic's capture list" || ok_ "neither form table is in the clinic's own capture list"

# --- the hub's capture ---------------------------------------------------------
inc="$(bash "$C/clinic/scripts/generate-table-config.sh" cloud | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
case ",${inc}," in *,openmrs.form,*openmrs.form_resource,*) ok_ "the hub's include list carries openmrs.form, then openmrs.form_resource" ;; *) bad "include list: ${inc}" ;; esac
case ",${inc}," in *,openmrs.person,*) bad "the hub's include list carries a relayed table: ${inc}" ;; *) ok_ "relayed tables stay out of the hub's include list" ;; esac
out="$(REPO_DIR="$C" HUB_DIR="$C/hub" DEBEZIUM_DB_PASSWORD=x bash "$C/hub/scripts/generate-cloud-source-connector.sh" "$TMP/src.json" 2>&1)"; rc=$?
got="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$TMP/src.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$got" = "$inc" ] && ok_ "the hub's source connector renders with both tables in table.include.list" || bad "hub source render: rc=$rc got=${got} out=${out}"

# --- the clinic's down sinks -------------------------------------------------------
out="$(LOCAL_MYSQL_PASSWORD=x bash "$C/clinic/scripts/generate-local-sink-connectors.sh" "$TMP/sinks" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$TMP/sinks/mysql-local-sink-form.json" ] && [ -f "$TMP/sinks/mysql-local-sink-form_resource.json" ] \
  && ok_ "the clinic gets one down sink per form table" || bad "down sinks: rc=$rc out=$out; $(ls "$TMP/sinks" 2>/dev/null | tr '\n' ' ')"
for t in form form_resource; do
  d="$(python3 - "$TMP/sinks/mysql-local-sink-users.json" "$TMP/sinks/mysql-local-sink-${t}.json" "$t" <<'PY' 2>&1
import json, sys
a = json.load(open(sys.argv[1]))["config"]; b = json.load(open(sys.argv[2]))["config"]; t = sys.argv[3]
want = {k: (v.replace("openmrs.users", "openmrs." + t) if k == "topics" else (t if k == "table.name.format" else v)) for k, v in a.items()}
diff = sorted(k for k in set(want) | set(b) if want.get(k) != b.get(k))
for k in ("insert.mode", "primary.key.mode", "delete.enabled", "errors.tolerance"):
    print(f"{k}={b.get(k)}")
print("DIFF " + " ".join(diff) if diff else "SAME")
PY
)"
  printf '%s\n' "$d" | grep -qx SAME && ok_ "${t}: configured exactly like the users down sink, apart from its topic and table" || bad "${t}: differs from the users sink: $(printf '%s' "$d" | tr '\n' ' ')"
  printf '%s\n' "$d" | grep -qx 'insert.mode=upsert' && printf '%s\n' "$d" | grep -qx 'primary.key.mode=record_key' && printf '%s\n' "$d" | grep -qx 'errors.tolerance=none' \
    && ok_ "${t}: upsert on the record key, errors stop the task" || bad "${t}: $(printf '%s' "$d" | tr '\n' ' ')"
done
grep -q '"topics": "remote.bahmni-cloud.openmrs.form"' "$TMP/sinks/mysql-local-sink-form.json" && ok_ "the form sink reads the mirrored hub topic" || bad "form sink topic: $(grep '"topics"' "$TMP/sinks/mysql-local-sink-form.json")"

# --- MirrorMaker's down topics -------------------------------------------------------
if command -v envsubst >/dev/null 2>&1; then
  printf 'BHS_LOCATION=t\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\n' > "$C/clinic/.env"
  out="$(bash "$C/clinic/scripts/setup-mirrormaker.sh" 2>&1)"; rc=$?
  down="$(grep -E '^remote->[A-Za-z0-9_]+\.topics' "$C/clinic/config/mirrormaker/mm2.properties" 2>/dev/null)"
  [ "$rc" -eq 0 ] && printf '%s' "$down" | grep -qF 'bahmni-cloud\.openmrs\.form|' && printf '%s' "$down" | grep -qF 'bahmni-cloud\.openmrs\.form_resource' \
    && ok_ "MirrorMaker mirrors both hub form topics down" || bad "MirrorMaker down topics: rc=$rc ${down:-none} ${out}"
else
  ok_ "envsubst not available here; MirrorMaker render skipped"
fi
exit "$fails"
