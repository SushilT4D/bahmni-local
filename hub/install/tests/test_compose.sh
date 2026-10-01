#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; HUB="$(cd "$HERE/../.." && pwd)"; fails=0
ok(){ printf '  ok   %s\n' "$*"; }; bad(){ printf '  FAIL %s\n' "$*"; fails=$((fails+1)); }
[ -f "$HUB/docker-compose.yml" ] && ok "hub compose exists" || bad "hub/docker-compose.yml missing"
# KAFKA_IMAGE and DEBEZIUM_CONNECT_IMAGE are fleet pins
# (sync/versions.env) the example does not carry -- hub_compose_env's
# versions_put writes them at render time (hub/install/lib.sh), not this file.
# KAFKA_SASL_BIND is given a REAL value rather than the placeholder "x" every
# other key gets: it renders inside a ports entry, and compose rejects the
# whole file with "invalid IP address: x" (the
# ports line is `${KAFKA_SASL_BIND:-0.0.0.0}:9092:9092` now, not a pinned
# 127.0.0.1). `env` applies assignments in order, so this one wins over the
# generated placeholder ahead of it.
hubcfg(){ local bind="$1"; shift; env $(grep -oE '^[A-Z_]+=' "$HUB/.env.example" | sed 's/=$/=x/' | tr '\n' ' ') $(grep -oE '^[A-Z_]+=[^ ]*' "$HUB/../sync/versions.env" | tr '\n' ' ') KAFKA_BASE_NETWORK=testnet KAFKA_SASL_BIND="$bind" docker compose -f "$HUB/docker-compose.yml" --profile ui config "$@"; }
hubcfg 0.0.0.0 >/tmp/hubcfg.yml 2>/tmp/hubcfg.err \
  && ok "hub compose validates with the example keys" || { bad "hub compose does not validate: $(head -3 /tmp/hubcfg.err)"; }
for s in kafka kafka-connect; do grep -qE "^  ${s}:" /tmp/hubcfg.yml && ok "service $s" || bad "service $s missing"; done
cfg="$(hubcfg 0.0.0.0 --format json 2>/dev/null)"
for s in kafka-controller schema-registry; do printf '%s' "$cfg" | jq -e --arg s "$s" '.services | has($s)' >/dev/null && bad "hub still declares $s" || ok "no $s service"; done
kenv="$(printf '%s' "$cfg" | jq -r '.services.kafka.environment')"
[ "$(printf '%s' "$kenv" | jq -r '.KAFKA_PROCESS_ROLES')" = "broker,controller" ] && ok "kafka holds both roles" || bad "kafka roles: $(printf '%s' "$kenv" | jq -r '.KAFKA_PROCESS_ROLES')"
[ "$(printf '%s' "$kenv" | jq -r '.KAFKA_CONTROLLER_QUORUM_VOTERS')" = "1@kafka:9093" ] && ok "kafka votes for itself" || bad "voters: $(printf '%s' "$kenv" | jq -r '.KAFKA_CONTROLLER_QUORUM_VOTERS')"
printf '%s' "$kenv" | jq -r '.KAFKA_LISTENERS' | grep -q 'CONTROLLER://0.0.0.0:9093' && ok "controller listener declared" || bad "no CONTROLLER listener"
printf '%s' "$kenv" | jq -r '.KAFKA_ADVERTISED_LISTENERS' | grep -q CONTROLLER && bad "controller listener advertised" || ok "controller listener not advertised"
[ "$(printf '%s' "$kenv" | jq -r '.KAFKA_HEAP_OPTS')" = "-Xms512m -Xmx1g" ] && ok "kafka heap stated (1 GiB)" || bad "kafka heap: $(printf '%s' "$kenv" | jq -r '.KAFKA_HEAP_OPTS')"
[ "$(printf '%s' "$cfg" | jq -r '.services["kafka-connect"].environment.HEAP_OPTS')" = "-Xms256m -Xmx1g" ] && ok "connect heap stated (1 GiB)" || bad "connect heap not stated"
printf '%s' "$cfg" | jq -e '.volumes | has("kafka-controller-data")' >/dev/null && bad "controller volume still declared" || ok "no controller volume"
awk '/^  kafka-ui:/{f=1} f' "$HUB/docker-compose.yml" | head -6 | grep -qE '^    profiles: \[ "ui" \]' && ok "kafka-ui only on request (profile ui)" || bad "kafka-ui starts by default"
left="$(git -C "$HUB/.." grep -il 'kafka-controller\|schema-registry\|SCHEMAREGISTRY' -- hub ':!*.md' ':!hub/install/tests/test_compose.sh' 2>/dev/null)"
[ -z "$left" ] && ok "nothing under hub/ names the controller or a registry" || bad "still named in: $(printf '%s' "$left" | tr '\n' ' ')"
grep -qE 'name: testnet' /tmp/hubcfg.yml && grep -qE 'external: true' /tmp/hubcfg.yml && ok "attaches to the base network" || bad "external network not declared"
for s in kafka kafka-connect; do grep -qE "^  ${s}:" "$HUB/../cloud/docker-compose.yml" && bad "cloud/ still defines $s" || ok "cloud/ no longer defines $s"; done

