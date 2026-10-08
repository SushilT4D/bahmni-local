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
- `hub/tls/`, mode 700, when the clinic listener is `SASL_SSL` (the default):
  the keystore (`kafka.keystore.p12`: the hub's private key and its
  certificate, whose name must cover `REMOTE_KAFKA_HOST`), `keystore_creds`
  holding the keystore password, and `key_creds` holding the key password
  (the same value for a PKCS12 keystore). Every clinic trusts the certificate
  through `sync/hub-ca.pem`.

Making the keystore from a key and certificate in PEM form:

```
cd hub && mkdir -p tls && chmod 700 tls && umask 077
openssl rand -hex 24 > tls/keystore_creds && cp tls/keystore_creds tls/key_creds
openssl pkcs12 -export -inkey server.key -in server.crt -name kafka -out tls/kafka.keystore.p12 -passout file:tls/keystore_creds
```

A JKS keystore works too: set `KAFKA_SSL_KEYSTORE_TYPE=JKS` and
`KAFKA_SSL_KEYSTORE_FILENAME` to its name.

## Running it

```
docker compose up -d                 # kafka, kafka-connect
docker compose --profile ui up -d    # also kafka-ui
```

Port 9092 is the listener every clinic dials: SASL over TLS (`SASL_SSL`) by
default, or `SASL_PLAINTEXT` when `KAFKA_CLINIC_PROTOCOL` says so, in which
case passwords and records cross the network unencrypted. It is published on
`KAFKA_SASL_BIND`, which defaults to `0.0.0.0`; set `127.0.0.1` only when a
local proxy fronts it. Tools on this host use the internal plain listener,
`kafka:29092`; pointed at 9092 without TLS settings they fail with an
out-of-memory error, because they read the TLS reply as a message length. Kafka Connect (8083) and kafka-ui (8080) are published
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

## Checks

- `scripts/check-clinical-fks.sh --container <hub mysql>` reads the foreign
  keys on `obs`, `orders` and `drug_order` (read-only). Any FK out of those
  tables fails it: the up sinks write each table in arrival order, and an FK
  out would stop a sink whenever a clinic's row arrives before its parent.
  The FKs into them are compared with `clinical-fks-in.conf`, and a difference
  is reported (exit 2). Run it before registering the up sinks for these
  tables and before and after every hub upgrade.

## Not provided yet

Per-site certificates (mTLS) and broker ACLs. Every clinic authenticates with
the same SASL user; there is no per-site revocable credential.
