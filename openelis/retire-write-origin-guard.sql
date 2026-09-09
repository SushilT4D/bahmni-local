-- sync-core, 2026-09-09: retire the clinlims write-origin guard on a CLINIC node.
-- Supersedes the row filters and triggers created by setup-clinlims-sync.sql /
-- apply-write-origin-guard.sql. The loop guard now lives in the engine (PG16):
-- sink sessions carry a replication origin (t4d.sync.SyncOriginCustomizer) and the
-- source decodes with origin=none, so a replicated transaction is never republished by
-- the node that applied it (sync-core F-044). The sync_origin COLUMN stays: every sink
-- caches the table descriptor (schema.evolution=none) and the cloud keeps its copy, so
-- dropping it is a fleet-wide schema change, not a local cleanup. New clinic rows carry
-- sync_origin NULL from now on; the sinks' accept filter treats NULL as "not mine".
-- Do NOT run on the hub: the cloud must publish everything it holds to relay.
-- Idempotent. Run as superuser on the openelis database:
--   psql -U odoo -d openelis -f retire-write-origin-guard.sql
ALTER PUBLICATION dbz_clinlims_owned DROP TABLE clinlims.sample;      ALTER PUBLICATION dbz_clinlims_owned ADD TABLE clinlims.sample;
ALTER PUBLICATION dbz_clinlims_owned DROP TABLE clinlims.sample_item; ALTER PUBLICATION dbz_clinlims_owned ADD TABLE clinlims.sample_item;
ALTER PUBLICATION dbz_clinlims_owned DROP TABLE clinlims.analysis;    ALTER PUBLICATION dbz_clinlims_owned ADD TABLE clinlims.analysis;
ALTER PUBLICATION dbz_clinlims_owned DROP TABLE clinlims.result;      ALTER PUBLICATION dbz_clinlims_owned ADD TABLE clinlims.result;
DROP TRIGGER IF EXISTS sample_origin      ON clinlims.sample;
DROP TRIGGER IF EXISTS sample_item_origin ON clinlims.sample_item;
DROP TRIGGER IF EXISTS analysis_origin    ON clinlims.analysis;
DROP TRIGGER IF EXISTS result_origin      ON clinlims.result;
SELECT 'pub '||tablename||' WHERE '||coalesce(rowfilter,'(none)') FROM pg_publication_tables WHERE pubname='dbz_clinlims_owned' ORDER BY 1;
SELECT 'clinlims triggers left: '||count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname='clinlims';
