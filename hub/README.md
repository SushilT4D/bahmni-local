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
- **Postgres (Odoo, OpenELIS), 16 or newer**: `wal_level=logical`,
  `max_wal_senders>=4`, `max_replication_slots` at least 4 and at least the
  number of replication origins the instance holds (below), and every synced
  sequence incrementing by 10 on residue 0. The synced tables are listed in
  `sync/subsystems.conf`. 16 is the first version whose `pgoutput` accepts the
  `origin` option the Odoo and OpenELIS sources decode with.
- **Accounts**: a MySQL account for the sinks and one for Debezium; Postgres
  roles `odoo_sink` and `clinlims_sink`, each with `EXECUTE` on
  `pg_replication_origin_session_setup`, `pg_replication_origin_session_reset`
  and `pg_replication_origin_session_is_setup` in its own database;
  `REPLICATION` on the roles the Odoo and OpenELIS sources log in as.
- **Publication** `dbz_odoo_owned` over exactly the down list,
  `sync/hub-down.conf`, built by `scripts/apply-down-publication.sh`. Each
  table with an `id` carries the row filter `(id < <floor> OR id % 10 = 0)`,
  with this hub's floors in `hub/odoo-down-floors.local` (below).
- **Publication** `dbz_clinlims_owned` over the OpenELIS rows of the down list,
  built by `scripts/apply-clinlims-down-publication.sh`: `result`, `analysis`
  and `sample` with no row filter (those rows keep the clinic's ids, and the
  source's `origin=none` is what keeps a clinic's own writes at the hub); the
  lab accounts, `system_user`, and the lab test catalogue (tests, panels,
  sample types, departments, result options and every table they point to)
  with `(id < <floor> OR id % 10 = 0)` on this hub's floors in
  `hub/clinlims-down-floors.local`, the catalogue's two link tables without an
  `id` unfiltered. The floors are recorded once, by the run that strides the
  hub's OpenELIS ids, just before it strides:
  `scripts/stride-openelis.sh -- <psql command>` (residue 0, from
  `openelis/apply-sequence-striding.sql`; a second run keeps the floors and
  moves nothing). On a hub strided before a table joined the down list,
  `scripts/record-clinlims-down-floors.sh --derive -- <psql command>` prints
  that table's floor read from its rows, and `--from-file <file>` adds it to
  the floors file, leaving the floors it already holds as they are.
- **Replication origins**, one per clinic per database: `clinic_<slug>_odoo` in
  the Odoo instance and `clinic_<slug>_clinlims` in the OpenELIS instance,
  created when the clinic joins.

## What the hub publishes

Master and reference tables, and the lab rows a hub lab user completes for a
clinic's sample; of those, only the rows written at the hub.

The clinics send up every table in `sync/subsystems.conf`. The hub sends down
only `sync/hub-down.conf`: products, categories, units of measure and the
address tables, plus the three product link tables and the central-transfer
tables; the OpenELIS `result`, `analysis` and `sample` rows, each routed to
one clinic; and, to every clinic, the OpenELIS lab accounts and lab test
catalogue and the OpenMRS concept dictionary (as changes only). Partners,
sales, invoices, stock levels and every other OpenELIS table stay at the
clinic that wrote them, so a hub edit to one of
those rows (by a person, or by the OpenMRS-to-Odoo
feed) reaches no clinic. The hub source's table list and aggregate regex, the
publication and each clinic's MirrorMaker down regex are all rendered from that
one list; `sync/hub-down.sh` reads it and refuses an up-only table by name.

On the tables that do go down, the row filter keeps a clinic's rows at the hub
even when the hub edits them: below a table's floor the rows predate striding
and are the hub's; above it the hub mints residue 0. A floor is the value the
table's sequence restarted at when the hub's Odoo ids were strided, and it is
recorded by that same run: `scripts/stride-odoo.sh -- <psql command>` strides
and writes `hub/odoo-down-floors.local` (one `<table> <floor>` line per table
with an `id`; never committed). A re-run strides again and leaves the file as
it is, refusing if a sequence would restart below its floor. Floors are never
read back from the sequences later: once the hub has issued ids they no longer
show it. A hub strided before this script records its floors from the values
captured then, with `scripts/record-down-floors.sh --from-file <file>`. The
publication step refuses, naming the table, when a floor is missing, and
publishes no TRUNCATE (it ignores row filters).

