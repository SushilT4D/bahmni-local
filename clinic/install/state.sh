#!/usr/bin/env bash
# The machine's install state (none, SEEDING, SEEDED) and the checks run on the seed folder and the databases.
STATE_FILE="${STATE_FILE:-${CLINIC_DIR}/.install-state}"

stamp_get(){ if [ -f "${STATE_FILE}" ]; then env_get "${STATE_FILE}" "$1"; fi; }
stamp_put(){ # KEY VALUE
  [ -f "${STATE_FILE}" ] || { : > "${STATE_FILE}"; chmod 644 "${STATE_FILE}"; }
  env_put "${STATE_FILE}" "$1" "$2"
}

stamp_gate_verdict(){
  case "${1:-}" in
    SEEDING)
      if [ "${2:-0}" = 1 ]; then printf 'this install stopped after the sync layer had started; redoing it needs the operator (replication state must be cleared first). Call the operator.\n'; return 1; fi
      printf 'ok\n' ;;
    SEEDED) printf 'this machine is already installed with the hub'"'"'s data; a clinic is installed once. Call the operator.\n'; return 1 ;;
    *) printf 'ok\n' ;;
  esac
}

run_gate_verdict(){
  if [ "${1:-}" = SEEDED ]; then
    [ "${3:-}" = 010 ] && { printf 'ok\n'; return 0; }
    printf 'this machine is already installed with the hub'"'"'s data; only --only 010 (the name service) may run on it.\n'; return 1
  fi
  if [ -z "${2:-}" ] && [ -z "${3:-}" ]; then printf 'ok\n'; return 0; fi
  [ "${1:-}" = SEEDING ] && { printf 'ok\n'; return 0; }
  if [ -n "${2:-}" ] && [ -z "${3:-}" ] && [ "$((10#${2}))" -le 5 ]; then printf 'ok\n'; return 0; fi
  case "${3:-}" in 000|005) printf 'ok\n'; return 0 ;; esac
  printf -- '--from and --only only resume an install that stopped part-way; this machine is %s. Run install.sh without them.\n' "${1:-not installed}"
  return 1
}

resume_redoes_drop(){
  local n="${2:-${1:-}}"
  [ -z "$n" ] && return 0
  [ "$((10#$n))" -le 50 ]
}

sha256_of(){ # FILE
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

seed_manifest_verdict(){
  local dir="$1" now="$2" max="$3" m="$1/manifest.env" taken epoch age f key want got
  [ -f "$m" ] || { printf 'the seed folder has no manifest.env; ask the operator for a fresh seed folder.\n'; return 1; }
  taken="$(env_get "$m" SEED_TAKEN_AT)"
  epoch="$(python3 -c 'import sys,datetime; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))' "$taken" 2>/dev/null)" \
    || { printf 'manifest.env has no readable SEED_TAKEN_AT (%s); ask the operator for a fresh seed folder.\n' "${taken:-empty}"; return 1; }
  if [ "$epoch" -gt $((now + 86400)) ]; then
    printf 'the dump is dated in the future (%s); check this machine'"'"'s date and time, then call the operator.\n' "$taken"; return 1
  fi

  age=$(( (now - epoch) / 86400 ))
  if [ "$age" -gt "$max" ]; then
    printf 'the dump is %s days old (taken %s); the limit is %s days because the hub keeps only a week of changes. Ask the operator for a fresh dump.\n' "$age" "$taken" "$max"; return 1
  fi

  for f in openmrs odoo openelis; do
    [ -s "$dir/$f.sql.gz" ] || { printf '%s.sql.gz is missing from the seed folder; ask the operator for a fresh copy.\n' "$f"; return 1; }
    key="SHA256_$(printf '%s' "$f" | tr a-z A-Z)"
    want="$(env_get "$m" "$key")"
    got="$(sha256_of "$dir/$f.sql.gz")"
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
      printf '%s.sql.gz does not match its checksum (damaged or replaced in the copy); ask the operator for a fresh copy.\n' "$f"; return 1
    fi
  done

  printf 'ok %s\n' "$taken"
}

seed_floor_tables(){
  type up_tables_read >/dev/null 2>&1 || . "${INSTALL_DIR}/../../sync/tables/tables.sh"
  local recs
  recs="$(up_tables_read "$1")" || return 1
  printf '%s\n' "$recs" | awk '$3=="seed" {print $1}'
}

SEED_COUNTER_TABLES="obs orders"

floor_key(){ printf 'FLOOR_%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; }
seed_counter_pk(){ case "$1" in obs) printf 'obs_id' ;; orders) printf 'order_id' ;; *) return 1 ;; esac; }

