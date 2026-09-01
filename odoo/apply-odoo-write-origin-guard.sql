-- ADDED 2026-09-02 (sync-core). Puts the ADR-003 write-origin guard on Odoo's
-- database, so Odoo can use the SAME CDC pipeline as OpenMRS and OpenELIS.
--
-- Usage: psql -U odoo -d odoo -v node=<rawach|ghated|cloud> -v residue=<4|3|0> \
--          -f odoo/apply-odoo-write-origin-guard.sql
--
-- TABLE SET. Deliberately a subset, exactly as OpenMRS syncs 12 of 247 tables and
-- OpenELIS 4. Odoo 10 has 375 tables and most are framework state (ir_*, sessions,
-- assets) that MUST NOT travel. These twelve are the Bahmni-facing business objects:
--   customers      res_partner
--   catalogue      product_template, product_product, product_category, product_uom
--   dispensing     sale_order, sale_order_line
--   inventory      stock_move, stock_quant, stock_picking
--   billing        account_invoice, account_invoice_line
--
-- NOTE ON STRICTNESS: the filter is `sync_origin = node` with NO "IS NULL" branch.
-- The NULL-allowing form caused a 341k-message loop on the clinlims path the same
-- day (F-019) because every node both published and accepted unstamped rows.
-- Pre-existing rows are backfilled from the residue before the filter goes on.
\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('sync.node', :'node', false);
SELECT set_config('sync.residue', :'residue', false);

-- session_user, NOT current_user: immune to SET ROLE and SECURITY DEFINER. The
-- PostgreSQL analogue of the MySQL USER()/CURRENT_USER() trap, where the wrong one
-- returns the trigger's definer and stamps every row identically while looking
-- installed. The sink role is exempt so a replicated row keeps the far node's stamp.
CREATE OR REPLACE FUNCTION public.stamp_sync_origin() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF session_user = 'odoo_sink' THEN
    RETURN NEW;
  END IF;
  NEW.sync_origin := TG_ARGV[0];
  RETURN NEW;
END $fn$;

DO $guard$
DECLARE
  t text;
  tables text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','product_uom',
    'sale_order','sale_order_line',
    'stock_move','stock_quant','stock_picking',
    'account_invoice','account_invoice_line'];
  node text := current_setting('sync.node');
  res  int  := current_setting('sync.residue')::int;
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF to_regclass('public.'||t) IS NULL THEN
      RAISE NOTICE 'skipping % (not present in this Odoo build)', t; CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS sync_origin varchar(16)', t);

    -- the filter column must be in the replica identity for UPDATE/DELETE filtering
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);

    -- backfill from residue BEFORE the strict filter goes on, so legacy rows
    -- have an owner and are not orphaned by it
    EXECUTE format($f$
      UPDATE public.%I SET sync_origin = CASE (id %% 10)
        WHEN 0 THEN 'cloud' WHEN 3 THEN 'ghated' WHEN 4 THEN 'rawach'
        ELSE %L END
      WHERE sync_origin IS NULL $f$, t, node);

    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_origin', t);
    EXECUTE format($f$
      CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.stamp_sync_origin(%L) $f$,
      t||'_origin', t, node);
  END LOOP;
END $guard$;

-- Publish only our own writes. STRICT: no NULL branch (F-019).
DROP PUBLICATION IF EXISTS dbz_odoo_owned;
CREATE PUBLICATION dbz_odoo_owned
  FOR TABLE public.res_partner          WHERE (sync_origin = :'node'),
            public.product_template     WHERE (sync_origin = :'node'),
            public.product_product      WHERE (sync_origin = :'node'),
            public.product_category     WHERE (sync_origin = :'node'),
            public.product_uom          WHERE (sync_origin = :'node'),
            public.sale_order           WHERE (sync_origin = :'node'),
            public.sale_order_line      WHERE (sync_origin = :'node'),
            public.stock_move           WHERE (sync_origin = :'node'),
            public.stock_quant          WHERE (sync_origin = :'node'),
            public.stock_picking        WHERE (sync_origin = :'node'),
            public.account_invoice      WHERE (sync_origin = :'node'),
            public.account_invoice_line WHERE (sync_origin = :'node');

COMMIT;

SELECT 'guarded tables: ' || COUNT(*)::text FROM pg_publication_tables WHERE pubname = 'dbz_odoo_owned';
SELECT 'unstamped rows remaining: ' || COALESCE(SUM(n),0)::text FROM (
  SELECT COUNT(*) n FROM public.res_partner WHERE sync_origin IS NULL
  UNION ALL SELECT COUNT(*) FROM public.sale_order WHERE sync_origin IS NULL
  UNION ALL SELECT COUNT(*) FROM public.stock_move WHERE sync_origin IS NULL) x;
