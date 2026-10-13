-- The hub's Odoo down publication: what the hub's Odoo source sends to every clinic.
--
-- It holds exactly the down tables passed in (sync/hub-down.conf, read through
-- sync/hub-down.sh), plus public.dbz_heartbeat when it exists, and nothing else:
-- SET TABLE replaces whatever the publication held before, so a table that is
-- not on the list leaves it.
--
-- A down table with an `id` column carries the row filter
--     (id < <floor> OR id % 10 = 0)
-- Rows below the hub's floor predate striding and are the hub's; above it the
-- hub mints residue 0 and each clinic its own residue. A row a clinic minted
-- that reached the hub therefore stays at the hub, whoever edits it there. A
-- bare id % 10 = 0 would drop the hub's edits to every legacy row whose id does
-- not end in 0. A table without `id` (the link tables) carries no filter.
--
-- Refused, naming the table, before the publication is touched:
--   - a down table that does not exist;
--   - a down table with `id` and no floor, or a floor that is not a multiple of 10;
--   - a floor for a table that is not a down table, or that has no `id`;
--   - a filtered table whose replica identity does not cover `id`: with a row
--     filter, PostgreSQL refuses every UPDATE and DELETE on such a table, so the
--     hub's Odoo could no longer edit it;
--   - a server older than PostgreSQL 15 (no row filters).
--
-- Usage: psql -d odoo -v pub=dbz_odoo_owned -v tables=product_template,uom_uom,... \
--             -v floors=product_template:4520,uom_uom:40,... -f apply-down-publication.sql
-- Prints one line per published table: "<table> <row filter>", "-" for none.
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
      RAISE EXCEPTION 'a floor is recorded for %, which the hub does not send down', split_part(v_f, ':', 1);
    END IF;
  END LOOP;

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
        RAISE EXCEPTION 'no floor recorded for %: it has an id column, so it is sent down only with the filter (id < floor OR id %% 10 = 0); record the floors when the hub''s ids are strided', v_t;
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
        RAISE EXCEPTION 'a floor is recorded for %, which has no id column (it is sent down unfiltered)', v_t;
      END IF;
      v_parts := v_parts || format('public.%I', v_t);
    END IF;
  END LOOP;

  IF to_regclass('public.dbz_heartbeat') IS NOT NULL THEN
    v_parts := v_parts || 'public.dbz_heartbeat'::text;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = v_pub) THEN
    EXECUTE format('ALTER PUBLICATION %I SET TABLE %s', v_pub, array_to_string(v_parts, ', '));
  ELSE
    EXECUTE format('CREATE PUBLICATION %I FOR TABLE %s', v_pub, array_to_string(v_parts, ', '));
  END IF;
END $do$;

SELECT tablename || ' ' || coalesce(rowfilter, '-') FROM pg_publication_tables
 WHERE pubname = :'pub' AND schemaname = 'public' ORDER BY tablename;