seed_floor_residue_sql(){
  local pk; pk="$(seed_counter_pk "$1")" || return 1
  printf 'select count(*) from openmrs.`%s` where `%s` >= %s and `%s` %% 10 <> 0;\n' "$1" "$pk" "$2" "$pk"
}

seed_floor_residue_verdict(){
  local t="$1" fl="$2" n="$3"
  case "$n" in ''|*[!0-9]*) printf 'could not count the %s rows at or above the floor %s (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$fl" "$n"; return 1 ;; esac
  if [ "$n" -gt 0 ]; then
    printf 'the seed holds %s %s row(s) at or above the floor %s that are not on the hub'"'"'s residue 0: a clinic on that residue would publish its edits to them as its own. This seed cannot be used; ask the operator for a fresh seed folder.\n' "$n" "$t" "$fl"; return 1
  fi

  printf 'ok %s: every seeded row at or above the floor %s is the hub'"'"'s (residue 0)\n' "$t" "$fl"
}

seed_floors_verdict(){
  local m="$1" conf="$2" ts t key v got=""
  ts="$(seed_floor_tables "$conf" 2>&1)" || { printf 'the clinic table list cannot be read: %s\n' "$ts"; return 1; }
  for t in $ts $SEED_COUNTER_TABLES; do
    case " ${got} " in *" ${t}="*) continue ;; esac
    key="$(floor_key "$t")"
    v="$(env_get "$m" "$key")"
    case "$v" in
      ''|*[!0-9]*) printf 'manifest.env carries no %s floor (%s): this seed was cut without measuring where the hub'"'"'s %s ids end, so this clinic cannot start its own above them. Ask the operator for a fresh seed folder.\n' "$t" "$key" "$t"; return 1 ;;
    esac

    if [ "$v" -le 0 ] || [ $((v % 10)) -ne 0 ]; then
      printf 'manifest.env %s=%s is not a positive multiple of 10, so floor + residue would not be on this clinic'"'"'s residue. Ask the operator for a fresh seed folder.\n' "$key" "$v"; return 1
    fi

    got="${got} ${t}=${v}"
  done

  printf 'ok%s\n' "$got"
}

seed_counter_plan(){
  local t="$1" ai="$2" fl="$3" r="$4" first
  case "$ai" in ''|*[!0-9]*) printf 'could not read the %s id counter (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$ai"; return 1 ;; esac
  case "$fl" in ''|*[!0-9]*) printf 'the %s floor '"'"'%s'"'"' is not a number, so the first %s id this clinic may write cannot be known. Rerun the install from its seed gate (install.sh ... --from 005) or call the operator.\n' "$t" "$fl" "$t"; return 1 ;; esac
  case "$r" in [1-9]) ;; *) printf 'residue %s is not a clinic residue (1 to 9)\n' "${r:-none}"; return 1 ;; esac
  first=$(( fl + (r - fl % 10 + 10) % 10 ))
  if [ "$ai" -lt "$first" ]; then printf 'set %s\n' "$first"; else printf 'keep\n'; fi
}

counter_floor_verdict(){
  local t="$1" ai="$2" fl="$3" r="$4" next
  case "$ai" in ''|*[!0-9]*) printf 'could not read the %s id counter (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$ai"; return 1 ;; esac
  case "$fl" in ''|*[!0-9]*) printf 'no %s floor is recorded on this machine, so its id counter cannot be checked. Rerun the install from its seed gate (install.sh ... --from 005) or call the operator.\n' "$t"; return 1 ;; esac
  next=$(( ai + (r - ai % 10 + 10) % 10 ))
  if [ "$next" -lt $((fl + r)) ]; then
    printf 'the %s id counter is below this clinic'"'"'s floor: the next %s id would be %s, and clinic-written %s ids start at %s (floor %s + residue %s). Ids below that belong to the hub'"'"'s own rows. Rerun the striding step (install.sh ... --from 060) or call the operator.\n' "$t" "$t" "$next" "$t" "$((fl + r))" "$fl" "$r"
    return 1
  fi

  printf 'ok %s next id %s, at or above floor %s + residue %s\n' "$t" "$next" "$fl" "$r"
}

