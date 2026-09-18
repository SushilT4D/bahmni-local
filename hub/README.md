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

- **MySQL (OpenMRS) -- 8.0.x**: `binlog_format=ROW`, `binlog_row_image=FULL`,
  at least 7 days of binlog retention, a `server_id` distinct from the Debezium
  connector's own id (F-059), and **striding**: `auto_increment_increment=10`,
  `auto_increment_offset=10` -- the hub is residue 0. The base stack's owner
  strides it; the installer only asserts. The version floor is Debezium 3.6.2's
  (MySQL 8.0.x only): task `000` still reads 5.6/5.7's binlog settings, but task
  `080` refuses to register a source against anything below major 8.
- **Postgres (Odoo, OpenELIS/clinlims) -- 10 or newer**: `wal_level=logical`,
  `max_replication_slots>=4`, `max_wal_senders>=4`, and the same striding
  contract on every synced sequence (`increment_by=10`, `last_value` a
  multiple of 10 or unused) -- checked per table, derived from
  `sync/subsystems.conf`, never hand-copied. The major-version floor is
  checked on **both** instances: `pgoutput` (every source here decodes with it)
  and the `pg_sequences` view the striding assertion reads both arrived in 10,
  and IPLIT's stock `openelis-db` image still ships 9.6.
- **The superusers**: whatever role each base actually bootstrapped --
  `postgres` on the mini and every clinic, `odoo` and `clinlims` on IPLIT's
  base. Task `000` connects as it before reading anything else and names the
  role when it cannot (`role "postgres" does not exist`), rather than failing
  later as an empty setting.
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
- **Disk -- two floors, two filesystems**: at least 60 GB free where Docker's
  volumes live (task 000 reads it inside the base MySQL container at its data
  volume's mount point, falling back to the host's DockerRootDir) -- that is
  the disk the hub's Kafka data and the base's databases grow on (F-066) --
  and at least 8 GB free on the image store (the container rootfs; the four
  hub images are ~4 GB and a pull needs headroom). A hub with a small OS disk
  and a large data disk passes on its real numbers. `HUB_MIN_DISK_GB` and
  `HUB_MIN_IMAGE_DISK_GB` are test-only overrides; never lower them on a hub.

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

**Where the base stack is described**: five values have no home in any of
those three files, because they describe the base *deployment* rather than its
configuration -- its network and its container/superuser names. They are read
from the install command's own environment (then the base `.env`, then a
default). For the Azure hub on IPLIT's base -- two Postgres containers, two
different bootstrap superusers -- that is the whole command:

```
KAFKA_BASE_NETWORK=iplit-base_default \
BASE_MYSQL_CONTAINER=iplit-base-openmrsdb-1 \
BASE_PG_CONTAINER=iplit-base-odoodb-1 BASE_PG_SUPERUSER=odoo \
BASE_ELIS_CONTAINER=iplit-base-openelisdb-1 BASE_ELIS_SUPERUSER=clinlims \
hub/install/install.sh --hub azure \
  --base-env /home/bahmni-hub/iplit-base/.env \
  --secrets ~/azure.secrets.env
```

On the mini or a clinic acting as the hub -- one Postgres container for both
databases, superuser `postgres` -- only `KAFKA_BASE_NETWORK` and the two
container names differ from their defaults, and the `BASE_ELIS_*` pair can be
left out entirely: each defaults from its `BASE_PG_*` counterpart.

Add `KAFKA_SASL_BIND=127.0.0.1` for a lab hub whose 9092 is fronted by
`tailscale serve` or another local proxy -- see the next section.

## The clinic-facing listener: 9092 is public by default

The broker publishes two ports. `9093` (the KRaft controller) is bound to
`127.0.0.1` and stays that way. `9092` -- the SASL_PLAINTEXT listener every
clinic's MirrorMaker dials -- is published on **`KAFKA_SASL_BIND`, which
defaults to `0.0.0.0`**: a hub exists to be dialled, and a hub bound to
loopback is a hub no clinic can reach.

A lab hub whose 9092 is fronted by `tailscale serve` (or any other local
proxy) sets `KAFKA_SASL_BIND=127.0.0.1` deliberately, in `hub/.env` or in the
install command's environment.

Both task `060` (right after the broker comes up) and task `090` (the exit
checks) read the binding back from the running container -- `docker port kafka
9092` -- and **fail** unless it matches what `hub/.env` declares. When the
declared value is a loopback address they also print a loud warning that
clinics cannot dial this hub directly. This is deliberately separate from the
SASL authentication check beside it: that one dials `127.0.0.1`, which answers
identically whether the port is published to the world or to loopback only, so
it structurally cannot catch a hub nobody can reach.

## hub/.env keys

