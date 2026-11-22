#!/usr/bin/env bash
# Creates the folders the containers mount, and the clinic's TLS certificate.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "30 · directories + certificate"
[ "${DRY}" = 1 ] && { info "would: create every bind source under ${CLINIC_DIR} listed by compose config, then an mkcert-signed cert for ${LAN_NAME} and odoo.${LAN_NAME}"; exit 0; }
setup_compose

compose_bind_sources 2>/dev/null | grep -E "^${CLINIC_DIR}/" | sort -u | while read -r src; do
  if [ -e "$src" ]; then continue; fi
  case "$src" in *.jar|*.conf|*.xml|*.sh|*.html|*.json|*.properties|*.pem|*.p12|*.sql|*.zip) mkdir -p "$(dirname "$src")" ;; *) mkdir -p "$src" ;; esac
done

n="$(compose_bind_sources 2>/dev/null | grep -cE "^${CLINIC_DIR}/")"
ok "bind sources present for ${n} mount(s)"
C="${CLINIC_DIR}/certs"; mkdir -p "$C/kafka"
# Signed by this Mac's mkcert CA, which macOS trusts, so browsers show the padlock.
command -v mkcert >/dev/null 2>&1 || fail "mkcert missing: brew install mkcert (or re-run --from 010)"
mkcert -install >/dev/null 2>&1 || fail "mkcert could not add its CA to the System keychain: run 'mkcert -install' and re-run --from 030"
CA="$(mkcert -CAROOT)/rootCA.pem"
# A certificate not signed by that CA, or not naming the LAN name and odoo.<LAN name>, is replaced; the old pair is kept as *.pem.old.
if [ -f "$C/cert.pem" ]; then
  old_san="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')"
  if ! openssl verify -CAfile "$CA" "$C/cert.pem" >/dev/null 2>&1 \
     || ! printf '%s,' "$old_san" | grep -q "DNS:${LAN_NAME}," || ! printf '%s,' "$old_san" | grep -q "DNS:odoo.${LAN_NAME},"; then
    mv "$C/cert.pem" "$C/cert.pem.old"; [ ! -f "$C/key.pem" ] || mv "$C/key.pem" "$C/key.pem.old"
    info "certificate (${old_san:-no names}) not signed by the mkcert CA for ${LAN_NAME}: replaced (old pair kept as cert.pem.old, key.pem.old)"
  fi
fi
if [ -f "$C/cert.pem" ] && [ -f "$C/key.pem" ]; then skip "certificate exists"; else
  err="$(mkcert -cert-file "$C/cert.pem" -key-file "$C/key.pem" "${LAN_NAME}" "odoo.${LAN_NAME}" localhost 127.0.0.1 2>&1)" \
    || fail "mkcert could not make the certificate: $(printf '%s' "$err" | tail -1)"
  chmod 600 "$C/key.pem"
fi
# Other devices (tablets, PCs) trust the site once they install this CA file.
cp "$CA" "$C/clinic-ca.pem"; ok "CA for other devices: ${C}/clinic-ca.pem"

[ -s "$C/kafka/kafka.truststore.p12" ] || : > "$C/kafka/kafka.truststore.p12"   # mounted as a file; task 090 fills it when the hub link is TLS

# cert-san:begin
text="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null)" || fail "could not read ${C}/cert.pem with $(openssl version 2>/dev/null)"
san="$(printf '%s\n' "$text" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')"
for n in "${LAN_NAME}" "odoo.${LAN_NAME}"; do printf '%s' "$san" | grep -q "DNS:${n}" || fail "certificate SAN does not name ${n}: ${san:-<none>} (an older certificate: move certs/cert.pem and certs/key.pem aside and re-run --from 030)"; done
ok "certificate SAN: ${san}"

# cert-san:end
