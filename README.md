# bahmni-local

One branch for every node of the Bahmni local-cloud sync lab. Three trees:

- `clinic/` -- the clinic compose project (Bahmni apps, the clinic's Kafka,
  Debezium and MirrorMaker, its config and connector templates, the ops
  scripts). A clinic node runs `docker compose` from here with `clinic/.env`
  holding that node's identity.
- `cloud/` -- the hub compose project (cloud Bahmni, the hub's Kafka and
  Kafka Connect, the up-direction sink generator). The hub runs from here.
- `sync/` -- what both sides read: the clinic-owned table list and connector
  templates (`sync/local/`), `subsystems.conf`, and the fleet ledger
  `clinics.txt`. The hub's own list stays at `cloud/tables.conf`.

Per-node values live in each project's gitignored `.env`; the committed
`.env.example` next to it enumerates every variable.
