# How the cloud server works

The explanations that used to be comments in files under `cloud/`, grouped by file. Each passage is followed by the line of code it described.

## `scripts/clinical-fks-in.conf`

the hub, one per line: <table> <column> <referenced table> <referenced column>.
cloud/scripts/check-clinical-fks.sh reports any difference from this list.

None of them stops an up sink when a clinic's row arrives before its parent:
they point at the clinical rows, not out of them. They do make a delete of a
clinical row that one of these hub rows references fail that table's sink,
on purpose (the sinks do not tolerate errors), so the stall is seen rather
than the row silently kept or lost. A new one widens that set; change this
list only after reading which module added it and what it references.
No key into test_order is listed: check-clinical-fks.sh names any key into it
it finds on a hub as a difference.

> Before: `document_reference order_id orders order_id`

## `scripts/_render_connector.py`

The down list's placeholders must be filled: left in, Debezium reads them as a
table pattern that matches nothing, and the source runs while sending nothing.

> Before: `down_left = [k for k, v in cfg.items() if isinstance(v, str) and '${HUB_DOWN_' in v]`

A source that reads one of the hub's down publications captures exactly the
down list of its subsystem (HUB_DOWN_ODOO_TABLES / HUB_DOWN_CLINLIMS_TABLES,
from sync/tables/tables.sh): any other table in its table list or aggregate regex
is refused, whatever the template says.

> Before: `DOWN_PUBLICATIONS = {'dbz_odoo_owned': 'HUB_DOWN_ODOO_TABLES', 'dbz_clinlims_owned': 'HUB_DOWN_CLINLIMS_TABLES`

## `scripts/register-odoo.sh`

Registers the hub's Postgres CDC connectors (the Odoo and OpenELIS down
sources and the per-clinic Odoo and OpenELIS up-sinks), substituting credentials from
.env at registration time so no committed file holds a literal secret. The four
clinlims connector JSONs predate this and DO carry literals -- see the note in
f74613f; do not copy their pattern.

> Before: `set -euo pipefail`

The hub's down sources take their table lists and aggregate regexes from the
down list (sync/tables/{odoo,openelis}.conf [down]): HUB_DOWN_ODOO_* for the Odoo source (schema
public), HUB_DOWN_CLINLIMS_* for the OpenELIS source (schema clinlims). Read
before anything is registered, and only when a template asks for that
subsystem; a list it refuses stops every registration.

> Before: `down_vars(){ # SUBSYSTEM PG_SCHEMA : exports HUB_DOWN_<SUB>_TABLES, _TABLE_INCLUDE_LIST, _ALTERNATION`

_render_connector.py substitutes
every value (passwords included) into cfg BEFORE its own unresolved-
placeholder check, so on some future failure path $body could carry
the rendered config, passwords and all -- masked with the same
JSON-escape-aware pattern used below, on the chance it ever does.

> Before: `printf '%s\n' "$body" | sed -E 's/("(database|connection)\.password"[[:space:]]*:[[:space:]]*")([^"\\]|\\.)*("`

Connect's response echoes the connector config back, database.password and
connection.password included -- so the body is never written to disk (was
/tmp/.reg.out, a fixed, world-readable path -- the same fix as
clinic/scripts/register-connectors.sh). It's held
only in this shell's own memory, split on the trailing newline curl's -w
appends, and on a non-2xx it's printed with any password value masked
before the human ever sees it.

> Before: `resp=$(printf '%s' "$body" | curl -s -w '\n%{http_code}' \`

The value group below must consume JSON escapes ([^"\\]|\\.)* rather than
stop at the first bare quote ([^"]*) -- a password containing an escaped
quote (\") would otherwise end the match early and leak everything after
it, e.g. "connection.password": "SEC\"RET" -> "connection.password":
"***"RET" with the naive pattern (d66aae8).

> Before: `[ "$code" -lt 300 ] || printf '%s\n' "${resp%$'\n'*}" \`

## `docker-compose.yml`

Clinics dial 9092 (SASL over TLS by default); this host dials kafka:29092; 9093 is never published.

> Before: `image: ${KAFKA_IMAGE:?}`

Read from cloud/tls/ when the clinic listener is SASL_SSL; the two passwords are files there.

> Before: `KAFKA_SSL_KEYSTORE_FILENAME: ${KAFKA_SSL_KEYSTORE_FILENAME:-kafka.keystore.p12}`

The OpenMRS source's row filter for lab results (sync/tables/openmrs.conf [down]
`clinic=` rows) is a Groovy Filter step, which needs these three jars
inside the MySQL connector's plugin directory. They are the clinic's,
fetched by clinic/config/kafka-connect/ext/fetch-scripting-jars.sh.

> Before: `- '../clinic/config/kafka-connect/ext/groovy-${GROOVY_VERSION:?}.jar:/kafka/connect/debezium-connector-mysql/g`

## `odoo/apply-down-publication.sql`

It publishes INSERT, UPDATE and DELETE, never TRUNCATE (a TRUNCATE ignores row
filters). It holds exactly the down tables passed in (sync/tables/{odoo,openelis}.conf [down], read through
sync/tables/tables.sh), plus public.dbz_heartbeat when it exists, and nothing else:
SET TABLE replaces whatever the publication held before, so a table that is
not on the list leaves it.

A down table with an `id` column carries the row filter
    (id < <floor> OR id % 10 = 0)
Rows below the hub's floor predate striding and are the hub's; above it the
hub mints residue 0 and each clinic its own residue. A row a clinic minted
that reached the hub therefore stays at the hub, whoever edits it there. A
bare id % 10 = 0 would drop the hub's edits to every legacy row whose id does
not end in 0. A table without `id` (the link tables) carries no filter.

