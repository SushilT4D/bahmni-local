#!/usr/bin/env bash
# The databases keep their data on named volumes.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
C="${HERE}/../.."
command -v docker >/dev/null 2>&1 || { ok_ "compose not available here; render checks skipped"; exit "$fails"; }
VARS="$(mktemp "${TMPDIR:-/tmp}/macos-volumes.vars.XXXXXX")"; trap 'rm -f "$VARS"' EXIT
{ grep -E '^[A-Z_0-9]+=' "$C/.env.example" | cut -d= -f1
  grep -ohE '\$\{[A-Z_0-9]+:\?' "$C/docker-compose.yml" | sed -E 's/.*\{([A-Z_0-9]+):\?/\1/'
} | sort -u | awk '/PATH$|DIR$|BACKUP$/{print $0"=/p"; next} {print $0"=1"}' > "$VARS"
base="$( cd "$C" && BAHMNI_UI_DIR=/x BAHMNI_CONFIG_DIR=/y BAHMNI_WEB_IMAGE=a/b:1 BAHMNI_CONFIG_IMAGE=a/c:1 CONTAINER_DATA_PATH=/tmp docker compose --env-file "$VARS" --profile local --profile openelis --profile debezium config 2>/dev/null )"
mount_type(){ printf '%s\n' "$base" | grep -B3 -E "target: $1\$" | grep -oE 'type: [a-z]+' | tail -1 | cut -d' ' -f2; }
[ "$(mount_type /var/lib/postgresql/data)" = volume ] && ok_ "PostgreSQL data on a named volume" || bad "PostgreSQL data is a $(mount_type /var/lib/postgresql/data)"
[ "$(mount_type /var/lib/mysql)" = volume ] && ok_ "MySQL data on a named volume" || bad "MySQL data is a $(mount_type /var/lib/mysql)"
exit "$fails"