counter_floor_verdicts(){
  local conf="$1" r="$2" reader="$3" ts t v out=""
  ts="$(seed_floor_tables "$conf" 2>&1)" || { printf 'the clinic table list cannot be read, so no id counter was checked: %s\n' "${ts:-no reason given}"; return 1; }
  ts="$(printf '%s' "$ts" | tr '\n' ' ')"
  for t in $SEED_COUNTER_TABLES; do
    case " ${ts} " in *" ${t} "*) continue ;; esac
    [ -z "$(stamp_get "$(floor_key "$t")")" ] || ts="${ts} ${t}"
  done

  [ -n "${ts// /}" ] || { printf 'ok no table in the OpenMRS [up] list takes its floor from the seed, and no obs or orders floor is recorded: no id counter to check\n'; return 0; }
  for t in $ts; do
    v="$(counter_floor_verdict "$t" "$("$reader" "$t")" "$(stamp_get "$(floor_key "$t")")" "$r")" || { printf '%s\n' "$v"; return 1; }
    out="${out}${v}
"
  done

  printf '%s' "$out"
}

mysql_stride_verdict(){
  case "$1" in
    "10 $2") printf 'ok MySQL issues ids 10 apart on residue %s\n' "$2" ;;
    '') printf 'could not read MySQL'"'"'s id increment and offset; the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n'; return 1 ;;
    *) printf 'MySQL issues ids with increment and offset %s, not 10 %s: new rows would land on another node'"'"'s residue. Rerun the striding step (install.sh ... --from 060) or call the operator.\n' "$1" "$2"; return 1 ;;
  esac
}

node_counters_verdict(){
  local st="${1:-}" conf="$2" r="$3" reader="$4" v
  case "$st" in
    SEEDED) ;;
    SEEDING) printf 'skip id counters not checked: this machine is part-way through its seed, whose striding step checks them\n'; return 0 ;;
    *) printf 'skip id counters not checked: this machine is not seeded yet, so it has no id floors\n'; return 0 ;;
  esac

  v="$(mysql_stride_verdict "$("$reader" --stride)" "$r")" || { printf '%s\n' "$v"; return 1; }
  counter_floor_verdicts "$conf" "$r" "$reader" || return 1
  printf '%s\n' "$v"
}

ORDER_RANGE_WIDTH=10000000
ORDER_RANGE_MARGIN=1000000

order_seed_range(){
  case "${1:-}" in [1-9]) ;; *) printf 'residue %s has no order-number range: a clinic is residue 1 to 9, and below 10,000,000 is the hub'"'"'s.\n' "${1:-none}"; return 1 ;; esac
  printf '%s %s\n' $(( $1 * ORDER_RANGE_WIDTH + 1 )) $(( ($1 + 1) * ORDER_RANGE_WIDTH - 1 ))
}

order_seed_owner(){
  if [ "$1" -lt "${ORDER_RANGE_WIDTH}" ]; then printf 'the hub'"'"'s range (below 10,000,000)'
  elif [ "$1" -lt $(( 10 * ORDER_RANGE_WIDTH )) ]; then printf 'the range of the clinic with residue %s' $(( $1 / ORDER_RANGE_WIDTH ))
  else printf 'no node'"'"'s range (above 99,999,999)'; fi
}

order_seed_plan(){
  local v="$1" r="$2" rg lo hi
  rg="$(order_seed_range "$r")" || { printf '%s\n' "$rg"; return 1; }
  lo="${rg% *}"
  hi="${rg#* }"
  case "$v" in
    '') printf 'set %s\n' "$lo"; return 0 ;;
    *[!0-9]*) printf 'order.nextOrderNumberSeed is '"'"'%s'"'"', not a number, so the next order number this clinic issues cannot be known. Call the operator.\n' "$v"; return 1 ;;
  esac

  if [ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ]; then printf 'keep\n'; return 0; fi
  if [ "$v" -lt "${ORDER_RANGE_WIDTH}" ]; then printf 'set %s\n' "$lo"; return 0; fi
  printf 'order.nextOrderNumberSeed is %s, in %s, not this clinic'"'"'s (%s to %s): this database carries another node'"'"'s order counter, and numbers issued from it would duplicate that node'"'"'s. Call the operator.\n' "$v" "$(order_seed_owner "$v")" "$lo" "$hi"
  return 1
}