Refused, naming the table, before the publication is touched:
  - a down table that does not exist;
  - a down table with `id` and no floor, or a floor that is not a multiple of 10;
  - a floor for a table that is not a down table, or that has no `id`;
  - a filtered table whose replica identity does not cover `id`: with a row
    filter, PostgreSQL refuses every UPDATE and DELETE on such a table, so the
    hub's Odoo could no longer edit it;
  - a server older than PostgreSQL 15 (no row filters).

Usage: psql -d odoo -v pub=dbz_odoo_owned -v tables=product_template,uom_uom,... \
            -v floors=product_template:4520,uom_uom:40,... -f apply-down-publication.sql
Prints one line per published table: "<table> <row filter>", "-" for none.

> Before: `\set ON_ERROR_STOP on`

TRUNCATE ignores row filters, so it is never published.

> Before: `IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = v_pub) THEN`

## `odoo/apply-odoo-sequence-striding.sql`

WHY THIS EXISTS. OpenMRS avoids cross-node primary-key collisions with MySQL's
auto_increment_increment=10 plus a per-node auto_increment_offset, so Rawach mints
4, 14, 24 ... and the cloud mints 10, 20, 30 .... clinlims does the same with
PostgreSQL sequences at increment_by=10 (sample_*_seq all carry incr=10). Odoo ships every sequence at increment_by=1 starting at 1, so two
nodes both mint sale_order id=1 for different orders. Under an idempotent upsert
keyed on the PK that is not a loud failure -- it is silent data loss: the
second node's order OVERWRITES the first node's. This script closes that.

SCOPE. Only the 12 synced business tables plus the join/child tables that hang off
them. Framework sequences (ir_*) are deliberately untouched: they never travel, and
striding them would desynchronise module installation across nodes.

THE RESTART FORMULA. A sequence cannot simply RESTART WITH <residue>; existing rows
already occupy low ids. We restart at the first value ABOVE the current maximum that
carries this node's residue:
    next := ((max(current_max_id, last_value) / 10) + 1) * 10 + residue
Integer division floors, so the +1 guarantees strictly-greater, and the * 10 + residue
guarantees the residue. For residue 0 the cloud mints 10, 20, 30 ...; id 0 is never
minted, which is correct -- Odoo treats 0 as a false id in several ORM paths.

IDEMPOTENT. Re-running moves sequences forward only, never backward, so it is safe
to re-apply after a restore or a resync.

NOT COVERED, ON PURPOSE: Odoo's ir_sequence table, which mints the human-facing
document numbers (SO0001, WH/OUT/0001). Those are business identifiers, not the sync
key, so striding does not protect them -- the same exposure the MRN and the lab accession
number have. Two clinics WILL both mint SO0001. That needs a per-node prefix and is filed
separately; this script does not pretend to fix it.

Usage: psql -U postgres -d odoo -v residue=4 -f odoo/apply-odoo-sequence-striding.sql

> Before: `\set ON_ERROR_STOP on`

psql does NOT interpolate :variables inside a dollar-quoted block (they are string
literals to the lexer), so the residue is handed in through a GUC set out here, where
interpolation does happen, and read back with current_setting() inside.

> Before: `SELECT set_config('myvars.residue', :'residue', false);`

The Odoo 16 table set (matching staging): the unit-of-measure and two
invoicing tables changed names between
Odoo versions; the other nine carry over unchanged.

> Before: `v_tables  text[] := ARRAY[`

pg_get_serial_sequence resolves the real owning sequence, which is not always
<table>_id_seq (inherited and renamed tables differ). NULL means no serial PK.

> Before: `v_seq := pg_get_serial_sequence('public.' || v_tbl, 'id');`

## `odoo/create-odoo-sink-role.sh`

Creates the odoo_sink login role -- the prerequisite that makes the write-origin guard
possible at all. The trigger distinguishes a replicated write from a local one by
session_user, so the sink MUST connect as a role the Odoo application never uses.
This is the same prerequisite that blocked the OpenELIS guard until clinlims_sink
existed.

PASSWORD HANDLING. The DDL is written to a file inside the container and run with -f,
never passed with -c and never interpolated into a logged command. This is not
theoretical caution: a generated password once leaked into a PostgreSQL ERROR
CONTEXT line, because a failing statement echoes its own text -- including the literal
-- back to the client. With -f, the error cites a file and line, not the statement.
The value is written once to .env (gitignored) and never printed.

> Before: `set -euo pipefail`

READ .env BY SOURCING IT, NOT BY CUTTING THE LINE. Bahmni's .env files carry inline
comments -- ODOO_DB_SERVER=odoodb                      # [OK] -- and `cut -d= -f2-` keeps
the padding and the comment as part of the value. On the cloud that produced a 76-char
"password" where the real one is 4 chars: the role was created with the polluted string
while every consumer sources .env and gets the clean one, so Debezium failed with
"password authentication failed for user odoo" against a role that had just been
created successfully. Source it the same way the consumers do.
Reuse only a NON-EMPTY value: the .env template ships CLINLIMS_SINK_PASSWORD=""
and a bare `grep ^KEY=` took that blank as a password -- PostgreSQL then cleared
the role's password.

> Before: `[ -f "$ENV_FILE" ] || { echo "  no .env at $ENV_FILE" >&2; exit 1; }`

Bounded input on purpose: `tr </dev/urandom | head -c 32` never lets tr
finish, so head's exit sends it SIGPIPE and under pipefail the assignment
fails with 141 on Linux AND macOS -- every fresh node died here, before the
append. 512 bytes give ~124 [A-Za-z0-9].

