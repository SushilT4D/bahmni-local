#!/usr/bin/env bash
# Sync-layer boot on a small host (manpur, 1 vCPU, 2026-09-21): kafka-connect
# needs minutes to scan its plugins, its healthcheck allowed ~50 s with no
# start_period, and task 090's single `compose up` died on kafka-ui's
# depends_on: service_healthy. The healthchecks now carry a start_period, kafka's
# JVM probe has a timeout a loaded host can meet, and 090 waits for Connect's
# REST itself on a named budget, bringing kafka-ui up afterwards, non-fatally.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
C="${HERE}/../../docker-compose.yml"; T90="${HERE}/../tasks/090-local-sync.sh"
hc(){ python3 - "$C" "$1" "$2" <<'PY'
import sys,re
src=open(sys.argv[1]).read().split('\n'); svc=sys.argv[2]; key=sys.argv[3]
i=next(n for n,l in enumerate(src) if l.rstrip()==f"  {svc}:")
blk=[]
for l in src[i+1:]:
    if re.match(r'^  [A-Za-z#]', l) and not l.startswith('   '): break
    blk.append(l)
h=next((n for n,l in enumerate(blk) if l.strip()=='healthcheck:'), None)
if h is None: sys.exit(0)
ind=len(blk[h])-len(blk[h].lstrip())
for l in blk[h+1:]:
    if l.strip() and len(l)-len(l.lstrip())<=ind: break
    m=re.match(rf'\s*{key}:\s*(\S+)', l)
    if m: print(m.group(1)); break
PY
}
secs(){ case "$1" in *m) echo $(( ${1%m}*60 ));; *s) echo "${1%s}";; *) echo 0;; esac; }
sp="$(hc kafka-connect start_period)"; [ "$(secs "${sp:-0s}")" -ge 600 ] && ok_ "kafka-connect healthcheck start_period ${sp}" || bad "kafka-connect start_period is '${sp:-unset}', want >= 600s"
sp="$(hc kafka start_period)"; [ "$(secs "${sp:-0s}")" -ge 120 ] && ok_ "kafka healthcheck start_period ${sp}" || bad "kafka start_period is '${sp:-unset}', want >= 120s"
to="$(hc kafka timeout)"; [ "$(secs "${to:-0s}")" -ge 20 ] && ok_ "kafka's JVM probe gets ${to}" || bad "kafka probe timeout is '${to:-unset}', want >= 20s (it starts a JVM)"
code="$(grep -vE '^[[:space:]]*#' "$T90")"
first_up="$(printf '%s\n' "$code" | grep -m1 -- '--profile debezium up -d')"
printf '%s' "$first_up" | grep -q 'kafka-ui' && bad "090's first up still includes kafka-ui (gated on connect's health)" || ok_ "090's first up leaves kafka-ui out"
printf '%s' "$code" | grep -q 'CONNECT_BOOT_TIMEOUT_S:-1800' && ok_ "090 waits for Connect on a named budget (default 1800 s)" || bad "090 has no CONNECT_BOOT_TIMEOUT_S:-1800"
printf '%s' "$code" | grep -qE 'up -d kafka-ui.*\|\| *warn' && ok_ "kafka-ui comes up afterwards and cannot stop the install" || bad "kafka-ui up is missing or fatal"
# 090's task-state verdict, run with real jq over fixtures. The filters are lifted
# from the task file itself so the test cannot drift from what runs.
eval "$(grep -E "^(JQ_NOT_RUNNING|JQ_FAILED)=" "$T90")"
[ -n "${JQ_NOT_RUNNING:-}" ] && [ -n "${JQ_FAILED:-}" ] || bad "090 does not define JQ_NOT_RUNNING / JQ_FAILED"
fx(){ printf '{"a":{"status":{"tasks":[{"state":"%s"}]}},"b":{"status":{"tasks":[%s]}}}' "$1" "$2"; }
r="$(fx RUNNING '{"state":"RUNNING"}' | jq -r "$JQ_NOT_RUNNING" | tr '\n' ' ')"; [ -z "$r" ] && ok_ "all RUNNING -> nothing pending" || bad "all RUNNING reported pending: $r"
r="$(fx RUNNING '' | jq -r "$JQ_NOT_RUNNING" | tr '\n' ' ')"; [ "$r" = "b " ] && ok_ "a connector with NO tasks counts as not running" || bad "empty task list passed as running: '$r'"
r="$(fx UNASSIGNED '{"state":"RUNNING"}' | jq -r "$JQ_NOT_RUNNING" | tr '\n' ' ')"; [ "$r" = "a " ] && ok_ "UNASSIGNED is pending" || bad "UNASSIGNED not pending: '$r'"
r="$(fx FAILED '{"state":"RUNNING"}' | jq -r "$JQ_FAILED" | tr '\n' ' ')"; [ "$r" = "a " ] && ok_ "FAILED is named at once" || bad "FAILED not named: '$r'"
printf '%s' "$code" | grep -q 'CONNECT_TASKS_TIMEOUT_S:-600' && ok_ "090 polls task state on a named budget" || bad "090 has no CONNECT_TASKS_TIMEOUT_S:-600"
( cd "${HERE}/../.." && command -v docker >/dev/null 2>&1 && [ -f .env ] ) && { ( cd "${HERE}/../.." && BAHMNI_UI_DIR="${BAHMNI_UI_DIR:-/tmp/ui}" BAHMNI_CONFIG_DIR="${BAHMNI_CONFIG_DIR:-/tmp/cfg}" BAHMNI_WEB_IMAGE="${BAHMNI_WEB_IMAGE:-x/web:1}" BAHMNI_CONFIG_IMAGE="${BAHMNI_CONFIG_IMAGE:-x/config:1}" docker compose --profile debezium config -q 2>/dev/null ) && ok_ "compose config validates" || bad "compose config does not validate"; } || ok_ "compose validation skipped (no docker or no .env here)"
exit "$fails"