order_seed_sql(){
  printf "INSERT INTO global_property (property, property_value, description, uuid) VALUES ('order.nextOrderNumberSeed', '%s', 'The next order number to seed the order number generator', UUID()) ON DUPLICATE KEY UPDATE property_value = '%s';\n" "$1" "$1"
}

order_seed_verdict(){
  local v="$1" r="$2" rg lo hi
  rg="$(order_seed_range "$r")" || { printf '%s\n' "$rg"; return 1; }
  lo="${rg% *}"
  hi="${rg#* }"
  case "$v" in ''|*[!0-9]*) printf 'could not read order.nextOrderNumberSeed (got '"'"'%s'"'"'); without it OpenMRS starts order numbers at 1, in the hub'"'"'s range. Rerun the striding step (install.sh ... --from 060) or call the operator.\n' "$v"; return 1 ;; esac
  if [ "$v" -lt "$lo" ] || [ "$v" -gt "$hi" ]; then
    printf 'order.nextOrderNumberSeed is %s, in %s, not this clinic'"'"'s (%s to %s): the next order number would duplicate another node'"'"'s. Rerun the striding step (install.sh ... --from 060) or call the operator.\n' "$v" "$(order_seed_owner "$v")" "$lo" "$hi"
    return 1
  fi

  if [ $(( hi - v )) -lt "${ORDER_RANGE_MARGIN}" ]; then
    printf 'order.nextOrderNumberSeed is %s, within 1,000,000 of the top of this clinic'"'"'s range (%s): past it, numbers are the next clinic'"'"'s. Call the operator.\n' "$v" "$hi" >&2
  fi

  printf 'ok order.nextOrderNumberSeed %s, in this clinic'"'"'s range %s to %s\n' "$v" "$lo" "$hi"
}

seed_shape_verdict(){
  local dir="$1" f out tfound inc t q
  for f in openmrs.sql.gz odoo.sql.gz openelis.sql.gz; do
    [ -s "$dir/$f" ] || { printf 'seed file missing or empty: %s\n' "$dir/$f"; return 1; }
    gzip -t "$dir/$f" 2>/dev/null || { printf 'seed file is not valid gzip: %s\n' "$dir/$f"; return 1; }
  done

  { gzip -dc "$dir/openmrs.sql.gz" 2>/dev/null || true; } | grep -qm1 '20251223-drop-default-value-from-column' \
    || { printf 'seed openmrs.sql.gz is not an iplit-1.2.0 dump (changeset 20251223-drop-default-value-from-column absent); the hub must be on %s before it is dumped\n' "${OPENMRS_IMAGE_NAME:-the pinned OpenMRS}"; return 1; }
  { gzip -dc "$dir/odoo.sql.gz" 2>/dev/null || true; } | grep -qm1 -E 'CREATE TABLE (public\.)?uom_uom\b' \
    || { printf 'seed odoo.sql.gz is not an Odoo 16 dump (no uom_uom)\n'; return 1; }

  out="$({ gzip -dc "$dir/odoo.sql.gz" 2>/dev/null || true; } | awk '
    function chk(tbl) { if ($0 ~ ("CREATE TABLE (public\\.)?" tbl "[[:space:](]")) print "TABLE_FOUND=" tbl }
    { chk("village_village"); chk("res_partner_attributes") }
    index($0, "village_village_id_seq") > 0 && w1 == 0 { w1 = 9 }
    w1 > 0 { if (match($0, /INCREMENT BY [0-9]+/)) { n = substr($0, RSTART, RLENGTH); sub(/INCREMENT BY /, "", n); print "INC=village_village_id_seq=" n; w1 = -1 } else w1-- }
    index($0, "res_partner_attributes_id_seq") > 0 && w2 == 0 { w2 = 9 }
    w2 > 0 { if (match($0, /INCREMENT BY [0-9]+/)) { n = substr($0, RSTART, RLENGTH); sub(/INCREMENT BY /, "", n); print "INC=res_partner_attributes_id_seq=" n; w2 = -1 } else w2-- }
  ')"
  for t in village_village res_partner_attributes; do
    q="${t}_id_seq"
    tfound="$(printf '%s\n' "$out" | grep -c "^TABLE_FOUND=${t}\$" || true)"
    inc="$(printf '%s\n' "$out" | grep "^INC=${q}=" | head -1 | cut -d= -f3 || true)"
    [ "${tfound:-0}" -ge 1 ] || { printf 'seed odoo.sql.gz has no %s table -- wrong-shape seed (this table'"'"'s ids are partitioned across the fleet); ask the operator for a fresh seed\n' "$t"; return 1; }
    [ "$inc" = 10 ] || { printf 'seed odoo.sql.gz: %s is not INCREMENT BY 10 (found %s) -- this seed was dumped before the hub partitioned its address and customer-attribute ids; a clinic built from it would hand out %s ids the hub also uses; ask the operator for a fresh seed\n' "$q" "${inc:-none}" "$t"; return 1; }
  done

  printf 'ok seed shape: openmrs iplit-1.2.0, odoo 16; village_village, res_partner_attributes sequences step 10\n'
}