> Before: `PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"`

key present but blank: replace the line in place -- a second line would leave
first-match readers on the blank one; write through cat to keep the file's mode

> Before: `tmp="$(mktemp)"; grep -v '^ODOO_SINK_PASSWORD=' "$ENV_FILE" > "$tmp" || true`

umask so the DDL file is not world-readable even for the moment it exists

> Before: `TMP="$(mktemp)"; chmod 600 "$TMP"`

-f, not -c: on failure psql cites the file and line, not the statement text

> Before: `docker exec "$CTR" psql -U postgres -d odoo -v ON_ERROR_STOP=1 -q -f /tmp/.odoo_sink.sql`

## `odoo/down-sequence-state.sql`

One line per down table with an `id`, in the order passed:
  <table>|<restart>|<next>|<increment>
<restart> is where the hub's striding would restart the sequence if it ran now
(residue 0): apply-odoo-sequence-striding.sql's ((max(max id, last_value) / 10)
+ 1) * 10, and for res_country_state apply-master-sequence-striding.sql's
((max(max id, 1000) / 10) + 1) * 10, which runs after it and wins.
<next> is the id the sequence would issue next.

Refused, naming the table: a down table that does not exist, or one with an
`id` and no owning sequence.

Usage: psql -d odoo -v tables=product_template,uom_uom,... -f down-sequence-state.sql

> Before: `\set ON_ERROR_STOP on`

## `openelis/apply-down-publication.sql`

captures for clinics to pull.

