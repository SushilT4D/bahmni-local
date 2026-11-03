#!/usr/bin/env bash
# The certificate's SAN is read in a form both OpenSSL and LibreSSL (macOS's
# stock /usr/bin/openssl) understand, and a failed read names itself instead
# of ending the task silently under set -e / pipefail.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok_(){ printf '  ok   %s\n' "$1"; }
bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
T30="${HERE}/../tasks/030-dirs-certs.sh"
blk="$(sed -n '/# cert-san:begin/,/# cert-san:end/p' "$T30")"
[ -n "$blk" ] || { bad "030 has no cert-san block"; exit 1; }
grep -vE '^[[:space:]]*#' "$T30" | grep -q -- '-ext subjectAltName' && bad "030 still uses x509 -ext (LibreSSL has no such option)" || ok_ "030 does not use x509 -ext"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes -keyout "$W/key.pem" -out "$W/cert.pem" -subj "/CN=bahmni.clinic" -addext "subjectAltName=DNS:bahmni.clinic,DNS:odoo.bahmni.clinic,DNS:node.example,DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1 || { bad "could not make a fixture cert with $(openssl version)"; exit 1; }
run(){ env -i PATH="$PATH" HOME="$W" bash -c "set -euo pipefail; . '${HERE}/../lib.sh'; C='$W'; CERT_HOSTNAME='$1'; LAN_NAME='${2:-bahmni.clinic}'; ${blk}" 2>&1; }
out="$(run node.example)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'DNS:node.example' && ok_ "SAN read and matched with $(openssl version | cut -d' ' -f1-2)" || bad "SAN read failed (rc=$rc): $out"
out="$(run other.example)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not name other.example' && ok_ "a SAN that lacks the hostname is a named FAIL" || bad "wrong-hostname case: rc=$rc: $out"
out="$(run node.example other.lan)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'does not name other.lan' && ok_ "a SAN that lacks the LAN name is a named FAIL" || bad "wrong LAN name case: rc=$rc: $out"
printf 'not a certificate\n' > "$W/cert.pem"
out="$(run node.example)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'could not read' && ok_ "an unreadable certificate is a named FAIL, not a silent exit" || bad "unreadable cert: rc=$rc: $out"
grep -q 'DNS:odoo.${LAN_NAME}' "$T30" && ok_ "the certificate is made for odoo.<LAN name> too" || bad "030 does not put odoo.<LAN name> in the SAN"
exit "$fails"