PROVENANCE_COPY="${PROVENANCE_COPY:-${CLINIC_DIR}/.seed-provenance.tsv}"

seed_provenance_verdict(){
  local dir="$1" m="$1/manifest.env" p want got n k
  p="$(env_get "$m" PROVENANCE)"
  [ -n "$p" ] || { printf 'manifest.env names no provenance record (PROVENANCE): this seed was cut without recording what the hub'"'"'s master tables held, so this clinic could never show it was built from the hub it joins. Ask the operator for a fresh seed folder.\n'; return 1; }
  case "$p" in */*|.*) printf 'manifest.env PROVENANCE=%s is not a file in the seed folder. Ask the operator for a fresh seed folder.\n' "$p"; return 1 ;; esac
  [ -s "$dir/$p" ] || { printf '%s is missing from the seed folder; ask the operator for a fresh copy.\n' "$p"; return 1; }
  want="$(env_get "$m" SHA256_PROVENANCE)"
  got="$(sha256_of "$dir/$p")"
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    printf '%s does not match its checksum (damaged or replaced in the copy); ask the operator for a fresh copy.\n' "$p"; return 1
  fi

  n="$(awk -F'\t' '$1=="content"' "$dir/$p" | grep -c . || true)"
  [ "$n" -gt 0 ] || { printf '%s records no master table content, so nothing could be compared at join. Ask the operator for a fresh seed folder.\n' "$p"; return 1; }
  awk -F'\t' '$1=="tool" && $2=="master-checksum.sh" && $3!="" {f=1} END {exit !f}' "$dir/$p" \
    || { printf '%s does not say which checksum tool computed it. Ask the operator for a fresh seed folder.\n' "$p"; return 1; }
  k="$(awk -F'\t' '$1=="fk" && $2=="set" {print $3}' "$dir/$p" | head -1)"
  case "$k" in ''|*[!0-9]*) printf '%s records no foreign key set, so this clinic'"'"'s schema could not be compared with the hub'"'"'s. Ask the operator for a fresh seed folder.\n' "$p"; return 1 ;; esac
  printf 'ok %s master tables, %s foreign keys\n' "$n" "$k"
}

provenance_content_verdict(){
  local rec="$1" lines="$2" sha="$3" xf="$4" t want got n=0 a b
  a="$(awk -F'\t' '$1=="tool" && $2=="master-checksum.sh" {print $3}' "$rec" | head -1)"
  if [ "$a" != "$sha" ]; then
    printf 'this checkout'"'"'s clinic/scripts/master-checksum.sh is not the one the seed'"'"'s record was computed with, so their checksums cannot be compared. Check out the commit the seed was cut against, or ask the operator for a seed cut with this one.\n'; return 1
  fi

  a="$(awk -F'\t' '$1=="exclude" {print $2}' "$rec" | LC_ALL=C sort | tr '\n' ' ')"
  b="$(awk '{ sub(/#.*/, "") } NF { print $1 }' "$xf" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
  if [ "$a" != "$b" ]; then
    printf 'this checkout leaves out other columns from the checksums (%s) than the seed'"'"'s record did (%s), so they cannot be compared. Check out the commit the seed was cut against.\n' "${b:-none}" "${a:-none}"; return 1
  fi

  while IFS='	' read -r t want; do
    [ -n "$t" ] || continue
    n=$((n+1))
    got="$(printf '%s\n' "$lines" | awk -F'\t' -v t="$t" '$1==t { sub(/^[^\t]*\t/, ""); print; exit }')"
    if [ "$got" != "$want" ]; then
      printf 'this clinic'"'"'s %s is not the %s of the seed it was built from (seed: %s; this clinic: %s). It was seeded from another dump, or its %s rows changed after the seed. A clinic joins only the hub it was seeded from; call the operator.\n' "$t" "$t" "$(printf '%s' "$want" | tr '\t' ' ')" "$(printf '%s' "${got:-no line}" | tr '\t' ' ')" "$t"
      return 1
    fi
  done <<EOF