It holds exactly the OpenELIS down tables passed in (sync/tables/{odoo,openelis}.conf [down], read
through sync/tables/tables.sh), plus clinlims.dbz_heartbeat when it exists, and
nothing else: SET TABLE replaces whatever the publication held before. It
publishes INSERT, UPDATE and DELETE, never TRUNCATE (a TRUNCATE at the hub
would empty every clinic's copy).

A table kept by one clinic only (result, analysis, sample) carries no row
filter: the rows keep the ids the clinic gave them (a result answers a
clinic's analysis; the analysis and sample are the clinic's own rows, moved
on by the hub), so an id filter would drop exactly the rows the clinic must
pull. What is captured is chosen by replication origin instead: the source
decodes with origin=none, so a row a clinic's up-sink applied here is never
published. Each clinic keeps only the rows whose routing column names it.

A table every clinic keeps (system_user, the lab test catalogue)
carries the filter
    (id < <floor> OR id % 10 = 0)
with this hub's floor (./clinlims-down-floors.local): the hub's own rows,
from before its ids were strided and since. A row a clinic minted that the
hub edits stays at the hub. Such a table without an id column (a link table,
keyed by the ids it links) carries no filter: only the hub writes the
catalogue's link tables, and they have no id to filter on.

Refused, naming the table, before the publication is touched:
  - a down table that does not exist;
  - a down table without a replica identity (no primary key and none set):
    PostgreSQL refuses every UPDATE and DELETE on a table that a publication
    publishes updates for without one, so the hub's OpenELIS could no longer
    write it; for a filtered table, one whose replica identity does not
    cover id;
  - a filtered table with an id and no floor, or a floor that is not a
    multiple of 10; a floor for a table that is not a down table, or that
    has no id column;
  - a server older than PostgreSQL 16 (the source's origin=none needs it).

Usage: psql -d openelis -v pub=dbz_clinlims_owned -v tables=system_user,result,analysis,sample \
            -v filtered=system_user -v floors=system_user:170 -f apply-down-publication.sql
Prints one line per published table: "<table> <row filter>", "-" for none.

> Before: `\set ON_ERROR_STOP on`

## `openelis/apply-sequence-striding.sql`

10 and restarts at ((greatest(last_value, largest id) / 10) + 1) * 10, the
restart cloud/openelis/down-sequence-state.sql reports, so a floor recorded
just before this run is exactly where its sequence restarts.

The largest id is taken over every table OpenELIS numbers from that
sequence, not the sequence alone: some lab test catalogue sequences stand
below the rows they hold (the rows were loaded with fixed ids), and a
sequence restarted from its last value would issue ids those tables already
have, so each such save would fail on the duplicate key.

A sequence already stepping by 10 from a multiple of 10 is left as it is,
unless the next id it would issue is at or below the largest id of its
tables: then it restarts above them, on the same rule. So a second run moves
nothing that is already clear of its rows. A sequence stepping by 10 from any
other value is another node's striding, not the hub's: refused, naming it,
before anything changes (cloud/scripts/stride.sh openelis asks the same
question before it records any floor).

Last, every sequence is checked: step 10, a multiple of 10, and its next id
above the largest id of its tables. Any that is not is named and the run
fails.

One NOTICE per sequence restarted or lifted, one summary NOTICE, then one line:
  sequences step 10: <n> of <total>
Usage: psql -d openelis -f apply-sequence-striding.sql

> Before: `\set ON_ERROR_STOP on`

The largest id of the tables OpenELIS numbers from sequence SEQ (0 when they
are empty). OpenELIS takes a table's ids from clinlims.<table>_seq, except for
the tables listed here, whose sequences its mappings name otherwise (two
tables can share one). The same list is in cloud/openelis/down-sequence-state.sql
and clinic/openelis/apply-sequence-striding.sql; a test fails when they differ.

> Before: `CREATE OR REPLACE FUNCTION pg_temp.clinlims_rows_top(seq text) RETURNS bigint LANGUAGE sql STABLE AS $f$`

pg_get_serial_sequence raises on a table without an id column, and the
planner may call it before the column test above: CASE keeps the order

> Before: `OR CASE WHEN c.column_name = 'id' THEN pg_get_serial_sequence(format('clinlims.%I', c.table_name), 'id') END =`

## `openelis/down-sequence-state.sql`

publication filters on its floor (sync/tables/tables.sh openelis unrouted),
read-only: it creates nothing, so it runs in a read-only session too.

One line per table, in the order passed:
  <table>|<restart>|<next>|<increment>
<restart> is where striding the hub's OpenELIS ids (residue 0) restarts the
sequence if it runs now: ((greatest(last_value, largest id) / 10) + 1) * 10,
last_value read from the sequence itself and the largest id taken over the
table and every other table OpenELIS numbers from the same sequence, as the
hub's OpenELIS striding reads them. <next> is the id the sequence would issue
next.

With -v detail=1 each line also carries what the table holds:
  <table>|<restart>|<next>|<increment>|<max id>|<max id not ending in 0>|id
(0 for an empty table), so a floor can be judged against the rows as well
as the sequence: rows on another residue than 0 above a floor would not
pass the publication's filter.

The sequence is the id column's own, else the one OpenELIS's mappings name
where that is not clinlims.<table>_seq (the list in `names` below; the same
list is in cloud/openelis/apply-sequence-striding.sql and
clinic/openelis/apply-sequence-striding.sql, and a test fails when they
differ), else clinlims.<table>_seq. A table with
an id and no sequence at all (OpenELIS never issues ids for it) reads
<restart> and <next> as the first multiple of 10 above its largest id and
<increment> as 0. A table with no id column (a link table, keyed otherwise)
takes no floor: it prints no line, or with detail=1
  <table>|0|0|0|0|0|noid
Refused, naming the table: a table that does not exist.

Usage: psql -d openelis -v tables=system_user -f down-sequence-state.sql
       psql -d openelis -v tables=system_user,test -v detail=1 -f down-sequence-state.sql

> Before: `\set ON_ERROR_STOP on`

the largest id of every table OpenELIS numbers from this sequence

> Before: `CASE WHEN s.seq IS NOT NULL THEN (`

## `scripts/apply-down-publication.sh`

apply-down-publication.sh odoo|openelis FLOORS-FILE -- PSQL-COMMAND...

openelis: converges dbz_clinlims_owned to the OpenELIS [down] tables, with
(id < <floor> OR id % 10 = 0) on the tables every clinic keeps (floors from
./clinlims-down-floors.local); cloud/openelis/apply-down-publication.sql
does the work.

odoo: converges the hub's Odoo down publication, dbz_odoo_owned, to exactly the down
list (sync/tables/{odoo,openelis}.conf [down] through sync/tables/tables.sh), each table with an `id`
filtered with (id < <floor> OR id % 10 = 0) from FLOORS-FILE (the hub's
./odoo-down-floors.local), plus public.dbz_heartbeat. cloud/odoo/
apply-down-publication.sql does the work and refuses, naming the table, a
missing floor, a missing table, or a replica identity that does not cover
`id`. Prints "<table> <row filter>" per published table on success.

PSQL-COMMAND reaches the hub's Odoo database as a role that may alter the
publication, for example: docker exec -i <odoo-db-container> psql -U odoo -d odoo

> Before: `set -u`

## `scripts/check-clinical-fks.sh`

The physical foreign keys on obs, orders, drug_order and test_order in the hub's
OpenMRS schema, read from information_schema. Read-only.

  cloud/scripts/check-clinical-fks.sh --container NAME [--database DB]
  cloud/scripts/check-clinical-fks.sh --from FILE

Two checks:
  OUT  No foreign key may point OUT of obs, orders, drug_order or test_order
       to a table a clinic writes. The hub's up sinks write one table each,
       in arrival order, and a clinic's obs can arrive before the encounter
       it belongs to; with no FK out of the table the early row is written
       and its parent follows. One FK out to a clinic-written parent turns
       that ordinary early arrival into a stopped sink, and fails the check,
       named. An FK out to a table only the hub writes (verdict DOWN in
       cloud/table-verdicts.conf) or that only changesets and the seed write
       (RESEED) is allowed and named: its rows are at the hub before any
       clinic can name one. A table with no verdict counts as clinic-written.
       A module upgrade can add an FK, so run this before and after every
       hub upgrade, and before any up sink for these tables is registered.
  IN   The FKs pointing INTO the four tables are compared with
       cloud/scripts/clinical-fks-in.conf. These do not stop a sink on an early
       arrival, but each makes a clinic's delete of a referenced row fail
       the sink. A difference is reported, added or gone.

--container  the hub's MySQL container (queried as root inside it)
--database   the OpenMRS schema (default openmrs)
--from       a file holding the query's output instead (tab-separated:
             table, column, referenced table, referenced column, constraint)

Exit status: 0 both checks pass; 1 an FK out of a clinical table (or the
read failed); 2 no FK out, but the FKs in differ from the recorded list.
It runs docker through sudo.

> Before: `set -euo pipefail`

the same list as SQL: 'obs', 'orders', ...

> Before: `CLINICAL_SQL="$(printf "'%s', " $CLINICAL | sed 's/, $//')"`

the tables only the hub writes (DOWN) or only changesets and the seed write (RESEED)

> Before: `HUB_WRITTEN=" $(awk '{ sub(/#.*/, "") } NF >= 2 && ($2 == "DOWN" || $2 == "RESEED") { print $1 }' "$VERDICTS" `

every clinical table must be there, or "no FK out" would be a check of nothing

> Before: `n="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="schema" {print $2}')"`

set differences through a pipe, not process substitution (a /dev/fd closed
before the reader opens it reads as empty, and a difference would be lost)

> Before: `lines_not_in(){ { printf '%s\n' "$1"; printf '\001\n'; printf '%s\n' "$2"; } | awk '$0 == "\001" { s = 1; next`

## `scripts/down-floors.sh`

down-floors.sh FILE [clinlims] : prints FILE's "<table> <floor>" lines,
validated, one per line. FILE is a hub's own record of its down-table floors
(./odoo-down-floors.local, written once by stride.sh odoo in the run that
strides the hub's Odoo ids; with clinlims, ./clinlims-down-floors.local,
written once by record-down-floors.sh openelis before the hub's OpenELIS ids
are strided; never committed, because each hub has its own).

Refuses (exit 1, naming the line) a line that is not "<table> <floor>", a
floor that is not a whole multiple of 10, a table listed twice, and a table
that is not a down table (sync/tables/tables.sh odoo down; with clinlims, an OpenELIS
down table the publication filters: sync/tables/tables.sh" openelis unrouted).
Blank lines and "#"
comments are skipped.

> Before: `set -uf`

## `scripts/generate-cloud-source-connector.sh`

generate-cloud-source-connector.sh — render the DOWN-direction Debezium source that
runs ON THE CLOUD and publishes cloud-owned admin tables as bahmni-cloud.openmrs.*

table.include.list comes from sync/tables/openmrs.conf [down] via generate-table-config.sh,
so the whitelist can never drift from the declared ownership split.

> Before: `set -euo pipefail`

The file this script writes carries DEBEZIUM_DB_PASSWORD in plaintext, so it
is created mode 600, not the default 644. umask
here rather than a chmod afterwards: a chmod leaves a window in which the
rendered file is world-readable, however short.

> Before: `umask 077`

Two roots, resolved separately:
  ROOT     the REPO checkout -- clinic/scripts/generate-table-config.sh and
           sync/tables/openmrs.conf [up], which are repo files wherever the hub tree
           happens to live;
  HUB_ROOT the HUB directory -- the template, cloud/.env and the default output.
Both fall back to this script's own location.

> Before: `ROOT="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"`

Env: repo root first, then cloud/.env (which wins).
The sync layer is deployed from cloud/, so DEBEZIUM_DB_PASSWORD and the
other hub-side values live in cloud/.env, not at the repo root.

> Before: `# shellcheck disable=SC1091`

## `scripts/generate-sink-connectors.sh`

Generate the hub's UP-direction JDBC sink configs, one per clinic per table.

Usage: generate-sink-connectors.sh [--db openmrs,odoo,clinlims] [clinic ...]
(default: all three databases, every clinic). Only the chosen databases'
settings are required in cloud/.env, so a hub without Odoo or OpenELIS
generates its OpenMRS sinks with `--db openmrs`.

Every connector is named from the clinic's slug (openmrs-, odoo- and
clinlims-<slug>-sink): a name without the slug would let a second clinic's run
overwrite the first clinic's files and, on registration, PUT over its live
connectors. The table list is the
CLINIC's (see below); a table listed in both directions is warned about, not
refused -- see the ownership note in the loop.

> Before: `set -e`

Every file this script writes carries DEBEZIUM_DB_PASSWORD in plaintext, so
they are created mode 600, not the default 644.
umask rather than a chmod per file: a chmod leaves a window in which the
rendered config is world-readable, however short.

> Before: `umask 077`

These sinks apply UP-direction data: they consume <clinic>.<server>.openmrs.*
topics and write clinic-authored rows into the cloud. So the table list is the
CLINIC's (sync/tables/openmrs.conf [up]), NOT the [down] section --
which lists the tables that flow the other way.

Generating up-direction sinks from the [down] section instead would
produce sinks for users/role/role_privilege/role_role/user_property/user_role/
provider, all subscribed to topics the clinic never publishes: inert, but
reporting RUNNING and inflating any "all sinks green" check.

> Before: `TABLES_CONF="${TABLES_CONF:-${PROJECT_DIR}/../sync/tables/openmrs.conf}"`

The clinics come from sync/clinics.json: every clinic with a site number
except the cloud. Every name derives from the slug: topics <slug>.bahmni-<slug>.<db>.all,
sinks openmrs-, odoo- and clinlims-<slug>-sink, origins clinic_<slug>_odoo and
clinic_<slug>_clinlims.

> Before: `CLINICS_JSON="${CLINICS_JSON:-${PROJECT_DIR}/../sync/clinics.json}"`

The clinic's list is read by the reader every script of it shares, so a line
the clinic captures is never one this generator skips: a skipped line is a
topic with no sink. A list it refuses stops the run before anything is written.

> Before: `# shellcheck source=../../sync/tables/tables.sh`

Every clinic sends every [up] table, obs, orders, drug_order and test_order
included, and its sink writes all of them. The schema is fixed fleet-wide, so a
sink never changes the hub's schema to fit a record: schema.evolution=none is
set explicitly, and auto.create/auto.evolve are left out. A mismatch stops the
sink. validate-sink-config.py refuses a sink with any transforms, since a
filter would drop a table the clinic sends.

A table appearing in BOTH directions is legitimate: ownership is per
ROW, and more than one node may write a table provided no two nodes
write the same row, which the strided PK guarantees. Refusing such a
table (per-table ownership) would stop the generator dead on
person/person_name, which the hub relays. It warns instead, because a
bidirectional table is still worth a human glance -- it is only safe
ABOVE that table's base_id floor (rows below it occupy all ten residues).

> Before: `if [ -f "${DOWN_TABLES_CONF}" ] && tables_section "${DOWN_TABLES_CONF}" down | grep -qE "^[[:space:]]*${table}`

SHAPE IS AUTHORITATIVE: scripts/templates/known-good.json is the committed
record of a sink that actually works, and the validator diffs against
it. Both were taken from a LIVE hub.

Heredoc is UNQUOTED, so bash expands $ and collapses \\ . Therefore:
  - a literal $1 for RegexRouter must be written \$1 (bare $1 expands
    to the script's first positional arg, silently routing nowhere)
  - a JSON \\. must be written \\\\.

> Before: `cat > "${config_file}" <<EOF`

## `scripts/record-down-floors.sh openelis`

record-down-floors.sh openelis [--from-file FILE | --derive] [--out OUT] -- PSQL-COMMAND...

Records the hub's floor of each OpenELIS down table its publication filters
(sync/tables/tables.sh" openelis unrouted: the lab accounts and the lab test
catalogue) in OUT, default ./clinlims-down-floors.local, one
"<table> <floor>" line each. The publication sends such a table's rows below
the floor (the hub's, from before its ids were strided) or ending in 0 (the
hub's since), and nothing a clinic minted. A table without an id column (a
link table) takes no floor and has no line.

A recorded line is never changed. When OUT already exists, only the tables it
does not hold yet are added (a table that joined the down list after OUT was
written); a value given for a table OUT already holds must equal it. With
nothing to add, it refuses and changes nothing.

Without --from-file or --derive it is run immediately BEFORE the hub's
OpenELIS ids are strided, and records where each floor must lie: for the lab
accounts, which clinics also write and send up, where the stride will restart
the sequence, ((greatest(last_value, largest id) / 10) + 1) * 10, the hub's
OpenELIS striding's own restart; for a catalogue table, which only the hub writes, that or the first
multiple of 10 above the largest id the table holds, whichever is higher (some
catalogue sequences stand below the rows they hold; a floor below a row the
hub owns would stop that row's changes from going down). Refused, writing
nothing, when a sequence already steps by more than 1 (the hub was strided
before: record the floors with --derive and --from-file), or when any
clinic's replication origin (clinic_*) shows progress (clinics' rows may
already sit above it).

With --derive it writes nothing and prints, for each table OUT does not hold
yet, a floor read from the rows: the first multiple of 10 above the table's
largest id. That is the floor for a hub whose OpenELIS ids were strided
before the table joined the down list. Refused for a table clinics send up
(sync/tables/{odoo,openelis}.conf [up]) once any clinic's replication origin shows progress:
a clinic's rows may then be the largest ids, and a floor above them would
let every clinic pull them. Save the output and record it with --from-file.

With --from-file FILE ("<table> <floor>" lines) it records values captured
or derived elsewhere, after checking them against the database: each table
listed once, its sequence stepping by 10 (a table without a sequence aside),
the floor a multiple of 10; for a table clinics send up, not above the id
the sequence issues next; for a catalogue table, above every id the table
holds that does not end in 0 (those rows are the hub's, and must pass the
filter) and not above the higher of the id its sequence issues next and the
first multiple of 10 above its largest id.

PSQL-COMMAND reaches the hub's openelis database as a superuser, for example:
  cloud/scripts/record-down-floors.sh openelis -- docker exec -i <openelis-db-container> psql -U postgres -d openelis
On a hub strided before:
  cloud/scripts/record-down-floors.sh openelis --derive -- <psql command...> > /tmp/floors &&
  cloud/scripts/record-down-floors.sh openelis --from-file /tmp/floors -- <psql command...>

> Before: `set -u`

the tables clinics send up: their rows can reach this hub

> Before: `up=" $(bash "$R/sync/tables/tables.sh" openelis up | tr '\n' ' ') "`

the id tables OUT does not hold yet

> Before: `need="$(printf '%s\n' "$state" | awk -F'|' 'NF == 7 && $7 == "id" { print $1 }' | while read -r t; do [ -n "$(`

## `scripts/record-down-floors.sh odoo`

record-down-floors.sh odoo --from-file FILE [--out OUT] -- PSQL-COMMAND...

Records this hub's down-table floors from values captured when its Odoo ids
were strided, for a hub whose striding ran before stride.sh odoo recorded
them itself. FILE holds "<table> <floor>" lines: each down table with an id
(sync/tables/{odoo,openelis}.conf [down]) and the value its sequence restarted at. OUT defaults to
./odoo-down-floors.local and is never rewritten.

Floors are never read from the sequences now: once a hub has issued ids, or
been strided again, its sequences no longer show where they restarted. The
values are checked against the database instead, and refused, naming the
table, when a down table with an id has no floor, a floor names a table
without one, a sequence does not step by 10, or a floor is above the id the
sequence issues next (it cannot be where that sequence restarted).

> Before: `set -u`

## `scripts/register-all-sink-connectors.sh`

Registers the sink configs given as arguments, or every generated one in
connectors/.

> Before: `connector_files=("${CONNECTORS_DIR}"/*-sink.json)`

Every up sink writes obs, orders, drug_order and test_order in arrival order, so a
clinic's row can land before its parent. That is safe only while no foreign
key points out of those tables on the hub: one would stop the sink at every
early arrival. Before any sink is registered, when the list holds an OpenMRS
sink, check-clinical-fks.sh reads
the hub's keys (HUB_MYSQL_CONTAINER names the hub's OpenMRS MySQL container)
and a key out of a clinical table stops the registration. A change in the
keys pointing into them is shown and does not stop it.

> Before: `if [ -z "${HUB_MYSQL_CONTAINER:-}" ]; then`

Check if connector already exists

> Before: `status_code=$(curl -s -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors/${connector_name}")`

## `scripts/setup-connectors.sh`

Usage: setup-connectors.sh [--db openmrs,odoo,clinlims] [clinic ...]

Generates the chosen sinks with generate-sink-connectors.sh and registers
exactly those files with register-all-sink-connectors.sh, so sinks generated
earlier for other databases or clinics are left alone.

> Before: `"${SCRIPT_DIR}/generate-sink-connectors.sh" "${gen_args[@]}" "$@"`

## `scripts/stride.sh odoo`

stride.sh odoo [--floors FILE] -- PSQL-COMMAND...

Strides the hub's Odoo ids (residue 0) and records the floor of each down
table in the same run: clinic/odoo/apply-odoo-sequence-striding.sql over every
synced Odoo table, then clinic/odoo/apply-master-sequence-striding.sql. A
table's floor is the value its sequence restarts at, read from the striding
scripts' own report of each restart, at the moment it happens. FILE defaults
to ./odoo-down-floors.local, one "<table> <floor>" line per down table with
an id (sync/tables/{odoo,openelis}.conf [down]).

The floors are recorded once. When FILE already exists, a re-run strides
again (forward only) and never changes it: it refuses, before striding, when a
sequence would restart below its recorded floor (the database went back), or
when a down table with an id has no recorded floor.

A first recording is allowed only on a first striding: before the run, every
down table's sequence still steps by 1. On a hub strided before, a floor read
now would sit above rows clinics may already have sent (before replication
origins existed, or from a clinic that has since left), so it is refused, and
so is a first recording while any clinic's replication origin (clinic_*) shows
progress. Either way, record the values captured at the first striding:
record-down-floors.sh odoo --from-file.

PSQL-COMMAND reaches the hub's Odoo database as its owner, for example:
  cloud/scripts/stride.sh odoo -- docker exec -i <odoo-db-container> psql -U odoo -d odoo

> Before: `set -u`

A first recording is a first striding: every down sequence still steps by 1.
On a hub strided before, the restart values are long gone, and rows a clinic
sent before replication origins existed, or from a clinic that has since
left, can sit anywhere above them; only the values captured then will do.

> Before: `strided="$(printf '%s\n' "$state" | awk -F'|' 'NF == 4 && $4 != 1 { printf "%s%s (steps by %s)", (n++ ? ", " :`

the last restart each table reported wins: the master script runs second

> Before: `rows=""`

## `scripts/stride.sh openelis`

stride.sh openelis [--floors FILE] -- PSQL-COMMAND...

Strides the hub's OpenELIS ids (residue 0) with cloud/openelis/apply-sequence-striding.sql
and, on the first striding, records the floor of each down table the hub's
OpenELIS publication filters (sync/tables/tables.sh" openelis unrouted; today
system_user) just before it: record-down-floors.sh openelis, which reads where
the striding is about to restart each sequence. FILE defaults to
./clinlims-down-floors.local, one "<table> <floor>" line per table.

The floors are recorded once. When FILE already exists, a re-run never
changes it: it refuses, before striding, when a filtered table's sequence
would restart (or already issues) below its recorded floor, which means the
database went back, or when a filtered table has no recorded floor. Sequences
already stepping by 10 are left as they are, unless one would issue an id at
or below the largest id of its tables: a re-run lifts that one above them.

A first recording is allowed only on a first striding, and only while no
clinic's replication origin shows progress (record-down-floors.sh openelis
refuses otherwise and names --from-file). Nothing is strided when the floors
cannot be recorded.

