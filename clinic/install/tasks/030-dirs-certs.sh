#!/usr/bin/env bash
# Creates the folders the containers mount, and the clinic's TLS certificate.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "30 · directories + certificate"
[ "${DRY}" = 1 ] && { info "would: create every bind source under ${CLINIC_DIR} listed by compose config, then a self-signed cert for ${LAN_NAME} and odoo.${LAN_NAME}"; exit 0; }
setup_compose

compose_bind_sources 2>/dev/null | grep -E "^${CLINIC_DIR}/" | sort -u | while read -r src; do
  if [ -e "$src" ]; then continue; fi
  case "$src" in *.jar|*.conf|*.xml|*.sh|*.html|*.json|*.properties|*.pem|*.p12|*.sql|*.zip) mkdir -p "$(dirname "$src")" ;; *) mkdir -p "$src" ;; esac
done

n="$(compose_bind_sources 2>/dev/null | grep -cE "^${CLINIC_DIR}/")"
ok "bind sources present for ${n} mount(s)"
C="${CLINIC_DIR}/certs"; mkdir -p "$C/kafka"
# A self-signed certificate that does not name the LAN name and odoo.<LAN name> is replaced; the old pair is kept as *.pem.old.
if [ -f "$C/cert.pem" ]; then
  old_san="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')"
  if ! printf '%s,' "$old_san" | grep -q "DNS:${LAN_NAME}," || ! printf '%s,' "$old_san" | grep -q "DNS:odoo.${LAN_NAME},"; then
    mv "$C/cert.pem" "$C/cert.pem.old"; [ ! -f "$C/key.pem" ] || mv "$C/key.pem" "$C/key.pem.old"
    info "certificate named ${old_san:-nothing}, not ${LAN_NAME}: replaced (old pair kept as cert.pem.old, key.pem.old)"
  fi
fi
if [ -f "$C/cert.pem" ] && [ -f "$C/key.pem" ]; then skip "certificate exists"; else
  err="$(openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes -keyout "$C/key.pem" -out "$C/cert.pem" \
    -subj "/CN=${LAN_NAME}" -addext "subjectAltName=DNS:${LAN_NAME},DNS:odoo.${LAN_NAME},DNS:localhost,IP:127.0.0.1" 2>&1 >/dev/null)" \
    || fail "openssl could not make the certificate ($(openssl version 2>/dev/null)): $(printf '%s' "$err" | tail -1)"
  chmod 600 "$C/key.pem"
fi

[ -s "$C/kafka/kafka.truststore.p12" ] || : > "$C/kafka/kafka.truststore.p12"   # mounted as a file; task 090 fills it when the hub link is TLS

# cert-san:begin
text="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null)" || fail "could not read ${C}/cert.pem with $(openssl version 2>/dev/null)"
san="$(printf '%s\n' "$text" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')"
for n in "${LAN_NAME}" "odoo.${LAN_NAME}"; do printf '%s' "$san" | grep -q "DNS:${n}" || fail "certificate SAN does not name ${n}: ${san:-<none>} (an older certificate: move certs/cert.pem and certs/key.pem aside and re-run --from 030)"; done
ok "certificate SAN: ${san}"

# cert-san:end
