#!/usr/bin/env bash
# The cloud server's clinic listener is SASL over TLS, its keystore passwords come from .env,
# and a clinic's MirrorMaker and installer use TLS with its certificate when sync/hub.env says SASL_SSL.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"; R="$(cd "$C/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
H="$R/cloud/docker-compose.yml"

# cloud server
grep -q 'KAFKA_LISTENER_SECURITY_PROTOCOL_MAP:.*EXTERNAL:SASL_SSL' "$H" && ok_ "cloud: clinic listener (EXTERNAL) is SASL_SSL" || bad "cloud: clinic listener is not SASL_SSL"
grep -q 'certs/kafka/kafka.keystore.p12:/etc/kafka/secrets/kafka.keystore.p12:ro' "$H" && ok_ "cloud: keystore mounted read-only from certs/kafka" || bad "cloud: keystore is not mounted from certs/kafka"
grep -E 'KAFKA_SSL_(KEYSTORE|KEY|TRUSTSTORE)_PASSWORD:' "$H" | grep -qvE ':[[:space:]]*\$\{[A-Z_]+\}[[:space:]]*$' && bad "cloud: a TLS password is written into compose" || ok_ "cloud: TLS passwords come from .env"
( cd "$R" && git check-ignore -q cloud/certs/kafka/kafka.keystore.p12 ) && ok_ "cloud keystore is gitignored" || bad "cloud keystore is not gitignored"

# clinic MirrorMaker: the template reads the cloud login and truststore from the container environment
T="$C/config/mirrormaker/mm2.properties.template"
grep -q '^config.providers.env.class = org.apache.kafka.common.config.provider.EnvVarConfigProvider$' "$T" && ok_ "mm2: env config provider enabled" || bad "mm2: no env config provider in the template"
grep -q '^remote.security.protocol = ${env:REMOTE_KAFKA_SECURITY_PROTOCOL}$' "$T" && ok_ "mm2: protocol from the environment" || bad "mm2: protocol not read from the environment"
grep -q 'password="${env:REMOTE_KAFKA_PASSWORD}"' "$T" && ok_ "mm2: password from the environment" || bad "mm2: password not read from the environment"
grep -q '^remote.ssl.truststore.password = ${env:REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD}$' "$T" && ok_ "mm2: truststore password from the environment" || bad "mm2: truststore password not read from the environment"
grep -q 'command: \["connect-mirror-maker", "/etc/kafka-connect/mm2.properties"\]' "$C/docker-compose.yml" && ok_ "compose runs connect-mirror-maker on mm2.properties" || bad "compose does not run connect-mirror-maker directly"
grep -q 'REMOTE_KAFKA_SECURITY_PROTOCOL: ${REMOTE_KAFKA_SECURITY_PROTOCOL:-SASL_PLAINTEXT}' "$C/docker-compose.yml" && ok_ "compose passes the protocol to MirrorMaker; a node without the setting keeps plaintext" || bad "compose does not pass REMOTE_KAFKA_SECURITY_PROTOCOL to MirrorMaker"
grep -qE '^REMOTE_KAFKA_SECURITY_PROTOCOL=' "$R/sync/hub.env" && ok_ "sync/hub.env names the hub's protocol" || bad "sync/hub.env has no REMOTE_KAFKA_SECURITY_PROTOCOL"

# installer
proto(){ ( HUB_ENV="$1" REMOTE_KAFKA_SECURITY_PROTOCOL="${2:-}" INSTALL_DIR="${HERE}/.." DRY=0 bash -c '. "$INSTALL_DIR/lib.sh"; hub_protocol' 2>&1 ); }
printf 'REMOTE_KAFKA_SECURITY_PROTOCOL=SASL_PLAINTEXT\n' > "$TMP/hub-plain.env"; : > "$TMP/hub-none.env"
[ "$(proto "$TMP/hub-plain.env")" = SASL_PLAINTEXT ] && ok_ "hub_protocol reads sync/hub.env" || bad "hub_protocol ignores sync/hub.env: $(proto "$TMP/hub-plain.env")"
[ "$(proto "$TMP/hub-none.env")" = SASL_SSL ] && ok_ "hub_protocol defaults to SASL_SSL" || bad "hub_protocol default is $(proto "$TMP/hub-none.env")"
[ "$(proto "$TMP/hub-plain.env" SASL_SSL)" = SASL_SSL ] && ok_ "the environment overrides sync/hub.env" || bad "the environment does not override sync/hub.env"
grep -q 'put REMOTE_KAFKA_SECURITY_PROTOCOL "$proto"' "${HERE}/../tasks/020-env.sh" && ok_ "020 writes the protocol into .env" || bad "020 does not write REMOTE_KAFKA_SECURITY_PROTOCOL"
grep -q 'the hub link is SASL_SSL but' "${HERE}/../tasks/020-env.sh" && ok_ "020 stops when SASL_SSL has no hub certificate" || bad "020 does not check sync/hub-ca.pem"
grep -q 'hub_truststore "$TS"' "${HERE}/../tasks/090-local-sync.sh" && ok_ "090 builds the truststore" || bad "090 does not build the truststore"
grep -q "security.protocol=%s" "${HERE}/../tasks/090-local-sync.sh" && grep -q 'ssl.truststore.location=/tmp/twin-guard.p12' "${HERE}/../tasks/090-local-sync.sh" \
  && ok_ "090's hub check uses the same protocol and truststore" || bad "090's hub check still assumes plaintext"
exit $((fails > 0))
