# bahmni-local

One branch for every node of the Bahmni local-cloud sync lab. Three trees:

- `clinic/` -- the clinic compose project and installer (Bahmni apps, the
  clinic's Kafka, Debezium and MirrorMaker, its config and connector
  templates, the ops scripts). A clinic node runs `docker compose` from here
  with `clinic/.env` holding that node's identity.
- `cloud/` -- the hub's sync layer as its own compose project: Kafka, Kafka
  Connect, the connector generators, and the sinks for every clinic in `sync/clinics.json`.
  It runs beside the hub's Bahmni application stack, which is not in this
  repository.
- `sync/` -- shared definitions both sides read: the table lists, one file per
  database (`sync/tables/`), the MirrorMaker template (`sync/local/`), and the
  fleet list `clinics.json`: every node keyed by its slug, with its site
  number and MRN prefix. The site number is the digit every id the
  clinic creates ends in, and starts its OpenELIS lab numbers: unique, and
  never reused or changed on a node that has written rows. A clinic without
  one (`null`) cannot sync.

Per-node values live in each project's gitignored `.env`; the committed
`.env.example` next to it enumerates every variable.
