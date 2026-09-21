#!/usr/bin/env bash
# scripts/seed-odoo-conf.sh against a fake container runtime: the image's own
# /etc/odoo/odoo.conf is copied out WITHOUT starting it (create+cp+rm, same
# technique as extract-ui-config.sh's pull_tree), an existing conf is left
# alone, a conf that does not look like Bahmni's own is refused and nothing is
# left behind, and DRY makes no container call at all. See the script's own
# header for the manpur/staging incident (an empty bind mount over /etc/odoo
# hides the image's conf -- no db_name, no addons_path).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/seed-odoo-conf.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no scripts/seed-odoo-conf.sh"; exit 1; }

# --- fake runtime: $FAKE_ROOT/<image with / and : as _>/<path in image> -----
mkdir -p "$TMP/bin"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
san(){ printf '%s' "$1" | tr '/:' '__'; }
echo "$*" >> "$FAKE_LOG"
case "$1" in
  create) img="$2"; echo "cid-$(san "$img")" ;;
  cp) src="$2"; dst="$3"; cid="${src%%:*}"; p="${src#*:}"; img="${cid#cid-}"
      [ -f "$FAKE_ROOT/$img$p" ] || exit 1
      cp "$FAKE_ROOT/$img$p" "$dst" ;;
  rm) : ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/fakect"
export FAKE_ROOT="$TMP/images"; mkdir -p "$FAKE_ROOT"
mkimg(){ # NAME REL-PATH CONTENT... : write CONTENT lines to REL-PATH inside the fake image
  local d="$FAKE_ROOT/$(printf '%s' "$1" | tr '/:' '__')" rel="$2"; shift 2
  mkdir -p "$(dirname "$d$rel")"; printf '%s\n' "$@" > "$d$rel"
}
mkimg acme/odoo:1 /etc/odoo/odoo.conf \
  '[options]' \
  'addons_path = /mnt/extra-addons,/opt/bahmni-erp/bahmni-addons,/opt/bahmni-erp/bahmni-addons/community_modules' \
  'data_dir = /var/lib/odoo' 'db_name = odoo' 'dbfilter = .*' 'limit_time_cpu = 1700' 'limit_time_real = 1700'
mkimg acme/notodoo:1 /etc/odoo/odoo.conf '[options]' 'foo = bar'

mk_json(){ printf '{"services":{"odoo":{"image":"%s"}}}' "$1" > "$TMP/compose.json"; }

run(){ # CLINIC_DIR IMAGE, then extra env
  local clinic="$1" image="$2"; shift 2
  mk_json "$image"
  env -i PATH="$TMP/bin:$PATH" HOME="$HOME" \
    CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$TMP/calls.log" \
    DOCKER_HOST="unix:///dev/null" \
    CLINIC_DIR="$clinic" COMPOSE_JSON_FILE="$TMP/compose.json" \
    "$@" bash "$S" 2>&1
}

# === seeded when missing ======================================================
C1="$TMP/clinic1"; mkdir -p "$C1"
: > "$TMP/calls.log"
out="$(run "$C1" acme/odoo:1 DRY=0)"; rc=$?
D1="$C1/config/odoo/odoo.conf"
[ "$rc" -eq 0 ] && ok_ "seeds when missing: exits 0" || bad "rc=$rc: $out"
[ -f "$D1" ] && ok_ "odoo.conf written at config/odoo/odoo.conf" || bad "no file at $D1: $out"
grep -q '^db_name = odoo$' "$D1" 2>/dev/null && grep -q 'bahmni-addons' "$D1" 2>/dev/null && ok_ "seeded file carries the image's own db_name and addons_path" || bad "seeded file content wrong: $(cat "$D1" 2>/dev/null)"
# A clinic runs Odoo on the SHARED PostgreSQL beside openelis: the image's own
# `dbfilter = .*` then matches two databases and /web/login answers 303 to the
# database selector (manpur, 2026-09-21, WITH the image's conf in place).
grep -q '^dbfilter = \^odoo\$$' "$D1" 2>/dev/null && ok_ "dbfilter pinned to the conf's own db_name (^odoo$)" || bad "dbfilter not pinned: $(grep '^dbfilter' "$D1" 2>/dev/null)"
[ "$(grep -c '^dbfilter' "$D1" 2>/dev/null)" = 1 ] && ok_ "exactly one dbfilter line" || bad "dbfilter line count is not 1"
printf '%s' "$out" | grep -q 'seeded from acme/odoo:1' && ok_ "ok line names the source image" || bad "no ok line naming the image: $out"
grep -q '^create acme/odoo:1$' "$TMP/calls.log" && ok_ "a create container ran for the image" || bad "no create call: $(cat "$TMP/calls.log")"
perm="$(stat -f '%Lp' "$D1" 2>/dev/null || stat -c '%a' "$D1" 2>/dev/null)"
[ "$perm" = 644 ] && ok_ "seeded file is mode 644" || bad "seeded file mode is $perm, want 644"

