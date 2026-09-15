#!/bin/sh
# ADDED (not in Sushil's repo, not in the upstream image).
#
# Replicates the image's own /start.sh EXCEPT the two liquibase steps. Upstream's
# liquibase 1.9.5 cannot acquire its changelog lock against PostgreSQL: it never
# detects clinlims.databasechangeloglock, so it issues CREATE TABLE on every
# waitForLock retry — succeeding once, then failing "already exists" until it gives
# up. Verified identical on PostgreSQL 14 AND on 9.6.24 (the version the dump came
# from), so this is neither our configuration nor a version skew.
#
# Safe here because the restored dump is an already-migrated OpenELIS schema
# (clinlims.databasechangelog carries 142 applied changesets). If the app needs a
# changeset newer than the dump, it will surface at runtime — that is the risk this
# bypass accepts, and it is why the app is smoke-tested after boot.
set -e

export OPENELIS_DB_SERVER=${OPENELIS_DB_SERVER:-'openelisdb'}
export OPENELIS_DB_PORT=${OPENELIS_DB_PORT:-5432}
export OPENELIS_DB_USERNAME=${OPENELIS_DB_USERNAME:-'clinlims'}
export OPENELIS_DB_PASSWORD=${OPENELIS_DB_PASSWORD:-'clinlims'}
export OPENELIS_DB_NAME=${OPENELIS_DB_NAME:-'clinlims'}

echo "Waiting for ${OPENELIS_DB_SERVER}:${OPENELIS_DB_PORT} for 3600 seconds"
sh wait-for.sh --timeout=3600 ${OPENELIS_DB_SERVER}:${OPENELIS_DB_PORT}

rm -rf /var/www/bahmni_config/
mkdir -p /var/www/bahmni_config/
ln -s /etc/bahmni_config/openelis /var/www/bahmni_config/openelis

envsubst < /etc/bahmni-lab/atomfeed.properties.template \
  > ${WAR_DIRECTORY}/WEB-INF/classes/atomfeed.properties
envsubst < /etc/bahmni-lab/hibernate.cfg.xml.template \
  > ${WAR_DIRECTORY}/WEB-INF/classes/us/mn/state/health/lims/hibernate/hibernate.cfg.xml

./update_openmrs_host_port.sh

echo "[INFO] SKIPPING liquibase migrations (see header; dump is pre-migrated)"
echo "[INFO] Starting Application"
exec java -jar $SERVER_OPTS $DEBUG_OPTS /opt/bahmni-lab/lib/bahmni-lab.jar
