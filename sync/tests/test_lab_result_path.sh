#!/usr/bin/env bash
# Lab results entered at the hub reach the clinic that placed the order, and
# nothing else moves with them (hub/tables.conf, `clinic=` rows).
#
#   - the readers of hub/tables.conf accept the role: the hub source captures
#     encounter and obs, the clinic gets their sinks and grants, the master-data
#     checksum leaves them out, the verdict check passes;
#   - the hub's source still refuses orders and drug_order, and refuses obs
#     without the role;
#   - the rendered hub source and clinic sinks, run through Kafka Connect's own
#     transform chain in the pinned Debezium image with the scripting jars:
#     the hub publishes only the rows it wrote, for any patient, and a clinic
#     keeps an encounter only in a visit it opened and an obs only for an order
#     it placed (residue and base of visit_id / order_id);
#   - a clinic that keeps its own OpenMRS database and takes the hub's staff
#     (role hub-written in its down list): its sinks keep only rows at or above
#     the hub's floor ending in 0, never apply a delete of a user, provider or
#     person, apply a revoked role, keep only the property names given and never
#     a node-local one, and the generator refuses users without the link
#     statement, a missing or off-grid floor, and a link row judged by anything
#     but its user. The records skipped (not failed) without docker,
#     the image or the jars, unless REQUIRE_FILTER_RUN=1.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- the readers ------------------------------------------------------------------
inc="$(bash "$R/clinic/scripts/generate-table-config.sh" cloud | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
case ",$inc," in *,openmrs.encounter,*openmrs.obs,*) ok_ "the hub source's table list carries encounter and obs" ;; *) bad "hub table list: $inc" ;; esac
case ",$inc," in *,openmrs.person,*openmrs.person_name,*) ok_ "the hub source's table list carries person and person_name (the hub's own rows, behind their filter)" ;; *) bad "hub table list without person/person_name: $inc" ;; esac
bash "$R/clinic/scripts/check-table-verdicts.sh" >/dev/null 2>&1 && ok_ "the table verdicts accept the routed rows (both are UP: the clinics write them)" || bad "check-table-verdicts: $(bash "$R/clinic/scripts/check-table-verdicts.sh" 2>&1 | tail -2)"
lists="$(REPO_DIR="$R" bash -c '. "$0/clinic/install/lib.sh"; echo "DOWN $(down_tables | tr "\n" " ")"; echo "MASTER $(master_down_tables | tr "\n" " ")"' "$R")"
printf '%s\n' "$lists" | grep '^DOWN' | grep -q ' obs ' && ok_ "the down tables (sink grants) include obs" || bad "down tables: $lists"
printf '%s\n' "$lists" | grep '^MASTER' | grep -qE ' (obs|encounter) ' && bad "the master-data checksum would compare encounter or obs: $lists" || ok_ "the master-data checksum leaves encounter and obs out"

