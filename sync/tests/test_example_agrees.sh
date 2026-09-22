#!/usr/bin/env bash
# clinic/.env.example must agree with sync/versions.env for every KEY present
# in both. The installer overwrites clinic/.env from sync/versions.env
# (lib.sh versions_put), so a real node never sees a mismatch -- but a
# hand-built node copies the example, and finding 12 caught
# GROOVY_VERSION disagreeing (4.0.22 in the example vs 4.0.17, the corrected
# value, in versions.env) with nothing to catch it.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
fails=0
ok(){ printf '  ok   %s\n' "$*"; }
bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }

EX="$REPO/clinic/.env.example"
V="$REPO/sync/versions.env"
[ -f "$EX" ] || { bad "clinic/.env.example missing"; exit 1; }
[ -f "$V" ] || { bad "sync/versions.env missing"; exit 1; }

# KEY=value per file, comments stripped, quotes/trailing space trimmed --
# same normalization lib.sh's versions_put applies when it copies a value.
kv(){ # FILE
  sed -E 's/[[:space:]]+#.*$//' "$1" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | while IFS='=' read -r k v; do
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+$//')"
    printf '%s=%s\n' "$k" "$v"
  done
}

EX_KV="$(kv "$EX")"
V_KV="$(kv "$V")"

mismatches=0
while IFS='=' read -r k vv; do
  [ -n "$k" ] || continue
  exline="$(printf '%s\n' "$EX_KV" | grep -E "^${k}=" | head -1)"
  [ -n "$exline" ] || continue   # key not in the example: not this test's concern
  ev="${exline#*=}"
  if [ "$ev" = "$vv" ]; then
    ok "agree: $k=$vv"
  else
    bad "disagree: $k is '$ev' in .env.example but '$vv' in sync/versions.env"
    mismatches=$((mismatches + 1))
  fi
done <<EOF
$V_KV
EOF

[ "$mismatches" -eq 0 ] && ok "no KEY present in both files disagrees" || bad "${mismatches} key(s) disagree between clinic/.env.example and sync/versions.env"
exit "$fails"
