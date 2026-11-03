#!/usr/bin/env bash
# pull_image: an image published only for amd64 is pulled as amd64 on an arm64
# host (it runs emulated) instead of failing the native pull every time.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${HERE}/../lib.sh"
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
# fake runtime: only an amd64 image exists
ct(){ printf '%s\n' "$*" >> "$LOG"; case "$*" in "pull --platform linux/amd64 "*) return 0 ;; pull*) return 1 ;; esac; }
: > "$LOG"; pull_image acme/odoo:1 arm64 >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok_ "arm64: amd64-only image pulled" || bad "arm64: pull failed rc=$rc"
grep -q -- '--platform linux/amd64 acme/odoo:1' "$LOG" && ok_ "arm64: fell back to linux/amd64" || bad "arm64: no amd64 fallback: $(cat "$LOG")"
: > "$LOG"; pull_image acme/odoo:1 x86_64 >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok_ "x86_64: a failed pull stays failed" || bad "x86_64: pull reported success"
grep -q -- '--platform' "$LOG" && bad "x86_64: tried a platform override" || ok_ "x86_64: no platform override"
exit $((fails > 0))
