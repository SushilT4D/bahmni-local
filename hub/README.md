# hub/

The sync layer (Kafka, Schema Registry, Kafka Connect, kafka-ui) as its own
compose project, split out of `cloud/` so one hub can serve several clinics.
This file replaces the sync half of `cloud/README.md` -- `cloud/` is the base
Bahmni application stack (OpenMRS/Odoo/OpenELIS); everything about the sync
layer that sat on top of it now lives here.

Attaches to a base stack's Docker network via `KAFKA_BASE_NETWORK` (e.g.
`cloud_default`) -- it does not run standalone. The base stack itself is not
part of this directory; `hub/install/` only *asserts* the base is fit to be a
Debezium source (see "The base stack's contract" below), it never builds or
configures OpenMRS/Odoo/OpenELIS themselves.

## The base stack's contract

`hub/install/tasks/000-preflight.sh` refuses to proceed unless the base
stack already satisfies all of this; `hub/install/tasks/050-base-db.sh`
asserts the striding half of it again once the sync identities exist. The
hub never fixes a violation here -- striding an already-written base is a
data-moving operation, not a prerequisite check's job.

- **MySQL (OpenMRS)**: `binlog_format=ROW`, `binlog_row_image=FULL`, at least
  7 days of binlog retention, a `server_id` distinct from the Debezium
  connector's own id (F-059), and **striding**: `auto_increment_increment=10`,
  `auto_increment_offset=10` -- the hub is residue 0. The base stack's owner
  strides it; the installer only asserts.
- **Postgres (Odoo, OpenELIS/clinlims)**: `wal_level=logical`,
  `max_replication_slots>=4`, `max_wal_senders>=4`, and the same striding
  contract on every synced sequence (`increment_by=10`, `last_value` a
  multiple of 10 or unused) -- checked per table, derived from
  `sync/subsystems.conf`, never hand-copied.
- **One Postgres container or two**: the mini and every clinic run Odoo and
  OpenELIS in one shared Postgres container/superuser. IPLIT's real hub base
  runs them as two separate containers with different bootstrap superusers.
  Both shapes are supported: `BASE_ELIS_CONTAINER`/`BASE_ELIS_SUPERUSER`
  default from `BASE_PG_CONTAINER`/`BASE_PG_SUPERUSER` when unset (the
  one-container case) and are set explicitly for the two-container case.
  Every task that touches Postgres (`pg_admin`, `hub/install/lib.sh`)
  dispatches to the right container purely from the database name it's
  given (`odoo` vs. `openelis`).
- **The network**: `KAFKA_BASE_NETWORK` must already exist and be the base
  stack's own compose network -- the hub attaches to it, never creates it.

## Install

```
hub/install/install.sh --hub <name> --base-env <path> --secrets <path> [--from NNN] [--dry-run]
```

`--base-env` is the base stack's own `.env` (root credentials, existing sink
passwords); `--secrets` is the operator's file holding the fleet SASL
password. Both are only required the first time (before `hub/.env` exists) --
a resume after task `NNN` needs neither:

```
hub/install/install.sh --hub <name> --from 060
```

