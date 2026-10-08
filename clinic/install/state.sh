#!/usr/bin/env bash
# Machine state between the two sittings, and the rules the seed sitting
# checks before it replaces a single database. Pure functions: no runtime is
# touched here, so every rule is tested without one. bash 3.2 compatible.
STATE_FILE="${STATE_FILE:-${CLINIC_DIR}/.install-state}"

stamp_get(){ if [ -f "${STATE_FILE}" ]; then env_get "${STATE_FILE}" "$1"; fi; }
stamp_put(){ # KEY VALUE
  [ -f "${STATE_FILE}" ] || { : > "${STATE_FILE}"; chmod 644 "${STATE_FILE}"; }
  env_put "${STATE_FILE}" "$1" "$2"
}

# install_gate_verdict STATE ONLY : install never runs over a seeded machine.
# A resume (--from) skips the fresh-install check in task 000 and would stamp
# the machine INSTALLED again, re-opening it to a seed that drops live data.
# The one exception is re-running the host layer alone (--only 010), which
# re-points the name service after the machine moved and touches no data.
install_gate_verdict(){
  case "${1:-}" in
    SEEDED|SEEDING)
      [ "${2:-}" = 010 ] && { printf 'ok\n'; return 0; }
      if [ "$1" = SEEDED ]; then printf 'this machine is already seeded; install.sh would put it back to the baseline state. Only --only 010 (the name service) may run on it.\n'
      else printf 'this machine is being seeded; install.sh would put it back to the baseline state. Finish or rerun the seed (seed.sh) instead.\n'; fi
      return 1 ;;
    *) printf 'ok\n' ;;
  esac
}

# stamp_gate_verdict STATE [SYNC_STARTED] : the seed sitting runs once, after
# install. SEEDING is allowed: an earlier seed stopped part-way and its
# databases hold nothing anyone entered, so it is redone from the start --
# unless it got as far as the sync layer, whose replication slots and
# connector positions a database drop would leave pointing at nothing.
stamp_gate_verdict(){
  case "${1:-}" in
    SEEDING)
      if [ "${2:-0}" = 1 ]; then printf 'this seed stopped after the sync layer had started; redoing it needs the operator (replication state must be cleared first). Call the operator.\n'; return 1; fi
      printf 'ok\n' ;;
    INSTALLED) printf 'ok\n' ;;
    SEEDED) printf 'this machine is already seeded; a clinic is seeded once. Call the operator.\n'; return 1 ;;
    *) printf 'this machine is not installed yet (no install state found); the operator runs install.sh first. Call the operator.\n'; return 1 ;;
  esac
}

# seed_resume_verdict STATE FROM ONLY : --from and --only skip tasks, the gate
# (005) among them, so they may only resume a seed that already passed it and
# stopped part-way (SEEDING).
seed_resume_verdict(){
  if [ -z "${2:-}" ] && [ -z "${3:-}" ]; then printf 'ok\n'; return 0; fi
  [ "${1:-}" = SEEDING ] && { printf 'ok\n'; return 0; }
  printf -- '--from and --only only resume a seed that stopped part-way; this machine is %s. Run seed.sh --seed <folder> without them.\n' "${1:-not installed}"
  return 1
}

# resume_redoes_drop FROM ONLY : does this run reach task 050, which drops the
# databases? Only such a run is dangerous once the sync layer has started.
resume_redoes_drop(){
  local n="${2:-${1:-}}"
  [ -z "$n" ] && return 0
  [ "$((10#$n))" -le 50 ]
}

sha256_of(){ # FILE
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# seed_manifest_verdict DIR NOW_EPOCH MAX_DAYS
# The hub keeps a limited window of changes; a clinic learns what the hub
# wrote after the dump only from that window, so an old dump silently loses
# the gap. The age comes from the manifest, never from file times, which a
# copy rewrites.
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
    key="SHA256_$(printf '%s' "$f" | tr a-z A-Z)"; want="$(env_get "$m" "$key")"; got="$(sha256_of "$dir/$f.sql.gz")"
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
      printf '%s.sql.gz does not match its checksum (damaged or replaced in the copy); ask the operator for a fresh copy.\n' "$f"; return 1
    fi
  done
  printf 'ok %s\n' "$taken"
}

# seed_floor_tables TABLES_CONF : the tables whose floor sync/local/tables.conf
# takes from the seed (table:pk:seed), one per line. A list the reader refuses
# fails, with the reader's reason on stderr.
seed_floor_tables(){
  type up_tables_read >/dev/null 2>&1 || . "${INSTALL_DIR}/../../sync/local/tables-conf.sh"
  local recs
  recs="$(up_tables_read "$1")" || return 1
  printf '%s\n' "$recs" | awk '$3=="seed" {print $1}'
}

