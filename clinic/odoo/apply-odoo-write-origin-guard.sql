-- SUPERSEDED 2026-09-09 on clinic nodes by retire-write-origin-guard.sql: row filters and the
-- origin stamp are retired; the last-writer rule lives on in sync_lww() without an origin
-- tie-break (sync-core F-048). Columns and sequences this file creates stay.
-- REWRITTEN 2026-09-04 for PostgreSQL 15 (sync-core, D7 Odoo full-replication build).
-- Supersedes the 2026-09-02 draft, which targeted Odoo's shipped PostgreSQL 9.6 and so
-- could not use publication row filters at all -- the whole reason Odoo is being moved
-- onto bahmni-postgres first. Odoo 10 on PG 15.18 was verified 2026-09-04: 375 tables
-- restore with zero errors, 49 modules load, web + XML-RPC both serve.
--
-- WHAT THIS IS. The ADR-003 write-origin guard, identical in shape to the OpenELIS one
-- (openelis/apply-write-origin-guard.sql), so Odoo rides the SAME CDC pipeline as
-- OpenMRS and OpenELIS rather than inventing a third mechanism.
--
--   1. sync_origin column on each synced table
--   2. a BEFORE trigger that stamps this node's name on LOCAL writes and preserves the
--      far node's stamp on SINK writes
--   3. a publication whose row filter yields only this node's own rows
--
-- session_user, NOT current_user: current_user returns the trigger's definer under
-- SECURITY DEFINER and is changed by SET ROLE, so it stamps every row identically while
-- looking correctly installed. This is the PostgreSQL analogue of the MySQL
-- USER()/CURRENT_USER() trap.
--
-- STRICT FILTER, NO NULL ALLOWANCE. The clinlims first draft read
--     WHERE (sync_origin IS NULL OR sync_origin = :'node')
-- with a comment asserting NULL could not loop. It could and it did: 341,175 messages
-- on Ghated, because a NULL row is published by EVERY node and accepted by EVERY node,
-- so it circulates forever. Pre-existing rows are therefore BACKFILLED from the id
-- residue before the filter goes on, and the filter is an equality test only.
--
-- REPLICA IDENTITY FULL is required for the row filter to apply to UPDATE and DELETE --
-- without it Postgres has only the key column and cannot evaluate sync_origin, so
-- updates escape the filter and loop. Set explicitly here rather than assumed.
--
-- PREREQUISITE: the odoo_sink login role must exist. Created by
-- odoo/create-odoo-sink-role.sh, which keeps the password out of the shell history and
-- out of any error message (a failed CREATE ROLE echoes its own DDL to the client).
--
-- Usage: psql -U postgres -d odoo -v node=rawach -v residue=4 \
--          -f odoo/apply-odoo-write-origin-guard.sql
\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('myvars.node',    :'node',    false);
SELECT set_config('myvars.residue', :'residue', false);

CREATE OR REPLACE FUNCTION public.stamp_sync_origin() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF session_user = 'odoo_sink' THEN
    RETURN NEW;                    -- replicated row: keep the originating node's stamp
  END IF;
  NEW.sync_origin := TG_ARGV[0];   -- local Odoo/odoo-connect write: stamp this node
  RETURN NEW;
END $fn$;

