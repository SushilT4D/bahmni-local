#!/usr/bin/env bash
sinks_to(){ # OUT [VAR=value...] : run generate/mysql-sinks.sh in this clinic copy, then move its connectors/ to OUT
  local o="$1" rc; shift; rm -rf connectors "$o"
  env "$@" bash scripts/generate/mysql-sinks.sh; rc=$?
  if [ -d connectors ]; then mv connectors "$o"; fi
  return "$rc"
}
# The [down] section of sync/tables/openmrs.conf is the one list of what OpenMRS
# sends hub -> clinic. Each reader is
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
for f in sync/tables/openmrs.conf sync/tables/odoo.conf sync/tables/openelis.conf sync/tables/tables.sh \
         clinic/scripts/generate-table-config.sh clinic/scripts/generate-connectors.sh clinic/scripts/generate/mysql-sinks.sh \
         clinic/scripts/_fill_template.py clinic/scripts/setup-mirrormaker.sh \
         clinic/config/mirrormaker/mm2.properties.template \
         clinic/scripts/templates/mysql-local-sink-connector.json \
         cloud/scripts/generate-cloud-source-connector.sh cloud/scripts/templates/mysql-cloud-source-connector.json.template; do
  mkdir -p "$C/$(dirname "$f")"; cp "$RP/$f" "$C/$f" || bad "fixture: copy $f"
done

# --- the file ----------------------------------------------------------------
DOWN="$(bash "$RP/sync/tables/tables.sh" openmrs down)"
lines="$DOWN"
printf '%s\n' "$lines" | grep -qx 'form:form_id' && ok_ "the OpenMRS [down] list has form:form_id" || bad "the OpenMRS [down] list has no form:form_id line"
printf '%s\n' "$lines" | grep -qx 'form_resource:form_resource_id' && ok_ "the OpenMRS [down] list has form_resource:form_resource_id (no role: the hub authors it)" || bad "the OpenMRS [down] list has no form_resource:form_resource_id line"
nf="$(printf '%s\n' "$lines" | grep -n '^form:' | cut -d: -f1)"; nr="$(printf '%s\n' "$lines" | grep -n '^form_resource:' | cut -d: -f1)"
[ -n "$nf" ] && [ -n "$nr" ] && [ "$nf" -lt "$nr" ] && ok_ "form is listed before form_resource" || bad "form (line ${nf:-none}) is not before form_resource (line ${nr:-none})"
bash "$RP/sync/tables/tables.sh" openmrs up | grep -qE '^form(_resource)?:' && bad "a form table is also in the clinic's capture list" || ok_ "neither form table is in the clinic's own capture list"

# --- the hub's capture ---------------------------------------------------------
inc="$(bash "$C/clinic/scripts/generate-table-config.sh" cloud | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
case ",${inc}," in *,openmrs.form,*openmrs.form_resource,*) ok_ "the hub's include list carries openmrs.form, then openmrs.form_resource" ;; *) bad "include list: ${inc}" ;; esac
case ",${inc}," in *,openmrs.person,*) ok_ "the hub's include list carries person (its own rows, filtered at the source)" ;; *) bad "the hub's include list lacks person: ${inc}" ;; esac
out="$(REPO_DIR="$C" HUB_DIR="$C/cloud" DEBEZIUM_DB_PASSWORD=x OPENMRS_DB_HOST=openmrsdb OPENMRS_DB_NAME=openmrs bash "$C/cloud/scripts/generate-cloud-source-connector.sh" "$TMP/src.json" 2>&1)"; rc=$?
got="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$TMP/src.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$got" = "$inc" ] && ok_ "the hub's source connector renders with both tables in table.include.list" || bad "hub source render: rc=$rc got=${got} out=${out}"

# --- the clinic's down sinks -------------------------------------------------------
# RESIDUE: a clinic's .env always carries it (task 020); FLOOR_ORDERS: the seed
# records it (.install-state); the lab-result sinks need both
out="$(cd "$C/clinic" && sinks_to "$TMP/sinks" RESIDUE=3 FLOOR_ORDERS=441560 2>&1)"; rc=$?
F="$TMP/sinks/mysql-local-sink-all.json"
[ "$rc" -eq 0 ] && [ -f "$F" ] && [ "$(ls "$TMP/sinks" | grep -c '^mysql-local-sink-')" = 1 ] \
  && ok_ "the clinic gets one down sink for every [down] table" || bad "down sinks: rc=$rc out=$out; $(ls "$TMP/sinks" 2>/dev/null | tr '\n' ' ')"

# The one down sink: reads the hub's ordered topic, writes each record to its own table with an
# idempotent upsert on the hub's key, a failure stops the task, the clinic's schema is never
# created or altered, and its writes stay out of the clinic's binlog so they are not sent back up.
# Deletes are dropped for the tables marked `changes`: the hub retires those rows.
CHANGES="$(printf '%s\n' "$DOWN" | grep -E ':changes$' | cut -d: -f1 | tr '\n' ' ')"
d="$(python3 - "$F" "$CHANGES" <<'PY' 2>&1
import json, sys
c = json.load(open(sys.argv[1]))["config"]
want = {"topics": "remote.bahmni-cloud.openmrs.all", "collection.name.format": "${source.table}",
        "insert.mode": "upsert", "primary.key.mode": "record_key", "errors.tolerance": "none",
        "auto.create": "false", "auto.evolve": "false", "schema.evolution": "none", "delete.enabled": "true",
        "tasks.max": "1", "batch.size": "1", "connection.pool.max_size": "1"}
bad = ["%s=%s (want %s)" % (k, c.get(k), v) for k, v in sorted(want.items()) if c.get(k) != v]
if "sessionVariables=sql_log_bin=0" not in c.get("connection.url", ""):
    bad.append("connection.url lacks sessionVariables=sql_log_bin=0")
cond = c.get("transforms.rowsThisClinicKeeps.condition", "")
for t in sys.argv[2].split():
    if f"t == '{t}' ? (" not in cond or "value.get('op') != 'd'" not in cond:
        bad.append(f"{t} is marked changes but its deletes are not dropped")
for t in ("form", "form_resource"):
    if f"t == '{t}'" in cond:
        bad.append(f"{t} has a filter; it is published whole")
print("; ".join(bad) if bad else "SAME")
PY
)"
[ "$d" = SAME ] && ok_ "the down sink: ordered topic, routed by table, upsert on record_key, deletes dropped for the changes-only tables, schema never changed, sql_log_bin=0" \
  || bad "down sink: ${d}"

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