$(awk -F'\t' '$1=="content" { sub(/^content\t/, ""); print }' "$rec" | LC_ALL=C sort)
EOF
  [ "$n" -gt 0 ] || { printf 'the seed'"'"'s record holds no master table content to compare\n'; return 1; }
  printf 'ok %s master tables equal to the seed this clinic was built from\n' "$n"
}

CLINIC_FK_READ_SQL="select table_name, column_name, referenced_table_name, referenced_column_name, constraint_name from information_schema.key_column_usage where table_schema='openmrs' and referenced_table_name is not null order by 1, 2;"

lines_not_in(){
  { printf '%s\n' "$1"; printf '\001\n'; printf '%s\n' "$2"; } | awk '$0 == "\001" { s = 1; next } !s { a[$0] = 1; next } $0 != "" && !($0 in a) { print }'
}

provenance_fk_verdict(){
  local rec="$1" rows="$2" out hub mine t plus minus n hw
  hw=" $( [ -f "${REPO_DIR}/cloud/table-verdicts.conf" ] && awk '{ sub(/#.*/, "") } NF >= 2 && ($2 == "DOWN" || $2 == "RESEED") { print $1 }' "${REPO_DIR}/cloud/table-verdicts.conf" | tr '\n' ' ') "
  out="$(printf '%s\n' "$rows" | awk -F'\t' -v hw="$hw" 'NF >= 4 && ($1=="obs" || $1=="orders" || $1=="drug_order" || $1=="test_order") && index(hw, " " $3 " ") == 0 {print $1 "." $2 " -> " $3 "." $4}' | head -3)"
  if [ -n "$out" ]; then
    printf 'this clinic has a foreign key out of a clinical table (%s): the hub would stop taking that table whenever a row arrived before its parent. The schema change that added it must not run at a clinic; call the operator.\n' "$(printf '%s' "$out" | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
    return 1
  fi

  awk -F'\t' '$1=="fk" && $2=="set" {f=1} END {exit !f}' "$rec" 2>/dev/null \
    || { printf 'the seed'"'"'s provenance record holds no foreign key set, so this clinic'"'"'s schema cannot be compared with the hub'"'"'s. Call the operator.\n'; return 1; }
  hub="$(awk -F'\t' '$1=="fk" && $2!="set" && NF >= 5 {print $2 "\t" $3 "\t" $4 "\t" $5}' "$rec" | LC_ALL=C sort -u)"
  mine="$(printf '%s\n' "$rows" | awk -F'\t' 'NF >= 4 {print $1 "\t" $2 "\t" $3 "\t" $4}' | LC_ALL=C sort -u)"
  if [ "$hub" != "$mine" ]; then
    t="$( { lines_not_in "$hub" "$mine"; lines_not_in "$mine" "$hub"; } | cut -f1 | grep . | LC_ALL=C sort | head -1)"
    plus="$(lines_not_in "$hub" "$mine" | awk -F'\t' -v t="$t" '$1==t {print $1 "." $2 " -> " $3 "." $4}' | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
    minus="$(lines_not_in "$mine" "$hub" | awk -F'\t' -v t="$t" '$1==t {print $1 "." $2 " -> " $3 "." $4}' | tr '\n' ';' | sed 's/;$//; s/;/; /g')"
    printf 'this clinic'"'"'s foreign keys on %s differ from the hub'"'"'s (%s%s%s). The hub is the reference: a clinic with a key the hub lacks ran a schema change ahead of it, one without a hub key is behind it. Call the operator.\n' "$t" "${plus:+only at this clinic: ${plus}}" "${plus:+${minus:+; }}" "${minus:+only at the hub: ${minus}}"
    return 1
  fi

  n="$(printf '%s\n' "$mine" | grep -c . || true)"
  printf 'ok %s foreign keys, the same as the hub'"'"'s when the seed was cut; none out of obs, orders, drug_order or test_order to a table a clinic writes\n' "$n"
}

