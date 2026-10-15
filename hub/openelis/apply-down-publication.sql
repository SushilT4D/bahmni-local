-- The hub's OpenELIS down publication: what the hub's OpenELIS source sends to
-- every clinic.
--
-- It holds exactly the OpenELIS down tables passed in (sync/hub-down.conf, read
-- through sync/hub-down.sh), plus clinlims.dbz_heartbeat when it exists, and
-- nothing else: SET TABLE replaces whatever the publication held before. It
-- publishes INSERT, UPDATE and DELETE, never TRUNCATE (a TRUNCATE at the hub
-- would empty every clinic's copy).
--
-- No table carries a row filter. The rows keep the ids the clinic gave them (a
-- result answers a clinic's analysis; the analysis and sample are the clinic's
-- own rows, moved on by the hub), so an id filter would drop exactly the rows
-- that must go down. What goes down is chosen by replication origin instead:
-- the source decodes with origin=none, so a row a clinic's up-sink applied here
-- is never published. Each clinic keeps only the rows routed to it.
--
-- Refused, naming the table, before the publication is touched:
--   - a down table that does not exist;
--   - a down table without a replica identity (no primary key and none set):
--     PostgreSQL refuses every UPDATE and DELETE on a table that a publication
--     publishes updates for without one, so the hub's OpenELIS could no longer
--     write it;
--   - a server older than PostgreSQL 16 (the source's origin=none needs it).
--
-- Usage: psql -d openelis -v pub=dbz_clinlims_owned -v tables=result,analysis,sample \
--             -f apply-down-publication.sql
-- Prints one line per published table: "<table> <row filter>", "-" for none.
\set ON_ERROR_STOP on
SELECT set_config('myvars.pub', :'pub', false) \g /dev/null
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null

DO $do$
DECLARE
  v_pub    text   := current_setting('myvars.pub');
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_parts  text[] := '{}';
  v_t      text;
  v_rel    regclass;
  v_ri     "char";
BEGIN
  IF current_setting('server_version_num')::int < 160000 THEN
    RAISE EXCEPTION 'the hub''s OpenELIS source decodes with origin=none, which needs PostgreSQL 16 or newer; this server is %', current_setting('server_version');
  END IF;
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_t IN ARRAY v_tables LOOP
    v_rel := to_regclass(format('clinlims.%I', v_t));
    IF v_rel IS NULL THEN
      RAISE EXCEPTION 'down table clinlims.% does not exist in this database', v_t;
    END IF;
    SELECT relreplident INTO v_ri FROM pg_class WHERE oid = v_rel;
    IF v_ri = 'n' OR (v_ri = 'd' AND NOT EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_rel AND indisprimary)) THEN
      RAISE EXCEPTION 'clinlims.% has no replica identity (no primary key): published for updates, PostgreSQL would refuse every UPDATE and DELETE on it', v_t;
    END IF;
    v_parts := v_parts || format('clinlims.%I', v_t);
  END LOOP;
  IF to_regclass('clinlims.dbz_heartbeat') IS NOT NULL THEN
    v_parts := v_parts || 'clinlims.dbz_heartbeat'::text;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = v_pub) THEN
    EXECUTE format('ALTER PUBLICATION %I SET TABLE %s', v_pub, array_to_string(v_parts, ', '));
    EXECUTE format('ALTER PUBLICATION %I SET (publish = %L)', v_pub, 'insert, update, delete');
  ELSE
    EXECUTE format('CREATE PUBLICATION %I FOR TABLE %s WITH (publish = %L)', v_pub, array_to_string(v_parts, ', '), 'insert, update, delete');
  END IF;
END $do$;

SELECT tablename || ' ' || coalesce(rowfilter, '-') FROM pg_publication_tables
 WHERE pubname = :'pub' AND schemaname = 'clinlims' ORDER BY tablename;
