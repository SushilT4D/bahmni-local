#!/usr/bin/env bash
# The seed's provenance record, checked at the seed gate and compared at join:
#   - the gate refuses a seed whose manifest names no record, whose record is
#     missing or altered, or that lacks the content lines, the tool line or
#     the foreign key set; a good record passes and the gate keeps a copy;
#   - at join, a clinic whose master tables equal the record passes; one
#     seeded from another dump is refused, naming the first table that
#     differs; a different checksum tool or exclusion list is refused first;
#   - with docker and the pinned MySQL image, the record is computed by
#     clinic/scripts/master-checksum.sh on a throwaway server, the same rows
#     pass, and a row edited in place (same id, same uuid) is refused; the
#     foreign keys read from information_schema are compared with the hub's
#     record, and one out of obs or one the hub lacks is refused.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; MYC=""
cleanup(){ [ -n "$MYC" ] && docker rm -f -v "$MYC" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
export CLINIC_DIR="$TMP/clinic" REPO_DIR="$RP" INSTALL_DIR="${HERE}/.."
mkdir -p "$CLINIC_DIR"
. "${HERE}/../lib.sh"; . "${HERE}/../state.sh"
T="$(printf '\t')"
TOOL="$(sha256_of "$RP/clinic/scripts/master-checksum.sh")"
X="$RP/hub/checksum-exclusions.conf"
record(){ # CONTENT-LINES (table<TAB>rest) -> a provenance record on stdout
  printf 'hub\tdump_taken_at\tfixture\n'
  printf 'tool\tmaster-checksum.sh\t%s\n' "$TOOL"
  awk '{ sub(/#.*/, "") } NF { print "exclude\t" $1 }' "$X"
  printf '%s\n' "$1" | awk 'NF { print "content\t" $0 }'
  printf 'fk\tset\t2\tabc\nfk\tobs\tconcept_id\tconcept\tconcept_id\tobs_concept\nfk\tvisit\tpatient_id\tpatient\tpatient_id\tvisit_patient\n'
}
CONTENT="concept${T}3${T}111${T}4:aaaa
drug${T}2${T}222${T}5:bbbb
location${T}1${T}333${T}6:cccc"
seed(){ # CONTENT [MANIFEST-EXTRA] : a seed folder in $TMP/seed whose manifest binds the record
  rm -rf "$TMP/seed"; mkdir -p "$TMP/seed"
  record "$1" > "$TMP/seed/provenance.tsv"
  printf 'PROVENANCE=provenance.tsv\nSHA256_PROVENANCE=%s\n%s' "$(sha256_of "$TMP/seed/provenance.tsv")" "${2:-}" > "$TMP/seed/manifest.env"
}

# --- the seed gate ------------------------------------------------------------------
seed "$CONTENT"
out="$(seed_provenance_verdict "$TMP/seed")" && [ "$out" = "ok 3 master tables, 2 foreign keys" ] && ok_ "a good record passes: $out" || bad "good record: $out"
printf 'SEED_TAKEN_AT=x\n' > "$TMP/seed/manifest.env"
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && case "$out" in *"names no provenance record"*) true ;; *) false ;; esac && ok_ "a manifest naming no record is refused" || bad "no PROVENANCE: $out"
seed "$CONTENT"; printf 'tampered\n' >> "$TMP/seed/provenance.tsv"
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && case "$out" in *"does not match its checksum"*) true ;; *) false ;; esac && ok_ "an altered record is refused" || bad "tampered: $out"
seed "$CONTENT"; rm "$TMP/seed/provenance.tsv"
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && case "$out" in *"missing from the seed folder"*) true ;; *) false ;; esac && ok_ "a missing record is refused" || bad "missing: $out"
seed "$CONTENT"; grep -v '^fk' "$TMP/seed/provenance.tsv" > "$TMP/p"; mv "$TMP/p" "$TMP/seed/provenance.tsv"
printf 'PROVENANCE=provenance.tsv\nSHA256_PROVENANCE=%s\n' "$(sha256_of "$TMP/seed/provenance.tsv")" > "$TMP/seed/manifest.env"
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && case "$out" in *"no foreign key set"*) true ;; *) false ;; esac && ok_ "a record without the foreign key set is refused" || bad "no fk set: $out"
seed ""
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && case "$out" in *"no master table content"*) true ;; *) false ;; esac && ok_ "a record without content lines is refused" || bad "no content: $out"
printf 'PROVENANCE=../x\n' > "$TMP/seed/manifest.env"
out="$(seed_provenance_verdict "$TMP/seed")"; [ $? = 1 ] && ok_ "a record named outside the seed folder is refused" || bad "path: $out"
G="${HERE}/../tasks/005-seed-gate.sh"
grep -q 'seed_provenance_verdict "${SEED_DIR}")" || refuse' "$G" && ok_ "005 refuses a seed whose record fails" || bad "005 does not check the record"
awk '/DRY}" = 1 \]/ {d=NR} /cp "\$\{SEED_DIR\}\/\$\{prov\}" "\$\{PROVENANCE_COPY\}"/ {c=NR} END {exit !(d && c > d)}' "$G" && ok_ "005 keeps a copy of the record, after the dry-run exit" || bad "005 does not keep the record (or keeps it in a dry run)"