# === left alone when present ==================================================
: > "$TMP/calls.log"
out="$(run "$C1" acme/odoo:1 DRY=0)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "second run (file present) exits 0" || bad "rc=$rc: $out"
printf '%s' "$out" | grep -qi 'skip.*config/odoo/odoo.conf already exists' && ok_ "existing conf: skip, an operator's edits win" || bad "no skip line for an existing conf: $out"
# an existing file that still carries the image's match-everything default is the
# known-bad case (a node seeded by hand from the image): corrected in place, and
# nothing else in the file is touched; any OTHER dbfilter is an operator's choice.
printf '[options]\ndb_name = odoo\ndbfilter = .*\nmy_own = kept\n' > "$D1"
out="$(run "$C1" acme/odoo:1)"
grep -q '^dbfilter = \^odoo\$$' "$D1" && grep -q '^my_own = kept$' "$D1" && ok_ "existing conf with 'dbfilter = .*' is pinned in place, the rest kept" || bad "existing default dbfilter not corrected: $(cat "$D1")"
printf '[options]\ndb_name = odoo\ndbfilter = ^(odoo|test)$\n' > "$D1"
out="$(run "$C1" acme/odoo:1)"
grep -qF 'dbfilter = ^(odoo|test)$' "$D1" && ok_ "an operator's own dbfilter is left alone" || bad "operator's dbfilter was changed: $(cat "$D1")"
: > "$TMP/calls.log"; out="$(run "$C1" acme/odoo:1)"
grep -q '^create' "$TMP/calls.log" && bad "a container was created even though the conf already existed" || ok_ "no create call when the conf already exists"

# === refused when the image's conf is not Bahmni's own =======================
C2="$TMP/clinic2"; mkdir -p "$C2"
out="$(run "$C2" acme/notodoo:1 DRY=0)"; rc=$?
D2="$C2/config/odoo/odoo.conf"
[ "$rc" -ne 0 ] && ok_ "a conf without db_name/bahmni-addons is refused (non-zero exit)" || bad "bad conf accepted: rc=$rc"
printf '%s' "$out" | grep -q "not the Bahmni Odoo image's conf" && ok_ "FAIL names why it was refused" || bad "no FAIL naming the reason: $out"
[ ! -e "$D2" ] && ok_ "nothing left behind at the destination after a refusal" || bad "a file was left behind after a refusal: $(cat "$D2" 2>/dev/null)"

# === DRY=1 makes no container call at all =====================================
C3="$TMP/clinic3"; mkdir -p "$C3"
: > "$TMP/calls.log"
out="$(run "$C3" acme/odoo:1 DRY=1)"; rc=$?
D3="$C3/config/odoo/odoo.conf"
[ "$rc" -eq 0 ] && ok_ "DRY run exits 0" || bad "DRY run rc=$rc: $out"
[ ! -s "$TMP/calls.log" ] && ok_ "DRY run made no container calls at all" || bad "DRY run invoked the container runtime: $(cat "$TMP/calls.log")"
[ ! -e "$D3" ] && ok_ "DRY run wrote nothing" || bad "DRY run wrote a file: $D3"
printf '%s' "$out" | grep -q 'would copy acme/odoo:1' && ok_ "DRY names the image it would copy from" || bad "DRY output missing the would-copy line: $out"

# the node preflight fails on an untracked path, so what the installer creates must be ignored
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
for f in clinic/config/odoo/odoo.conf clinic/files/odoo/filestore/x clinic/files/postgresql/x; do
  ( cd "$REPO_ROOT" && git check-ignore -q "$f" ) && printf '  ok   %s is gitignored\n' "$f" || { printf '  FAIL %s is not gitignored\n' "$f"; fails=$((fails+1)); }
done
exit "$fails"
