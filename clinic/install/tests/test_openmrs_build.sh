#!/usr/bin/env bash
# openmrs/build-native.sh against a fake container runtime: the native arm64
# image is assembled from the source's own /usr/local/tomcat, /openmrs,
# /etc/bahmni-emr, /home/bahmni via create+cp+rm (the source is never run),
# skipped when its labels already match the current source+base image ids,
# rebuilt when either id changes or --force is given, refused when the
# extracted tree carries no WAR or the built image is not arm64, and DRY
# never touches the runtime at all. See openmrs/Dockerfile.native and
# task1b-report.md for the recipe this proves.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../openmrs/build-native.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
[ -f "$S" ] || { bad "no openmrs/build-native.sh"; exit 1; }

san(){ printf '%s' "$1" | tr '/:' '__'; }
mkdir -p "$TMP/bin" "$TMP/clinic" "$TMP/images"
export FAKE_ROOT="$TMP/images" FAKE_LOG="$TMP/calls.log"

# --- fake runtime: $FAKE_ROOT/<image, / and : as _>/ is that image's filesystem;
# a built image also gets .id / .arch / .labels written by the fake `build`.
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
san(){ printf '%s' "$1" | tr '/:' '__'; }
echo "$*" >> "$FAKE_LOG"
case "$1" in
  image)
    shift
    [ "$1" = inspect ] || exit 2
    shift
    if [ "$1" = "--format" ]; then
      fmt="$2"; img="$3"
      d="$FAKE_ROOT/$(san "$img")"
      [ -d "$d" ] || exit 1
      case "$fmt" in
        '{{.Id}}') cat "$d/.id" 2>/dev/null ;;
        '{{.Architecture}}') cat "$d/.arch" 2>/dev/null || echo arm64 ;;
        '{{index .Config.Labels "'*)
          key="${fmt#*\"}"; key="${key%%\"*}"
          [ -f "$d/.labels" ] && { grep "^${key}=" "$d/.labels" | head -1 | cut -d= -f2-; } ;;
        *) exit 2 ;;
      esac
    else
      img="$1"; d="$FAKE_ROOT/$(san "$img")"; [ -d "$d" ]
    fi
    ;;
  pull) img="${@: -1}"; d="$FAKE_ROOT/$(san "$img")"; [ -d "$d" ] ;;
  create) img="${@: -1}"; d="$FAKE_ROOT/$(san "$img")"; [ -d "$d" ] || exit 1; echo "cid-$(san "$img")" ;;
  cp)
    src="$2"; dst="$3"; cid="${src%%:*}"; p="${src#*:}"; img="${cid#cid-}"
    [ -e "$FAKE_ROOT/$img$p" ] || exit 1
    cp -R "$FAKE_ROOT/$img$p" "$dst" ;;
  rm) : ;;
  build)
    shift
    labelsfile="$(mktemp)"; tag=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -f) shift 2 ;;
        --build-arg) shift 2 ;;
        --label) echo "$2" >> "$labelsfile"; shift 2 ;;
        -t) tag="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$tag" ] || { rm -f "$labelsfile"; exit 2; }
    d="$FAKE_ROOT/$(san "$tag")"; mkdir -p "$d"; mv "$labelsfile" "$d/.labels"
    n="$(cat "$FAKE_ROOT/.build_count" 2>/dev/null || echo 0)"; n=$((n+1)); echo "$n" > "$FAKE_ROOT/.build_count"
    printf 'sha256:built%s\n' "$n" > "$d/.id"
    printf '%s\n' "${FAKE_BUILD_ARCH:-arm64}" > "$d/.arch"
    ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/fakect"

mkimg(){ # NAME ID : creates FAKE_ROOT/<name>/ with .id, prints the dir path
  local d="$FAKE_ROOT/$(san "$1")"; mkdir -p "$d"; printf 'sha256:%s\n' "$2" > "$d/.id"; printf '%s' "$d"
}
SRC="acme/openmrs:1.2.0"; BASE="acme/base:1"
S_DIR="$(mkimg "$SRC" aaa)"
mkdir -p "$S_DIR/usr/local/tomcat/webapps" "$S_DIR/openmrs/distribution/openmrs_core" "$S_DIR/etc/bahmni-emr" "$S_DIR/home/bahmni"
echo tomcatfile > "$S_DIR/usr/local/tomcat/webapps/.keep"
printf '#!/bin/sh\n' > "$S_DIR/openmrs/bahmni_startup.sh"
echo warbytes > "$S_DIR/openmrs/distribution/openmrs_core/openmrs.war"
echo emrfile > "$S_DIR/etc/bahmni-emr/.keep"
echo homefile > "$S_DIR/home/bahmni/.keep"
mkimg "$BASE" base1 >/dev/null

CLINIC="$TMP/clinic"
DRY_=0; ARCH_=arm64
run(){
  env -i PATH="$PATH" HOME="$HOME" CT="$TMP/bin/fakect" FAKE_ROOT="$FAKE_ROOT" FAKE_LOG="$FAKE_LOG" \
    CLINIC_DIR="$CLINIC" OPENMRS_IMAGE_NAME="$SRC" OPENMRS_ARM64_BASE_IMAGE="$BASE" \
    DRY="$DRY_" FAKE_BUILD_ARCH="$ARCH_" \
    bash "$S" "$@" 2>&1
}
OUTTAG="bahmni-local/openmrs:1.2.0-arm64"

