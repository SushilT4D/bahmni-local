#!/usr/bin/env bash
# scripts/fix-mount-ownership.sh against a fake container runtime + a fake
# `stat`: only a genuine read-write bind-mounted DIRECTORY under CLINIC_DIR
# gets chowned, only when its current owner differs from the image's uid:gid,
# a root-uid image is skipped entirely, DRY never runs a container, and a
# chown that does not take is a WARN on macOS but a FAIL (non-zero exit) on
# Linux. See scripts/fix-mount-ownership.sh's header for the manpur incident
# (Odoo uid 101 could not write a dir owned 1000:1000 by mkdir -p).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/fix-mount-ownership.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no scripts/fix-mount-ownership.sh"; exit 1; }

# --- fake runtime -------------------------------------------------------------
# $FAKE_ROOT/images.tsv : image<TAB>uid<TAB>gid, what that image "runs as".
# $OWNER_STORE          : realpath<TAB>uid<TAB>gid, the fake's notion of who
#                          owns a directory -- real chown needs root, which this
#                          sandbox does not have, so ownership is tracked here
#                          instead of on the real filesystem, and a fake `stat`
#                          (ahead of the real one on PATH) reads it back.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
lookup(){ awk -F'\t' -v img="$1" '$1==img{print;exit}' "$FAKE_ROOT/images.tsv"; }
store_set(){ # PATH UID GID
  python3 - "$OWNER_STORE" "$1" "$2" "$3" <<'PY'
import sys
store, path, u, g = sys.argv[1:5]
try:
    lines = open(store).read().splitlines()
except FileNotFoundError:
    lines = []
lines = [l for l in lines if not l.startswith(path + "\t")]
lines.append("%s\t%s\t%s" % (path, u, g))
open(store, "w").write("\n".join(lines) + "\n")
PY
}
if [ "$1" = run ] && [ "$3" = --entrypoint ] && [ "$4" = id ]; then
  image="$5"; flag="$6"
  line="$(lookup "$image")"
  uid="$(printf '%s' "$line" | cut -f2)"; gid="$(printf '%s' "$line" | cut -f3)"
  [ -n "$uid" ] || { echo "fakect: unknown image $image" >&2; exit 1; }
  case "$flag" in -u) printf '%s\n' "$uid" ;; -g) printf '%s\n' "$gid" ;; esac
  exit 0
elif [ "$1" = run ] && [ "$3" = -u ] && [ "$4" = 0 ] && [ "$5" = --entrypoint ] && [ "$6" = chown ]; then
  bind="$8"; src="${bind%%:*}"; uidgid="${11}"
  rp="$(cd "$src" && pwd)" || exit 1
  [ "${FAKE_NOOP_CHOWN:-0}" = 1 ] || store_set "$rp" "${uidgid%%:*}" "${uidgid##*:}"
  exit 0
else
  exit 2
fi
SH
chmod +x "$TMP/bin/fakect"
cat > "$TMP/bin/stat" <<'SH'
#!/usr/bin/env bash
# stands in for BOTH GNU `stat -c FMT PATH` and BSD `stat -f FMT PATH`: the
# script's owner_of() tries -c then -f, and only the format (%u / %g) and the
# path matter here.
fmt="$2"; path="$3"
rp="$(cd "$path" 2>/dev/null && pwd)" || exit 1
line="$(python3 - "$OWNER_STORE" "$rp" <<'PY'
import sys
store, path = sys.argv[1], sys.argv[2]
try:
    lines = open(store).read().splitlines()
except FileNotFoundError:
    lines = []
match = ""
for l in lines:
    if l.startswith(path + "\t"):
        match = l
print(match)
PY
)"
if [ -z "$line" ]; then u=1000; g=1000; else u="$(printf '%s' "$line" | cut -f2)"; g="$(printf '%s' "$line" | cut -f3)"; fi
case "$fmt" in %u) printf '%s\n' "$u" ;; %g) printf '%s\n' "$g" ;; *) exit 1 ;; esac
SH
chmod +x "$TMP/bin/stat"
export FAKE_ROOT="$TMP/fake"; mkdir -p "$FAKE_ROOT"
printf 'acme/odoo:1\t101\t101\nacme/kafka:1\t1000\t1000\nacme/root:1\t0\t0\n' > "$FAKE_ROOT/images.tsv"