# --- the hub source ----------------------------------------------------------------
gen_hub(){ DEBEZIUM_DB_PASSWORD=x REPO_DIR="$1" HUB_DIR="$1/hub" bash "$1/hub/scripts/generate-cloud-source-connector.sh" "$T/src.json" 2>&1; }
out="$(gen_hub "$R")"; rc=$?
[ "$rc" = 0 ] && ok_ "the hub source renders" || bad "hub source: rc=$rc $out"
copy(){ rm -rf "$T/r"; mkdir -p "$T/r"; (cd "$R" && tar cf - hub clinic/scripts sync) | (cd "$T/r" && tar xf -); }
copy; printf 'orders:order_id:clinic=order_id\n' >> "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "only encounter and obs carry the hub's lab results" && [ ! -s "$T/src.json.x" ] && ok_ "orders is refused, even with the role" || bad "orders with role: rc=$rc $out"
copy; sed -i.bak 's/^obs:obs_id:clinic=order_id$/obs:obs_id:clinic=person_id/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "obs goes to a clinic by order_id" && ok_ "obs routed by any column but order_id is refused" || bad "obs by person_id: rc=$rc $out"
copy; sed -i.bak 's/^obs:obs_id:clinic=order_id$/obs:obs_id/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "never publishes \['obs'\]" && ok_ "obs without the role is refused" || bad "obs without role: rc=$rc $out"
copy; sed -i.bak 's/^person:person_id:230000$/person:person_id/' "$T/r/sync/local/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "person is marked hub-rows, and its floor in sync/local/tables.conf (person:person_id:<floor>) is missing" && ok_ "a hub-rows table without a floor refuses the source" || bad "no person floor: rc=$rc $out"
copy; sed -i.bak 's/^person:person_id:230000$/person:person_id:230005/' "$T/r/sync/local/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "is 230005, not a multiple of 10" && ok_ "a floor off the residue grid refuses the source" || bad "odd person floor: rc=$rc $out"
copy; sed -i.bak 's/^person:person_id:hub-rows$/person:person_id/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "appear in BOTH direction files: \['person'\]" && ok_ "person without its hub-rows mark is refused: every clinic's people would go to every clinic" || bad "unmarked person: rc=$rc $out"
copy; sed -i.bak 's/^person:person_id:hub-rows$/person:person_id:relay/' "$T/r/hub/tables.conf"
out="$(gen_hub "$T/r")"; rc=$?
inc_r="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$T/src.json" 2>/dev/null)"
[ "$rc" = 0 ] && case ",$inc_r," in *,openmrs.person,*) false ;; *) true ;; esac && ok_ "a relay mark is not published by the hub" || bad "relay person: rc=$rc inc=$inc_r $out"
gen_hub "$R" >/dev/null 2>&1
python3 - "$T/src.json" "$R/hub/tables.conf" <<'EOF' && ok_ "the hub source snapshots encounter and obs with no rows (and the changes-only concept tables), person and person_name on their floor filter, every other table whole" || bad "snapshot overrides: $(grep -o '"snapshot.select[^,]*' "$T/src.json" | tr '\n' ' ')"
import json, sys
c = json.load(open(sys.argv[1]))['config']
changes = {"openmrs." + l.split("#")[0].strip().split(":")[0] for l in open(sys.argv[2]) if l.split("#")[0].strip().endswith(":changes")}
want = {"openmrs.encounter", "openmrs.obs"} | changes
own = {"openmrs.person": "person_id", "openmrs.person_name": "person_name_id"}
assert set(c.get("snapshot.select.statement.overrides", "").split(",")) == want | set(own)
for t in want:
    assert c["snapshot.select.statement.overrides." + t].endswith("WHERE 1 = 0"), t
for t, pk in own.items():
    assert c["snapshot.select.statement.overrides." + t].endswith(f"WHERE `{pk}` >= 230000 AND `{pk}` % 10 = 0"), t
assert not [k for k in c if k.startswith("snapshot.select.statement.overrides.") and k[len("snapshot.select.statement.overrides."):] not in want | set(own)]
EOF
python3 - "$T/src.json" > "$T/hub.cfg" <<'EOF'
import json, sys
for k, v in json.load(open(sys.argv[1]))['config'].items(): print(f"{k}\t{v}")
EOF

# --- the clinic sinks --------------------------------------------------------------
( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE=3 FLOOR_ORDERS=441560 bash scripts/generate-local-sink-connectors.sh "$T/sinks" >/dev/null 2>&1 ) || bad "the clinic sinks did not render"
[ -f "$T/sinks/mysql-local-sink-obs.json" ] && [ -f "$T/sinks/mysql-local-sink-encounter.json" ] && ok_ "the clinic gets sinks for encounter and obs" || bad "no lab-result sinks: $(ls "$T/sinks" 2>/dev/null | tr '\n' ' ')"
grep -q rowsForThisClinic "$T/sinks/mysql-local-sink-users.json" && bad "a master table's sink carries the routing filter" || ok_ "master-table sinks are unchanged"
out="$( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE= MYSQL_AUTO_INCREMENT_OFFSET= FLOOR_ORDERS=441560 bash scripts/generate-local-sink-connectors.sh "$T/none" 2>&1 )"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "residue (RESIDUE, 1-9) is not set" && [ ! -d "$T/none" ] && ok_ "without this clinic's residue nothing is generated" || bad "no residue: rc=$rc $out"
out="$( cd "$R/clinic" && LOCAL_MYSQL_PASSWORD=x RESIDUE=3 FLOOR_ORDERS= bash scripts/generate-local-sink-connectors.sh "$T/nofloor" 2>&1 )"; rc=$?
[ "$rc" != 0 ] && printf '%s' "$out" | grep -q "FLOOR_ORDERS (the orders floor recorded at seeding)" && [ ! -d "$T/nofloor" ] && ok_ "without the orders floor nothing is generated" || bad "no orders floor: rc=$rc $out"
cfg_of(){ python3 - "$1" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))['config']
# the sink's topic rename runs first; the probe feeds records already named for the table
c['transforms'] = ','.join(t for t in c['transforms'].split(',') if t != 'dropPrefix')
for k, v in c.items(): print(f"{k}\t{v}")
EOF
}
cfg_of "$T/sinks/mysql-local-sink-obs.json" > "$T/sink.cfg"
cfg_of "$T/sinks/mysql-local-sink-encounter.json" > "$T/enc.cfg"