PSQL-COMMAND reaches the hub's openelis database as a superuser, for example:
  cloud/scripts/stride.sh openelis -- docker exec -i <openelis-db-container> psql -U postgres -d openelis

> Before: `set -u`

Another node's striding (a sequence stepping by something other than 1 or 10,
or by 10 off a multiple of 10) is refused before anything is recorded or
strided. apply-sequence-striding.sql refuses the same sequences itself.
Each last value is read from the sequence itself: pg_sequences shows none for
a sequence restarted and not used since, and its start value says nothing
about where the striding left it.

> Before: `bad="$("$@" -v ON_ERROR_STOP=1 -qAt -c "select coalesce(string_agg(format('%s (steps by %s from %s)', s.sequen`

The tables clinics also write and send up (sync/tables/{odoo,openelis}.conf [up]). Only for
those does an id issued below the floor matter; the lab test catalogue is
written at the hub alone, and its floor may stand above its sequence (some
catalogue sequences stand below the rows they hold).

> Before: `up=" $(bash "$R/sync/tables/tables.sh" openelis up | tr '\n' ' ') "`

## `scripts/trace-change.sh`

Trace a database change through REMOTE components
Usage: ./trace-change.sh <table_name> <record_id> [topic_name]
Example: ./trace-change.sh person 99999
         ./trace-change.sh person 99999 bahmni-local.openmrs.person
