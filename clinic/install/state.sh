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

# stamp_gate_verdict STATE : the seed sitting runs once, after install.
# SEEDING is allowed: an earlier seed stopped part-way and its databases hold
# nothing anyone entered, so it is redone from the start.
stamp_gate_verdict(){
  case "${1:-}" in
    INSTALLED|SEEDING) printf 'ok\n' ;;
    SEEDED) printf 'this machine is already seeded; a clinic is seeded once. Call the operator.\n'; return 1 ;;
    *) printf 'this machine is not installed yet (no install state found); the operator runs install.sh first. Call the operator.\n'; return 1 ;;
  esac
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
  local o="$1" d="$2" e="$3" discard="$4" what
  what="OpenMRS people: ${o}, Odoo customers: ${d}, OpenELIS samples: ${e}"
  if [ "$o" = 0 ] && [ "$d" = 0 ] && [ "$e" = 0 ]; then printf 'ok\n'; return 0; fi
  if [ "$discard" = 1 ]; then printf 'discard %s\n' "$what"; return 0; fi
  printf 'records were entered on this machine before seeding (%s); seeding replaces them. If they are only tests, run again with --discard-baseline-data. Otherwise call the operator.\n' "$what"
  return 1
}
