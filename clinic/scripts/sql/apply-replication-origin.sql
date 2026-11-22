-- Replication origins the clinic's down sinks claim, so the clinic's sources
-- (origin=none) skip the rows those sinks write. One session holds an origin at a
-- time: cloud_odoo is the Odoo down sink's, cloud_openelis the OpenELIS down sink's.
-- Run as superuser on the clinic's bahmni-postgres; origins are cluster-wide, the
-- grants per database. Idempotent.
SELECT 'origin '||o||': '||CASE WHEN EXISTS (SELECT 1 FROM pg_replication_origin WHERE roname=o)
       THEN 'exists' ELSE 'created '||pg_replication_origin_create(o)::text END
FROM unnest(ARRAY['cloud_odoo','cloud_openelis']) AS o;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_setup(text) TO odoo_sink, clinlims_sink;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_reset() TO odoo_sink, clinlims_sink;
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_is_setup() TO odoo_sink, clinlims_sink;
SELECT 'origins now: '||string_agg(roname, ',' ORDER BY roident) FROM pg_replication_origin;