Run this from the remote/ directory

Colors

> Before: `GREEN='\033[0;32m'`

Find topic if not provided

> Before: `if [ -z "$TOPIC" ]; then`

Check for messages containing the record ID

> Before: `echo "   Checking for messages containing: $RECORD_ID"`

Check for errors

> Before: `ERRORS=$(curl -s http://localhost:8083/connectors/$SINK_CONNECTOR/status 2>/dev/null | jq -r '.tasks[]?.trace `

Try to check MySQL (requires mysql client and credentials)

> Before: `if command -v mysql &> /dev/null; then`

Try common connection methods

> Before: `MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD:-} openmrs 2>/dev/null || mysql -u root openmrs 2>/dev/null"`

## `scripts/validate-sink-config.py`

Keys whose value legitimately differs per deployment, so `known-good.json`'s
value is an example rather than a requirement. Presence is still required.

> Before: `ENVIRONMENT_KEYS = {`

embeds MYSQL_SERVER_NAME / database name, which vary per clinic

> Before: `"transforms.dropPrefix.regex",`

the hub serves several clinics, so the topic carries the
clinic's MirrorMaker alias and server name; generator_rules() checks its
SHAPE instead.

> Before: `"topics",`

The clinical tables and the key each sink upserts on: the strided integer PK
the clinic's record key carries. drug_order's and test_order's key is
orders.order_id.