# --- the join comparison ------------------------------------------------------------
seed "$CONTENT"; R="$TMP/seed/provenance.tsv"
out="$(provenance_content_verdict "$R" "$CONTENT" "$TOOL" "$X")" && [ "$out" = "ok 3 master tables equal to the seed this clinic was built from" ] && ok_ "the same seed joins: $out" || bad "same: $out"
other="concept${T}3${T}111${T}4:aaaa
drug${T}2${T}999${T}5:bbbb
location${T}2${T}444${T}6:cccc"
out="$(provenance_content_verdict "$R" "$other" "$TOOL" "$X")"; [ $? = 1 ] && case "$out" in "this clinic's drug is not the drug of the seed"*"seed: 2 222 5:bbbb; this clinic: 2 999 5:bbbb"*) true ;; *) false ;; esac \
  && ok_ "a clinic seeded from another dump is refused, naming the first differing table (drug)" || bad "other dump: $out"
out="$(provenance_content_verdict "$R" "$(printf '%s\n' "$CONTENT" | grep -v '^location')" "$TOOL" "$X")"; [ $? = 1 ] && case "$out" in *"location"*"no line"*) true ;; *) false ;; esac && ok_ "a table the clinic did not report is refused" || bad "missing table: $out"
out="$(provenance_content_verdict "$R" "$CONTENT" "0000" "$X")"; [ $? = 1 ] && case "$out" in *"master-checksum.sh is not the one"*) true ;; *) false ;; esac && ok_ "a different checksum tool is refused before any table is compared" || bad "tool: $out"
printf 'privilege.uuid\nrole.uuid\n' > "$TMP/x2"
out="$(provenance_content_verdict "$R" "$CONTENT" "$TOOL" "$TMP/x2")"; [ $? = 1 ] && case "$out" in *"leaves out other columns"*) true ;; *) false ;; esac && ok_ "a different exclusion list is refused" || bad "exclusions: $out"
J="${HERE}/../tasks/090-local-sync.sh"
blk="$(sed -n '/^# provenance:begin/,/^# provenance:end/p' "$J")"
printf '%s' "$blk" | grep -q 'provenance_content_verdict' && printf '%s' "$blk" | grep -q 'provenance_content_lines' && ok_ "090 compares the clinic with the record" || bad "090 does not compare the record"
printf '%s' "$blk" | grep -q 'provenance_fk_verdict' && ok_ "090 compares the clinic's foreign keys with the hub's" || bad "090 does not compare the foreign keys"
# the hub's master changes reach the clinic once its sync starts, so the
# comparison must come before anything in 090 that starts or registers sync
awk '/^# provenance:end/ {e=NR} /stamp_put SYNC_STARTED 1/ && !s {s=NR} /(compose_up|register|generate-|setup-mirrormaker)/ && !/would:/ && !c {c=NR} END {exit !(e && s > e && (c == 0 || c > e))}' "$J" && ok_ "090 compares before its sync layer starts" || bad "090 starts sync before comparing"
printf '%s' "$blk" | grep -q 'stamp_get SYNC_STARTED' && ok_ "a resume after sync started does not compare again (the hub's changes have arrived)" || bad "090 compares again after sync started"
sed -n '/^# provenance:begin/,/^# provenance:end/p' "${HERE}/../tasks/110-hub-join.sh" | grep -q 'provenance_content_verdict' && bad "110 still compares masters with the seed after sync started" || ok_ "110 does not compare masters with the seed (the hub's changes have arrived by then)"
grep -q 'provenance_fk_verdict "${PROVENANCE_COPY}"' "${HERE}/../tasks/100-exit-checks.sh" && ok_ "100 compares them once OpenMRS has started (a module change made at its first start shows there)" || bad "100 does not compare the foreign keys"