# --- the hub's staff at a clinic that keeps its own OpenMRS database ----------------
# its down list (role hub-written), the hub's recorded floors for users and provider
printf 'users:user_id:hub-written\nuser_role:user_id,role:hub-written=user_id\nuser_property:user_id,property:hub-written=user_id\nprovider:provider_id:hub-written\nperson:person_id:hub-written\nperson_name:person_name_id:hub-written\nrole:role:changes\n' > "$T/staff.conf"
printf 'users 2000\nprovider 500\n' > "$T/staff-floors"
gen_staff(){ # OUT-DIR, then VAR=value... for the generator
  local o="$1"; shift
  ( cd "$R/clinic" && env LOCAL_MYSQL_PASSWORD=x TABLES_CONF="$T/staff.conf" HUB_STAFF_FLOORS="$T/staff-floors" USER_PROPERTY_KEEP=defaultLocale HUB_LINK_PER_SITE_TLS=yes "$@" bash scripts/generate-local-sink-connectors.sh "$o" 2>&1 )
}
out="$(gen_staff "$T/staff")"; rc=$?
[ "$rc" = 0 ] && [ "$(ls "$T/staff" | grep -c .)" = 7 ] && ok_ "a clinic's down list with hub-written rows renders its seven staff sinks" || bad "staff sinks: rc=$rc $out"
python3 - "$T/staff" <<'EOF' && ok_ "users, provider, person and person_name never apply a delete; user_role and user_property do; role takes changes only" || bad "staff sink deletes: $(grep -h '"delete.enabled"' "$T"/staff/*.json | tr -d ' \n')"
import json, sys, os
d = {t: json.load(open(os.path.join(sys.argv[1], f"mysql-local-sink-{t}.json")))["config"] for t in
     ("users", "provider", "person", "person_name", "user_role", "user_property", "role")}
for t in ("users", "provider", "person", "person_name", "role"):
    assert d[t]["delete.enabled"] == "false" and "noDeletes" in d[t]["transforms"].split(","), t
for t in ("user_role", "user_property"):
    assert d[t]["delete.enabled"] == "true" and "noDeletes" not in d[t]["transforms"].split(","), t