# kafka-ui: exists, wired to the central sync/versions.env pin
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
# --- the clinic-facing SASL listener is publishable ------------------------
# In the source: the ports entry is the variable with a PUBLIC default, never
# a pinned loopback address. The pattern is SINGLE-quoted: in double quotes
# the shell would expand ${KAFKA_SASL_BIND:-0.0.0.0} and grep for its value.
grep -qF -e 'KAFKA_SASL_BIND:-0.0.0.0}:9092:9092' "$HUB/docker-compose.yml" \
  && ok "kafka's 9092 mapping is \${KAFKA_SASL_BIND:-0.0.0.0}:9092:9092 (public by default)" \
  || bad "kafka's 9092 mapping is not \${KAFKA_SASL_BIND:-0.0.0.0}:9092:9092 -- a hub clinics cannot dial"
grep -qE "^ *- '127\\.0\\.0\\.1:9092:9092'" "$HUB/docker-compose.yml" \
  && bad "kafka still pins a loopback 9092 mapping" || ok "no pinned loopback 9092 mapping left in the compose file"
# Rendered: what compose actually installs for the 9092 mapping specifically
# (9093, the controller port, is not published at all) -- read as JSON, so this depends on no output shape.
bind_of(){ hubcfg "$1" --format json 2>/dev/null | jq -r '.services.kafka.ports[] | select(.target==9092) | .host_ip'; }
got="$(bind_of 0.0.0.0)"
[ "$got" = "0.0.0.0" ] && ok "KAFKA_SASL_BIND=0.0.0.0 renders host_ip 0.0.0.0 on the 9092 mapping" || bad "KAFKA_SASL_BIND=0.0.0.0 rendered host_ip '${got:-<none>}' on 9092"
got="$(bind_of 127.0.0.1)"
[ "$got" = "127.0.0.1" ] && ok "KAFKA_SASL_BIND=127.0.0.1 renders a loopback 9092 mapping (the lab-hub case)" || bad "KAFKA_SASL_BIND=127.0.0.1 rendered host_ip '${got:-<none>}' on 9092"
got="$(bind_of '')"
[ "$got" = "0.0.0.0" ] && ok "an empty KAFKA_SASL_BIND falls back to the public 0.0.0.0 default" || bad "an empty KAFKA_SASL_BIND rendered host_ip '${got:-<none>}' on 9092, want the 0.0.0.0 default"
# 9093 is the controller listener inside the container; nothing publishes it.
[ -z "$(hubcfg 0.0.0.0 --format json 2>/dev/null | jq -r '.services.kafka.ports[] | select(.target==9093) | .target')" ] && ok "the controller port 9093 is not published at all" || bad "9093 is still published"

git -C "$HUB/.." ls-files cloud/kafka_server_jaas.conf | grep -q . && bad "JAAS still tracked" || ok "JAAS not tracked"
# `check-ignore -q` refuses more than one pathname ("--quiet is only valid
# with a single pathname", confirmed on git 2.39.5) -- split into two calls,
# same assertion.
git -C "$HUB/.." check-ignore -q hub/.env && git -C "$HUB/.." check-ignore -q hub/kafka_server_jaas.conf && ok "hub/.env and JAAS ignored" || bad "hub secrets not ignored"
git -C "$HUB/.." check-ignore -q hub/connectors/generated/x.json && ok "hub/connectors/generated/ ignored" || bad "hub/connectors/generated/ not ignored"
printf '%s\n' "$fails failure(s)"; exit $((fails>0))