node_fk_verdict(){
  local rows
  case "${1:-}" in
    SEEDED) ;;
    *) printf 'skip foreign keys not compared with the hub'"'"'s: this machine is not seeded yet, so it holds no record of them\n'; return 0 ;;
  esac

  [ -s "$2" ] || { printf 'this machine is seeded but keeps no seed provenance record (%s), so its foreign keys cannot be compared with the hub'"'"'s. Call the operator.\n' "$2"; return 1; }
  rows="$("$3")" && [ -n "$rows" ] || { printf 'could not read this clinic'"'"'s foreign keys from MySQL; the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n'; return 1; }
  provenance_fk_verdict "$2" "$rows"
}

clinlims_floor_tables(){
  local r
  r="$(bash "${REPO_DIR}/sync/tables/tables.sh" openelis routes)" || return 1
  [ -n "${UP_CLINLIMS_OWN_ROWS+x}" ] || . "${REPO_DIR}/sync/tables/tables.sh"
  { printf '%s\n' "$r" | awk 'NF == 3 { print $3 }'; printf '%s\n' ${UP_CLINLIMS_OWN_ROWS}; } | awk 'NF && !seen[$1]++ { print $1 }'
}

clinlims_floor_key(){ printf 'CLINLIMS_FLOOR_%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; }

clinlims_seq_sql(){
  printf "with s as (select coalesce(case when to_regclass('clinlims.%s') is not null then pg_get_serial_sequence('clinlims.%s', 'id') end, (select quote_ident(schemaname) || '.' || quote_ident(sequencename) from pg_sequences where schemaname = 'clinlims' and sequencename = '%s_seq')) as n) select format('select %%L || ''|'' || last_value::text from %%s', n, n) from s where n is not null \\gexec\n" "$1" "$1" "$1"
}

clinlims_floor_plan(){
  local t="$1" rec="$2" read="$3" seq lv
  if [ -n "$rec" ]; then
    case "$rec" in *[!0-9]*|0*) printf '.install-state has %s=%s, not a whole number above 0; it is never rewritten, so call the operator.\n' "$(clinlims_floor_key "$t")" "$rec"; return 1 ;; esac
    [ $(( rec % 10 )) = 0 ] || { printf '.install-state has %s=%s, not a multiple of 10; it is never rewritten, so call the operator.\n' "$(clinlims_floor_key "$t")" "$rec"; return 1; }
    printf 'keep %s\n' "$rec"; return 0
  fi

  case "$read" in
    *'|'*) seq="${read%%|*}"; lv="${read#*|}" ;;
    *) printf 'no id sequence found for clinlims.%s (neither its id column'"'"'s own nor clinlims.%s_seq), so where this clinic'"'"'s %s ids begin cannot be recorded and lab results entered at the hub could not be kept here. Nothing was strided; call the operator.\n' "$t" "$t" "$t"; return 1 ;;
  esac

  case "$lv" in '') lv=0 ;; *[!0-9]*) printf 'the last value of %s reads '"'"'%s'"'"', not a number; nothing was strided.\n' "$seq" "$lv"; return 1 ;; esac
  printf 'set %s\n' $(( (lv / 10 + 1) * 10 ))
}

record_clinlims_floors(){
  local reader="$1" tables t key rec got plan
  tables="$(clinlims_floor_tables)" || { printf 'the hub'"'"'s down list could not be read (reason above), so the OpenELIS floors could not be recorded; nothing was strided.\n'; return 1; }
  for t in $tables; do
    key="$(clinlims_floor_key "$t")"
    rec="$(stamp_get "$key")"
    got=""
    if [ -z "$rec" ]; then got="$("$reader" "$t")" || { printf 'could not read the id sequence of clinlims.%s; the database is not answering. Nothing was strided; run the same command again.\n' "$t"; return 1; }; fi
    plan="$(clinlims_floor_plan "$t" "$rec" "$(printf '%s\n' "$got" | grep . | tail -1)")" || { printf '%s\n' "$plan"; return 1; }
    case "$plan" in
      keep*) printf 'ok %s=%s (kept: recorded before, never moved)\n' "$key" "${plan#keep }" ;;
      set*) stamp_put "$key" "${plan#set }"; printf 'ok %s=%s (recorded from the sequence before the stride)\n' "$key" "${plan#set }" ;;
    esac
  done
}
