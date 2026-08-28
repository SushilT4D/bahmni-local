#!/bin/bash
# check-sink-tasks.sh — sweep ALL connectors and judge on TASK state, not connector state.
#
# Why this exists (BL-038/BL-039, 2026-08-20): a Kafka Connect connector object stays
# RUNNING while its task is FAILED. We had 7 of 19 sink tasks dead — the whole patient
# registration path — while every connector, every container, and the source connector
# all reported healthy. The existing check-sink-connectors.sh inspects ONE connector at
# a time and only pretty-prints its JSON, so nothing alarms.
#
# Exit codes:  0 = all tasks RUNNING   1 = at least one task not RUNNING   2 = unreachable
#
# Usage: ./check-sink-tasks.sh [host] [--restart|--restart-all]
#        --restart      restart any FAILED task after reporting (BL-039: Connect does
#                       NOT auto-restart failed tasks; recovery is manual by default)
#        --restart-all  restart EVERY task, healthy-looking ones included. Use this after
#                       any database restart: a task with nothing to write cannot discover
#                       that its pooled connection is dead, so it reports RUNNING and then
#                       dies on its FIRST record. They fail one at a time, which looks like
#                       an intermittent sync bug and is really one stale pool.

# Arguments are order-independent: the host is the one positional, flags are flags.
# The previous version read the host as "$1" and only special-cased the literal
# "--restart", so `check-sink-tasks.sh --restart-all` — the form this script's own
# usage block recommends after a database restart — took the flag as the hostname and
# died with "cannot reach Kafka Connect at http://--restart-all:8083" without
# restarting anything. An unknown flag now fails loudly rather than becoming a host.
HOST=""
RESTART=false; RESTART_ALL=false
for a in "$@"; do
  case "$a" in
    --restart)      RESTART=true ;;
    --restart-all)  RESTART=true; RESTART_ALL=true ;;
    -h|--help)      sed -n '2,19p' "$0"; exit 0 ;;
    --*)            echo "unknown option: $a  (see --help)" >&2; exit 2 ;;
    *)
      if [ -z "$HOST" ]; then HOST="$a"
      else echo "unexpected extra argument: $a  (see --help)" >&2; exit 2; fi ;;
  esac
done
HOST="${HOST:-localhost}"
URL="http://${HOST}:8083"

CONNECTORS=$(curl -s --connect-timeout 5 "${URL}/connectors" | tr ',' '\n' | tr -d '[]"')
if [ -z "$CONNECTORS" ]; then
    echo "✗ cannot reach Kafka Connect at ${URL}"; exit 2
fi

bad=0; total=0
printf '%-44s %-10s %s\n' "CONNECTOR" "CONNECTOR" "TASKS"
for c in $CONNECTORS; do
    total=$((total+1))
    st=$(curl -s "${URL}/connectors/${c}/status")
    conn=$(echo "$st" | grep -o '"state":"[A-Z]*"' | head -1 | cut -d'"' -f4)
    tasks=$(echo "$st" | grep -o '"state":"[A-Z]*"' | tail -n +2 | cut -d'"' -f4 | tr '\n' ' ')
    [ -z "$tasks" ] && tasks="NO_TASKS"
    mark=" "
    if echo "$tasks" | grep -qvE '^(RUNNING )+$'; then mark="✗"; bad=$((bad+1)); fi
    printf '%s %-42s %-10s %s\n' "$mark" "$c" "$conn" "$tasks"

    if { [ "$mark" = "✗" ] || [ "$RESTART_ALL" = true ]; } && [ "$RESTART" = true ]; then
        code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${URL}/connectors/${c}/tasks/0/restart")
        echo "    → restart requested (HTTP $code)"
    fi
done

echo
if [ "$bad" -gt 0 ]; then
    echo "✗ ${bad}/${total} connectors have a task that is not RUNNING."
    echo "  Most likely BL-039: idle longer than MySQL wait_timeout (28800s) closes the"
    echo "  pooled connection; the next write fails and Connect kills the task as"
    echo "  unrecoverable. Re-run with --restart, then fix the pool lifetime properly."
    exit 1
fi
echo "✓ ${total}/${total} connectors: all tasks RUNNING."
echo "  NOTE: a task with nothing to write cannot prove its connection is alive."
echo "  RUNNING here means 'not yet failed', not 'verified working' — confirm with row counts."
