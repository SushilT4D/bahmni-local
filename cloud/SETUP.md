
# SETUP

Here are the cloud setup steps as commands. Run them on the cloud server.

## Setup (every session)

```bash
cd /App/bahmni-std-cloud-package-master
export BASE_DIR=/home/ubuntu/bahmni-local
set -a; . ./.env; . "${BASE_DIR}/sync/versions.env"; set +a   # versions.env: the image pins docker compose reads
export BASE_PG_CONTAINER=bahmni-std-cloud-package-master-odoodb-1
export BASE_ELIS_CONTAINER=bahmni-std-cloud-package-master-openelisdb-1
export BASE_MYSQL_CONTAINER=bahmni-std-cloud-package-master-openmrsdb-1
C="${KAFKA_CONNECT_URL:-http://localhost:8083}"
my()      { docker exec -i "$BASE_MYSQL_CONTAINER" sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -t'; }
pg_odoo() { docker exec -i "$BASE_PG_CONTAINER" psql -U "$ODOO_DB_USER" -d "$ODOO_DB_NAME" -v ON_ERROR_STOP=1 "$@"; }
pg_elis() { docker exec -i "$BASE_ELIS_CONTAINER" psql -U "$OPENELIS_DB_USER" -d openelis -v ON_ERROR_STOP=1 "$@"; }
kt()      { docker exec kafka kafka-topics --bootstrap-server kafka:29092 "$@"; }
```

## One-time

### MySQL

**Check settings**
```bash
my <<'SQL'
SELECT @@version, @@log_bin, @@binlog_format, @@binlog_row_image,
       @@binlog_expire_logs_seconds, @@server_id,
       @@auto_increment_increment, @@auto_increment_offset;
SQL
```
Want: 8.0.x, 1, ROW, FULL, ≥604800, ≠184055, 10, 10.

**Fix settings and stride**
```bash
my <<'SQL'
SET PERSIST binlog_format = 'ROW';
SET PERSIST binlog_row_image = 'FULL';
SET PERSIST binlog_expire_logs_seconds = 604800;
SET PERSIST auto_increment_increment = 10;
SET PERSIST auto_increment_offset = 10;
SQL
docker restart "$(docker ps --format '{{.Names}}' | grep -i openmrs | grep -vi db | head -1)"
```

**Create the Debezium account**
```bash
my <<SQL
CREATE USER IF NOT EXISTS '${DEBEZIUM_DB_USER}'@'%' IDENTIFIED BY '${DEBEZIUM_DB_PASSWORD}';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT, SESSION_VARIABLES_ADMIN ON *.* TO '${DEBEZIUM_DB_USER}'@'%';
GRANT INSERT, UPDATE, DELETE ON \`${OPENMRS_DB_NAME}\`.* TO '${DEBEZIUM_DB_USER}'@'%';
SQL
```

**Check the clinical foreign keys**
```bash
${BASE_DIR}/cloud/scripts/check-clinical-fks.sh --container "$BASE_MYSQL_CONTAINER"
```

### Postgres

**Check settings**
```bash
pg_odoo <<'SQL'
SELECT version();
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SQL
pg_elis <<'SQL'
SELECT version();
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SQL
```
Want: ≥16, logical, ≥4, ≥ (number of clinics + 2).

**Fix settings** (restarts Postgres)
```bash
pg_odoo <<'SQL'
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 20;
SQL
pg_elis <<'SQL'
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 20;
SQL
docker restart "$BASE_PG_CONTAINER" "$BASE_ELIS_CONTAINER"
```

**Stride ids and record floors**
```bash
${BASE_DIR}/cloud/scripts/stride.sh odoo     -- docker exec -i "$BASE_PG_CONTAINER" psql -U "$ODOO_DB_USER" -d "$ODOO_DB_NAME"
${BASE_DIR}/cloud/scripts/stride.sh openelis -- docker exec -i "$BASE_ELIS_CONTAINER" psql -U "$OPENELIS_DB_USER" -d openelis
ls -l odoo-down-floors.local clinlims-down-floors.local
```

**Create the sink roles**
```bash
pg_odoo -q <<SQL
CREATE ROLE odoo_sink LOGIN PASSWORD '${ODOO_SINK_PASSWORD}';
GRANT USAGE ON SCHEMA public TO odoo_sink;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO odoo_sink;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO odoo_sink;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO odoo_sink;
SQL
pg_elis -q <<SQL
CREATE ROLE clinlims_sink LOGIN PASSWORD '${CLINLIMS_SINK_PASSWORD}';
GRANT USAGE ON SCHEMA clinlims TO clinlims_sink;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA clinlims TO clinlims_sink;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA clinlims TO clinlims_sink;
ALTER DEFAULT PRIVILEGES IN SCHEMA clinlims GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO clinlims_sink;
SQL
```

**Give REPLICATION to the source logins**
```bash
pg_odoo -c "ALTER ROLE \"$ODOO_DB_USER\" REPLICATION;"
pg_elis -c "ALTER ROLE \"$OPENELIS_DB_USER\" REPLICATION;"
```

