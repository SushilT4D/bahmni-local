#!/usr/bin/env bash
# The clinic runs from one compose file (plus the macOS one), and a COMPOSE_FILE
# that names a missing file stops the installer with the fix.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ ! -e "$C/docker-compose.override.yml" ] && ok_ "no override file" || bad "docker-compose.override.yml exists again"
grep -q 'put COMPOSE_FILE docker-compose.yml:docker-compose.macos.yml' "${HERE}/../tasks/020-env.sh" && ok_ "020 selects the two files on macOS" || bad "020 does not select docker-compose.yml:docker-compose.macos.yml"
run(){ ( CLINIC_DIR="$TMP" INSTALL_DIR="${HERE}/.." DRY=0 bash -c '. "$INSTALL_DIR/lib.sh"; compose_files_exist' 2>&1 ); }
touch "$TMP/docker-compose.yml" "$TMP/docker-compose.macos.yml"
printf 'COMPOSE_FILE=docker-compose.yml:docker-compose.macos.yml\n' > "$TMP/.env"
out="$(run)" && ok_ "existing files pass" || bad "existing files refused: $out"
printf 'COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml:docker-compose.macos.yml\n' > "$TMP/.env"
if out="$(run)"; then bad "a missing file passed"; else
  printf '%s' "$out" | grep -q 'docker-compose.override.yml' && ok_ "a missing file stops it, named" || bad "the stop does not name the file: $out"
fi
printf 'TZ=x\n' > "$TMP/.env"
out="$(run)" && ok_ "no COMPOSE_FILE passes" || bad "no COMPOSE_FILE refused: $out"
exit $((fails > 0))
