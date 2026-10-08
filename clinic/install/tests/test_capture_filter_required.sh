#!/usr/bin/env bash
# test_capture_filter.sh runs the capture filter on records only where docker
# with the pinned Connect image, or a Java with the scripting jars, is at
# hand; elsewhere it skips that half and passes on rendering alone. Under
# REQUIRE_FILTER_RUN=1 a skipped half fails it instead, so a machine that must
# prove the filter cannot pass without running it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/nojars"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/docker"; chmod +x "$TMP/bin/docker"   # a docker that does not answer
run(){ env PATH="$TMP/bin:$PATH" SCRIPTING_JARS_DIR="$TMP/nojars" "$@" bash "${HERE}/test_capture_filter.sh" </dev/null > "$TMP/out" 2>&1; echo $? > "$TMP/rc"; }
run
[ "$(cat "$TMP/rc")" = 0 ] && grep -q '^  skip neither docker' "$TMP/out" && ok_ "without the tools: the record half is skipped, said, and the test passes" || bad "default: rc=$(cat "$TMP/rc") $(grep -E 'skip|FAIL' "$TMP/out" | head -3)"
run REQUIRE_FILTER_RUN=1
[ "$(cat "$TMP/rc")" != 0 ] && grep -q 'FAIL the records were not run, and REQUIRE_FILTER_RUN=1' "$TMP/out" && ok_ "REQUIRE_FILTER_RUN=1 without the tools: the test fails, naming why" || bad "required: rc=$(cat "$TMP/rc") $(grep -E 'skip|FAIL' "$TMP/out" | head -3)"
exit $((fails > 0))
