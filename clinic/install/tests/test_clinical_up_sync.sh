#!/usr/bin/env bash
# A clinic sends obs, orders and drug_order to the hub only when installed with
# CLINICAL_UP_SYNC=test; the default, off, keeps them at the clinic even though
# sync/local/tables.conf lists them, so a production clinic installed from this
# tree sends none. On the hub, a clinic gets sinks for them only when its
# hub/clinics.conf row is marked clinical.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/clinic/config" "$C/hub"
cp -R "$RP/clinic/scripts" "$C/clinic/"; cp -R "$RP/clinic/config/mirrormaker" "$C/clinic/config/"; cp -R "$RP/sync" "$C/"
cp -R "$RP/hub/scripts" "$RP/hub/connectors" "$C/hub/"; cp "$RP/hub/tables.conf" "$C/hub/"
{ grep -E '^[a-z_]+:' "$RP/sync/local/tables.conf" | grep -vE '^(obs|orders|drug_order):'
  printf 'obs:obs_id:seed\norders:order_id:seed\ndrug_order:order_id:floor=orders\n'; } > "$C/sync/local/tables.conf"
printf 'FLOOR_OBS=5000000\nFLOOR_ORDERS=300000\n' > "$TMP/manifest.env"
printf 'REMOTE_MYSQL_HOST=h\nREMOTE_MYSQL_PORT=3306\nREMOTE_MYSQL_DATABASE=openmrs\nREMOTE_MYSQL_USER=u\nREMOTE_MYSQL_PASSWORD=p\nDEBEZIUM_DB_PASSWORD=x\n' > "$C/hub/.env"
clinic(){ # CLINICAL_UP_SYNC-LINE : renders the clinic side; results in $TMP/{tc,src,mm,cu} and $TMP/rc.*
  printf 'MYSQL_SERVER_NAME=bahmni-t\nBHS_LOCATION=alpha\nRESIDUE=3\nREMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.invalid:9092\nMYSQL_ROOT_PASSWORD=x\nCOMPOSE_PROJECT_NAME=t\n%s\n' "$1" > "$C/clinic/.env"
  rm -rf "$C/clinic/connectors" "$C/clinic/config/mirrormaker/mm2.properties"
  bash "$C/clinic/scripts/generate-table-config.sh" local > "$TMP/tc" 2>&1; echo $? > "$TMP/rc.tc"
  SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/generate-connectors.sh" > "$TMP/gc" 2>&1; echo $? > "$TMP/rc.gc"
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))["config"]; print(c["table.include.list"]); print("transforms=" + c.get("transforms", ""))' "$C/clinic/connectors/mysql-local-source-connector.json" > "$TMP/src" 2>/dev/null || : > "$TMP/src"
  if command -v envsubst >/dev/null 2>&1; then
    bash "$C/clinic/scripts/setup-mirrormaker.sh" > "$TMP/mmout" 2>&1; echo $? > "$TMP/rc.mm"
    grep -E -- '->remote\.topics' "$C/clinic/config/mirrormaker/mm2.properties" 2>/dev/null > "$TMP/mm" || : > "$TMP/mm"
  fi
  SEED_MANIFEST="$TMP/manifest.env" bash "$C/clinic/scripts/catch-up-clinical.sh" --dry-run --id t1 > "$TMP/cu" 2>&1; echo $? > "$TMP/rc.cu"
}
has_clinical(){ grep -qE 'openmrs[.\\]+(obs|orders|drug_order)([,"|)\\]|$)' "$1"; }