`hub/.env` is composed once by `hub_compose_env` (`hub/install/lib.sh`) from
three sources: `sync/hub.env` (the fleet's endpoint pointer), the base
stack's own `.env`, and the operator's `--secrets` file. A value already
present in `hub/.env` is kept on every subsequent run -- a resume never
regenerates a secret.

## hub/.env keys

Every key below is blank in `hub/.env.example`; `hub_compose_env` fills them
in (from the three sources above, or a fresh random value via `gen_secret`).
Never hand-fill a real value into the example and commit it.

| Key | What it is |
|---|---|
| `KAFKA_CLUSTER_ID` | KRaft cluster id for this hub's broker; must match the `kafka-data` volume's `meta.properties`. |
| `REMOTE_KAFKA_HOST` | Hostname/IP this hub's broker advertises on its SASL_PLAINTEXT listener, for clinics to dial. |
| `KAFKA_BASE_NETWORK` | Docker network name of the base stack this hub attaches to. |
| `KAFKA_ADMIN_PASSWORD` | SASL PLAIN password for the broker's own `admin` JAAS user. |
| `REMOTE_KAFKA_PASSWORD` | SASL PLAIN password clinics present when authenticating to this hub. |
| `DEBEZIUM_DB_USER` | MySQL user the down-direction (cloud→clinic) Debezium source logs in as. |
| `DEBEZIUM_DB_PASSWORD` | Password for `DEBEZIUM_DB_USER`. |
| `REMOTE_MYSQL_HOST` | Host of the MySQL server the up-direction JDBC sinks write into (the base's own `openmrsdb`). |
| `REMOTE_MYSQL_PORT` | Port of that same sink-target MySQL server. |
| `REMOTE_MYSQL_DATABASE` | Database name on the sink-target MySQL server. |
| `REMOTE_MYSQL_USER` | MySQL role the JDBC sinks use to write into `REMOTE_MYSQL_HOST`. |
| `REMOTE_MYSQL_PASSWORD` | Password for `REMOTE_MYSQL_USER`. |
| `REMOTE_MYSQL_USE_SSL` | Whether the JDBC sinks connect over SSL (`true`/`false`). |
| `ODOO_SINK_PASSWORD` | Password for the `odoo_sink` Postgres role the up-direction sinks write through. |
| `CLINLIMS_SINK_PASSWORD` | Password for the `clinlims_sink` Postgres role the up-direction sinks write through. |
| `CLOUD_MYSQL_SERVER_NAME` | Debezium logical server name (topic prefix) for the down-direction MySQL source. |
| `CLOUD_DEBEZIUM_SERVER_ID` | MySQL replication server-id the down-direction source presents; unique fleet-wide. |
| `KAFKA_CONNECT_URL` | Base URL the register/generate scripts use to reach Kafka Connect's REST API. |
| `BASE_MYSQL_ROOT_PASSWORD` | Root password of the base stack's MySQL. |
| `BASE_PG_SUPERUSER` | Postgres superuser name on the base's Odoo Postgres. |
| `BASE_PG_PASSWORD` | Password for `BASE_PG_SUPERUSER`; may be blank (no network password). |
| `BASE_MYSQL_CONTAINER` | Container name of the base stack's MySQL service. |
| `BASE_PG_CONTAINER` | Container name of the base stack's Postgres service (Odoo's). |
| `BASE_ELIS_CONTAINER` | Container name of the Postgres hosting OpenELIS/clinlims; defaults from `BASE_PG_CONTAINER`. |
| `BASE_ELIS_SUPERUSER` | Superuser on that container; defaults from `BASE_PG_SUPERUSER`. |
| `CLOUD_MYSQL_HOST` | Hostname the down-direction source dials; defaults from `BASE_MYSQL_CONTAINER`. |
| `CLOUD_MYSQL_PORT` | Port of the base's MySQL server the down-direction source reads from. |
| `CLOUD_MYSQL_DATABASE` | Database on the base's MySQL server the down-direction source captures from. |
| `ODOO_DB_PASSWORD` | The base's own `odoo` Postgres role password; the `odoo-cloud-source` connector logs in with it. |
| `CLINLIMS_SOURCE_PASSWORD` | The base's own `clinlims` Postgres role password (from its `OPENELIS_DB_PASSWORD`). |
| `REMOTE_SERVER_NAME` | Debezium logical server name the two Postgres relay sources reference. |
| `KAFKA_UI_USER` | Login for kafka-ui (127.0.0.1:8080 only); defaults to `admin`. |
| `KAFKA_UI_PASSWORD` | Password for `KAFKA_UI_USER`; generated like every other secret here. |

Every fleet image pin (`KAFKA_IMAGE`, `DEBEZIUM_CONNECT_IMAGE`,
`KAFKA_UI_IMAGE`, ...) is copied in from `sync/versions.env` at compose time
(`versions_put`) -- change a pin there, never in `hub/.env` directly (L-005:
lockstep, cloud first, one place).

## Tasks

Each task is idempotent, ends with a value read back from the live system
(never just "it didn't error"), and can be resumed with `--from NNN`.

| Task | Proves |
|---|---|
| `000-preflight` | The base network and both containers exist; base MySQL/Postgres (and the ELIS Postgres too, when it's a separate container) meet the contract above; the host has disk and memory to start. |
| `020-env` | `hub/.env` is composed, every `HUB_KEYS` entry is present and non-empty, the file is mode 600, and every value round-trips through actually `.`-sourcing the file (not just `env_get`'s own parse of it). |
| `030-jaas` | `kafka_server_jaas.conf` is generated (never hand-written or committed) with the admin and mirrormaker users, mode 600; `hub/connectors/` exists. |
| `040-images` | Every image `docker compose config --images` names is present locally. |
| `050-base-db` | The MySQL sink+debezium accounts and the Postgres `odoo_sink`/`clinlims_sink` roles exist, are granted, and authenticate over the network; the two ownership publications are converged from `sync/subsystems.conf`; a heartbeat table exists in both databases; sequence striding holds; no `hub_%` replication origin exists on either Postgres instance. |
| `060-kafka` | The KRaft controller + broker + Schema Registry come up; the broker's cluster id matches; the published SASL_PLAINTEXT listener authenticates the mirrormaker user; Schema Registry answers. |
| `070-connect` | Kafka Connect comes up with all three plugin classes (MySQL source, Postgres source, JDBC sink) resolved; kafka-ui comes up behind a real login -- the login page answers, an unauthenticated API call is refused, and `KAFKA_UI_USER`/`KAFKA_UI_PASSWORD` actually log in and read the cluster back. |
| `080-sources` | The base MySQL is fit for Debezium 3.6.2 (major version 8+); the down-direction MySQL source and the two up-direction Postgres relay sources are registered, all RUNNING (connector and every task); both down-direction replication slots are active; schema-history retention is `-1`; the heartbeat keys are present in both Postgres sources' configs. |
| `090-exit-checks` | Everything above still holds, read fresh: disk free under the broker's own data volume; every connector and task still RUNNING; both replication slots retain under 2 GB; the SASL listener still answers; `hub/.env` and the JAAS file are still mode 600; the git checkout is clean. |
| `100-join` | Nothing about the hub itself -- prints the operator hand-off (see below). |

## Joining and leaving a clinic

The hub's own authority ends at task `090`. Adding or removing a clinic is
the **operator's** job, run from the Bahmni workspace on a machine that
reaches both GitHub and this hub -- never from the hub's own install. Task
`100` prints the exact command, with this hub's own `HUB_SSH`/`HUB_REPO`
filled in from `hub/.env` at run time (the SSH key path and the checkout
path on the hub are genuinely unknowable from here, and are always printed
as placeholders, never invented):

```
HUB_KEY=<path to this hub's operator SSH private key> HUB_SSH=<ssh-user>@<REMOTE_KAFKA_HOST> \
HUB_REPO=<path to the bahmni-local checkout on this hub> HUB_GIT=pull \
skills/install-clinic.sh join <slug>
```

and the equivalent `leave <slug>` to make the hub forget a clinic so it can
be reinstalled and joined anew. `HUB_GIT=pull` is deliberate: unlike the dev
mini (which receives a push over SSH), a real hub fetches GitHub itself.

**What this fleet cannot yet give a joining clinic**: mTLS and per-site
broker ACLs (L-007). Every clinic dials this hub's public listener
(`SASL_PLAINTEXT://<REMOTE_KAFKA_HOST>:9092`) with the same fleet-wide SASL
user -- there is no per-site revocable credential yet.

## The origin model: none, on the hub

Replication origins exist so a **clinic** can tell a row it just received
back from the hub apart from one it wrote itself (L-009) -- without one, a
clinic would re-publish what it just received, an infinite loop. The hub has
no such problem: its whole job is to relay everything every clinic sent it
onward to every other clinic, so an origin on the hub would make it start
filtering its own relay. `050-base-db.sh` therefore creates no origin and
asserts none exists (`pg_replication_origin` carrying no `hub_%` row), on
both Postgres instances when the base runs two.

The two ownership publications this task converges
(`dbz_odoo_owned`/`dbz_clinlims_owned`) are also **unfiltered** `FOR TABLE`
lists, unlike a clinic's own row-filtered publication (`id % 10 = residue`):
a spoke publishes only the rows it owns so it never re-publishes what it
received, but the hub relays everything, so per-table filtering would
silently drop the rows this layer exists to move.

**F-072**: `hub/openelis/enable-hub-relay.sql` and
`hub/openelis/setup-clinlims-sync.sql` predate this design (pre-F-049) and
are **not** part of the procedure above -- the publications are derived
live from `sync/subsystems.conf` by `050-base-db.sh`, not from those two
files. They are kept for history, not run by anything here.

## kafka-ui

A Kafka/Connect/topic browser at `http://127.0.0.1:8080`, bound to loopback
only -- reach it over an SSH tunnel to the hub, never expose it publicly.
Behind a real login (`AUTH_TYPE=LOGIN_FORM`, `KAFKA_UI_USER`/
`KAFKA_UI_PASSWORD` from `hub/.env`), started by task `070` alongside Kafka
Connect. An unauthenticated request to any real API route is refused --
kafbat's own build redirects it to the login page (HTTP 302) rather than a
bare 401/403; both tasks `070` and `090` treat either shape as a pass, and
`070` additionally logs in with the configured credentials and reads the
cluster back, so a stale or wrong password is caught at install time, not
the first time an operator tries to use it.