# seed_floors_verdict MANIFEST TABLES_CONF
# Each table whose floor comes from the seed needs FLOOR_<TABLE> in the
# manifest: the id below which every row is the hub's, measured on the hub when
# the dump was cut. A clinic strides the table to start above it, and the sync
# layer tells this clinic's rows from the hub's by it, so a seed without it
# cannot be used. It is a multiple of 10, so floor + residue is on the residue.
# Prints "ok" and the floors (TABLE=FLOOR ...), or the refusal.
seed_floors_verdict(){
  local m="$1" conf="$2" ts t key v got=""
  ts="$(seed_floor_tables "$conf" 2>&1)" || { printf 'the clinic table list cannot be read: %s\n' "$ts"; return 1; }
  for t in $ts; do
    key="FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
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

# counter_floor_verdict TABLE AUTO_INCREMENT FLOOR RESIDUE
# With auto_increment_increment 10 and offset RESIDUE, the next id MySQL issues
# is the smallest value at or above AUTO_INCREMENT that is RESIDUE mod 10. It
# must be at or above FLOOR + RESIDUE: below the floor, ids belong to the hub's
# legacy rows, and a row written there could carry an id the hub already has.
counter_floor_verdict(){
  local t="$1" ai="$2" fl="$3" r="$4" next
  case "$ai" in ''|*[!0-9]*) printf 'could not read the %s id counter (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$ai"; return 1 ;; esac
  case "$fl" in ''|*[!0-9]*) printf 'no %s floor is recorded on this machine, so its id counter cannot be checked. Rerun the seed from its gate (seed.sh --seed <folder> --from 005) or call the operator.\n' "$t"; return 1 ;; esac
  next=$(( ai + (r - ai % 10 + 10) % 10 ))
  if [ "$next" -lt $((fl + r)) ]; then
    printf 'the %s id counter is below this clinic'"'"'s floor: the next %s id would be %s, and clinic-written %s ids start at %s (floor %s + residue %s). Ids below that belong to the hub'"'"'s own rows. Rerun the striding step (seed.sh --seed <folder> --from 060) or call the operator.\n' "$t" "$t" "$next" "$t" "$((fl + r))" "$fl" "$r"
    return 1
  fi
  printf 'ok %s next id %s, at or above floor %s + residue %s\n' "$t" "$next" "$fl" "$r"
}

# counter_floor_verdicts TABLES_CONF RESIDUE READER : counter_floor_verdict for
# every table whose floor comes from the seed, against the floor this machine
# recorded at the seed gate. READER TABLE prints that table's AUTO_INCREMENT.
# Prints one "ok ..." line per table, or the first refusal and returns 1. A
# table list that cannot be read is a refusal: checking no table is never a
# pass, because a broken list would otherwise skip every counter.
counter_floor_verdicts(){
  local conf="$1" r="$2" reader="$3" ts t v out=""
  ts="$(seed_floor_tables "$conf" 2>&1)" || { printf 'the clinic table list cannot be read, so no id counter was checked: %s\n' "${ts:-no reason given}"; return 1; }
  [ -n "$ts" ] || { printf 'ok no table in sync/local/tables.conf takes its floor from the seed: no id counter to check\n'; return 0; }
  for t in $ts; do
    v="$(counter_floor_verdict "$t" "$("$reader" "$t")" "$(stamp_get "FLOOR_$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')")" "$r")" || { printf '%s\n' "$v"; return 1; }
    out="${out}${v}
"
  done
  printf '%s' "$out"
}

# mysql_stride_verdict "INCREMENT OFFSET" RESIDUE : MySQL must issue ids 10
# apart on this clinic's residue; with any other pair a new row lands on
# another node's residue whatever its counter says.
mysql_stride_verdict(){
  case "$1" in
    "10 $2") printf 'ok MySQL issues ids 10 apart on residue %s\n' "$2" ;;
    '') printf 'could not read MySQL'"'"'s id increment and offset; the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n'; return 1 ;;
    *) printf 'MySQL issues ids with increment and offset %s, not 10 %s: new rows would land on another node'"'"'s residue. Rerun the striding step (seed.sh --seed <folder> --from 060) or call the operator.\n' "$1" "$2"; return 1 ;;
  esac
}

# node_counters_verdict STATE TABLES_CONF RESIDUE READER : the id counter check
# for a machine whose install state is STATE. READER TABLE prints the table's
# AUTO_INCREMENT; READER --stride prints MySQL's "increment offset". On a
# seeded machine every floored counter must still be at or above its floor and
# MySQL must stride on this residue: a restored database or a reset counter
# would hand out ids that rows written elsewhere already carry. Any other
# machine has no floors yet (the seed gate records them and the striding step
# checks the counters itself), so it prints "skip" and the reason.
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

