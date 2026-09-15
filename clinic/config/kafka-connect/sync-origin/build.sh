#!/usr/bin/env bash
# Reproduces ../sync-origin-customizer.jar from SyncOriginCustomizer.java (AL-021).
# Compiles against the c3p0 jar the Debezium image ships, inside a JDK container,
# so no host needs Java. Usage: build.sh [docker|podman]
set -euo pipefail
CT="${1:-docker}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT_IMAGE="${CONNECT_IMAGE:-quay.io/debezium/connect:3.2.4.Final}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cid="$("$CT" create "$CONNECT_IMAGE")"
"$CT" cp "$cid:/kafka/connect/debezium-connector-jdbc/." "$tmp/plugin" >/dev/null
"$CT" rm "$cid" >/dev/null
c3p0="$(ls "$tmp"/plugin/c3p0-*.jar | head -1)"
[ -n "$c3p0" ] || { echo "no c3p0 jar in ${CONNECT_IMAGE}" >&2; exit 1; }
mkdir -p "$tmp/out"
"$CT" run --rm -v "$HERE:/src:ro" -v "$tmp:/w" eclipse-temurin:17-jdk sh -c \
  "javac -cp /w/plugin/$(basename "$c3p0") -d /w/out /src/t4d/sync/SyncOriginCustomizer.java && cd /w/out && jar cf /w/sync-origin-customizer.jar t4d"
# A jar's bytes carry zip timestamps, so compare the CLASS bytes with the tracked
# jar: identical -> the tracked jar stays (nothing to commit); different -> replace.
tracked="$HERE/../sync-origin-customizer.jar"
if [ -f "$tracked" ] && cmp -s <(unzip -p "$tracked" t4d/sync/SyncOriginCustomizer.class) <(unzip -p "$tmp/sync-origin-customizer.jar" t4d/sync/SyncOriginCustomizer.class); then
  echo "reproducible: the class in $tracked is byte-identical to a fresh build from source"
else
  cp "$tmp/sync-origin-customizer.jar" "$tracked"; echo "REPLACED $tracked -- the source and the tracked jar had diverged; commit the new jar"
fi