> Before: `CLINICAL_KEYS = {"obs": "obs_id", "orders": "order_id", "drug_order": "order_id", "test_order": "order_id"}`

These keys must be absent: the sink never changes the hub's schema.

> Before: `CLINICAL_ABSENT = ("auto.create", "auto.evolve")`

`//`-prefixed keys are this repo's JSON comment convention, never settings.

> Before: `return {k: v for k, v in cfg.items() if not k.startswith("//")}`

The sync-key rule is stated here rather than left to the known-good diff
so the failure names the invariant instead of reporting a shape mismatch.
The sync key must be collision-free BY CONSTRUCTION: under v1 that is the
strided integer PK carried in the Kafka record KEY. record_value keys the
upsert on a value field, which striding does not protect. This generator
once emitted record_value while every live sink ran record_key.

> Before: `pkm = cfg.get("primary.key.mode")`

A per-clinic sink must carry a clinic-distinguishing topic. Two clinics
sharing one connector name is how the hub lost clinic 2's configs: the
second registration PUT over the first.

> Before: `topics = cfg.get("topics", "")`

known-good carries ${TABLE} / ${PRIMARY_KEY} here: the generated
value is per-table, so only require that something was filled in
and that no placeholder survived substitution.

> Before: `if not str(actual).strip():`

