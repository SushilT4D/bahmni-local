# bahmni-local

One branch for every node of the Bahmni local-cloud sync lab. Three trees:

- `clinic/` -- the clinic compose project and installer (Bahmni apps, the
  clinic's Kafka, Debezium and MirrorMaker, its config and connector
  templates, the ops scripts). A clinic node runs `docker compose` from here
  with `clinic/.env` holding that node's identity.
- `cloud/` -- the hub's sync layer as its own compose project: Kafka, Kafka
  Connect, the connector generators, and the sinks for every clinic in `sync/clinics.txt`.
  It runs beside the hub's Bahmni application stack, which is not in this
  repository.
- `sync/` -- shared definitions both sides read: the table lists, one file per
  database (`sync/tables/`), the MirrorMaker template (`sync/local/`), and the
  fleet ledger `clinics.txt`.

Per-node values live in each project's gitignored `.env`; the committed
`.env.example` next to it enumerates every variable.