assert "hubWrittenOnly" not in d["role"]["transforms"], "role"
assert ">= 230000L" in d["person"]["transforms.hubWrittenOnly.condition"]
assert ">= 2000L" in d["user_role"]["transforms.hubWrittenOnly.condition"]
assert ">= 500L" in d["provider"]["transforms.hubWrittenOnly.condition"]
EOF
refuse(){ # LABEL EXPECTED-TEXT VAR=value...
  local label="$1" want="$2"; shift 2
  rm -rf "$T/staff-r"; out="$(gen_staff "$T/staff-r" "$@")"; rc=$?
  [ "$rc" != 0 ] && printf '%s' "$out" | grep -qF "$want" && [ ! -d "$T/staff-r" ] && ok_ "$label" || bad "$label: rc=$rc $out"
}
refuse "users is refused, nothing generated, unless the link to the hub is TLS with a login of this clinic's own" "REFUSING users: its rows carry password hashes" HUB_LINK_PER_SITE_TLS=
refuse "without the hub's recorded floors nothing is generated" "no floor for users" HUB_STAFF_FLOORS=
refuse "a user_property receiver without the property names to keep is refused" "USER_PROPERTY_KEEP (the property names the hub's users carry as settings) is empty" USER_PROPERTY_KEEP=
refuse "a node-local property name is never kept" "keeps loginAttempts, which holds each node's own state" USER_PROPERTY_KEEP=defaultLocale,loginAttempts
printf 'users 2005\nprovider 500\n' > "$T/staff-floors-odd"
refuse "a floor off the residue grid is refused" "the floor of users is '2005', not a whole multiple of 10" HUB_STAFF_FLOORS="$T/staff-floors-odd"
printf 'users 2000\nprovider 500\nperson 240000\n' > "$T/staff-floors-person"
refuse "a floors file that moves person off the hub source's own floor is refused" "gives person a floor, but its floor is its base" HUB_STAFF_FLOORS="$T/staff-floors-person"
cp "$T/staff.conf" "$T/staff.conf.keep"
printf 'user_role:user_id,role:hub-written=role\n' > "$T/staff.conf"
refuse "a link row judged by anything but its user is refused" "a link row can be judged only by user_id"
printf 'user_role:user_id,role:hub-written\n' > "$T/staff.conf"
refuse "a composite key with no column named is refused" "judged on its own key, which must be one column"
cp "$T/staff.conf.keep" "$T/staff.conf"
for t in users user_role user_property person provider; do cfg_of "$T/staff/mysql-local-sink-$t.json" > "$T/staff-$t.cfg"; done
cat > "$T/staff-users.cases" <<'EOF'
remote.bahmni-cloud.openmrs.users	user_id	2010	c	person_id	230010	kept	a login the hub created
remote.bahmni-cloud.openmrs.users	user_id	2010	u	person_id	230010	kept	the hub's change to it (a password reset at the hub)
remote.bahmni-cloud.openmrs.users	user_id	1500	u	person_id	120	dropped	a hub edit to an older login, whose id this clinic's own history may share
remote.bahmni-cloud.openmrs.users	user_id	2013	c	person_id	230013	dropped	a login not on the hub's residue
remote.bahmni-cloud.openmrs.users	user_id	2010	d	person_id	230010	dropped	a delete: a login is retired, never deleted
remote.bahmni-cloud.openmrs.users	user_id	2010	t	person_id	230010	dropped	its tombstone
EOF
cat > "$T/staff-user_role.cases" <<'EOF'
remote.bahmni-cloud.openmrs.user_role	user_id,role	2010,Doctor	c	creator	1	kept	a role granted to a hub user
remote.bahmni-cloud.openmrs.user_role	user_id,role	2010,Doctor	d	creator	1	kept	the role revoked from a hub user
remote.bahmni-cloud.openmrs.user_role	user_id,role	2010,Doctor	t	creator	1	kept	its tombstone, judged on the key
remote.bahmni-cloud.openmrs.user_role	user_id,role	1500,Doctor	d	creator	1	dropped	a hub change to an older user's roles
remote.bahmni-cloud.openmrs.user_role	user_id,role	2013,Doctor	c	creator	1	dropped	a grant to a user not on the hub's residue
EOF
cat > "$T/staff-user_property.cases" <<'EOF'
remote.bahmni-cloud.openmrs.user_property	user_id,property	2010,defaultLocale	c	creator	1	kept	a hub user's setting
remote.bahmni-cloud.openmrs.user_property	user_id,property	2010,defaultLocale	d	creator	1	kept	that setting removed at the hub
remote.bahmni-cloud.openmrs.user_property	user_id,property	2010,loginAttempts	u	creator	1	dropped	the hub's failed-login counter (each node keeps its own)
remote.bahmni-cloud.openmrs.user_property	user_id,property	2010,favouriteWards	u	creator	1	dropped	a name not in the kept list
remote.bahmni-cloud.openmrs.user_property	user_id,property	1500,defaultLocale	u	creator	1	dropped	an older user's setting
EOF
cat > "$T/staff-person.cases" <<'EOF'
remote.bahmni-cloud.openmrs.person	person_id	230010	c	creator	1	kept	the person behind a hub login
remote.bahmni-cloud.openmrs.person	person_id	230013	c	creator	1	dropped	a person on this clinic's residue, even if the hub's source let it pass
remote.bahmni-cloud.openmrs.person	person_id	120000	u	creator	1	dropped	a hub edit to an older person
remote.bahmni-cloud.openmrs.person	person_id	230010	d	creator	1	dropped	a delete: a person is retired, never deleted
EOF
cat > "$T/staff-provider.cases" <<'EOF'
remote.bahmni-cloud.openmrs.provider	provider_id	510	c	person_id	230010	kept	a provider the hub created
remote.bahmni-cloud.openmrs.provider	provider_id	490	u	person_id	120	dropped	a hub edit to a provider below its floor
EOF

