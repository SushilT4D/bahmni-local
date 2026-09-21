#!/usr/bin/env bash
# Runs every tests/test_*.sh in its own bash; exits 1 if any fails. On Darwin,
# a second pass runs every file again under /bin/bash specifically -- macOS's
# own stock bash 3.2, not whatever `bash` resolves to on PATH (Homebrew's
# bash 5, on a Mac that has it) -- so a script that only works on bash 4+
# (associative arrays, mapfile, ${x,,}, <<< inside a function, ...) is caught
# here, not on a real clinic Mac. Linux runs only the first pass, unchanged.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
run_pass(){ # BASH-BINARY LABEL
  local bin="$1" label="$2" t
  printf '\n########## %s: %s ##########\n' "$label" "$bin"
  for t in "${HERE}"/test_*.sh; do
    printf '\n== %s ==\n' "$(basename "$t")"
    if "$bin" "$t"; then printf '   PASS %s\n' "$(basename "$t")"; else printf '   FAIL %s (%s)\n' "$(basename "$t")" "$label"; failed=$((failed+1)); fi
  done
}
run_pass bash "pass 1"
if [ "$(uname -s)" = Darwin ]; then
  run_pass /bin/bash "pass 2, stock macOS bash 3.2"
fi
printf '\n%s test file(s) failed\n' "$failed"
[ "$failed" -eq 0 ]
