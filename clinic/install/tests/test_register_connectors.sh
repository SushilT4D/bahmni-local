#!/usr/bin/env bash
# scripts/register-connectors.sh must never leave a connector config -- with
# its plaintext database.password / connection.password -- in a file under
# /tmp, and must never print a password. A fake curl on PATH stands in for
# Kafka Connect: it answers normally for the first connector and fails outright
# (a process crash, not just a non-2xx HTTP response) for the second, so an
# early abort cannot skip a cleanup and leave the first connector's password on
# disk. A third fixture (conn-badmask) exercises the masking sed itself against
# a password containing an escaped quote and an escaped backslash: a naive
# [^"]* value pattern stops at the embedded \" and leaks the remainder.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_ne(){ if [ "$2" -ne "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s\n' "$1" "$2"; fails=$((fails+1)); fi; }
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_not_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  FAIL %s: output contains %q\n' "$1" "$3"; fails=$((fails+1)); else printf '  ok   %s\n' "$1"; fi; }

# The script reads the configs from CONNECTORS_DIR and the passwords from
# CLINIC_DIR/.env; it is run from the repository as it is.
mkdir -p "$TMP/connectors"
: > "$TMP/.env"
printf '{"name":"conn-ok","config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","database.password":"irrelevant-A"}}\n' > "$TMP/connectors/conn-ok.json"
printf '{"name":"conn-bad","config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","database.password":"irrelevant-B"}}\n' > "$TMP/connectors/conn-bad.json"
printf '{"name":"conn-badmask","config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","database.password":"irrelevant-C"}}\n' > "$TMP/connectors/conn-badmask.json"

# Fake curl: Connect is reachable, no connector exists yet, and the PUT for
# conn-bad crashes (nonzero exit) while conn-badmask gets an HTTP 500 whose
# echoed config carries a JSON-escaped quote and backslash in its password.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
put=0; last=""
for a in "$@"; do [ "$a" = PUT ] && put=1; last="$a"; done
[ "$put" = 1 ] && cat >/dev/null
case "$put:$last" in
  0:*/connectors) printf '[]'; exit 0 ;;
  0:*) exit 22 ;;
  1:*/connectors/conn-bad/config)
    printf '{"name":"conn-bad","config":{"connection.password":"SECRET_VALUE_XYZ"}}\n500'
    exit 1 ;;
  1:*/connectors/conn-badmask/config)
    printf '%s\n%s' '{"name":"conn-badmask","config":{"connection.password":"SEC\"RET\\VAL"}}' '500'
    exit 0 ;;
  *)
    printf '{"name":"conn-ok","config":{"connection.password":"SECRET_VALUE_XYZ"}}\n201'
    exit 0 ;;
esac
EOF
chmod +x "$TMP/bin/curl"

reg(){ PATH="$TMP/bin:$PATH" CLINIC_DIR="$TMP" CONNECTORS_DIR="$TMP/connectors" CONNECT_URL="http://fake-connect:8083" \
       bash "${REPO}/clinic/scripts/register-connectors.sh" "$@" 2>&1; }

before="$(ls -a /tmp 2>/dev/null | sort)"
out="$(reg conn-ok conn-bad)"; rc=$?
after="$(ls -a /tmp 2>/dev/null | sort)"
assert_ne "a hard failure on the second connector is a nonzero script exit" "$rc" 0
assert_eq "no stray file left under /tmp" "$after" "$before"
assert_not_contains "the password Connect echoes never reaches the script's own output" "$out" "SECRET_VALUE_XYZ"

maskout="$(reg conn-badmask)"; maskrc=$?
assert_ne "an HTTP error from Connect is a nonzero script exit" "$maskrc" 0
assert_not_contains "an escaped-quote password does not leak its prefix (SEC)" "$maskout" 'SEC\\"'
assert_not_contains "an escaped-quote password does not leak its middle (RET)" "$maskout" "RET"
assert_not_contains "an escaped-quote password does not leak its suffix (VAL)" "$maskout" "VAL"

exit "$fails"