DO $do$
DECLARE
  v_node    text   := current_setting('myvars.node');
  v_residue int    := current_setting('myvars.residue')::int;
  v_tbl     text;
  v_tables  text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','product_uom',
    'sale_order','sale_order_line',
    'stock_move','stock_quant','stock_picking',
    'account_invoice','account_invoice_line'
  ];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'odoo_sink') THEN
    RAISE EXCEPTION 'odoo_sink role missing -- run odoo/create-odoo-sink-role.sh first';
  END IF;

  FOREACH v_tbl IN ARRAY v_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS sync_origin varchar(16)', v_tbl);

    -- DROP THE TRIGGER BEFORE THE BACKFILL, not after. On a virgin table the order does
    -- not matter because no trigger exists yet; on a RE-RUN it decides correctness. The
    -- backfill is itself an UPDATE, so with the previous run's trigger still attached it
    -- fires that trigger, which overwrites every computed value with this node's name.
    -- Measured 2026-09-04: a re-run stamped all 4,124 catalogue rows 'rawach' instead of
    -- 'cloud'. On a node already holding replicated rows the same re-run would relabel
    -- other nodes' data as locally-owned, and the node would start republishing rows it
    -- does not own -- two publishers for one row, which is the L-008 violation this
    -- whole mechanism exists to prevent. Re-running a guard must be safe.
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', v_tbl || '_origin', v_tbl);

    -- Backfill BEFORE the filter exists, because a NULL row is published by every node
    -- and accepted by every node -- the F-019 loop.
    --
    -- SEED ROWS ARE CLOUD-OWNED, NOT RESIDUE-OWNED. Residue identifies the minting node
    -- only ABOVE a table's base_id floor (architecture s3/s4). Everything at or below the
    -- floor arrived in the shared install image and exists byte-identically on every
    -- node -- no node minted it. An earlier draft of this block ran the residue map over
    -- those rows too, which is wrong in two ways at once: a residue-3 seed row would be
    -- claimed by Ghated AND by Rawach's copy of it, and a residue-5 row (no node owns 5)
    -- would be claimed by whichever node happened to apply the guard. Same row, two
    -- publishers, both republishing each other's copy forever.
    --
    -- Stamping seed rows 'cloud' is deterministic: every node computes the SAME owner for
    -- the SAME row, so exactly one publisher exists and the cloud is the master-data
    -- authority it already is for the product catalogue.
    --
    -- THE FLOOR IS max(id) AT APPLY TIME, and that is only sound because all three lab
    -- nodes are transaction-free today (verified 2026-09-04: sale_order, stock_move,
    -- account_invoice, procurement_order all 0 on cloud and Rawach). Applying this to a
    -- node that ALREADY holds local business rows would stamp that node's own history
    -- 'cloud', and since the cloud does not have those rows they would never publish from
    -- anywhere -- silent loss, the exact F-015 failure. Such a node needs its floor
    -- measured, not assumed.
    EXECUTE format($f$
      UPDATE public.%I SET sync_origin =
        CASE WHEN id <= (SELECT COALESCE(MAX(id),0) FROM public.%I) THEN 'cloud'
             ELSE CASE (id %% 10)
                    WHEN 0 THEN 'cloud' WHEN 3 THEN 'ghated' WHEN 4 THEN 'rawach'
                    ELSE %L
                  END
        END
      WHERE sync_origin IS NULL $f$, v_tbl, v_tbl, v_node);

    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', v_tbl);

    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION public.stamp_sync_origin(%L)',
      v_tbl || '_origin', v_tbl, v_node);
  END LOOP;
END $do$;

-- The publication is built in a SECOND DO block, after every column exists and every
-- pre-existing row is stamped. Splitting it is not cosmetic: ALTER PUBLICATION ... SET
-- TABLE with a row filter is validated against the live column at execution time, so a
-- single block would reference sync_origin on table 12 before the loop had added it.
DO $pub$
DECLARE
  v_node   text := current_setting('myvars.node');
  v_tbl    text;
  v_parts  text[] := '{}';
  v_tables text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','product_uom',
    'sale_order','sale_order_line',
    'stock_move','stock_quant','stock_picking',
    'account_invoice','account_invoice_line'
  ];
BEGIN
  -- THE HUB PUBLISHES EVERYTHING; A SPOKE PUBLISHES ONLY ITS OWN.
  --
  -- This asymmetry is the whole reason every clinic can hold every clinic's data. A spoke
  -- filters to its own rows so it never re-publishes what it received. The cloud must NOT
  -- filter, because its job is to relay: Rawach's order reaches the cloud, and only an
  -- unfiltered cloud publication carries it onward to Ghated.
  --
  -- MEASURED ON THE LIVE LAB 2026-09-04, and this is not hypothetical. The cloud's
  -- clinlims publication IS filtered to sync_origin='cloud', so the cloud holds 6 Rawach
  -- and 1 Ghated samples plus 18 Rawach analyses and will publish NONE of them downward.
  -- OpenELIS clinic-to-clinic sync therefore does not work at all today, silently, with
  -- every connector RUNNING. OpenMRS escapes this only by accident of mechanism: MySQL
  -- filters in the SMT and the cloud's MySQL source has no SMT filter, so the hub there
  -- does relay. Odoo is built correct rather than inheriting the clinlims defect.
  IF v_node = 'cloud' THEN
    FOREACH v_tbl IN ARRAY v_tables LOOP
      v_parts := v_parts || format('public.%I', v_tbl);
    END LOOP;
    RAISE NOTICE 'hub node: publication is UNFILTERED so clinic rows relay onward';
  ELSE
    FOREACH v_tbl IN ARRAY v_tables LOOP
      v_parts := v_parts || format('public.%I WHERE (sync_origin = %L)', v_tbl, v_node);
    END LOOP;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'dbz_odoo_owned') THEN
    EXECUTE 'ALTER PUBLICATION dbz_odoo_owned SET TABLE ' || array_to_string(v_parts, ', ');
  ELSE
    EXECUTE 'CREATE PUBLICATION dbz_odoo_owned FOR TABLE ' || array_to_string(v_parts, ', ');
  END IF;
  RAISE NOTICE 'publication dbz_odoo_owned covers % tables, %',
               array_length(v_tables,1),
               CASE WHEN v_node = 'cloud' THEN 'UNFILTERED (hub relays every node)'
                    ELSE 'filtered to sync_origin=' || v_node END;
END $pub$;

COMMIT;