# --- the records, through Kafka Connect's transform chain --------------------------
#   topic   key column   key   op   row column   row value   want   why
cat > "$T/hub.cases" <<'EOF'
bahmni-cloud.openmrs.obs	obs_id	9000000	c	order_id	441563	kept	the hub's result obs for clinic 3's order
bahmni-cloud.openmrs.obs	obs_id	9000003	c	order_id	441563	dropped	an obs clinic 3 sent up (its residue, not the hub's)
bahmni-cloud.openmrs.obs	obs_id	9000010	c	order_id	12001	kept	the hub's obs on an old order: the hub passes every row it wrote and the clinics decide
bahmni-cloud.openmrs.obs	obs_id	9000030	d	order_id	441564	kept	the delete of the hub's result obs for clinic 4's order
bahmni-cloud.openmrs.obs	obs_id	9000030	t	order_id	441564	dropped	a tombstone (no row)
bahmni-cloud.openmrs.encounter	encounter_id	530000	c	visit_id	625004	kept	the hub's lab-result encounter in clinic 4's visit
bahmni-cloud.openmrs.encounter	encounter_id	530004	u	visit_id	625004	dropped	an encounter clinic 4 sent up
bahmni-cloud.openmrs.users	user_id	50	u	person_id	50	kept	a master table passes unchanged
bahmni-cloud.openmrs.person	person_id	240790	c	creator	1	kept	a person the hub created (above the floor, ending in 0)
bahmni-cloud.openmrs.person	person_id	240793	c	creator	1	dropped	a person clinic 3 sent up
bahmni-cloud.openmrs.person	person_id	120000	u	creator	1	dropped	a hub edit to a person older than the floor (on every residue below it)
bahmni-cloud.openmrs.person	person_id	240800	d	creator	1	kept	the delete of a person the hub created
bahmni-cloud.openmrs.person	person_id	240800	t	creator	1	kept	its tombstone, judged on the key, so the clinic's row goes too
bahmni-cloud.openmrs.person	person_id	240804	t	creator	1	dropped	the tombstone of clinic 4's person
bahmni-cloud.openmrs.person_name	person_name_id	231350	c	creator	1	kept	the name of a person the hub created
bahmni-cloud.openmrs.person_name	person_name_id	231353	u	creator	1	dropped	a hub edit to a name clinic 3 wrote
EOF
cat > "$T/sink.cases" <<'EOF'
remote.bahmni-cloud.openmrs.obs	obs_id	9000000	c	order_id	441563	kept	clinic 3 keeps the result of its own order, whatever the patient's id
remote.bahmni-cloud.openmrs.obs	obs_id	9000010	c	order_id	441564	dropped	clinic 3 drops the result of clinic 4's order
remote.bahmni-cloud.openmrs.obs	obs_id	9000020	c	order_id	441570	dropped	clinic 3 drops the result of an order the hub placed
remote.bahmni-cloud.openmrs.obs	obs_id	9000040	c	order_id	441553	dropped	clinic 3 drops a result for an order below the floor, where a residue proves nothing
remote.bahmni-cloud.openmrs.obs	obs_id	9000030	d	order_id	441563	kept	clinic 3 applies the delete of its order's result
remote.bahmni-cloud.openmrs.obs	obs_id	9000030	t	order_id	441563	dropped	a tombstone (no row)
EOF
cat > "$T/enc.cases" <<'EOF'
remote.bahmni-cloud.openmrs.encounter	encounter_id	530000	c	visit_id	625003	kept	clinic 3 keeps the hub's result encounter in its own visit
remote.bahmni-cloud.openmrs.encounter	encounter_id	530010	c	visit_id	625004	dropped	clinic 3 drops an encounter in clinic 4's visit
remote.bahmni-cloud.openmrs.encounter	encounter_id	530020	c	visit_id	625010	dropped	clinic 3 drops an encounter in a visit the hub opened
remote.bahmni-cloud.openmrs.encounter	encounter_id	530030	c	visit_id	600003	dropped	clinic 3 drops an encounter in a visit below the visit base
EOF
judge(){ # LABEL CASES GOT
  local n w g
  n="$(grep -c . "$2")"; [ "$(grep -c . "$3")" = "$n" ] || { bad "$1: $(head -3 "$3" | tr '\n' ' ')"; return; }
  paste "$2" "$3" | while IFS='	' read -r _t _k key op _c rv want why got; do
    if [ "$got" = "$want" ]; then printf '  ok   %s: %s (%s)\n' "$1" "$why" "$got"; else printf '  FAIL %s: %s -> %s, want %s\n' "$1" "$why" "$got" "$want"; fi
  done > "$T/judged"
  cat "$T/judged"; fails=$((fails + $(grep -c '^  FAIL' "$T/judged")))
}
skipped(){ if [ "${REQUIRE_FILTER_RUN:-0}" = 1 ]; then bad "the records were not run, and REQUIRE_FILTER_RUN=1: $1"; else printf '  skip %s\n' "$1"; fi; }
. "$R/sync/versions.env"
EXT="${SCRIPTING_JARS_DIR:-$R/clinic/config/kafka-connect/ext}"
JARS="groovy-${GROOVY_VERSION}.jar groovy-jsr223-${GROOVY_VERSION}.jar debezium-scripting-${DEBEZIUM_SCRIPTING_VERSION}.jar"
have_jars=1; for j in $JARS; do [ -f "$EXT/$j" ] || have_jars=0; done
IMG="${DEBEZIUM_CONNECT_IMAGE%% *}"
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }; sleep 1; i=$((i+1)); done
  wait "$p"
}
if [ "$have_jars" != 1 ]; then
  skipped "the scripting jars are not in ${EXT#$R/} (clinic/config/kafka-connect/ext/fetch-scripting-jars.sh fetches them)"