# Order numbers. OpenMRS issues ORD-<k> from the global property
# order.nextOrderNumberSeed, which is node-local and not synced, and every
# seeded node starts with the value the seed carries. Two nodes issuing from
# the same value would write the same order number for different orders, and
# the orders table does not refuse a duplicate. So each node issues from its
# own range: a clinic of residue r from r x 10,000,000 + 1 to
# (r + 1) x 10,000,000 - 1, the hub below 10,000,000, where every number issued
# before clinics wrote orders already lies.
ORDER_RANGE_WIDTH=10000000
ORDER_RANGE_MARGIN=1000000

# order_seed_range RESIDUE : prints "FIRST LAST", the order numbers this clinic
# may issue. A residue outside 1..9 has no clinic range.
order_seed_range(){
  case "${1:-}" in [1-9]) ;; *) printf 'residue %s has no order-number range: a clinic is residue 1 to 9, and below 10,000,000 is the hub'"'"'s.\n' "${1:-none}"; return 1 ;; esac
  printf '%s %s\n' $(( $1 * ORDER_RANGE_WIDTH + 1 )) $(( ($1 + 1) * ORDER_RANGE_WIDTH - 1 ))
}

# order_seed_owner VALUE : whose range VALUE lies in, in words.
order_seed_owner(){
  if [ "$1" -lt "${ORDER_RANGE_WIDTH}" ]; then printf 'the hub'"'"'s range (below 10,000,000)'
  elif [ "$1" -lt $(( 10 * ORDER_RANGE_WIDTH )) ]; then printf 'the range of the clinic with residue %s' $(( $1 / ORDER_RANGE_WIDTH ))
  else printf 'no node'"'"'s range (above 99,999,999)'; fi
}

# order_seed_plan VALUE RESIDUE : what task 060 does with the seed's value.
# "keep" when it is already in this clinic's range (a rerun after orders were
# issued must not move it back); "set FIRST" when it is the hub's value the
# seed carries, or absent (OpenMRS would otherwise start at 1, in the hub's
# range); refused when it is in another clinic's range or not a number, which
# only a database copied from another clinic, or edited, can hold.
order_seed_plan(){
  local v="$1" r="$2" rg lo hi
  rg="$(order_seed_range "$r")" || { printf '%s\n' "$rg"; return 1; }
  lo="${rg% *}"; hi="${rg#* }"
  case "$v" in
    '') printf 'set %s\n' "$lo"; return 0 ;;
    *[!0-9]*) printf 'order.nextOrderNumberSeed is '"'"'%s'"'"', not a number, so the next order number this clinic issues cannot be known. Call the operator.\n' "$v"; return 1 ;;
  esac
  if [ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ]; then printf 'keep\n'; return 0; fi
  if [ "$v" -lt "${ORDER_RANGE_WIDTH}" ]; then printf 'set %s\n' "$lo"; return 0; fi
  printf 'order.nextOrderNumberSeed is %s, in %s, not this clinic'"'"'s (%s to %s): this database carries another node'"'"'s order counter, and numbers issued from it would duplicate that node'"'"'s. Call the operator.\n' "$v" "$(order_seed_owner "$v")" "$lo" "$hi"
  return 1
}

# order_seed_sql FIRST : the statement that sets the property, creating the row
# when the seed lacks it (global_property.uuid is NOT NULL).
order_seed_sql(){
  printf "INSERT INTO global_property (property, property_value, description, uuid) VALUES ('order.nextOrderNumberSeed', '%s', 'The next order number to seed the order number generator', UUID()) ON DUPLICATE KEY UPDATE property_value = '%s';\n" "$1" "$1"
}

# order_seed_verdict VALUE RESIDUE : the value read back must be in this
# clinic's range. Within 1,000,000 of the top it still passes, with a warning
# on stderr: the range is nearly used up, and past its top the numbers would be
# the next clinic's.
order_seed_verdict(){
  local v="$1" r="$2" rg lo hi
  rg="$(order_seed_range "$r")" || { printf '%s\n' "$rg"; return 1; }
  lo="${rg% *}"; hi="${rg#* }"
  case "$v" in ''|*[!0-9]*) printf 'could not read order.nextOrderNumberSeed (got '"'"'%s'"'"'); without it OpenMRS starts order numbers at 1, in the hub'"'"'s range. Rerun the striding step (seed.sh --seed <folder> --from 060) or call the operator.\n' "$v"; return 1 ;; esac
  if [ "$v" -lt "$lo" ] || [ "$v" -gt "$hi" ]; then
    printf 'order.nextOrderNumberSeed is %s, in %s, not this clinic'"'"'s (%s to %s): the next order number would duplicate another node'"'"'s. Rerun the striding step (seed.sh --seed <folder> --from 060) or call the operator.\n' "$v" "$(order_seed_owner "$v")" "$lo" "$hi"
    return 1
  fi
  if [ $(( hi - v )) -lt "${ORDER_RANGE_MARGIN}" ]; then
    printf 'order.nextOrderNumberSeed is %s, within 1,000,000 of the top of this clinic'"'"'s range (%s): past it, numbers are the next clinic'"'"'s. Call the operator.\n' "$v" "$hi" >&2
  fi
  printf 'ok order.nextOrderNumberSeed %s, in this clinic'"'"'s range %s to %s\n' "$v" "$lo" "$hi"
}

