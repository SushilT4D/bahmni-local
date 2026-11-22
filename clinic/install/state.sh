#!/usr/bin/env bash
# The machine's install state (none, SEEDED), the floors recorded from the restored databases, and the checks run on the seed folder and the databases.
STATE_FILE="${STATE_FILE:-${CLINIC_DIR}/.install-state}"

stamp_get(){ if [ -f "${STATE_FILE}" ]; then env_get "${STATE_FILE}" "$1"; fi; }
stamp_put(){ # KEY VALUE
  [ -f "${STATE_FILE}" ] || { : > "${STATE_FILE}"; chmod 644 "${STATE_FILE}"; }
  env_put "${STATE_FILE}" "$1" "$2"
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

seed_floor_pk(){ # TABLE CONF
  seed_counter_pk "$1" && return 0
  type up_tables_read >/dev/null 2>&1 || . "${INSTALL_DIR}/../../sync/tables/tables.sh"
  up_tables_read "$2" | awk -v t="$1" '$1==t {print $2}'
}

seed_floor_plan(){ # TABLE RECORDED MAX_ID
  local t="$1" rec="$2" max="$3" key
  key="$(floor_key "$t")"
  if [ -n "$rec" ]; then
    case "$rec" in *[!0-9]*|0*) printf '.install-state has %s=%s, not a whole number above 0; it is never rewritten, so call the operator.\n' "$key" "$rec"; return 1 ;; esac
    [ $(( rec % 10 )) = 0 ] || { printf '.install-state has %s=%s, not a multiple of 10; it is never rewritten, so call the operator.\n' "$key" "$rec"; return 1; }
    printf 'keep %s\n' "$rec"; return 0
  fi
  case "$max" in ''|*[!0-9]*) printf 'could not read the highest %s id (got '"'"'%s'"'"'); the database is not answering. Run the same command again.\n' "$t" "$max"; return 1 ;; esac
  printf 'set %s\n' $(( (max / 10 + 1) * 10 ))
}

record_seed_floors(){ # CONF READER -- READER TABLE PK prints the restored table's highest id
  local conf="$1" reader="$2" ts t pk key rec got plan
  ts="$(seed_floor_tables "$conf" 2>&1)" || { printf 'the clinic table list cannot be read: %s\n' "$ts"; return 1; }
  for t in $(printf '%s\n' $ts $SEED_COUNTER_TABLES | awk 'NF && !seen[$1]++'); do
    key="$(floor_key "$t")"
    rec="$(stamp_get "$key")"
    got=""
    if [ -z "$rec" ]; then
      pk="$(seed_floor_pk "$t" "$conf")"
      [ -n "$pk" ] || { printf '%s has no primary key in %s, so its floor cannot be measured.\n' "$t" "${conf##*/}"; return 1; }
      got="$("$reader" "$t" "$pk")" || got=""
    fi
    plan="$(seed_floor_plan "$t" "$rec" "$got")" || { printf '%s\n' "$plan"; return 1; }
    case "$plan" in
      keep*) printf 'ok %s=%s (kept: recorded before, never moved)\n' "$key" "${plan#keep }" ;;
      set*) stamp_put "$key" "${plan#set }"; printf 'ok %s=%s (recorded from the restored data, highest id %s)\n' "$key" "${plan#set }" "$got" ;;
    esac
  done
}

seed_counter_plan(){
  local t="$1" ai="$2" fl="$3" r="$4" first
  case "$ai" in ''|*[!0-9]*) printf 'could not read the %s id counter (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$ai"; return 1 ;; esac
  case "$fl" in ''|*[!0-9]*) printf 'the %s floor '"'"'%s'"'"' is not a number, so the first %s id this clinic may write cannot be known. Rerun the databases step (install.sh ... --from 050) or call the operator.\n' "$t" "$fl" "$t"; return 1 ;; esac
  case "$r" in [1-9]) ;; *) printf 'residue %s is not a clinic residue (1 to 9)\n' "${r:-none}"; return 1 ;; esac
  first=$(( fl + (r - fl % 10 + 10) % 10 ))
  if [ "$ai" -lt "$first" ]; then printf 'set %s\n' "$first"; else printf 'keep\n'; fi
}

counter_floor_verdict(){
  local t="$1" ai="$2" fl="$3" r="$4" next
  case "$ai" in ''|*[!0-9]*) printf 'could not read the %s id counter (got '"'"'%s'"'"'); the database is not answering. Wait a minute and run the same command again; if it persists, call the operator.\n' "$t" "$ai"; return 1 ;; esac
  case "$fl" in ''|*[!0-9]*) printf 'no %s floor is recorded on this machine, so its id counter cannot be checked. Rerun the databases step (install.sh ... --from 050) or call the operator.\n' "$t"; return 1 ;; esac
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