# --- on a real server: the tool computes the record, then an in-place edit -----------
. "$RP/sync/versions.env"
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
  MYC="provtest$$"
  docker run -d --name "$MYC" -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=openmrs "${MYSQL_IMAGE}" >/dev/null 2>&1 || bad "could not start ${MYSQL_IMAGE}"
  my(){ docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -uroot openmrs' 2>&1; }
  # a first start initialises the data directory and restarts the server: on a
  # busy machine that takes minutes (MYSQL_BOOT_S, default 300)
  up=0; for i in $(seq 1 $(( ${MYSQL_BOOT_S:-300} / 2 ))); do [ "$(echo 'select 1' | docker exec -i "$MYC" sh -c 'MYSQL_PWD=x mysql -h127.0.0.1 -uroot -N' 2>/dev/null)" = 1 ] && { up=1; break; }; sleep 2; done
  if [ "$up" = 1 ]; then
    my <<'SQL' >/dev/null
CREATE TABLE form (form_id INT PRIMARY KEY, name VARCHAR(255), version VARCHAR(50), uuid CHAR(38));
INSERT INTO form VALUES (454, 'Vitals', '3', 'u-454'), (457, 'History', '2', 'u-457');
CREATE TABLE location (location_id INT PRIMARY KEY, name VARCHAR(255), uuid CHAR(38));
INSERT INTO location VALUES (1, 'Clinic', 'u-1');
SQL
    printf 'tool\tmaster-checksum.sh\t%s\ncontent\tform\ncontent\tlocation\n' "$TOOL" > "$TMP/tables.rec"
    hub_lines="$(CT=docker provenance_content_lines "$TMP/tables.rec" "$MYC" 2>"$TMP/err")" || bad "master-checksum.sh on ${MYSQL_IMAGE}: $(cat "$TMP/err")"
    seed "$hub_lines"; R="$TMP/seed/provenance.tsv"
    [ "$(awk -F'\t' '$1=="content"' "$R" | grep -c .)" = 2 ] && ok_ "${MYSQL_IMAGE}: the record holds the tool's lines for form and location" || bad "record: $(cat "$R")"
    lines="$(CT=docker provenance_content_lines "$R" "$MYC")"
    out="$(provenance_content_verdict "$R" "$lines" "$TOOL" "$X")" && ok_ "${MYSQL_IMAGE}: the same rows join: $out" || bad "${MYSQL_IMAGE} same rows: $out"
    echo "UPDATE form SET name = 'Vitals (revised)' WHERE form_id = 454;" | my >/dev/null
    lines="$(CT=docker provenance_content_lines "$R" "$MYC")"
    out="$(provenance_content_verdict "$R" "$lines" "$TOOL" "$X")"; [ $? = 1 ] && case "$out" in "this clinic's form is not the form of the seed"*) true ;; *) false ;; esac \
      && ok_ "${MYSQL_IMAGE}: a form rewritten in place (same id, same uuid) is refused, named" || bad "${MYSQL_IMAGE} in-place edit: $out"
    # the foreign keys, read from information_schema the way the installer reads them
    my <<'SQL' >/dev/null
CREATE TABLE encounter (encounter_id INT PRIMARY KEY);
CREATE TABLE obs (obs_id INT PRIMARY KEY, encounter_id INT, location_id INT, CONSTRAINT obs_location FOREIGN KEY (location_id) REFERENCES location (location_id));
SQL
    hub_fks="$(ct(){ docker "$@"; }; clinic_fk_rows "$MYC")"
    { printf 'fk\tset\t1\tx\n'; printf '%s\n' "$hub_fks" | awk 'NF { print "fk\t" $0 }'; } > "$TMP/fk.rec"
    rows="$(ct(){ docker "$@"; }; clinic_fk_rows "$MYC")"
    out="$(provenance_fk_verdict "$TMP/fk.rec" "$rows")"; [ $? = 1 ] && case "$out" in *"obs.location_id -> location.location_id"*) true ;; *) false ;; esac \
      && ok_ "${MYSQL_IMAGE}: a key out of obs, read from information_schema, is refused even when the hub's record has it" || bad "${MYSQL_IMAGE} fk out of obs: $out"
    echo 'ALTER TABLE obs DROP FOREIGN KEY obs_location; CREATE TABLE ipd_slot (id INT PRIMARY KEY, order_id INT, location_id INT, CONSTRAINT ipd_slot_location FOREIGN KEY (location_id) REFERENCES location (location_id));' | my >/dev/null
    rows="$(ct(){ docker "$@"; }; clinic_fk_rows "$MYC")"
    printf 'fk\tset\t0\tx\n' > "$TMP/fk.rec"
    out="$(provenance_fk_verdict "$TMP/fk.rec" "$rows")"; [ $? = 1 ] && case "$out" in *"foreign keys on ipd_slot differ from the hub's (only at this clinic: ipd_slot.location_id -> location.location_id)"*) true ;; *) false ;; esac \
      && ok_ "${MYSQL_IMAGE}: a key the hub's record lacks is refused, named by table" || bad "${MYSQL_IMAGE} extra fk: $out"
    { printf 'fk\tset\t1\tx\n'; printf '%s\n' "$rows" | awk 'NF { print "fk\t" $0 }'; } > "$TMP/fk.rec"
    out="$(provenance_fk_verdict "$TMP/fk.rec" "$rows")" && ok_ "${MYSQL_IMAGE}: the same keys as the record: $out" || bad "${MYSQL_IMAGE} same fks: $out"
  else
    bad "${MYSQL_IMAGE} did not answer within ${MYSQL_BOOT_S:-300} s (MYSQL_BOOT_S)"
  fi
else
  printf '  skip docker with %s is not here; the record was not computed on a server\n' "${MYSQL_IMAGE}"
fi
exit $((fails > 0))
