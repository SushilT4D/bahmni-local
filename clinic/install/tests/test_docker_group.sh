#!/usr/bin/env bash
# A shell opened before the login user joined the docker group cannot reach
# the daemon. install.sh (on any resume) and seed.sh re-run themselves under
# the group instead of stopping on "permission denied".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
mkdir -p "$TMP/bin"
# docker answers only once the group is active (the re-exec marks that)
printf '#!/bin/sh\n[ "$1" = info ] && [ "${_KRAFT_SG:-}" != 1 ] && { echo "permission denied" >&2; exit 1; }\nexit 0\n' > "$TMP/bin/docker"
printf '#!/bin/sh\n[ "$1" = -nG ] && { echo "bahmni docker"; exit 0; }\nexec /usr/bin/id "$@"\n' > "$TMP/bin/id"
printf '#!/bin/sh\necho "SG $*" >> "$SG_LOG"\n' > "$TMP/bin/sg"
chmod +x "$TMP/bin/"*
run(){ env PATH="$TMP/bin:$PATH" SG_LOG="$TMP/sg.log" PLATFORM=linux RUNTIME=docker DRY=0 _KRAFT_SG="${SGSET:-}" \
  bash -c ". '${HERE}/../lib.sh'; docker_group_reexec \"\$@\"; echo CONTINUED" _ "$@" 2>&1; }
: > "$TMP/sg.log"; out="$(run clinic/install/install.sh --clinic manpur --from 050)"
grep -q "^SG docker -c .*install.sh --clinic manpur --from 050" "$TMP/sg.log" && ok_ "re-runs the same command under the docker group" || bad "no sg re-exec: $(cat "$TMP/sg.log") / $out"
case "$out" in *CONTINUED*) bad "carried on without the group" ;; *) ok_ "does not carry on without the group" ;; esac
: > "$TMP/sg.log"; out="$(SGSET=1 run x)"
[ ! -s "$TMP/sg.log" ] && case "$out" in *CONTINUED*) true ;; *) false ;; esac && ok_ "under the group: carries on, no second re-exec" || bad "looped: $(cat "$TMP/sg.log")"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/docker"; : > "$TMP/sg.log"; out="$(run x)"
[ ! -s "$TMP/sg.log" ] && ok_ "docker already reachable: nothing to do" || bad "re-exec when not needed"
for s in install.sh seed.sh; do grep -q 'docker_group_reexec' "${HERE}/../$s" && ok_ "$s calls it" || bad "$s does not call docker_group_reexec"; done
exit $((fails > 0))
