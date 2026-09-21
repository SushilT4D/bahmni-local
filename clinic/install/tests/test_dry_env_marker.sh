#!/usr/bin/env bash
# A dry run left a real clinic/.env behind, and the real run that followed
# refused it as "already exists" (manpur rebuild, 2026-09-21). A dry-run render
# is now stamped on its first line; preflight moves a stamped file aside on a
# real run (never deletes it) and still refuses an unstamped one.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T00="${HERE}/../tasks/000-preflight.sh"; T20="${HERE}/../tasks/020-env.sh"
MARK='# DRY-RUN RENDER'

grep -vE '^[[:space:]]*#' "$T20" | grep -q 'DRY-RUN RENDER' && ok_ "020 stamps a dry-run render" || bad "020 does not stamp a dry-run render"

blk="$(sed -n '/# fresh-only:begin/,/# fresh-only:end/p' "$T00")"
[ -n "$blk" ] || bad "000 has no fresh-only block"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
run(){ env -i PATH="$PATH" DRY="$1" CLINIC_DIR="$W" PLATFORM=linux bash -c ". '${HERE}/../lib.sh'; ${blk}" 2>&1; }

rm -f "$W"/.env*; out="$(run 0)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "no .env: passes" || bad "no .env exits $rc: $out"

printf 'A=1\n' > "$W/.env"; out="$(run 0)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'already exists' && ok_ "a live .env is still refused" || bad "a live .env was accepted (rc=$rc): $out"
[ -f "$W/.env" ] && ok_ "the refused .env is left in place" || bad "the refused .env was moved"

printf '%s -- x\nA=1\n' "$MARK" > "$W/.env"; out="$(run 0)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "a dry-run leftover does not stop a real run" || bad "a dry-run leftover stopped a real run (rc=$rc): $out"
[ ! -e "$W/.env" ] && ok_ "the leftover is out of the way" || bad "the leftover is still clinic/.env"
n="$(ls "$W"/.env.dryrun.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" = 1 ] && ok_ "the leftover was moved aside, not deleted" || bad "expected one .env.dryrun.* file, found $n"

rm -f "$W"/.env*; printf '%s -- x\nA=1\n' "$MARK" > "$W/.env"; out="$(run 1)"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$W/.env" ] && ok_ "a second dry run passes and moves nothing" || bad "second dry run: rc=$rc, .env present=$([ -f "$W/.env" ] && echo yes || echo no): $out"

# each of these holds generated passwords, and the repository is public
REPO="$(cd "${HERE}/../../.." && pwd)"
for f in clinic/.env.dryrun.20260921T000000Z clinic/.env.rejected clinic/.env.render.abc123; do
  ( cd "$REPO" && git check-ignore -q "$f" ) && ok_ "$f is gitignored" || bad "$f is NOT gitignored"
done
exit "$fails"
