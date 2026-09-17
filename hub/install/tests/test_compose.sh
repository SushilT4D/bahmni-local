#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; HUB="$(cd "$HERE/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
[ -f "$HUB/docker-compose.yml" ] && ok "hub compose exists" || bad "hub/docker-compose.yml missing"
# KAFKA_IMAGE, SCHEMA_REGISTRY_IMAGE and DEBEZIUM_CONNECT_IMAGE are fleet pins
# (sync/versions.env) the example does not carry -- hub_compose_env's
# versions_put writes them at render time (hub/install/lib.sh), not this file.
env $(grep -oE '^[A-Z_]+=' "$HUB/.env.example" | sed 's/=$/=x/' | tr '\n' ' ') $(grep -oE '^[A-Z_]+=[^ ]*' "$HUB/../sync/versions.env" | tr '\n' ' ') KAFKA_BASE_NETWORK=testnet docker compose -f "$HUB/docker-compose.yml" config >/tmp/hubcfg.yml 2>/tmp/hubcfg.err \
  && ok "hub compose validates with the example keys" || { bad "hub compose does not validate: $(head -3 /tmp/hubcfg.err)"; }
for s in kafka-controller kafka schema-registry kafka-connect; do grep -qE "^  ${s}:" /tmp/hubcfg.yml && ok "service $s" || bad "service $s missing"; done
grep -qE 'name: testnet' /tmp/hubcfg.yml && grep -qE 'external: true' /tmp/hubcfg.yml && ok "attaches to the base network" || bad "external network not declared"
for s in kafka-controller kafka schema-registry kafka-connect; do grep -qE "^  ${s}:" "$HUB/../cloud/docker-compose.yml" && bad "cloud/ still defines $s" || ok "cloud/ no longer defines $s"; done

# kafka-ui (Ruling 3): exists, wired to the central sync/versions.env pin
# (never a hardcoded tag in the compose file), and bound to 127.0.0.1 only.
grep -qE '^\s*image: \$\{KAFKA_UI_IMAGE:\?\}' "$HUB/docker-compose.yml" && ok "kafka-ui's image is wired to \${KAFKA_UI_IMAGE:?}, not a literal tag" || bad "kafka-ui does not reference \${KAFKA_UI_IMAGE:?}"
grep -qE "^  kafka-ui:" /tmp/hubcfg.yml && ok "service kafka-ui" || bad "service kafka-ui missing"
expected_kafka_ui_image="$(grep -oE '^KAFKA_UI_IMAGE=[^ ]*' "$HUB/../sync/versions.env" | cut -d= -f2-)"
kafka_ui_image="$(awk '/^  kafka-ui:/{f=1} f && /^    image:/{print $2; exit}' /tmp/hubcfg.yml)"
[ -n "$expected_kafka_ui_image" ] && [ "$kafka_ui_image" = "$expected_kafka_ui_image" ] \
  && ok "kafka-ui image resolves to sync/versions.env's pin (${kafka_ui_image})" \
  || bad "kafka-ui image is '${kafka_ui_image:-<none>}', want sync/versions.env's KAFKA_UI_IMAGE ('${expected_kafka_ui_image:-<missing>}')"
kafka_ui_block="$(awk '/^  kafka-ui:/{f=1} f' /tmp/hubcfg.yml)"
# `docker compose config` renders `ports:` in short form ("host:container") on
# some versions and long form (host_ip:/target:/published: fields) on others
# -- accept either rather than pin to one compose version's own output shape.
ports_block="$(printf '%s' "$kafka_ui_block" | awk '/^    ports:/{f=1;next} f && /^    [a-zA-Z]/{exit} f')"
if printf '%s' "$ports_block" | grep -qE '^\s*-\s*"?127\.0\.0\.1:8080:8080"?\s*$'; then
  ok "kafka-ui's port mapping is 127.0.0.1:8080:8080 (short form)"
elif printf '%s' "$ports_block" | grep -q 'host_ip: 127.0.0.1' && printf '%s' "$ports_block" | grep -q 'target: 8080' && printf '%s' "$ports_block" | grep -qE 'published: "?8080"?'; then
  ok "kafka-ui's port mapping is 127.0.0.1:8080 (long form: host_ip/target/published)"
else
  bad "kafka-ui's port mapping is not 127.0.0.1:8080 in either short or long form (got: $(printf '%s' "$ports_block" | tr '\n' ' '))"
fi
n_ports="$(printf '%s' "$ports_block" | grep -cE '^\s*-\s')"
[ "$n_ports" = 1 ] && ok "kafka-ui publishes exactly one port (no non-loopback exposure)" || bad "kafka-ui publishes ${n_ports:-0} port entries, want exactly 1"
printf '%s' "$kafka_ui_block" | grep -qE 'AUTH_TYPE: ?LOGIN_FORM' && ok "kafka-ui AUTH_TYPE is LOGIN_FORM" || bad "kafka-ui AUTH_TYPE is not LOGIN_FORM"
git -C "$HUB/.." ls-files cloud/kafka_server_jaas.conf | grep -q . && bad "JAAS still tracked" || ok "JAAS not tracked"
# `check-ignore -q` refuses more than one pathname ("--quiet is only valid
# with a single pathname", confirmed on git 2.39.5) -- split into two calls,
# same assertion.
git -C "$HUB/.." check-ignore -q hub/.env && git -C "$HUB/.." check-ignore -q hub/kafka_server_jaas.conf && ok "hub/.env and JAAS ignored" || bad "hub secrets not ignored"
git -C "$HUB/.." check-ignore -q hub/connectors/generated/x.json && ok "hub/connectors/generated/ ignored" || bad "hub/connectors/generated/ not ignored"
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
