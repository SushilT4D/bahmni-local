#!/usr/bin/env bash
# Bind-mount directories from the RENDERED compose config (never a hand list),
# so a new mount in the compose is created here without editing this file;
# then the per-node certificate.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
begin_task "30 · directories + certificate"
[ "${DRY}" = 1 ] && { info "would: create every bind source under ${CLINIC_DIR} listed by compose config, then a self-signed cert for ${CERT_HOSTNAME}"; exit 0; }
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
  openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes -keyout "$C/key.pem" -out "$C/cert.pem" \
    -subj "/CN=${CERT_HOSTNAME}" -addext "subjectAltName=DNS:${CERT_HOSTNAME},DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
  chmod 600 "$C/key.pem"
fi
[ -s "$C/kafka/kafka.truststore.p12" ] || : > "$C/kafka/kafka.truststore.p12"   # mounted as a file; unused under SASL_PLAINTEXT
san="$(openssl x509 -noout -ext subjectAltName -in "$C/cert.pem" 2>/dev/null | tail -1 | sed 's/^ *//')"
printf '%s' "$san" | grep -q "DNS:${CERT_HOSTNAME}" && ok "certificate SAN: ${san}" || fail "certificate SAN does not name ${CERT_HOSTNAME}: ${san}"
