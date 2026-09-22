#!/usr/bin/env bash
# A dry run on a host with no Docker must not fail the compose-plugin check
# that the real run's Docker install satisfies; it says what it would verify.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# a PATH with no docker and no podman: bash and the coreutils the function calls, a sudo that does nothing
mkdir -p "$W/bin"
for t in bash sh curl id grep cut sed awk cat printf uname tr head mktemp dirname basename date; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$W/bin/$t"; done
printf '#!%s\nexit 0\n' "$(command -v bash)" > "$W/bin/sudo"; chmod +x "$W/bin/sudo"
printf '#!%s\nexit 0\n' "$(command -v bash)" > "$W/bin/sg"; chmod +x "$W/bin/sg"
out="$(env -i PATH="$W/bin" HOME="$W" USER=tester DRY=1 RUNTIME=docker bash -c ". '${HERE}/../lib.sh'; . '${HERE}/../host-linux.sh'; host_linux" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "dry run without docker exits 0" || bad "dry run without docker exits $rc: $out"
printf '%s' "$out" | grep -q 'compose' && ok_ "dry run mentions the compose check it would make" || bad "dry run says nothing about compose: $out"
printf '%s' "$out" | grep -qi 'plugin missing' && bad "dry run still FAILs on the missing plugin" || ok_ "no plugin-missing FAIL under dry run"
exit "$fails"
