#!/usr/bin/env bash
# phase: install
# Bind-mount directories from the RENDERED compose config (never a hand list),
# so a new mount in the compose is created here without editing this file;
# then the per-node certificate.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "30 · directories + certificate"
LAN_NAME="$(env_get "${CLINIC_DIR}/.env" LAN_NAME 2>/dev/null || true)"; LAN_NAME="${LAN_NAME:-bahmni.clinic}"
[ "${DRY}" = 1 ] && { info "would: create every bind source under ${CLINIC_DIR} listed by compose config, then a self-signed cert for ${LAN_NAME}, odoo.${LAN_NAME} and ${CERT_HOSTNAME}"; exit 0; }
setup_compose
# Sources that are directories today or do not exist yet -> mkdir. Existing
# files (config files, jars) are left alone.
compose config 2>/dev/null | awk '/^ *source: /{print $2}' | grep -E "^${CLINIC_DIR}/" | sort -u | while read -r src; do
  if [ -e "$src" ]; then continue; fi
  case "$src" in *.jar|*.conf|*.xml|*.sh|*.html|*.json|*.properties|*.pem|*.p12|*.sql|*.zip) mkdir -p "$(dirname "$src")" ;; *) mkdir -p "$src" ;; esac
done
n="$(compose config 2>/dev/null | awk '/^ *source: /{print $2}' | grep -cE "^${CLINIC_DIR}/")"
ok "bind sources present for ${n} mount(s)"
C="${CLINIC_DIR}/certs"; mkdir -p "$C/kafka"
if [ -f "$C/cert.pem" ] && [ -f "$C/key.pem" ]; then skip "certificate exists"; else
  err="$(openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes -keyout "$C/key.pem" -out "$C/cert.pem" \
    -subj "/CN=${LAN_NAME}" -addext "subjectAltName=DNS:${LAN_NAME},DNS:odoo.${LAN_NAME},DNS:${CERT_HOSTNAME},DNS:localhost,IP:127.0.0.1" 2>&1 >/dev/null)" \
    || fail "openssl could not make the certificate ($(openssl version 2>/dev/null)): $(printf '%s' "$err" | tail -1)"
  chmod 600 "$C/key.pem"
fi
[ -s "$C/kafka/kafka.truststore.p12" ] || : > "$C/kafka/kafka.truststore.p12"   # mounted as a file; unused under SASL_PLAINTEXT
# cert-san:begin
# Read the SAN from the text dump: `x509 -ext` exists only in OpenSSL 1.1.1+,
# not in LibreSSL (macOS's stock openssl), and a failed read inside a pipeline
# would end this task silently under pipefail.
text="$(openssl x509 -noout -text -in "$C/cert.pem" 2>/dev/null)" || fail "could not read ${C}/cert.pem with $(openssl version 2>/dev/null)"
san="$(printf '%s\n' "$text" | grep -A1 'Subject Alternative Name' | tail -1 | sed 's/^ *//')"
for n in "${LAN_NAME}" "odoo.${LAN_NAME}" "${CERT_HOSTNAME}"; do printf '%s' "$san" | grep -q "DNS:${n}" || fail "certificate SAN does not name ${n}: ${san:-<none>} (an older certificate: move certs/cert.pem and certs/key.pem aside and re-run --from 030)"; done
ok "certificate SAN: ${san}"
# cert-san:end
