-- Sets the cloud Odoo publication: the [down] tables its source captures for clinics to pull.
-- psql -d odoo -v pub=dbz_odoo_owned -v tables=a,b -v floors=a:4520,b:40 -f apply-down-publication.sql

-- Pass the psql variables into the DO block.
\set ON_ERROR_STOP on
SELECT set_config('myvars.pub', :'pub', false) \g /dev/null
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
SELECT set_config('myvars.floors', :'floors', false) \g /dev/null

DO $do$
DECLARE
  v_pub    text   := current_setting('myvars.pub');
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_floors text[] := coalesce(string_to_array(nullif(current_setting('myvars.floors'), ''), ','), '{}');
  v_parts  text[] := '{}';
  v_t      text;
  v_f      text;
  v_floor  bigint;
  v_rel    regclass;
  v_has_id boolean;
  v_ri     "char";
  v_ri_ok  boolean;
BEGIN
  -- Refuse: PostgreSQL older than 15, no tables, or a malformed or misplaced floor.
  IF current_setting('server_version_num')::int < 150000 THEN
    RAISE EXCEPTION 'row filters need PostgreSQL 15 or newer; this server is %', current_setting('server_version');
  END IF;
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_f IN ARRAY v_floors LOOP
    IF split_part(v_f, ':', 2) !~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'floor entry "%" is not <table>:<whole number>', v_f;
    END IF;
    IF NOT split_part(v_f, ':', 1) = ANY (v_tables) THEN
      RAISE EXCEPTION 'a floor is recorded for %, which clinics do not pull', split_part(v_f, ':', 1);
    END IF;
  END LOOP;

  -- A table with an id gets the floor filter (id < floor OR id % 10 = 0); one without is captured whole.
  FOREACH v_t IN ARRAY v_tables LOOP
    v_rel := to_regclass(format('public.%I', v_t));
    IF v_rel IS NULL THEN
      RAISE EXCEPTION 'down table public.% does not exist in this database', v_t;
    END IF;
    v_has_id := EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v_rel AND attname = 'id' AND NOT attisdropped);
    v_floor := NULL;
    FOREACH v_f IN ARRAY v_floors LOOP
      IF split_part(v_f, ':', 1) = v_t THEN v_floor := split_part(v_f, ':', 2)::bigint; END IF;
    END LOOP;
    IF v_has_id THEN
      IF v_floor IS NULL THEN
        RAISE EXCEPTION 'no floor recorded for %: it has an id column, so it is captured only with the filter (id < floor OR id %% 10 = 0); record the floors when the hub''s ids are strided', v_t;
      END IF;
      IF v_floor % 10 <> 0 THEN
        RAISE EXCEPTION 'the floor recorded for % is %, not a multiple of 10: the hub mints residue 0 from its floor', v_t, v_floor;
      END IF;
      SELECT relreplident INTO v_ri FROM pg_class WHERE oid = v_rel;
      v_ri_ok := v_ri = 'f'
        OR EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
                   WHERE i.indrelid = v_rel AND a.attname = 'id'
                     AND ((v_ri = 'd' AND i.indisprimary) OR (v_ri = 'i' AND i.indisreplident)));
      IF NOT v_ri_ok THEN
        RAISE EXCEPTION '%: its replica identity (relreplident %) does not cover id, so with the row filter PostgreSQL would refuse every UPDATE and DELETE on it', v_t, v_ri;
      END IF;
      v_parts := v_parts || format('public.%I WHERE (id < %s OR id %% 10 = 0)', v_t, v_floor);
    ELSE
      IF v_floor IS NOT NULL THEN
        RAISE EXCEPTION 'a floor is recorded for %, which has no id column (it is captured unfiltered)', v_t;
      END IF;
      v_parts := v_parts || format('public.%I', v_t);
    END IF;
  END LOOP;

  -- Include the heartbeat table, then create the publication or replace its table list.
  IF to_regclass('public.dbz_heartbeat') IS NOT NULL THEN
    v_parts := v_parts || 'public.dbz_heartbeat'::text;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = v_pub) THEN
    EXECUTE format('ALTER PUBLICATION %I SET TABLE %s', v_pub, array_to_string(v_parts, ', '));
    EXECUTE format('ALTER PUBLICATION %I SET (publish = %L)', v_pub, 'insert, update, delete');
  ELSE
    EXECUTE format('CREATE PUBLICATION %I FOR TABLE %s WITH (publish = %L)', v_pub, array_to_string(v_parts, ', '), 'insert, update, delete');
  END IF;
END $do$;

SELECT tablename || ' ' || coalesce(rowfilter, '-') FROM pg_publication_tables
 WHERE pubname = :'pub' AND schemaname = 'public' ORDER BY tablename;
