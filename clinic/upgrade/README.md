# clinic/upgrade — moving a clinic off the old stack

The old stack is the single-directory layout: `docker-compose.yml`, `initialize/` and
`debezium/local/` at the root of the checkout, ZooKeeper Kafka, and an Odoo 10. A clinic
moves to the stack under `clinic/` by a fresh install and a seed from the hub, not by
changing the old one in place.

The seed **replaces** the clinic's databases with the hub's. The old stack sends only the
tables its Debezium source captures (registration, visits, encounters). Everything else
the clinic wrote stays on its own disk, and a reseed loses it:
- the rest of the patient record (obs, orders, diagnoses, programs);
- everything in its Odoo;
- every patient file.

So the first step on every old machine is to find out whether it holds such data.

## 1. Inspect the old machine (read-only)

Copy `inspect-old-node.sh` to the old machine (it needs nothing else from this
checkout) and run it from the old checkout, as the user that runs the stack, with
the stack up:

    ./inspect-old-node.sh                       # or --old-dir <old checkout>
    ./inspect-old-node.sh --since YYYY-MM-DD    # when the old stack never set a stride

It opens read-only database sessions, changes no container, file or setting of the
stack, and writes only its report folder (`--out`, default
`./old-node-inspection-<host>-<utc time>`). It never prints or writes a secret from
the old `.env`. Copy the folder off the machine.

What it reads:

| Part | What it reports |
|---|---|
| Host | OS, memory, disk, the podman machine (rootful or not, size), old boot-time starters, `bahmni.local` in `/etc/hosts`, the old dnsmasq lines, which needed ports are in use |
| Old checkout | branch, commit, uncommitted paths, image names and identity from `.env` (no secrets) |
| Sync | Debezium and MirrorMaker connector states, the tables the live source captures, the end offsets of the clinic's topics (the drain later compares them with the hub's) |
| OpenMRS | per table, the rows this clinic wrote, by month (`clinic-rows.tsv`, `clinic-rows-by-month.tsv`) |
| Odoo | per business table, rows created since the clinic started (`odoo-rows.tsv`) |
| Files | per file tree, files and size, and how many are newer than the start (`files.tsv`) |

**How clinic rows are told apart.** The old stack sets MySQL's global
`auto_increment_increment`/`auto_increment_offset` to the clinic's stride. Every row
the clinic inserted, in every auto-increment table, therefore has an id on the
clinic's residue, and sits above every row of the starting copy, which came from a
server that never strided.

Per table, the script walks the key down from the top. The first id off the residue is
the last row of the copy, and the rows above it are the clinic's. The clinic's start is
its first person, visit or encounter above that table's base id in
`debezium/local/tables.conf`. Rows above the boundary but older than the start are
rows of the copy that happened to land on the residue, and are not counted.

A table with no `date_created` cannot be filtered that way. Its count is marked
`undated`: it is listed for a person to check, and it does not decide the verdict. Odoo
has no stride, so its rows are dated from the clinic's start.

**Verdict** (`summary.env` `verdict=`, last lines of `report.txt`):

| Verdict | Meaning | Exit |
|---|---|---|
| `A` | Nothing found that exists only on this machine. A reinstall and reseed loses no clinic data. | 0 |
| `B` | Patient-record rows the source does not capture, Odoo business rows, or patient files were created here. Each needs a decision before anything is removed: move it to the central server, or keep it as an archive. | 0 |
| `UNKNOWN` | A part could not be read (`GAP` lines). Fix it and run again. | 2 |

`CONNECT_PORT` / `MM_CONNECT_PORT` override the Connect REST ports (8083, 8084).

## Tests

`tests/live-inspect.sh` needs Docker. It builds an old-stack fixture the way the old
stack leaves a clinic: an unstrided starting copy, then the stride and base floors, then
clinic inserts. It runs three scenarios: clinic-only rows (B), registration only (A),
and MySQL down (UNKNOWN). Each runs under `bash` and, on macOS, under `/bin/bash`
(3.2).

The databases run on tmpfs, and the Connect REST APIs are stubbed on 18083/18084. It is
a fixture, not an old clinic: a run against a real old-stack machine is the proof.
