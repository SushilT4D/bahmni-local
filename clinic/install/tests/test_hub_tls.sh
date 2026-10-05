#!/usr/bin/env bash
# The hub's clinic listener is SASL over TLS by default, its key material stays
# in files, and a clinic's MirrorMaker and installer use TLS with the hub's
# certificate when sync/hub.env says SASL_SSL.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C="$(cd "${HERE}/../.." && pwd)"; R="$(cd "$C/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; ok_(){ printf '  ok   %s\n' "$1"; }; bad(){ printf '  FAIL %s\n' "$1"; fails=$((fails+1)); }
H="$R/hub/docker-compose.yml"

# hub
grep -q '${KAFKA_CLINIC_PROTOCOL:-SASL_SSL}://${REMOTE_KAFKA_HOST' "$H" && ok_ "hub: clinic listener defaults to SASL_SSL" || bad "hub: clinic listener is not SASL_SSL by default"
grep -q './tls:/etc/kafka/secrets:ro' "$H" && ok_ "hub: keystore read from hub/tls" || bad "hub: hub/tls is not mounted at /etc/kafka/secrets"
grep -qE 'KAFKA_SSL_(KEYSTORE|KEY|TRUSTSTORE)_PASSWORD' "$H" && bad "hub: a TLS password is in the environment" || ok_ "hub: no TLS password in the environment"
( cd "$R" && git check-ignore -q hub/tls/kafka.keystore.p12 ) && ok_ "hub/tls is gitignored" || bad "hub/tls is not gitignored"

# clinic MirrorMaker: render start-mm2.sh with the paths moved into a temp dir
printf 'clusters = local, remote\n' > "$TMP/mm2.properties"
sed -e "s#/etc/kafka-connect/mm2.properties#$TMP/mm2.properties#" -e "s#RUNTIME=/tmp/mm2-runtime.properties#RUNTIME=$TMP/rt#" \
    -e 's#exec connect-mirror-maker "$RUNTIME"#cat "$RUNTIME"#' "$C/config/mirrormaker/start-mm2.sh" > "$TMP/start.sh"
run(){ REMOTE_KAFKA_SECURITY_PROTOCOL="$1" REMOTE_KAFKA_USERNAME=u REMOTE_KAFKA_PASSWORD=p REMOTE_KAFKA_SSL_TRUSTSTORE_PASSWORD=t bash "$TMP/start.sh" 2>&1; }
out="$(run SASL_SSL)"
case "$out" in *"remote.security.protocol=SASL_SSL"*"remote.ssl.truststore.location=/etc/kafka-connect/secrets/kafka.truststore.p12"*"remote.ssl.truststore.password=t"*) ok_ "mm2: SASL_SSL adds the truststore" ;; *) bad "mm2: SASL_SSL render lacks the truststore: $out" ;; esac
out="$(run SASL_PLAINTEXT)"
case "$out" in *"remote.security.protocol=SASL_PLAINTEXT"*) case "$out" in *truststore*) bad "mm2: SASL_PLAINTEXT render carries a truststore" ;; *) ok_ "mm2: SASL_PLAINTEXT adds no truststore" ;; esac ;; *) bad "mm2: SASL_PLAINTEXT render wrong: $out" ;; esac
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
