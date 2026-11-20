#!/usr/bin/env bash
# pull_image: an image published only for amd64 is pulled as amd64 (it runs
# emulated) instead of failing the native arm64 pull every time.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HERE}/../lib.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
# fake runtime: only an amd64 image exists
ct(){ printf '%s\n' "$*" >> "$LOG"; case "$*" in "pull --platform linux/amd64 "*) return 0 ;; pull*) return 1 ;; esac; }
: > "$LOG"; pull_image acme/odoo:1 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok_ "amd64-only image pulled" || bad "pull failed rc=$rc"
grep -q -- '--platform linux/amd64 acme/odoo:1' "$LOG" && ok_ "fell back to linux/amd64" || bad "no amd64 fallback: $(cat "$LOG")"
exit $((fails > 0))