**Build the down publications**
```bash
${BASE_DIR}/cloud/scripts/apply-down-publication.sh odoo     odoo-down-floors.local     -- docker exec -i "$BASE_PG_CONTAINER" psql -U "$ODOO_DB_USER" -d "$ODOO_DB_NAME"
${BASE_DIR}/cloud/scripts/apply-down-publication.sh openelis clinlims-down-floors.local -- docker exec -i "$BASE_ELIS_CONTAINER" psql -U "$OPENELIS_DB_USER" -d openelis
```

### Kafka and Connect

**Set new Kafka passwords in .env**
```bash
for k in KAFKA_PASSWORD KAFKA_APP_PASSWORD KAFKA_ADMIN_PASSWORD KAFKA_KEYSTORE_PASSWORD KAFKA_TRUSTSTORE_PASSWORD; do
  sed -i "s/^$k=.*/$k=$(openssl rand -hex 24)/" .env
done
set -a; . ./.env; set +a
```

**Create certificates**
```bash
bash ${BASE_DIR}/cloud/setup-certs.sh
mkdir -p "$CONTAINER_DATA_PATH/certs/kafka"
cp certs/kafka/kafka.keystore.p12 certs/kafka/kafka.truststore.p12 "$CONTAINER_DATA_PATH/certs/kafka/"
```

**Fetch the Groovy jars**
```bash
bash ${BASE_DIR}/clinic/config/kafka-connect/ext/fetch-scripting-jars.sh
```

**Start (or restart) Kafka and Connect with the new passwords**
```bash
docker compose --profile debezium up -d --force-recreate kafka kafka-connect
```

**Load the Groovy jars into Connect**
```bash
for j in ${BASE_DIR}/clinic/config/kafka-connect/ext/*.jar; do docker cp "$j" kafka-connect:/kafka/connect/debezium-connector-mysql/; done
docker restart kafka-connect
```

**Publish the CA and give clinics their login settings** (on a checkout that can push)
```bash
cp certs/ca/ca.crt ${BASE_DIR}/sync/cloud-ca.pem
git -C ${BASE_DIR} add sync/cloud-ca.pem && git -C ${BASE_DIR} commit -m "Cloud Kafka CA" && git -C ${BASE_DIR} push
echo "Each clinic's clinic/.env: REMOTE_KAFKA_BOOTSTRAP_SERVERS=${KAFKA_CLOUD_HOST}:9092 REMOTE_KAFKA_USERNAME=app REMOTE_KAFKA_SECURITY_PROTOCOL=SASL_SSL REMOTE_KAFKA_PASSWORD=$KAFKA_APP_PASSWORD"
```

**Create the cloud's OpenMRS topic**
```bash
kt --create --if-not-exists --topic "${CLOUD_MYSQL_SERVER_NAME:-bahmni-cloud}.openmrs.all" --partitions 1 --replication-factor 1
```

**Register the cloud's sources**
```bash
${BASE_DIR}/cloud/scripts/generate-cloud-source-connector.sh
f=connectors/mysql-cloud-source-connector.json
jq .config "$f" | curl -s -X PUT -H 'Content-Type: application/json' --data-binary @- "$C/connectors/$(jq -r .name "$f")/config"
${BASE_DIR}/cloud/scripts/register-odoo.sh
curl -s "$C/connectors?expand=status" | jq -r '.[] | "\(.status.name) \(.status.connector.state) \([.status.tasks[].state] | join(","))"'
```

### Cleanup (after every clinic has switched over)

**Delete the old sinks** (per-table `mysql-sink-*` and `*-sink-all`)
```bash
for c in $(curl -s "$C/connectors" | jq -r '.[] | select(startswith("mysql-sink-") or endswith("-sink-all"))'); do
  curl -s -X DELETE "$C/connectors/$c"; echo "deleted $c"
done
```

## Per clinic

Every name comes from the clinic's slug, which is already in `sync/clinics.json`.

**Set the slug**
```bash
SLUG=<slug>
```

**Create the replication origins**
```bash
pg_odoo -v origin="clinic_${SLUG}_odoo"     -v role=odoo_sink     < postgres/apply-sink-origin.sql
pg_elis -v origin="clinic_${SLUG}_clinlims" -v role=clinlims_sink < postgres/apply-sink-origin.sql
```

**Create the topics**
```bash
for db in openmrs odoo clinlims; do
  kt --create --if-not-exists --topic "$SLUG.bahmni-$SLUG.$db.all" --partitions 1 --replication-factor 1
done
```

**Generate and register the sinks**
```bash
${BASE_DIR}/cloud/scripts/generate-sink-connectors.sh "$SLUG"
HUB_MYSQL_CONTAINER="$BASE_MYSQL_CONTAINER" ${BASE_DIR}/cloud/scripts/register-all-sink-connectors.sh
```

**Check the clinic's sinks**
```bash
curl -s "$C/connectors?expand=status" | jq -r --arg s "$SLUG" '.[] | select(.status.name | contains($s)) | "\(.status.name) \(.status.connector.state) \([.status.tasks[].state] | join(","))"'
```

## Gaps in the repo

- `cloud/docker-compose.yml` has no mounts for the Groovy jars, so the `docker cp` above is lost whenever kafka-connect is recreated.