# --- default: off ----------------------------------------------------------------------
clinic ''
[ "$(cat "$TMP/rc.tc")" = 0 ] && ! has_clinical "$TMP/tc" && ok_ "off (no key): the include list has no obs, orders or drug_order" || bad "off, table config: rc=$(cat "$TMP/rc.tc") $(grep INCLUDE "$TMP/tc")"
[ "$(cat "$TMP/rc.gc")" = 0 ] && ! has_clinical "$TMP/src" && grep -qx 'transforms=' "$TMP/src" && ok_ "off: the source captures none of them and carries no filter" || bad "off, source: rc=$(cat "$TMP/rc.gc") $(cat "$TMP/src")"
if [ -f "$TMP/rc.mm" ]; then [ "$(cat "$TMP/rc.mm")" = 0 ] && [ -s "$TMP/mm" ] && ! has_clinical "$TMP/mm" && ok_ "off: MirrorMaker forwards none of them" || bad "off, MirrorMaker: rc=$(cat "$TMP/rc.mm") $(cat "$TMP/mm")"; fi
[ "$(cat "$TMP/rc.cu")" = 0 ] && grep -q 'CLINICAL_UP_SYNC is off' "$TMP/cu" && ! grep -q '^INSERT' "$TMP/cu" && ok_ "off: the catch-up signals nothing" || bad "off, catch-up: $(cat "$TMP/cu")"
clinic 'CLINICAL_UP_SYNC=off'
! has_clinical "$TMP/tc" && ! has_clinical "$TMP/src" && ok_ "CLINICAL_UP_SYNC=off: the same" || bad "explicit off sends them"
cp "$C/clinic/connectors/mysql-local-source-connector.json" "$TMP/off.json"
# --- test ------------------------------------------------------------------------------
clinic 'CLINICAL_UP_SYNC=test'
has_clinical "$TMP/tc" && ok_ "test: the include list has them" || bad "test, table config: $(grep INCLUDE "$TMP/tc")"
has_clinical "$TMP/src" && grep -qx 'transforms=origin_obs,origin_orders,origin_drug_order' "$TMP/src" && ok_ "test: the source captures them behind their filters" || bad "test, source: $(cat "$TMP/src")"
if [ -f "$TMP/rc.mm" ]; then has_clinical "$TMP/mm" && ok_ "test: MirrorMaker forwards them" || bad "test, MirrorMaker: $(cat "$TMP/mm")"; fi
[ "$(grep -c '^INSERT' "$TMP/cu")" = 3 ] && ok_ "test: the catch-up signals the three" || bad "test, catch-up: $(cat "$TMP/cu")"
cp "$C/clinic/connectors/mysql-local-source-connector.json" "$TMP/test.json"
# --- anything else is refused ----------------------------------------------------------
clinic 'CLINICAL_UP_SYNC=yes'
[ "$(cat "$TMP/rc.tc")" != 0 ] && [ "$(cat "$TMP/rc.gc")" != 0 ] && [ "$(cat "$TMP/rc.cu")" != 0 ] && grep -q 'not off or test' "$TMP/gc" && [ ! -f "$C/clinic/connectors/mysql-local-source-connector.json" ] \
  && ok_ "CLINICAL_UP_SYNC=yes: every generator refuses, nothing written" || bad "yes: rc tc=$(cat "$TMP/rc.tc") gc=$(cat "$TMP/rc.gc") cu=$(cat "$TMP/rc.cu")"
