-- REQUIRED for every clinic, before its Odoo and OpenELIS sinks start: creates the clinic's
-- replication origin and lets the sink role claim it. Without it a sink fails to connect.
-- Run as superuser in each database:
--   psql -d odoo     -v origin=clinic_<slug>_odoo     -v role=odoo_sink     -f apply-sink-origin.sql
--   psql -d openelis -v origin=clinic_<slug>_clinlims -v role=clinlims_sink -f apply-sink-origin.sql
-- The sources capture with origin=none, so rows the sinks write are never captured for other clinics to pull.
SELECT 'created origin ' || :'origin' || ' (' || pg_replication_origin_create(:'origin') || ')'
 WHERE NOT EXISTS (SELECT 1 FROM pg_replication_origin WHERE roname = :'origin');
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_setup(text) TO :"role";
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_reset() TO :"role";
GRANT EXECUTE ON FUNCTION pg_replication_origin_session_is_setup() TO :"role";
SELECT 'origin ' || roname || ' present, ' || :'role' || ' may claim it: '
       || has_function_privilege(:'role', 'pg_replication_origin_session_setup(text)', 'EXECUTE')
  FROM pg_replication_origin WHERE roname = :'origin';
