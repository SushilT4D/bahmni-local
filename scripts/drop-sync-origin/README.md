# Drop the `sync_origin` column fleet-wide (sync-core F-049, 2026-09-09)

Step 4 of the column retirement. Preconditions, all done on 9 Sep: every clinic guard is
in the engine (F-044 origins, F-047 sql_log_bin), every publication is unfiltered, no
clinic trigger stamps the column, and **every JDBC sink on all three nodes carries
`field.exclude.list=.*:sync_origin`**, so a record produced before the drop is applied
cleanly after it. That last point is what makes the order across nodes irrelevant: the
Ghated->cloud MirrorMaker backlog (750k messages) can keep draining through it.

Order on each node: (1) triggers that reference the column go first, or every write
fails once the column is gone; (2) the DDL; (3) restart the sink tasks so the cached
table descriptors refresh; (4) on the clinics, Odoo must already be running the emptied
`bahmni_sync_acl` (no field declared) or `odoo -u all` recreates the column.

  clinic (PG):   psql -U odoo -d odoo     -f drop-sync-origin-odoo.sql
                 psql -U odoo -d openelis -f drop-sync-origin-clinlims.sql
  clinic (MySQL) mysql -uroot openmrs   < drop-sync-origin-openmrs.sql
  hub (PG):      psql -U postgres -d odoo     -f hub-retire-triggers-odoo.sql   (LWW kept, origin tie-break gone)
                 psql -U postgres -d openelis -f hub-retire-triggers-clinlims.sql
                 then the same two drop-*.sql; mysql < drop-sync-origin-openmrs.sql (5.6 rebuilds person, ~121k rows)

`sync_updated_at` stays on Odoo's twelve tables: it carries the last-writer rule.
