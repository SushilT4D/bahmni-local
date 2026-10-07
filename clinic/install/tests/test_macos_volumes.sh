#!/usr/bin/env bash
# On macOS the two databases keep their data on named volumes inside the
# podman machine: a virtiofs bind mount from the host is not a POSIX
# filesystem, and PostgreSQL crash-recovers on it under load. Linux keeps the
# host bind mounts.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
C="${HERE}/../.."; T20="${HERE}/../tasks/020-env.sh"
[ -f "$C/docker-compose.macos.yml" ] && ok_ "docker-compose.macos.yml exists" || { bad "no docker-compose.macos.yml"; exit 1; }
blk="$(sed -n '/# macos-compose:begin/,/# macos-compose:end/p' "$T20")"
printf '%s' "$blk" | grep -q 'put COMPOSE_FILE docker-compose.yml:docker-compose.macos.yml' && ok_ "020 selects the macOS file through COMPOSE_FILE" || bad "020 does not put COMPOSE_FILE on macOS"
printf '%s' "$blk" | grep -q '"${PLATFORM}" = macos' && ok_ "only on macOS" || bad "COMPOSE_FILE is not gated on the platform"
command -v docker >/dev/null 2>&1 || { ok_ "compose not available here; render checks skipped"; exit "$fails"; }
# Every variable the compose files need gets a stand-in from .env.example and
# the required (:?) references, so the render never depends on a node's own
# clinic/.env being present in this checkout.
VARS="$(mktemp "${TMPDIR:-/tmp}/macos-volumes.vars.XXXXXX")"; trap 'rm -f "$VARS"' EXIT
{ grep -E '^[A-Z_0-9]+=' "$C/.env.example" | cut -d= -f1
  grep -ohE '\$\{[A-Z_0-9]+:\?' "$C/docker-compose.yml" "$C/docker-compose.macos.yml" | sed -E 's/.*\{([A-Z_0-9]+):\?/\1/'
} | sort -u | awk '/PATH$|DIR$|BACKUP$/{print $0"=/p"; next} {print $0"=1"}' > "$VARS"
render(){ ( cd "$C" && BAHMNI_UI_DIR=/x BAHMNI_CONFIG_DIR=/y BAHMNI_WEB_IMAGE=a/b:1 BAHMNI_CONFIG_IMAGE=a/c:1 CONTAINER_DATA_PATH=/tmp COMPOSE_FILE="$1" docker compose --env-file "$VARS" --profile local --profile openelis --profile debezium config 2>/dev/null ); }
mount_type(){ # RENDERED TARGET -> type of the mount with that target
  printf '%s\n' "$1" | grep -B3 -E "target: $2\$" | grep -oE 'type: [a-z]+' | tail -1 | cut -d' ' -f2
}
mac="$(render docker-compose.yml:docker-compose.macos.yml)"
[ -n "$mac" ] && ok_ "the two-file set renders" || bad "the two-file set does not render"
[ "$(mount_type "$mac" /var/lib/postgresql/data)" = volume ] && ok_ "macOS: PostgreSQL data on a named volume" || bad "macOS: PostgreSQL data is a $(mount_type "$mac" /var/lib/postgresql/data)"
[ "$(mount_type "$mac" /var/lib/mysql)" = volume ] && ok_ "macOS: MySQL data on a named volume" || bad "macOS: MySQL data is a $(mount_type "$mac" /var/lib/mysql)"
printf '%s\n' "$mac" | grep -q 'target: /filestore' && ok_ "macOS: the PostgreSQL filestore bind is kept" || bad "macOS: the filestore bind was lost"
printf '%s\n' "$mac" | grep -q 'target: /etc/mysql/conf.d/sync-tuning.cnf' && ok_ "macOS: the MySQL tuning file is kept" || bad "macOS: the tuning file mount was lost"
lin="$(render docker-compose.yml)"
[ "$(mount_type "$lin" /var/lib/postgresql/data)" = bind ] && ok_ "Linux: PostgreSQL data stays a host bind" || bad "Linux: PostgreSQL data is a $(mount_type "$lin" /var/lib/postgresql/data)"
[ "$(mount_type "$lin" /var/lib/mysql)" = bind ] && ok_ "Linux: MySQL data stays a host bind" || bad "Linux: MySQL data is a $(mount_type "$lin" /var/lib/mysql)"
exit "$fails"