elif ! docker_answers || ! docker image inspect "$IMG" >/dev/null 2>&1; then
  skipped "docker with $IMG is not here"
else
  cp "$R/clinic/install/tests/probes/RowFilterChainProbe.java" "$T/"
  run(){ # PLUGIN-DIR CONFIG CASES -> one line per record
    local m="" j
    for j in $JARS; do m="$m -v $EXT/$j:/kafka/connect/$1/$j:ro"; done
    cut -f1-6 "$3" > "$T/records.tsv"
    # shellcheck disable=SC2086
    docker run --rm --entrypoint java -v "$T:/probe:ro" $m "$IMG" \
      -cp "/kafka/libs/*:/kafka/connect/$1/*" /probe/RowFilterChainProbe.java "/probe/$(basename "$2")" /probe/records.tsv 2>&1
  }
  run debezium-connector-mysql "$T/hub.cfg" "$T/hub.cases" > "$T/hub.got"
  judge "hub source" "$T/hub.cases" "$T/hub.got"
  run debezium-connector-jdbc "$T/sink.cfg" "$T/sink.cases" > "$T/sink.got"
  judge "clinic 3's obs sink" "$T/sink.cases" "$T/sink.got"
  run debezium-connector-jdbc "$T/enc.cfg" "$T/enc.cases" > "$T/enc.got"
  judge "clinic 3's encounter sink" "$T/enc.cases" "$T/enc.got"
  for t in users user_role user_property person provider; do
    run debezium-connector-jdbc "$T/staff-$t.cfg" "$T/staff-$t.cases" > "$T/staff-$t.got"
    judge "the hub's staff, $t sink" "$T/staff-$t.cases" "$T/staff-$t.got"
  done
fi
printf '\n%s failure(s)\n' "$fails"
exit $((fails > 0))
