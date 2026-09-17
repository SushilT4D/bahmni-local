#!/usr/bin/env bash
# F-073: register-odoo.sh must never leave a connector config -- with its
# plaintext database.password / connection.password -- sitting in a fixed,
# world-readable /tmp path. A fake curl on PATH stands in for Kafka Connect:
# it answers normally for the first connector and fails outright (a process
# crash, not just a non-2xx HTTP response) for the second, reproducing the
# exact "a crash leaves it forever" scenario the finding describes -- the old
# script only removed /tmp/.reg.out AFTER the whole loop, so an early abort
# skipped that cleanup and left the prior connector's password on disk.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
assert_rc(){ if [ "$2" -eq "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: rc %s want %s\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_eq(){ if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s: got %q want %q\n' "$1" "$2" "$3"; fails=$((fails+1)); fi; }
assert_not_contains(){ if printf '%s' "$2" | grep -q -- "$3"; then printf '  FAIL %s: output contains %q\n' "$1" "$3"; fails=$((fails+1)); else printf '  ok   %s\n' "$1"; fi; }

# Fixture ROOT: register-odoo.sh derives ROOT from its own script path
# ("$(dirname "$0")/.."), so it must live under connectors/ with a sibling
# .env and the real _render_connector.py alongside it.
mkdir -p "$TMP/connectors"
cp "${REPO}/clinic/connectors/register-odoo.sh" "$TMP/connectors/register-odoo.sh"
cp "${REPO}/clinic/connectors/_render_connector.py" "$TMP/connectors/_render_connector.py"
: > "$TMP/.env"
printf '{"config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","database.password":"irrelevant-A"}}\n' > "$TMP/connectors/conn-ok.json"
printf '{"config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","database.password":"irrelevant-B"}}\n' > "$TMP/connectors/conn-bad.json"

# Fake curl: drains stdin (so the script's `printf | curl` pipe never SIGPIPEs
# the way a real curl would not), inspects the request URL (its last arg) for
# the connector name, and for conn-bad simulates the registration call itself
# failing (nonzero exit) -- not merely Connect answering with an HTTP error --
# since that is the crash path the fix must survive without leaking anything.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
last=""
for a in "$@"; do last="$a"; done
case "$last" in
  */connectors/conn-bad/config)
    printf '{"name":"conn-bad","config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","connection.password":"SECRET_VALUE_XYZ"}}\n500'
    exit 1
    ;;
  *)
    printf '{"name":"conn-ok","config":{"connector.class":"io.debezium.connector.mysql.MySqlConnector","connection.password":"SECRET_VALUE_XYZ"}}\n201'
    exit 0
    ;;
esac
EOF
chmod +x "$TMP/bin/curl"

before="$(ls -a /tmp 2>/dev/null | sort)"
out="$(PATH="$TMP/bin:$PATH" NODE=test-node MYSQL_SERVER_NAME=test-server CONNECT_URL="http://fake-connect:8083" \
       bash "$TMP/connectors/register-odoo.sh" conn-ok conn-bad 2>&1)"
rc=$?
after="$(ls -a /tmp 2>/dev/null | sort)"

assert_rc "a hard failure on the second connector is a nonzero script exit" "$rc" 1
assert_rc "/tmp/.reg.out does not exist afterwards" "$([ -e /tmp/.reg.out ]; echo $?)" 1
assert_eq "no stray file left under /tmp" "$after" "$before"
assert_not_contains "the leaked password never reaches the script's own stdout/stderr" "$out" "SECRET_VALUE_XYZ"

exit "$fails"
