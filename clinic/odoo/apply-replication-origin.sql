-- sync-core: clinic half of the replication-origin loop guard (PG16+). Run as superuser on
-- the clinic's bahmni-postgres. PostgreSQL lets ONE session hold an origin at a time, so
-- the sinks' pooled connections each claim one of hub_1..hub_16 (the c3p0 customizer
-- t4d.sync.SyncOriginCustomizer creates a missing one on demand). Origins are cluster-wide
-- and count against max_replication_slots' origin budget; the grants are per database
-- because the function ACL lives in each database's pg_proc. Idempotent.
SELECT 'origin '||n||': '||CASE WHEN EXISTS (SELECT 1 FROM pg_replication_origin WHERE roname='hub_'||n)
       THEN 'exists' ELSE 'created '||pg_replication_origin_create('hub_'||n)::text END
FROM generate_series(1,8) AS n;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_setup(text) TO odoo_sink, clinlims_sink;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_reset() TO odoo_sink, clinlims_sink;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_is_setup() TO odoo_sink, clinlims_sink;
GRANT EXECUTE ON FUNCTION pg_replication_origin_create(text) TO odoo_sink, clinlims_sink;
SELECT 'origins now: '||string_agg(roname, ',' ORDER BY roident) FROM pg_replication_origin;
