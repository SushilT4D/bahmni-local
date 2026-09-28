#!/usr/bin/env bash
# scripts/extract-baseline.sh against a fake runtime: each pinned image's dump
# lands as <name>.sql.gz, an uncompressed dump is compressed, a missing file fails.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${HERE}/../../scripts/extract-baseline.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
mkdir -p "$TMP/bin"
cat > "$TMP/bin/fakect" <<'SH'
#!/usr/bin/env bash
san(){ printf '%s' "$1" | tr '/:' '__'; }
case "$1" in
  pull) exit 0 ;;
  create) eval "img=\${$#}"; echo "cid-$(san "$img")" ;;
  cp) cid="${2%%:*}"; p="${2#*:}"; [ -f "$FAKE_ROOT/${cid#cid-}$p" ] || exit 1; cp "$FAKE_ROOT/${cid#cid-}$p" "$3" ;;
  rm) : ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/fakect"
R="$TMP/root"
mkdir -p "$R/a_omrs_1/docker-entrypoint-initdb.d" "$R/a_odoo_1/docker-entrypoint-initdb.d" "$R/a_elis_1/resources"
printf 'omrs' | gzip > "$R/a_omrs_1/docker-entrypoint-initdb.d/openmrsdb_backup.sql.gz"
printf 'odoo' | gzip > "$R/a_odoo_1/docker-entrypoint-initdb.d/odoodb_backup.sql.gz"
printf 'elis' > "$R/a_elis_1/resources/openelis_backup.sql"
X(){ CT="$TMP/bin/fakect" FAKE_ROOT="$R" BASELINE_OPENMRS_IMAGE=a/omrs:1 BASELINE_ODOO_IMAGE=a/odoo:1 BASELINE_OPENELIS_IMAGE=a/elis:1 bash "$S" "$1" >/dev/null 2>&1; }
OUT="$TMP/out"
X "$OUT" && ok_ "extract ran" || bad "extract failed"
for f in openmrs odoo openelis; do gzip -t "$OUT/$f.sql.gz" 2>/dev/null && ok_ "$f.sql.gz is gzip" || bad "$f.sql.gz missing or not gzip"; done
[ "$(gzip -dc "$OUT/openelis.sql.gz" 2>/dev/null)" = elis ] && ok_ "uncompressed openelis dump compressed" || bad "openelis content"
[ "$(gzip -dc "$OUT/openmrs.sql.gz" 2>/dev/null)" = omrs ] && ok_ "openmrs dump kept as is" || bad "openmrs content"
rm "$R/a_odoo_1/docker-entrypoint-initdb.d/odoodb_backup.sql.gz"
X "$TMP/out2" && bad "missing dump did not fail" || ok_ "missing dump fails"
exit $((fails > 0))