# --- fixture: a clinic dir with the mount shapes the script must tell apart ---
mk_fixture(){
  local clinic="$1"
  mkdir -p "$clinic/data/odoo" "$clinic/config/odoo-ro" "$clinic/data/kafka" "$clinic/data/kafka-connect"
  echo 'not a dir' > "$clinic/config/odoo-file.conf"
  mkdir -p "$TMP/outside"
  cat > "$TMP/compose.json" <<JSON
{
  "services": {
    "odoo": {
      "image": "acme/odoo:1",
      "volumes": [
        {"type": "bind", "source": "${clinic}/data/odoo", "target": "/var/lib/odoo"},
        {"type": "bind", "source": "${clinic}/config/odoo-ro", "target": "/etc/odoo-ro", "read_only": true},
        {"type": "bind", "source": "${clinic}/config/odoo-file.conf", "target": "/etc/odoo.conf"},
        {"type": "volume", "source": "named-vol", "target": "/var/named"},
        {"type": "bind", "source": "${TMP}/outside", "target": "/outside"}
      ]
    },
    "kafka": {
      "image": "acme/kafka:1",
      "volumes": [
        {"type": "bind", "source": "${clinic}/data/kafka", "target": "/var/lib/kafka/data"}
      ]
    },
    "kafka-connect": {
      "image": "acme/root:1",
      "volumes": [
        {"type": "bind", "source": "${clinic}/data/kafka-connect", "target": "/kafka/connect/data"}
      ]
    }
  }
}
JSON
}

run(){ # CLINIC_DIR, then extra env, then the script
  local clinic="$1"; shift
  env -i PATH="$TMP/bin:$PATH" HOME="$HOME" \
    CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$TMP/calls.log" OWNER_STORE="$TMP/owners.tsv" \
    DOCKER_HOST="unix:///dev/null" \
    CLINIC_DIR="$clinic" COMPOSE_JSON_FILE="$TMP/compose.json" \
    "$@" bash "$S" 2>&1
}

# === scenario 1: a normal Linux run -- chown, skip, root-skip, untouched -----
mk_fixture "$TMP/clinic"
: > "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic/data/odoo" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic/data/kafka" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic/data/kafka-connect" && pwd)" >> "$TMP/owners.tsv"
: > "$TMP/calls.log"
out="$(run "$TMP/clinic" env DRY=0 PLATFORM=linux)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "normal run exits 0" || bad "normal run rc=$rc: $out"
printf '%s' "$out" | grep -q 'odoo: data/odoo -> 101:101' && ok_ "odoo's rw dir chowned to 101:101" || bad "no ok line for odoo/data/odoo: $out"
grep -q 'data/odoo:/fix' "$TMP/calls.log" && ok_ "a chown container ran for data/odoo" || bad "no chown call for data/odoo: $(cat "$TMP/calls.log")"
grep -q 'odoo-ro' "$TMP/calls.log" && bad "a read-only mount was touched" || ok_ "read-only mount untouched (odoo-ro never named in any call)"
grep -q 'odoo-file.conf' "$TMP/calls.log" && bad "a file mount was chowned" || ok_ "file mount untouched (not a directory)"
grep -q 'named-vol' "$TMP/calls.log" && bad "a named volume was touched" || ok_ "named volume untouched"
grep -q "$TMP/outside" "$TMP/calls.log" && bad "a directory outside CLINIC_DIR was touched" || ok_ "directory outside CLINIC_DIR untouched"
printf '%s' "$out" | grep -q 'kafka-connect.*root' && ok_ "root-uid service (kafka-connect) reported as skipped" || bad "no skip line naming kafka-connect as root: $out"
grep -q 'data/kafka-connect:/fix' "$TMP/calls.log" && bad "chown ran for the root-uid service's directory" || ok_ "no chown call for the root-uid service (kafka-connect)"
printf '%s' "$out" | grep -qE 'kafka: data/kafka already 1000:1000' && ok_ "kafka's dir already correct -> skip, no chown call" || bad "no skip line for kafka's already-correct owner: $out"
grep -q 'data/kafka:/fix' "$TMP/calls.log" && bad "chown ran for an already-correct directory (kafka)" || ok_ "no chown call for kafka (already correct)"

