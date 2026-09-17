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
git -C "$HUB/.." ls-files cloud/kafka_server_jaas.conf | grep -q . && bad "JAAS still tracked" || ok "JAAS not tracked"
# `check-ignore -q` refuses more than one pathname ("--quiet is only valid
# with a single pathname", confirmed on git 2.39.5) -- split into two calls,
# same assertion.
git -C "$HUB/.." check-ignore -q hub/.env && git -C "$HUB/.." check-ignore -q hub/kafka_server_jaas.conf && ok "hub/.env and JAAS ignored" || bad "hub secrets not ignored"
git -C "$HUB/.." check-ignore -q hub/connectors/generated/x.json && ok "hub/connectors/generated/ ignored" || bad "hub/connectors/generated/ not ignored"
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
