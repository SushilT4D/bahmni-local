#!/usr/bin/env bash
# Each direction's capture list keeps out the tables the other side writes.
#   - The hub's source never publishes obs, orders or drug_order: clinics write
#     them and the hub receives them through its up sinks. The generator refuses
#     any of them in hub/tables.conf, by name, whether or not the clinic's own
#     list carries it yet.
#   - A clinic never captures users, user_property (written at the hub) or
#     global_property (each node's own configuration): every reader of
#     sync/local/tables.conf refuses them, so the source connector cannot list them.
# Each guard is shown to catch a planted line, on a copy of the repo files.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
C="$TMP/repo"; mkdir -p "$C/clinic" "$C/hub" "$C/sync/local"
cp -R "$R/clinic/scripts" "$C/clinic/"; cp -R "$R/hub/scripts" "$R/hub/connectors" "$C/hub/"
cp "$R/sync/local/tables.conf" "$R/sync/local/tables-conf.sh" "$C/sync/local/"
hub_src(){ REPO_DIR="$C" HUB_DIR="$C/hub" DEBEZIUM_DB_PASSWORD=x bash "$C/hub/scripts/generate-cloud-source-connector.sh" "$TMP/src.json" 2>&1; }

# --- the lists as committed ----------------------------------------------------
cp "$R/hub/tables.conf" "$C/hub/tables.conf"
out="$(hub_src)"; rc=$?
inc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["config"]["table.include.list"])' "$TMP/src.json" 2>/dev/null)"
[ "$rc" -eq 0 ] && ok_ "the hub's source renders from hub/tables.conf" || bad "hub source: rc=$rc $out"
for t in obs orders drug_order; do
  case ",${inc}," in *",openmrs.${t},"*) bad "the hub publishes ${t}: ${inc}" ;; *) ok_ "the hub does not publish ${t}" ;; esac
done
up="$(bash "$C/clinic/scripts/generate-table-config.sh" local 2>&1 | sed -n 's/^TABLE_INCLUDE_LIST=//p')"
[ -n "$up" ] && ok_ "the clinic's include list renders" || bad "clinic include list empty"
for t in users user_property global_property; do
  case ",${up}," in *",openmrs.${t},"*) bad "the clinic captures ${t}: ${up}" ;; *) ok_ "the clinic does not capture ${t}" ;; esac
done

# --- a clinical table planted in hub/tables.conf --------------------------------
for line in obs:obs_id orders:order_id drug_order:order_id; do
  { cat "$R/hub/tables.conf"; printf '%s\n' "$line"; } > "$C/hub/tables.conf"
  rm -f "$TMP/src.json"; out="$(hub_src)"; rc=$?
  [ "$rc" -ne 0 ] && [ ! -f "$TMP/src.json" ] && printf '%s' "$out" | grep -q "never publishes.*'${line%%:*}'" \
    && ok_ "the hub's generator refuses ${line%%:*} in hub/tables.conf and writes nothing" || bad "planted ${line}: rc=$rc $(printf '%s' "$out" | tail -2)"
done
cp "$R/hub/tables.conf" "$C/hub/tables.conf"

# --- a hub-written or node-local table planted in the clinic's list --------------
for line in users:user_id user_property:user_id,property global_property:property; do
  { cat "$R/sync/local/tables.conf"; printf '%s\n' "$line"; } > "$C/sync/local/tables.conf"
  out="$(bash "$C/clinic/scripts/generate-table-config.sh" local 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "${line%%:*} is never captured at a clinic" && ! printf '%s' "$out" | grep -q '^TABLE_INCLUDE_LIST=' \
    && ok_ "the clinic's list refuses ${line%%:*}, and no include list is printed" || bad "planted ${line}: rc=$rc $(printf '%s' "$out" | tail -2)"
done
exit $((fails > 0))
