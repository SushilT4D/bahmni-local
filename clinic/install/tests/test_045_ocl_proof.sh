#!/usr/bin/env bash
# task 045's ocl-proof block: after extraction, the tree OpenMRS actually
# reads must carry no OCL dictionary zip (two zips left in
# place drove a days-long CIEL import), unless KEEP_OCL_ZIPS=1. Runs the block
# extracted verbatim from between its own markers, against fixture trees, with
# fake ok/skip/fail so no real lib.sh/extraction is needed.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T045="${HERE}/../tasks/045-ui-config.sh"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }

[ -f "$T045" ] || { bad "no tasks/045-ui-config.sh"; exit 1; }
snippet="$(sed -n '/# ocl-proof:begin/,/# ocl-proof:end/p' "$T045")"
[ -n "$snippet" ] || { bad "could not extract the ocl-proof:begin/end block from 045"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
run(){ # CF KEEP_OCL_ZIPS
  (
    CF="$1"; KEEP_OCL_ZIPS="${2:-}"
    ok(){ printf 'OK %s\n' "$*"; }
    skip(){ printf 'SKIP %s\n' "$*"; }
    fail(){ printf 'FAIL %s\n' "$*"; exit 1; }
    eval "$snippet"
  )
}

# --- no ocl dir at all: nothing to hold, must read as clean -----------------
d="$TMP/none/bahmni_config"; mkdir -p "$d/masterdata/configuration"
out="$(run "$d")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK no OCL dictionary zip' && ok_ "no ocl/ directory at all: reads clean" || bad "no ocl dir case failed (rc=$rc): $out"

# --- zips already held aside (extract-ui-config.sh did its job) -------------
d="$TMP/held/bahmni_config"; mkdir -p "$d/masterdata/configuration/ocl" "$TMP/held/ocl-held"
: > "$TMP/held/ocl-held/CIEL_v1.zip"
out="$(run "$d")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK no OCL dictionary zip in the tree OpenMRS reads (1 held aside)' && ok_ "zips already held aside: ok, names the count" || bad "held-aside case failed (rc=$rc): $out"

# --- a zip STILL in the served tree: must FAIL, naming the file -------------
d="$TMP/bad/bahmni_config"; mkdir -p "$d/masterdata/configuration/ocl"
: > "$d/masterdata/configuration/ocl/CIEL_v1.zip"
out="$(run "$d")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'CIEL_v1.zip' && ok_ "a zip left in the served tree: FAILs, naming the file" || bad "left-in-place zip did not fail (rc=$rc): $out"

# --- non-zip files in ocl/ are not a problem ---------------------------------
d="$TMP/readme/bahmni_config"; mkdir -p "$d/masterdata/configuration/ocl"
echo keepme > "$d/masterdata/configuration/ocl/README.txt"
out="$(run "$d")"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK no OCL dictionary zip' && ok_ "non-zip ocl file: still reads clean" || bad "non-zip file tripped the check (rc=$rc): $out"

# --- KEEP_OCL_ZIPS=1: skipped outright, even with a zip present -------------
d="$TMP/keep/bahmni_config"; mkdir -p "$d/masterdata/configuration/ocl"
: > "$d/masterdata/configuration/ocl/CIEL_v1.zip"
out="$(run "$d" 1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^SKIP' && ok_ "KEEP_OCL_ZIPS=1: skipped outright" || bad "KEEP_OCL_ZIPS=1 did not skip (rc=$rc): $out"

exit "$fails"
