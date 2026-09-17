#!/usr/bin/env bash
set -u; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; fails=0
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
export DRY=1 HUB_DIR="$TMP"; . "$HERE/../lib.sh"
write_jaas "$TMP/j.conf" 'adm1n' 'fl33t'
assert_eq "mode 600" "$(stat -c %a "$TMP/j.conf" 2>/dev/null || stat -f %Lp "$TMP/j.conf")" "600"
assert_eq "admin line" "$(grep -c 'user_admin="adm1n"' "$TMP/j.conf")" "1"
assert_eq "mirrormaker line" "$(grep -c 'user_mirrormaker="fl33t";' "$TMP/j.conf")" "1"
assert_eq "no placeholders" "$(grep -c '\${' "$TMP/j.conf")" "0"
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
