#!/usr/bin/env bash
# hub/scripts/check-clinical-fks.sh on fixture query output, and (with docker
# and the pinned MySQL image) on a throwaway server:
#   - no FK out of obs, orders, drug_order and the recorded FKs into them: passes;
#   - one FK out of any of the three: fails, naming it;
#   - an FK into them that is not recorded, or a recorded one gone: reported
#     (status 2), named;
#   - a schema without the three tables: fails, never "no FK found".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
S="$R/hub/scripts/check-clinical-fks.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; MYC=""
cleanup(){ [ -n "$MYC" ] && docker rm -f -v "$MYC" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
T="$(printf '\t')"
# the recorded FKs into the three tables, as the query prints them
awk -v T="$T" '{ sub(/#.*/, "") } NF == 4 { print $1 T $2 T $3 T $4 T $1 "_fk" }' "$R/hub/clinical-fks-in.conf" > "$TMP/in.tsv"
[ "$(grep -c . "$TMP/in.tsv")" = 11 ] && ok_ "the recorded list holds the 11 FKs into the clinical tables" || bad "recorded list: $(grep -c . "$TMP/in.tsv") lines"
check(){ # FIXTURE-FILE : runs the check; output in $TMP/out, status in $TMP/rc
  bash "$S" --from "$1" > "$TMP/out" 2>&1; echo $? > "$TMP/rc"
}
schema="schema${T}3"

{ cat "$TMP/in.tsv"; echo "$schema"; } > "$TMP/clean"
check "$TMP/clean"
[ "$(cat "$TMP/rc")" = 0 ] && [ "$(grep -c '^ok   .*: no foreign key out' "$TMP/out")" = 3 ] && grep -q '^ok   11 foreign key(s) into' "$TMP/out" \
  && ok_ "0 / 0 / 0 out and the 11 recorded in: passes" || bad "clean: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"

for t in obs orders drug_order; do
  { cat "$TMP/in.tsv"; printf '%s\tencounter_id\tencounter\tencounter_id\t%s_encounter_fk\n' "$t" "$t"; echo "$schema"; } > "$TMP/out_$t"
  check "$TMP/out_$t"
  [ "$(cat "$TMP/rc")" = 1 ] && grep -q "^FAIL ${t} has 1 foreign key(s) out of it" "$TMP/out" && grep -q "${t}.encounter_id -> encounter.encounter_id (${t}_encounter_fk)" "$TMP/out" \
    && ok_ "an FK out of ${t}: fails, named" || bad "FK out of ${t}: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
done
# an FK out of a clinical table that points at another clinical table counts too
{ cat "$TMP/in.tsv"; printf 'drug_order\torder_id\torders\torder_id\tdrug_order_primary_key_fk\n'; echo "$schema"; } > "$TMP/dd"
check "$TMP/dd"
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'drug_order.order_id -> orders.order_id' "$TMP/out" && ok_ "drug_order -> orders is an FK out of drug_order: fails" || bad "drug_order->orders: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"

{ cat "$TMP/in.tsv"; printf 'medication_administration_note\tobs_id\tobs\tobs_id\tman_obs_fk\n'; echo "$schema"; } > "$TMP/added"
check "$TMP/added"
[ "$(cat "$TMP/rc")" = 2 ] && grep -q '+ medication_administration_note.obs_id -> obs.obs_id' "$TMP/out" && ok_ "an FK into obs that is not recorded: reported (status 2), named" || bad "added FK in: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
{ grep -v '^ipd_slot' "$TMP/in.tsv"; echo "$schema"; } > "$TMP/gone"
check "$TMP/gone"
[ "$(cat "$TMP/rc")" = 2 ] && grep -q -- '- ipd_slot.order_id -> orders.order_id' "$TMP/out" && ok_ "a recorded FK into orders that is gone: reported (status 2), named" || bad "gone FK in: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
{ cat "$TMP/in.tsv"; printf 'obs\tconcept_id\tconcept\tconcept_id\tobs_concept\n'; printf 'x\tobs_id\tobs\tobs_id\tx_fk\n'; echo "$schema"; } > "$TMP/both"
check "$TMP/both"
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'CHANGED' "$TMP/out" && ok_ "an FK out and a change in: the FK out decides the status (1), the change is still named" || bad "both: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
cat "$TMP/in.tsv" > "$TMP/noschema"; check "$TMP/noschema"
[ "$(cat "$TMP/rc")" = 1 ] && grep -q 'does not hold obs, orders and drug_order' "$TMP/out" && ok_ "a schema without the three tables: fails, nothing checked" || bad "no schema: rc=$(cat "$TMP/rc") $(cat "$TMP/out")"
bash "$S" > "$TMP/out" 2>&1; [ $? = 1 ] && ok_ "neither --container nor --from: refused" || bad "no source: $(cat "$TMP/out")"

# --- the same query on a real server -------------------------------------------
. "$R/sync/versions.env"
docker_answers(){
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 & local p=$! i=0
  while kill -0 "$p" 2>/dev/null; do
    [ "$i" -ge "${DOCKER_PROBE_S:-15}" ] && { kill "$p" 2>/dev/null; return 1; }
    sleep 1; i=$((i+1))
  done
  wait "$p"
}
if docker_answers && docker image inspect "${MYSQL_IMAGE}" >/dev/null 2>&1; then
  MYC="fktest$$"
  docker run -d --name "$MYC" -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=openmrs "${MYSQL_IMAGE}" >/dev/null 2>&1 || bad "could not start ${MYSQL_IMAGE}"
  my(){ docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -uroot openmrs' 2>&1; }
  # a first start initialises the data directory and restarts the server: on a
  # busy machine that takes minutes (MYSQL_BOOT_S, default 300)
  up=0; for i in $(seq 1 $(( ${MYSQL_BOOT_S:-300} / 2 ))); do [ "$(echo 'select 1' | docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -uroot -N' 2>/dev/null)" = 1 ] && { up=1; break; }; sleep 2; done
  if [ "$up" = 1 ]; then
    my <<'SQL' >/dev/null
CREATE TABLE encounter (encounter_id INT PRIMARY KEY);
CREATE TABLE obs (obs_id INT PRIMARY KEY, encounter_id INT);
CREATE TABLE orders (order_id INT PRIMARY KEY);
CREATE TABLE drug_order (order_id INT PRIMARY KEY);
CREATE TABLE ipd_slot (id INT PRIMARY KEY, order_id INT, CONSTRAINT ipd_slot_order_fk FOREIGN KEY (order_id) REFERENCES orders (order_id));
SQL
    printf 'ipd_slot order_id orders order_id\n' > "$TMP/one.conf"
    CLINICAL_FKS_IN="$TMP/one.conf" bash "$S" --container "$MYC" > "$TMP/out" 2>&1; rc=$?
    [ "$rc" = 0 ] && grep -q '^ok   1 foreign key(s) into' "$TMP/out" && ok_ "${MYSQL_IMAGE}: no FK out, the one FK in as recorded: passes" || bad "${MYSQL_IMAGE} clean: rc=$rc $(cat "$TMP/out")"
    echo 'ALTER TABLE obs ADD CONSTRAINT obs_encounter FOREIGN KEY (encounter_id) REFERENCES encounter (encounter_id);' | my >/dev/null
    CLINICAL_FKS_IN="$TMP/one.conf" bash "$S" --container "$MYC" > "$TMP/out" 2>&1; rc=$?
    [ "$rc" = 1 ] && grep -q 'obs.encounter_id -> encounter.encounter_id (obs_encounter)' "$TMP/out" && ok_ "${MYSQL_IMAGE}: an FK added out of obs fails the check, named" || bad "${MYSQL_IMAGE} FK out: rc=$rc $(cat "$TMP/out")"
  else
    bad "${MYSQL_IMAGE} did not answer within ${MYSQL_BOOT_S:-300} s (MYSQL_BOOT_S)"
  fi
else
  printf '  skip docker with %s is not here; the query was not run on a server\n' "${MYSQL_IMAGE}"
fi
exit $((fails > 0))
