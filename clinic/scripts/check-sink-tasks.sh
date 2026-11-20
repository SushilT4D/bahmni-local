#!/bin/bash
# Check all sink tasks on the local Kafka Connect worker.
# Usage: ./check-sink-tasks.sh [host] [--restart|--restart-all]
# Exit codes: 0 all running, 1 task failure, 2 unreachable.
usage(){
  printf '%s\n' \
    'Usage: ./check-sink-tasks.sh [host] [--restart|--restart-all]' \
    '  --restart      restart failed tasks after reporting' \
    '  --restart-all  restart every task'
}
# The host and restart flags may appear in any order.
HOST=""
RESTART=false; RESTART_ALL=false
for a in "$@"; do
  case "$a" in
    --restart)      RESTART=true ;;
    --restart-all)  RESTART=true; RESTART_ALL=true ;;
    -h|--help)      usage; exit 0 ;;
    --*)            echo "unknown option: $a  (see --help)" >&2; exit 2 ;;
    *)
      if [ -z "$HOST" ]; then HOST="$a"
      else echo "unexpected extra argument: $a  (see --help)" >&2; exit 2; fi ;;
  esac
done
HOST="${HOST:-localhost}"
URL="http://${HOST}:8083"

# Fetch the registered connectors and inspect each task state.
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
# Report the overall task result.
if [ "$bad" -gt 0 ]; then
    echo "✗ ${bad}/${total} connectors have a task that is not RUNNING."
    echo "  Most likely: idle longer than MySQL wait_timeout (28800s) closes the"
    echo "  pooled connection; the next write fails and Connect kills the task as"
    echo "  unrecoverable. Re-run with --restart, then fix the pool lifetime properly."
    exit 1
fi
echo "✓ ${total}/${total} connectors: all tasks RUNNING."
echo "  NOTE: a task with nothing to write cannot prove its connection is alive."
echo "  RUNNING here means 'not yet failed', not 'verified working' — confirm with row counts."