# --- the read-back: a connector capturing them at an off clinic is refused --------------
. "$C/sync/local/tables-conf.sh"; . "$C/sync/origin-filter.sh"
reg(){ python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); c=d["config"]; c["name"]=d["name"]; json.dump(c, open(sys.argv[2],"w"))' "$1" "$TMP/reg.json"; }
reg "$TMP/test.json"; out="$(CLINICAL_UP_SYNC=off origin_filter_verdict "$TMP/reg.json" "$C/sync/local/tables.conf" "$TMP/manifest.env" 3)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"captures obs orders drug_order, but CLINICAL_UP_SYNC is off"*) true ;; *) false ;; esac && ok_ "read-back at an off clinic: a connector capturing them is refused" || bad "off read-back of a capturing connector: rc=$rc $out"
reg "$TMP/off.json"; out="$(CLINICAL_UP_SYNC=off origin_filter_verdict "$TMP/reg.json" "$C/sync/local/tables.conf" "$TMP/manifest.env" 3)" && case "$out" in "ok CLINICAL_UP_SYNC is off"*) true ;; *) false ;; esac && ok_ "read-back at an off clinic: the off connector passes" || bad "off read-back: $out"
reg "$TMP/test.json"; out="$(CLINICAL_UP_SYNC=test origin_filter_verdict "$TMP/reg.json" "$C/sync/local/tables.conf" "$TMP/manifest.env" 3)" && [ "$(printf '%s\n' "$out" | grep -c 'capture filter')" = 3 ] && ok_ "read-back at a test clinic: the three filters pass" || bad "test read-back: $out"
# --- the answer ------------------------------------------------------------------------
. "${HERE}/../lib.sh"
case " ${ANSWER_KEYS} " in *" CLINICAL_UP_SYNC "*) ok_ "CLINICAL_UP_SYNC is an install answer" ;; *) bad "not in ANSWER_KEYS" ;; esac
grep -qx 'CLINICAL_UP_SYNC=off' "${HERE}/../clinic.env.example" && ok_ "clinic.env.example offers it, set to off" || bad "clinic.env.example lacks CLINICAL_UP_SYNC=off"
printf 'CLINIC_SLUG=a\n' > "$TMP/ans.env"; answers_missing "$TMP/ans.env" | grep -qx CLINICAL_UP_SYNC && bad "an answers file without it is short of an answer" || ok_ "an answers file without it takes the default"
( unset CLINICAL_UP_SYNC; answer_defaults_apply; [ "$CLINICAL_UP_SYNC" = off ] ) && ok_ "the default is off" || bad "the default is not off"
mkdir -p "$TMP/ic"; cp "$RP/clinic/.env.example" "$TMP/ic/.env.example"
env20(){ env -i PATH="$PATH" HOME="$HOME" DRY=1 ENV_SKIP_COMPOSE=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/ic" REPO_DIR="$RP" PLATFORM=linux RUNTIME=docker \
  CLINIC_SLUG=tst RESIDUE=3 MRN_PREFIX=TST SITE_NUMBER=3 CLINIC_PHONE=+910000000000 CERT_HOSTNAME=t.test REMOTE_KAFKA_BOOTSTRAP_SERVERS=hub.test:9092 REMOTE_KAFKA_USERNAME=m REMOTE_KAFKA_PASSWORD=p \
  OPENMRS_ATOMFEED_PASSWORD=a OPENELIS_ATOMFEED_PASSWORD=b ODOO_ATOMFEED_PASSWORD=c BHS_LOCATION=tst COMPOSE_PROJECT_NAME=t MYSQL_SERVER_NAME=bahmni-tst LOCAL_CLUSTER_ALIAS=tst MYSQL_AUTO_INCREMENT_OFFSET=3 MYSQL_SERVER_ID=3 DEBEZIUM_SERVER_ID=184053 ODOO_DB_VOLUME_NAME=t_o ODOO_APP_VOLUME_NAME=t_a "$@" bash "${HERE}/../tasks/020-env.sh" >/dev/null 2>&1; }
rm -f "$TMP/ic/.env"; env20; grep -qx 'CLINICAL_UP_SYNC=off' "$TMP/ic/.env" 2>/dev/null && ok_ "task 20 writes CLINICAL_UP_SYNC=off into clinic/.env by default" || bad "020 default: $(grep CLINICAL "$TMP/ic/.env" 2>&1)"
rm -f "$TMP/ic/.env"; env20 CLINICAL_UP_SYNC=test; grep -qx 'CLINICAL_UP_SYNC=test' "$TMP/ic/.env" 2>/dev/null && ok_ "and test when the answers say so" || bad "020 test: $(grep CLINICAL "$TMP/ic/.env" 2>&1)"
mkdir -p "$TMP/pc"; printf 'tst:3\n' > "$TMP/ledger"
pre(){ env -i PATH="$PATH" HOME="$HOME" PREFLIGHT_SKIP_HOST=1 DRY=1 INSTALL_DIR="${HERE}/.." CLINIC_DIR="$TMP/pc" REPO_DIR="$TMP" LEDGER="$TMP/ledger" PLATFORM=linux RUNTIME=docker CLINIC_SLUG=tst RESIDUE=3 LOCAL_CLUSTER_ALIAS=tst "$@" bash "${HERE}/../tasks/000-preflight.sh" 2>&1; }
out="$(pre CLINICAL_UP_SYNC=maybe)"; rc=$?
[ "$rc" = 1 ] && case "$out" in *"CLINICAL_UP_SYNC is 'maybe', not off or test"*) true ;; *) false ;; esac && ok_ "preflight refuses CLINICAL_UP_SYNC=maybe" || bad "preflight maybe: rc=$rc $(printf '%s' "$out" | tail -2)"
out="$(pre)"; rc=$?
[ "$rc" = 0 ] && case "$out" in *"CLINICAL_UP_SYNC=off: obs, orders and drug_order stay at this clinic"*) true ;; *) false ;; esac && ok_ "preflight without the key: off, said" || bad "preflight default: rc=$rc $(printf '%s' "$out" | tail -2)"
# --- the hub ---------------------------------------------------------------------------
hub(){ printf '%s\n' "$1" > "$TMP/clinics.conf"; rm -f "$C/hub/connectors"/mysql-sink-alpha-*; CLINICS_CONF="$TMP/clinics.conf" bash "$C/hub/scripts/generate-sink-connectors.sh" > "$TMP/hs" 2>&1; echo $? > "$TMP/rc.hs"; }
hub 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha'
[ "$(cat "$TMP/rc.hs")" = 0 ] && [ -f "$C/hub/connectors/mysql-sink-alpha-visit.json" ] && ! ls "$C/hub/connectors"/mysql-sink-alpha-obs.json "$C/hub/connectors"/mysql-sink-alpha-orders.json "$C/hub/connectors"/mysql-sink-alpha-drug_order.json >/dev/null 2>&1 \
  && ok_ "hub: a clinic not marked clinical gets no obs, orders or drug_order sink, its other sinks as before" || bad "hub unmarked: rc=$(cat "$TMP/rc.hs") $(ls "$C/hub/connectors" | tr '\n' ' ')"
hub 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha:clinical'
[ "$(cat "$TMP/rc.hs")" = 0 ] && ls "$C/hub/connectors"/mysql-sink-alpha-obs.json "$C/hub/connectors"/mysql-sink-alpha-orders.json "$C/hub/connectors"/mysql-sink-alpha-drug_order.json >/dev/null 2>&1 \
  && ok_ "hub: a clinic marked clinical gets the three sinks" || bad "hub marked: rc=$(cat "$TMP/rc.hs") $(tail -2 "$TMP/hs")"
hub 'alpha:mysql-sink-alpha-:alpha:bahmni-alpha:yes'
[ "$(cat "$TMP/rc.hs")" != 0 ] && grep -q "the fifth field is 'yes'" "$TMP/hs" && ok_ "hub: any other fifth field is refused" || bad "hub bad flag: rc=$(cat "$TMP/rc.hs") $(tail -2 "$TMP/hs")"
exit $((fails > 0))
