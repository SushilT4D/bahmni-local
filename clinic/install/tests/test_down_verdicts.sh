#!/usr/bin/env bash
# hub/table-verdicts.conf decides which tables may travel in which direction,
# and clinic/scripts/check-table-verdicts.sh holds both table lists to it. The
# repo's own lists pass; a copy with a clinic-written, seed-only, unratified or
# unknown table added to the down list fails and names it, and so does a copy
# that captures a hub-written table at the clinic.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
S="${RP}/clinic/scripts/check-table-verdicts.sh"; V="${RP}/hub/table-verdicts.conf"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -f "$S" ] && [ -f "$V" ] || { bad "missing $S or $V"; exit 1; }

copy(){ # fresh copy of the three files under $TMP/r
  rm -rf "$TMP/r"; mkdir -p "$TMP/r/hub" "$TMP/r/sync/local"
  cp "$RP/hub/tables.conf" "$RP/hub/table-verdicts.conf" "$TMP/r/hub/"; cp "$RP/sync/local/tables.conf" "$TMP/r/sync/local/"
}
check(){ bash "$S" "$TMP/r" 2>&1; }

# --- the repo as it stands ----------------------------------------------------------
out="$(bash "$S" "$RP" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "the repo's two table lists agree with the verdicts" || bad "repo lists: rc=$rc $out"

# --- the verdicts the lists depend on ------------------------------------------------
vof(){ awk -v t="$1" '{ sub(/#.*/, "") } $1 == t { $1 = ""; sub(/^ +/, ""); print; exit }' "$V"; }
[ "$(vof encounter_type)" = UP ] && ok_ "encounter_type is UP: written at clinics, never sent down" || bad "encounter_type verdict: '$(vof encounter_type)'"
for t in metadatamapping_metadata_term_mapping metadatamapping_metadata_source metadatamapping_metadata_set metadatamapping_metadata_set_member fhir_concept_source scheduler_task_config; do
  case "$(vof "$t")" in "pending "*) ;; *) bad "$t should be pending: '$(vof "$t")'" ;; esac
done
ok_ "the four metadata-mapping tables, fhir_concept_source and scheduler_task_config are pending"
for t in form form_resource users role privilege concept drug location order_frequency encounter_role patient_identifier_type location_encounter_type_map; do
  [ "$(vof "$t")" = DOWN ] || bad "$t should be DOWN: '$(vof "$t")'"
done
ok_ "the hub-written masters are DOWN"
for t in concept_datatype care_setting address_hierarchy_entry address_hierarchy_level fhir_observation_category_map; do
  [ "$(vof "$t")" = RESEED ] || bad "$t should be RESEED: '$(vof "$t")'"
done
ok_ "the changeset-written and address-hierarchy tables are RESEED"
for t in person person_name; do [ "$(vof "$t")" = relay ] || bad "$t should be relay"; done

# --- the down list refuses what the hub does not solely write -----------------------------
refuse_down(){ # ROW EXPECT-SUBSTRING DESCRIPTION
  copy; printf '%s\n' "$1" >> "$TMP/r/hub/tables.conf"
  out="$(check)"; rc=$?
  [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "$2" && ok_ "$3" || bad "$3: rc=$rc out=$out"
}
refuse_down 'encounter_type:encounter_type_id' 'lists encounter_type for a down sink, but its verdict is UP' "encounter_type in the down list fails, by name"
refuse_down 'address_hierarchy_entry:address_hierarchy_entry_id' 'lists address_hierarchy_entry for a down sink, but its verdict is RESEED' "an address-hierarchy table in the down list fails"
refuse_down 'global_property:property' 'its verdict is OUT' "a node-local table in the down list fails"
refuse_down 'fhir_concept_source:fhir_concept_source_id' 'lists fhir_concept_source for a down sink, but its verdict is pending' "a table whose verdict is not final fails"
refuse_down 'obs:obs_id' 'lists obs for a down sink, but its verdict is UP' "a clinical table in the down list fails"
refuse_down 'no_such_table:id' 'lists no_such_table, which has no verdict' "a table with no verdict fails"
refuse_down 'concept:concept_id:relay' 'marks concept relay, but its verdict is DOWN' "a DOWN table marked relay fails"
copy; sed 's/^person:person_id:relay$/person:person_id/' "$RP/hub/tables.conf" > "$TMP/r/hub/tables.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'lists person for a down sink, but its verdict is relay' && ok_ "a relayed table listed as hub-written fails" || bad "unmarked person: rc=$rc out=$out"

# --- the clinic's capture list refuses a hub-written table -------------------------------------
copy; printf 'concept:concept_id\n' >> "$TMP/r/sync/local/tables.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'captures concept at the clinic, but its verdict is DOWN' && ok_ "a DOWN table in the clinic's capture list fails" || bad "concept captured up: rc=$rc out=$out"
copy; printf 'form:form_id:900000\n' >> "$TMP/r/sync/local/tables.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'captures form at the clinic' && ok_ "a form table in the clinic's capture list fails" || bad "form captured up: rc=$rc out=$out"
copy; printf 'care_setting:care_setting_id\n' >> "$TMP/r/sync/local/tables.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'captures care_setting at the clinic, but its verdict is RESEED' && ok_ "a RESEED table in the clinic's capture list fails" || bad "care_setting captured up: rc=$rc out=$out"

# --- the verdict file itself ---------------------------------------------------------------------
copy; printf 'concept DOWN\n' >> "$TMP/r/hub/table-verdicts.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'concept: listed twice' && ok_ "a table given two verdicts is refused" || bad "duplicate verdict: rc=$rc out=$out"
copy; printf 'some_table MAYBE\n' >> "$TMP/r/hub/table-verdicts.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'unknown verdict "MAYBE"' && ok_ "an unknown verdict is refused" || bad "unknown verdict: rc=$rc out=$out"
copy; printf 'some_table pending\n' >> "$TMP/r/hub/table-verdicts.conf"
out="$(check)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF 'pending needs the proposed verdict' && ok_ "a pending verdict without its proposal is refused" || bad "bare pending: rc=$rc out=$out"
exit "$fails"