Within those tables, only the rows written at the hub. A row from a clinic stops here: the up-sinks
that write a clinic's Odoo and OpenELIS rows into the hub claim that clinic's
replication origin on their one connection (`hibernate.agroal.initialSQL`), so
every row they apply is tagged, and the Odoo source decodes with
`slot.stream.params=origin=none`, so a tagged row is never published down to
another clinic or back to its sender.
OpenMRS gets the same result from the MySQL source's table list, which holds
only tables the hub writes. A clinic does the same in the other direction.

PostgreSQL lets one session at a time hold an origin, which is why each clinic
has its own and why those sinks keep `tasks.max` and the pool at one. A sink
that does not claim an origin writes rows the hub publishes to every clinic.

## Files this directory needs that are not tracked

- `hub/.env`, mode 600. Every key is listed and described in `.env.example`.
  Image names come from `sync/versions.env`; change a version there.
- The three Groovy scripting jars in `clinic/config/kafka-connect/ext/`
  (`bash clinic/config/kafka-connect/ext/fetch-scripting-jars.sh`). The hub's
  Connect mounts them into its MySQL connector, whose row filter sends down
  only the lab-result rows the hub wrote itself (`hub/tables.conf`, `clinic=`
  rows). Without them that connector fails at configuration.
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
  registers the Odoo source, `odoo-cloud-source`, filling its table list and
  aggregate regex from `sync/hub-down.conf`, and the OpenELIS source,
  `clinlims-cloud-source` (slot `dbz_clinlims_down`), filling its table list
  and aggregate regex from the same file's OpenELIS rows. Each decodes with
  `origin=none` and starts with `snapshot.mode=no_data`: nothing written
  before it is registered is sent.
- A table added to `tables.conf` after the MySQL source first started: the
  source records the structure of only the tables it captures
  (`schema.history.internal.store.only.captured.tables.ddl=true`) and resumes
  from its offsets, so it has no structure for the new table and stops at that
  table's first change ("whose schema isn't known to this connector"). Before
  it captures the table, rebuild its structure record: stop the source
  (`PUT .../stop`), delete its topic `schema-changes.<server name>`, register
  the generated config once with `"snapshot.mode": "recovery"` (the structure
  of every captured table, no rows), resume it, then register the generated
  config as it is. A source registered on a Kafka with no offsets reads every
  structure on its first start and needs none of this.
- Up direction, one set per clinic listed in this hub's `clinics.<HUB_NAME>.conf` (the sinks for
  `obs`, `orders`, `drug_order` and `test_order` only for a row ending in
  `:clinical`, a
  clinic installed with `CLINICAL_UP_SYNC=test`):
  `scripts/generate-sink-connectors.sh <slug>` then
  `scripts/register-all-sink-connectors.sh` for the MySQL sinks, and
  `connectors/register-odoo.sh` for that clinic's Odoo and OpenELIS sinks.

Rendered connector files hold passwords and are gitignored.

## Checks

- `scripts/check-clinical-fks.sh --container <hub mysql>` reads the foreign
  keys on `obs`, `orders`, `drug_order` and `test_order` (read-only). An FK out
  of those tables to a table a clinic writes fails it: the up sinks write each
  table in arrival order, and such an FK would stop a sink whenever a clinic's
  row arrives before its parent. An FK out to a table only the hub writes
  (`DOWN` in `table-verdicts.conf`) or only changesets and the seed write
  (`RESEED`) passes and is named: its rows are at the hub first.
  The FKs into them are compared with `clinical-fks-in.conf`, and a difference
  is reported (exit 2). Run it before and after every hub upgrade;
  `scripts/register-all-sink-connectors.sh` runs it itself before it registers
  any sink for these tables (set `HUB_MYSQL_CONTAINER`) and registers nothing
  when a key points out of one.

## Not provided yet

Per-site certificates (mTLS) and broker ACLs. Every clinic authenticates with
the same SASL user; there is no per-site revocable credential.
