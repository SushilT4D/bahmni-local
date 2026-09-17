# bahmni-local

One branch for every node of the Bahmni local-cloud sync lab. Four trees:

- `clinic/` -- the clinic compose project and installer (Bahmni apps, the
  clinic's Kafka, Debezium and MirrorMaker, its config and connector
  templates, the ops scripts). A clinic node runs `docker compose` from here
  with `clinic/.env` holding that node's identity.
- `cloud/` -- the Bahmni base stack the hub runs beside: cloud Bahmni on the
  IPLIT distribution. Under the target model this is app-only; the sync
  layer that used to run alongside it now lives in `hub/`.
- `hub/` -- the sync layer as its own compose project: Kafka, Schema
  Registry, Kafka Connect, the connector generators, and its own
  `clinics.conf`/`tables.conf`. The hub runs from here.
- `sync/` -- shared definitions both sides read: the clinic-owned table list
  and connector templates (`sync/local/`), `subsystems.conf`, and the fleet
  ledger `clinics.txt`.

Per-node values live in each project's gitignored `.env`; the committed
`.env.example` next to it enumerates every variable.