# early_data_verdict OMRS_NEW ODOO_NEW ELIS_NEW DISCARD
# Counts are rows created after install (above the marks install recorded).
# Nothing entered before seeding survives it, so the seed refuses rather than
# silently discarding someone's work, unless told to.
early_data_verdict(){
  local o="$1" d="$2" e="$3" discard="$4" what n
  # a count that could not be read is not zero: fail closed
  for n in "$o" "$d" "$e"; do
    case "$n" in ''|*[!0-9]*) printf 'could not count the records entered before seeding (a database is not answering yet); wait a few minutes and run the same command again. If it persists, call the operator.\n'; return 1 ;; esac
  done
  what="OpenMRS people: ${o}, Odoo customers: ${d}, OpenELIS samples: ${e}"
  if [ "$o" = 0 ] && [ "$d" = 0 ] && [ "$e" = 0 ]; then printf 'ok\n'; return 0; fi
  if [ "$discard" = 1 ]; then printf 'discard %s\n' "$what"; return 0; fi
  printf 'records were entered on this machine before seeding (%s); seeding replaces them. If they are only tests, run again with --discard-baseline-data. Otherwise call the operator.\n' "$what"
  return 1
}

# lan_name_verdict RESOLVED CURRENT_IP NAME : staff reach the stack by NAME, so
# it must resolve to the address this machine has now (a machine moved to a new
# network, or onto another interface, keeps an answer that points elsewhere).
lan_name_verdict(){
  local got="$1" ip="$2" name="$3"
  [ -n "$got" ] || { printf '%s does not resolve on this machine (asked at %s): the name service is not answering on this network. Call the operator; they re-point it with: clinic/install/install.sh --clinic <slug> --only 010\n' "$name" "${ip:-no address}"; return 1; }
  [ "$got" = "$ip" ] || { printf '%s resolves to %s, but this machine is %s: it was moved to another network or interface since install. Call the operator; they re-point the name service with: clinic/install/install.sh --clinic <slug> --only 010\n' "$name" "$got" "$ip"; return 1; }
  printf 'ok\n'
}

# seed_shape_verdict DIR : the dumps come from the pinned OpenMRS and Odoo
# versions, and the hub had partitioned its address and customer-attribute
# ids before it was dumped (a seed taken earlier would hand this clinic ids
# the hub also uses, and a clinic-minted village row can stop a sink).
# Streamed straight from the gz, never unpacked to disk.
seed_shape_verdict(){
  local dir="$1" f out tfound inc t q
  for f in openmrs.sql.gz odoo.sql.gz openelis.sql.gz; do
    [ -s "$dir/$f" ] || { printf 'seed file missing or empty: %s\n' "$dir/$f"; return 1; }
    gzip -t "$dir/$f" 2>/dev/null || { printf 'seed file is not valid gzip: %s\n' "$dir/$f"; return 1; }
  done
  # `{ gzip ... || true; }`: grep -m1 closes the pipe at its first match, gzip
  # then dies of SIGPIPE, and pipefail would report the whole pipeline failed
  { gzip -dc "$dir/openmrs.sql.gz" 2>/dev/null || true; } | grep -qm1 '20251223-drop-default-value-from-column' \
    || { printf 'seed openmrs.sql.gz is not an iplit-1.2.0 dump (changeset 20251223-drop-default-value-from-column absent); the hub must be on %s before it is dumped\n' "${OPENMRS_IMAGE_NAME:-the pinned OpenMRS}"; return 1; }
  { gzip -dc "$dir/odoo.sql.gz" 2>/dev/null || true; } | grep -qm1 -E 'CREATE TABLE (public\.)?uom_uom\b' \
    || { printf 'seed odoo.sql.gz is not an Odoo 16 dump (no uom_uom)\n'; return 1; }
  # pg_dump names a serial id's sequence either as CREATE SEQUENCE ... INCREMENT BY n
  # or inside a multi-line ADD GENERATED ... AS IDENTITY ( ... INCREMENT BY n ... ):
  # take the first INCREMENT BY within the lines after the first line naming it
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