Every key below is blank in `hub/.env.example`; `hub_compose_env` fills them
in (from the three sources above, or a fresh random value via `gen_secret`).
Never hand-fill a real value into the example and commit it. A value cannot
contain a single quote (`env_put` refuses it outright, naming the key) --
`hub/.env` is read by both bash `.`-sourcing and docker compose's own dotenv
parser, and a single-quoted literal with no `'` inside it is the only
representation both read identically.

| Key | What it is |
|---|---|
| `KAFKA_CLUSTER_ID` | KRaft cluster id for this hub's broker; must match the `kafka-data` volume's `meta.properties`. |
| `REMOTE_KAFKA_HOST` | Hostname/IP this hub's broker advertises on its SASL_PLAINTEXT listener, for clinics to dial. |
| `KAFKA_SASL_BIND` | Host interface that listener's port 9092 is published on. `0.0.0.0` (the default) is public; `127.0.0.1` is the lab-hub-behind-a-proxy case. |
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
| `BASE_PG_SUPERUSER` | Postgres superuser on the base's Odoo Postgres (`postgres`; `odoo` on IPLIT's base). From the install command's environment, then the base `.env`'s `POSTGRES_USER`, then the default. |
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

`BASE_MYSQL_ROOT_PASSWORD` and `BASE_PG_PASSWORD` were **removed** from this
list: nothing read either one. MySQL root is only ever used through the base
container's own `MYSQL_ROOT_PASSWORD` environment (so the value never reaches
the hub's process list), and `psql` runs over the container's local socket,
which its image trusts. Copying the base stack's root credentials into a
second file on disk bought nothing but exposure.

Every fleet image pin (`KAFKA_IMAGE`, `DEBEZIUM_CONNECT_IMAGE`,
`KAFKA_UI_IMAGE`, ...) is copied in from `sync/versions.env` at compose time
(`versions_put`) -- change a pin there, never in `hub/.env` directly (L-005:
lockstep, cloud first, one place).

## Tasks

Each task is idempotent, ends with a value read back from the live system
(never just "it didn't error"), and can be resumed with `--from NNN`.

| Task | Proves |
|---|---|
| `000-preflight` | The base network and both containers exist; `CLOUD_MYSQL_HOST` (the down-source's dial target, normally `BASE_MYSQL_CONTAINER`'s own value) is itself a running container too, so a stale value can never reach `080` silently; the declared Postgres superuser can actually log in (named in the failure if not); base MySQL/Postgres (and the ELIS Postgres too, when it's a separate container) meet the contract above, Postgres major >= 10 included; the docker storage pool has room and the host has memory. |
| `020-env` | `hub/.env` is composed, every `HUB_KEYS` entry is present and non-empty, the file is mode 600, and every value round-trips through actually `.`-sourcing the file (not just `env_get`'s own parse of it). |
| `030-jaas` | `kafka_server_jaas.conf` is generated (never hand-written or committed) with the admin and mirrormaker users, mode 600; `hub/connectors/` exists. |
| `040-images` | Every image `docker compose config --images` names is present locally. |
| `050-base-db` | The MySQL sink+debezium accounts and the Postgres `odoo_sink`/`clinlims_sink` roles exist, are granted, and authenticate over the network; the two ownership publications are converged from `sync/subsystems.conf`; a heartbeat table exists in both databases; sequence striding holds; no `hub_%` replication origin exists on either Postgres instance. |
| `060-kafka` | The KRaft controller + broker + Schema Registry come up; the broker's cluster id matches; port 9092 is published on the declared `KAFKA_SASL_BIND` (read back from the container); the published SASL_PLAINTEXT listener authenticates the mirrormaker user; Schema Registry answers. |
| `070-connect` | Kafka Connect comes up with all three plugin classes (MySQL source, Postgres source, JDBC sink) resolved; kafka-ui comes up behind a real login -- the login page answers, an unauthenticated API call is refused, and `KAFKA_UI_USER`/`KAFKA_UI_PASSWORD` actually log in and read the cluster back. |
| `080-sources` | The base MySQL is fit for Debezium 3.6.2 (major version 8+); the down-direction MySQL source and the two up-direction Postgres relay sources are registered, all RUNNING (connector and every task); both down-direction replication slots are active; schema-history retention is `-1`; the heartbeat keys are present in both Postgres sources' configs. |
| `090-exit-checks` | Everything above still holds, read fresh: disk free under the broker's own data volume; every connector and task still RUNNING; both replication slots retain under 2 GB; 9092 is still published on the declared bind and the SASL listener still answers; `hub/.env` and the JAAS file are still mode 600; nothing under `hub/` is dirty in git (edits elsewhere in the checkout are named, not failed -- a hub host legitimately carries its own base-stack changes). It also prints the base OpenMRS `event_records` count, informationally. |
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
