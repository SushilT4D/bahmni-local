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
