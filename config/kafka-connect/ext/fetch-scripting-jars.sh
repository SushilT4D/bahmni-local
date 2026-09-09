#!/bin/bash
# The Filter SMT (io.debezium.transforms.Filter, language jsr223.groovy) used by the
# mysql source and the PG sinks needs these three jars INSIDE each plugin directory.
# They were once docker-cp'd into a running container (MODIFICATIONS.md) and vanished on
# the first `compose up -d kafka-connect` recreate (2026-09-09). The compose override now
# bind-mounts them from this directory; the jars are gitignored (7.6 MB), fetch with:
#   bash config/kafka-connect/ext/fetch-scripting-jars.sh
set -eu; cd "$(dirname "$0")"
M=https://repo1.maven.org/maven2
curl -fsSLO $M/org/apache/groovy/groovy/4.0.22/groovy-4.0.22.jar
curl -fsSLO $M/org/apache/groovy/groovy-jsr223/4.0.22/groovy-jsr223-4.0.22.jar
curl -fsSLO $M/io/debezium/debezium-scripting/3.2.4.Final/debezium-scripting-3.2.4.Final.jar
ls -la *.jar
