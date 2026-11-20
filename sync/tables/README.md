# sync/tables — which tables sync

One file per database. Each file has two sections:

- `[up]` — tables a clinic sends to the hub
- `[down]` — tables the hub sends to clinics

| File | Database |
|---|---|
| `openmrs.conf` | OpenMRS (MySQL, `openmrs`) |
| `odoo.conf` | Odoo (Postgres, `odoo`) |
| `openelis.conf` | OpenELIS (Postgres, `clinlims`) |

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
   source for an OpenMRS `[down]` change, `connectors/register-odoo.sh` for an
   Odoo or OpenELIS `[down]` change, the sink generator for an `[up]` change.

## Checking a list

```
bash sync/tables/tables.sh openmrs up      # the OpenMRS tables a clinic sends
bash sync/tables/tables.sh hub-down odoo   # the Odoo tables the hub sends
```

The installer and the tests read the same files, so a mistake in a list fails
there, naming the line.