# === scenario 2: DRY=1 -- no run call of any kind, id probe included --------
mk_fixture "$TMP/clinic2"
: > "$TMP/calls.log"
out="$(run "$TMP/clinic2" env DRY=1 PLATFORM=linux)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "DRY run exits 0" || bad "DRY run rc=$rc: $out"
[ -s "$TMP/calls.log" ] && bad "DRY run invoked the container runtime: $(cat "$TMP/calls.log")" || ok_ "DRY run made no container calls at all (id probe included)"
printf '%s' "$out" | grep -q 'would chown odoo: data/odoo' && ok_ "DRY names the service and directory it would chown" || bad "DRY output missing the would-chown line: $out"

# === scenario 3: a chown that does not take -- macOS WARNs, exits 0 ---------
mk_fixture "$TMP/clinic3"
: > "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic3/data/odoo" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic3/data/kafka" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic3/data/kafka-connect" && pwd)" >> "$TMP/owners.tsv"
out="$(run "$TMP/clinic3" env DRY=0 PLATFORM=macos FAKE_NOOP_CHOWN=1)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "macOS: a chown that does not take still exits 0" || bad "macOS no-op chown rc=$rc: $out"
printf '%s' "$out" | grep -qi 'WARN.*odoo: data/odoo' && ok_ "macOS: a chown that does not take is a WARN" || bad "macOS: no WARN for the no-op chown: $out"

# === scenario 4: the same no-op chown on Linux -- FAIL, non-zero exit -------
mk_fixture "$TMP/clinic4"
: > "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic4/data/odoo" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic4/data/kafka" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$TMP/clinic4/data/kafka-connect" && pwd)" >> "$TMP/owners.tsv"
out="$(run "$TMP/clinic4" env DRY=0 PLATFORM=linux FAKE_NOOP_CHOWN=1)"; rc=$?
[ "$rc" -ne 0 ] && ok_ "Linux: a chown that does not take exits non-zero" || bad "Linux no-op chown rc=$rc (wanted non-zero): $out"
printf '%s' "$out" | grep -qi 'FAIL.*odoo: data/odoo' && ok_ "Linux: a chown that does not take is a FAIL" || bad "Linux: no FAIL for the no-op chown: $out"

# === scenario 5: a directory holding git-tracked files is never chowned -----
# (fix-round-1: a tracked dir chowned to a container uid would break the next
# `git pull` for the login user -- no candidate directory is tracked today,
# but the sweep must not assume that stays true).
GC="$TMP/clinicgit"
mk_fixture "$GC"
echo tracked > "$GC/data/odoo/.gitkeep"
( cd "$GC" && git init -q && git -c user.email=t@t -c user.name=t add data/odoo/.gitkeep && git -c user.email=t@t -c user.name=t commit -q -m seed ) >/dev/null
: > "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$GC/data/odoo" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$GC/data/kafka" && pwd)" >> "$TMP/owners.tsv"
printf '%s\t1000\t1000\n' "$(cd "$GC/data/kafka-connect" && pwd)" >> "$TMP/owners.tsv"
: > "$TMP/calls.log"
out="$(run "$GC" env DRY=0 PLATFORM=linux)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "a run against a checkout with a tracked dir still exits 0" || bad "rc=$rc: $out"
printf '%s' "$out" | grep -qi 'skip.*odoo: data/odoo holds git-tracked files' && ok_ "a git-tracked directory is skipped, not chowned, and the login user keeps it" || bad "no skip line for the tracked directory: $out"
grep -q 'data/odoo:/fix' "$TMP/calls.log" && bad "chown ran for a directory that holds git-tracked files" || ok_ "no chown call for the git-tracked directory"

exit "$fails"