Never pass silently just because the reference is missing - that is
the same "absent check reads as a passing check" trap this file exists
to close.

> Before: `errs.append(`

## `table-verdicts.conf`

node writes it and how a clinic gets it. sync/tables/openmrs.conf [down] (what travels hub ->
clinic) and sync/tables/openmrs.conf [up] (what a clinic captures and sends up) are
checked against this file by clinic/scripts/check-table-verdicts.sh, so a row
can only join either list with a verdict that allows it.

Format: <table> <verdict> [<proposed verdict>]

  DOWN     the hub is the only writer of every row; a clinic receives the
           table from the seed and then from its down sink. Allowed in
           sync/tables/openmrs.conf [down] (unmarked), never in sync/tables/openmrs.conf [up].
  relay    a clinic writes it and the hub passes it on to the other clinics.
           Allowed in both lists, marked `relay` in sync/tables/openmrs.conf [down].
  SHARED   the hub and the clinics each write their own rows of it; the hub
           captures only its own (above the floor, residue 0) and a clinic
           sends up only its own. Allowed in both lists, marked `hub-rows` in
           sync/tables/openmrs.conf [down].
  UP       a clinic writes it and sends it up; clinics never pull it.
           A table in both directions without an origin filter on both
           publishers loops, so an UP table never appears in sync/tables/openmrs.conf [down].
  RESEED   written only by OpenMRS core or module changesets, or changed so
           rarely that a change at the hub is a fleet reseed. Delivered by the
           seed alone and compared by checksum after it
           (clinic/scripts/master-checksum.sh --reseed); in neither list.
  OUT      node-local or unused; in neither list.
  pending  a proposed verdict that is not yet ratified. The table stays out of
           both lists until this line carries a final verdict.

A table that has no line here has no verdict: adding it to either list fails
the check until it is given one, and so does a release that starts writing it.

--- identity: users, roles and providers, authored at the hub -------------------

> Before: `users                                   DOWN`

--- forms ------------------------------------------------------------------------

> Before: `form                                    DOWN`

--- privileges (keyed by name) -----------------------------------------------------

> Before: `privilege                               DOWN`

--- concept dictionary and vocabulary ------------------------------------------------

> Before: `concept_class                           DOWN`

--- drugs ----------------------------------------------------------------------------

> Before: `drug                                    DOWN`

--- locations --------------------------------------------------------------------------

> Before: `location                                DOWN`

--- programs ---------------------------------------------------------------------------

> Before: `program                                 DOWN`

--- types that clinic rows refer to ------------------------------------------------------

> Before: `visit_type                              DOWN`

--- metadata mapping: proposed DOWN, not yet ratified -------------------------------------

> Before: `metadatamapping_metadata_term_mapping   pending DOWN`

--- written by changesets, or a change is a fleet reseed --------------------------------------

> Before: `concept_datatype                        RESEED`

carries a physical foreign key to concept_reference_source, so a child that
arrived before its parent would stop the sink: proposed RESEED, not yet ratified

> Before: `fhir_concept_source                     pending RESEED`

--- written at the clinic and sent up ------------------------------------------------------------

> Before: `encounter                               UP`

encounter_type is written at clinics and captured up; the hub does not filter
its own capture by origin, so sending it down as well would loop. A new
encounter type reaches clinics by reseed.

> Before: `encounter_type                          UP`

the patient-identifier counter; each clinic has its own range

> Before: `idgen_seq_id_gen                        UP`

--- written at the hub and at the clinics, each its own rows ---------------------------------------

> Before: `person                                  SHARED`

--- not synced ------------------------------------------------------------------------------------

> Before: `global_property                         OUT`

empty, and the map has no primary key to sync on

> Before: `concept_name_tag                        OUT`

its rows start scheduled tasks: the hub's set would start the hub's feed
publishers at a clinic. Proposed OUT, not yet ratified.

> Before: `scheduler_task_config                   pending OUT`
