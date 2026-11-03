#!/usr/bin/env bash
# Debezium 3.6 pools with Agroal, which REFUSES min_size > max_size ("Invalid min
# size: greater than max size") where c3p0 tolerated it. The JDBC sink's default
# min_size is 5, so any sink that caps max_size below 5 must state min_size too.
# Nine mysql-local-sink tasks once FAILED on a fresh clinic on exactly this.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fails=0
while IFS= read -r f; do
  max="$(grep -oE '"connection\.pool\.max_size"[[:space:]]*:[[:space:]]*"[0-9]+"' "$f" | grep -oE '[0-9]+' | head -1)"
  [ -n "$max" ] || continue
  min="$(grep -oE '"connection\.pool\.min_size"[[:space:]]*:[[:space:]]*"[0-9]+"' "$f" | grep -oE '[0-9]+' | head -1)"
  eff="${min:-5}"
  if [ "$eff" -le "$max" ] && [ "$eff" -ge 1 ]; then printf '  ok   %s (min %s%s, max %s)\n' "${f#$ROOT/}" "$eff" "${min:+}" "$max"
  else printf '  FAIL %s: min_size %s%s > max_size %s (or < 1)\n' "${f#$ROOT/}" "$eff" "$([ -z "$min" ] && printf ' [the default]')" "$max"; fails=$((fails+1)); fi
done < <(grep -rlE '"connection\.pool\.max_size"' "$ROOT/sync" "$ROOT/clinic/connectors" "$ROOT/hub/connectors" "$ROOT/hub/scripts" 2>/dev/null | grep -v '/tests/' | sort)
exit "$fails"