# === builds when absent ========================================================
: > "$FAKE_LOG"
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && ok_ "first run succeeds" || bad "first run rc=$rc: $out"
grep -qx "create --platform linux/amd64 ${SRC}" "$FAKE_LOG" && ok_ "create uses --platform linux/amd64" || bad "no matching create call: $(cat "$FAKE_LOG")"
seq="$(grep -oE '^(create|cp|rm|build)\b' "$FAKE_LOG" | tr '\n' ' ')"
[ "$seq" = "create cp cp cp cp rm build " ] && ok_ "create, 4x cp, rm, build called in that order" || bad "call sequence wrong: $seq"
paths="$(grep '^cp ' "$FAKE_LOG" | sed -E 's#^cp cid-[^:]+:##' | awk '{print $1}')"
want="$(printf '/usr/local/tomcat\n/openmrs\n/etc/bahmni-emr\n/home/bahmni')"
[ "$paths" = "$want" ] && ok_ "the four paths copied exactly, in order" || bad "paths copied: $(printf '%s' "$paths" | tr '\n' ' ')"
printf '%s' "$out" | tail -1 | grep -qx "image=${OUTTAG}" && ok_ "prints image=<tag> as the last line" || bad "last line is not image=<tag>: $(printf '%s' "$out" | tail -1)"

# === skips when labels match (no create/build) =================================
: > "$FAKE_LOG"
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && ! grep -qE '^(create|build)' "$FAKE_LOG"; then ok_ "unchanged source+base: skipped, no create/build"; else bad "second run re-built: rc=$rc log=$(tr '\n' ';' < "$FAKE_LOG")"; fi
printf '%s' "$out" | tail -1 | grep -qx "image=${OUTTAG}" && ok_ "skip path still prints image=<tag>" || bad "skip path missing image= line: $out"

# === rebuilds when the source id changed ========================================
printf 'sha256:ccc\n' > "$S_DIR/.id"
: > "$FAKE_LOG"
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^create' "$FAKE_LOG" && grep -q '^build' "$FAKE_LOG"; then ok_ "changed source id: rebuilt"; else bad "did not rebuild on changed source id: $out"; fi

# === --force rebuilds even when labels already match ============================
: > "$FAKE_LOG"
out="$(run --force)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^build' "$FAKE_LOG"; then ok_ "--force rebuilds even when labels already match"; else bad "--force did not rebuild: $out"; fi

# === refuses when the WAR is missing (no build call, non-zero exit) ============
BROKEN="acme/openmrs:broken"
BR_DIR="$(mkimg "$BROKEN" ddd)"
mkdir -p "$BR_DIR/usr/local/tomcat" "$BR_DIR/openmrs" "$BR_DIR/etc/bahmni-emr" "$BR_DIR/home/bahmni"
printf '#!/bin/sh\n' > "$BR_DIR/openmrs/bahmni_startup.sh"   # no distribution/openmrs_core/openmrs.war
: > "$FAKE_LOG"
SRC_SAVE="$SRC"; SRC="$BROKEN"
out="$(run)"; rc=$?
SRC="$SRC_SAVE"
[ "$rc" -ne 0 ] && ok_ "missing WAR is refused (non-zero exit)" || bad "missing WAR accepted"
grep -q '^build' "$FAKE_LOG" && bad "build was called despite the missing WAR" || ok_ "no build call when the WAR is missing"

# === refuses a non-arm64 result =================================================
NEWSRC="acme/openmrs:1.3.0"
N_DIR="$(mkimg "$NEWSRC" eee)"
mkdir -p "$N_DIR/usr/local/tomcat" "$N_DIR/openmrs/distribution/openmrs_core" "$N_DIR/etc/bahmni-emr" "$N_DIR/home/bahmni"
printf '#!/bin/sh\n' > "$N_DIR/openmrs/bahmni_startup.sh"
echo warbytes > "$N_DIR/openmrs/distribution/openmrs_core/openmrs.war"
: > "$FAKE_LOG"
SRC_SAVE="$SRC"; SRC="$NEWSRC"; ARCH_=amd64
out="$(run)"; rc=$?
SRC="$SRC_SAVE"; ARCH_=arm64
[ "$rc" -ne 0 ] && ok_ "a non-arm64 build result is refused" || bad "non-arm64 result accepted"
printf '%s' "$out" | grep -qi 'architecture' && ok_ "refusal names the architecture problem" || bad "refusal message unclear: $out"

# === DRY makes no runtime calls ==================================================
: > "$FAKE_LOG"
DRY_=1
out="$(run)"; rc=$?
DRY_=0
[ "$rc" -eq 0 ] && ok_ "DRY exits 0" || bad "DRY rc=$rc: $out"
[ ! -s "$FAKE_LOG" ] && ok_ "DRY made no runtime calls" || bad "DRY invoked the runtime: $(cat "$FAKE_LOG")"
printf '%s' "$out" | tail -1 | grep -qx "image=${OUTTAG}" && ok_ "DRY still prints image=<tag>" || bad "DRY missing image= line: $out"

# === temp context is gone afterwards, in every case above ======================
leftover="$(ls -d "$CLINIC"/.build-native.* 2>/dev/null)"
[ -z "$leftover" ] && ok_ "no leftover .build-native temp context after any run" || bad "leftover temp context: $leftover"

exit "$fails"
