# sync/tables — which tables sync

One file per database. Each file has two sections:

- `[up]` — tables a clinic sends to the hub
- `[down]` — tables changed on the cloud server: captured into its Kafka, and pulled into each clinic's Kafka by the clinic's MirrorMaker

| File | Database |
|---|---|
| `openmrs.conf` | OpenMRS (MySQL database `openmrs`) |
| `odoo.conf` | Odoo (Postgres database `odoo`, schema `public`) |
| `openelis.conf` | OpenELIS (Postgres database `openelis`, schema `clinlims`) |

Each section's line format is described in a comment at its top. Lines that
start with `#` are comments.

`tables.sh` is the one reader for these files; every script that needs a table
list goes through it.

## How to add or remove a table

1. Edit the right section of the right file.
2. On a clinic, regenerate and upload its connectors:

   ```
   cd clinic
   bash scripts/generate-connectors.sh
   bash scripts/register-connectors.sh
   ```

   A new OpenMRS `[down]` table also needs the sink user's grant first:
   `bash scripts/grant-down-tables.sh`.
3. On the hub, rerun the matching hub script (see `cloud/README.md`): the MySQL
   source for an OpenMRS `[down]` change, `cloud/scripts/register-odoo.sh` for an
   Odoo or OpenELIS `[down]` change, the sink generator for an `[up]` change.

## Special cases

- `obs`, `orders`, `drug_order` and `test_order` are in OpenMRS `[up]` and
  need a floor from the seed or from another table, so the capture filter
  keeps only this clinic's rows.
- The signal table `openmrs.debezium_signal` is captured on every clinic
  without a line here; the reader refuses a line for it. A row inserted there
  asks the source connector to re-read rows (`clinic/scripts/catch-up-clinical.sh`).

## Checking a list

```
bash sync/tables/tables.sh openmrs up      # the OpenMRS tables a clinic sends
bash sync/tables/tables.sh odoo down       # the Odoo tables clinics pull
```

The installer and the tests read the same files, so a mistake in a list fails
there, naming the line.
