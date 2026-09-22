#!/bin/bash
# The Filter SMT (io.debezium.transforms.Filter, language jsr223.groovy) used by the
# mysql source and the PG sinks needs these three jars INSIDE each plugin directory.
# They were once docker-cp'd into a running container (MODIFICATIONS.md) and vanished on
# the first `compose up -d kafka-connect` recreate. The compose override now
# bind-mounts them from this directory; the jars are gitignored (7.6 MB), fetch with:
#   bash config/kafka-connect/ext/fetch-scripting-jars.sh
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS="$HERE/../../../../sync/versions.env"
[ -f "$VERSIONS" ] || { echo "fetch-scripting-jars.sh: cannot find sync/versions.env (looked at $VERSIONS)" >&2; exit 1; }
. "$VERSIONS"
cd "$HERE"
M=https://repo1.maven.org/maven2
curl -fsSLO "$M/org/apache/groovy/groovy/${GROOVY_VERSION}/groovy-${GROOVY_VERSION}.jar"
curl -fsSLO "$M/org/apache/groovy/groovy-jsr223/${GROOVY_VERSION}/groovy-jsr223-${GROOVY_VERSION}.jar"
curl -fsSLO "$M/io/debezium/debezium-scripting/${DEBEZIUM_SCRIPTING_VERSION}/debezium-scripting-${DEBEZIUM_SCRIPTING_VERSION}.jar"
ls -la *.jar
