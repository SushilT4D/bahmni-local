-- The hub's OpenELIS down publication: what the hub's OpenELIS source sends to
-- every clinic.
--
-- It holds exactly the OpenELIS down tables passed in (sync/hub-down.conf, read
-- through sync/hub-down.sh), plus clinlims.dbz_heartbeat when it exists, and
-- nothing else: SET TABLE replaces whatever the publication held before. It
-- publishes INSERT, UPDATE and DELETE, never TRUNCATE (a TRUNCATE at the hub
-- would empty every clinic's copy).
--
-- A table routed to one clinic (result, analysis, sample) carries no row
-- filter: the rows keep the ids the clinic gave them (a result answers a
-- clinic's analysis; the analysis and sample are the clinic's own rows, moved
-- on by the hub), so an id filter would drop exactly the rows that must go
-- down. What goes down is chosen by replication origin instead: the source
-- decodes with origin=none, so a row a clinic's up-sink applied here is never
-- published. Each clinic keeps only the rows routed to it.
--
-- A table that goes to every clinic (system_user, the lab test catalogue)
-- carries the filter
--     (id < <floor> OR id % 10 = 0)
-- with this hub's floor (hub/clinlims-down-floors.local): the hub's own rows,
-- from before its ids were strided and since. A row a clinic minted that the
-- hub edits stays at the hub. Such a table without an id column (a link table,
-- keyed by the ids it links) carries no filter: only the hub writes the
-- catalogue's link tables, and they have no id to filter on.
--
-- Refused, naming the table, before the publication is touched:
--   - a down table that does not exist;
--   - a down table without a replica identity (no primary key and none set):
--     PostgreSQL refuses every UPDATE and DELETE on a table that a publication
--     publishes updates for without one, so the hub's OpenELIS could no longer
--     write it; for a filtered table, one whose replica identity does not
--     cover id;
--   - a filtered table with an id and no floor, or a floor that is not a
--     multiple of 10; a floor for a table that is not a down table, or that
--     has no id column;
--   - a server older than PostgreSQL 16 (the source's origin=none needs it).
--
-- Usage: psql -d openelis -v pub=dbz_clinlims_owned -v tables=system_user,result,analysis,sample \
--             -v filtered=system_user -v floors=system_user:170 -f apply-down-publication.sql
-- Prints one line per published table: "<table> <row filter>", "-" for none.
\set ON_ERROR_STOP on
SELECT set_config('myvars.pub', :'pub', false) \g /dev/null
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
SELECT set_config('myvars.filtered', :'filtered', false) \g /dev/null
SELECT set_config('myvars.floors', :'floors', false) \g /dev/null

DO $do$
DECLARE
  v_pub    text   := current_setting('myvars.pub');
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_filt   text[] := coalesce(string_to_array(nullif(current_setting('myvars.filtered'), ''), ','), '{}');
  v_floors text[] := coalesce(string_to_array(nullif(current_setting('myvars.floors'), ''), ','), '{}');
  v_parts  text[] := '{}';
  v_t      text;
  v_f      text;
  v_floor  bigint;
  v_rel    regclass;
  v_ri     "char";
  v_has_id boolean;
BEGIN
  IF current_setting('server_version_num')::int < 160000 THEN
    RAISE EXCEPTION 'the hub''s OpenELIS source decodes with origin=none, which needs PostgreSQL 16 or newer; this server is %', current_setting('server_version');
  END IF;
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_f IN ARRAY v_floors LOOP
    IF split_part(v_f, ':', 2) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'floor entry "%" is not <table>:<whole number>', v_f;
    END IF;
    IF NOT split_part(v_f, ':', 1) = ANY (v_filt) THEN
      RAISE EXCEPTION 'a floor is recorded for clinlims.%, which the hub does not send down filtered on a floor', split_part(v_f, ':', 1);
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY v_tables LOOP
    v_rel := to_regclass(format('clinlims.%I', v_t));
    IF v_rel IS NULL THEN
      RAISE EXCEPTION 'down table clinlims.% does not exist in this database', v_t;
    END IF;
    SELECT relreplident INTO v_ri FROM pg_class WHERE oid = v_rel;
    IF v_ri = 'n' OR (v_ri = 'd' AND NOT EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_rel AND indisprimary)) THEN
      RAISE EXCEPTION 'clinlims.% has no replica identity (no primary key): published for updates, PostgreSQL would refuse every UPDATE and DELETE on it', v_t;
    END IF;
    v_has_id := EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v_rel AND attname = 'id' AND NOT attisdropped);
    IF v_t = ANY (v_filt) AND NOT v_has_id THEN
      FOREACH v_f IN ARRAY v_floors LOOP
        IF split_part(v_f, ':', 1) = v_t THEN
          RAISE EXCEPTION 'a floor is recorded for clinlims.%, which has no id column: a link table is published whole', v_t;
        END IF;
      END LOOP;
      v_parts := v_parts || format('clinlims.%I', v_t);
    ELSIF v_t = ANY (v_filt) THEN
      v_floor := NULL;
      FOREACH v_f IN ARRAY v_floors LOOP
        IF split_part(v_f, ':', 1) = v_t THEN v_floor := split_part(v_f, ':', 2)::bigint; END IF;
      END LOOP;
      IF v_floor IS NULL THEN
        RAISE EXCEPTION 'no floor recorded for clinlims.%: it goes to every clinic, filtered (id < floor OR id %% 10 = 0); record it before the hub''s OpenELIS ids are strided, or on a hub strided before with record-clinlims-down-floors.sh --derive and --from-file', v_t;
      END IF;
      IF v_floor % 10 <> 0 THEN
        RAISE EXCEPTION 'the floor recorded for clinlims.% is %, not a multiple of 10', v_t, v_floor;
      END IF;
      IF NOT (v_ri = 'f' OR EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
                 WHERE i.indrelid = v_rel AND a.attname = 'id' AND ((v_ri = 'd' AND i.indisprimary) OR (v_ri = 'i' AND i.indisreplident)))) THEN
        RAISE EXCEPTION 'clinlims.%: its replica identity (relreplident %) does not cover id, so with the row filter PostgreSQL would refuse every UPDATE and DELETE on it', v_t, v_ri;
      END IF;
      v_parts := v_parts || format('clinlims.%I WHERE (id < %s OR id %% 10 = 0)', v_t, v_floor);
    ELSE
      v_parts := v_parts || format('clinlims.%I', v_t);
    END IF;
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
