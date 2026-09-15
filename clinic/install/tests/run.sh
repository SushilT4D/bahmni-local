#!/usr/bin/env bash
# Runs every tests/test_*.sh in its own bash; exits 1 if any fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for t in "${HERE}"/test_*.sh; do
  printf '\n== %s ==\n' "$(basename "$t")"
  if bash "$t"; then printf '   PASS %s\n' "$(basename "$t")"; else printf '   FAIL %s\n' "$(basename "$t")"; failed=$((failed+1)); fi
done
printf '\n%s test file(s) failed\n' "$failed"
[ "$failed" -eq 0 ]
