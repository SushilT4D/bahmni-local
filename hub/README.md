# hub/

The hub's sync layer as its own compose project: one Kafka node holding both
KRaft roles, Kafka Connect, and kafka-ui on request. It runs beside the hub's
Bahmni application stack (OpenMRS, Odoo, OpenELIS), which is not part of this
repository, and attaches to that stack's Docker network through
`KAFKA_BASE_NETWORK`. It does not run standalone.

## What the application stack must provide

- **MySQL (OpenMRS), 8.0.x**: `binlog_format=ROW`, `binlog_row_image=FULL`, at
  least 7 days of binlog retention, a `server_id` distinct from the Debezium
  connector's own id, and striding: `auto_increment_increment=10`,
  `auto_increment_offset=10`. The hub is residue 0.
- **Postgres (Odoo, OpenELIS), 10 or newer**: `wal_level=logical`,
  `max_replication_slots>=4`, `max_wal_senders>=4`, and every synced sequence
  incrementing by 10 on residue 0. The synced tables are listed in
  `sync/subsystems.conf`.
- **Accounts**: a MySQL account for the sinks and one for Debezium; Postgres
  roles `odoo_sink` and `clinlims_sink`; `REPLICATION` on the roles the two
  Postgres sources log in as.
- **Publications** `dbz_odoo_owned` and `dbz_clinlims_owned` over the synced
  tables, with no row filter and no replication origin. A clinic filters so it
  never re-publishes what it received; the hub relays everything, so a filter
  here would drop the rows this layer exists to move.

## Files this directory needs that are not tracked

- `hub/.env`, mode 600. Every key is listed and described in `.env.example`.
  Image names come from `sync/versions.env`; change a version there.
- `hub/kafka_server_jaas.conf`, mode 600: a `KafkaServer` section for the
  `PLAIN` mechanism with two users, `admin` (`KAFKA_ADMIN_PASSWORD`) and the
  one clinics log in as (`REMOTE_KAFKA_PASSWORD`).

## Running it

```
docker compose up -d                 # kafka, kafka-connect
docker compose --profile ui up -d    # also kafka-ui
```

Port 9092 is the SASL_PLAINTEXT listener every clinic dials. It is published
on `KAFKA_SASL_BIND`, which defaults to `0.0.0.0`; set `127.0.0.1` only when a
local proxy fronts it. Kafka Connect (8083) and kafka-ui (8080) are published
on loopback only; reach them over an SSH tunnel.

## Connectors

- Down direction, hub to clinics: `scripts/generate-cloud-source-connector.sh`
  renders the MySQL source from `tables.conf`; `connectors/register-odoo.sh`
  registers the two Postgres sources (`odoo-cloud-source`,
  `clinlims-cloud-source`).
- Up direction, one set per clinic listed in `clinics.conf`:
  `scripts/generate-sink-connectors.sh <slug>` then
  `scripts/register-all-sink-connectors.sh` for the MySQL sinks, and
  `connectors/register-odoo.sh` for that clinic's Odoo and OpenELIS sinks.

Rendered connector files hold passwords and are gitignored.

## Not provided yet

mTLS and per-site broker ACLs. Every clinic authenticates with the same SASL
user; there is no per-site revocable credential.
