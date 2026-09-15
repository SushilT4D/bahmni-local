-- sync-core, 2026-09-09: retire the Odoo write-origin guard on a CLINIC node (F-048).
-- Supersedes apply-odoo-write-origin-guard.sql (row filters + stamp triggers) and the
-- sync_origin half of apply-odoo-conflict-rule.sql. The loop guard is now the engine's:
-- sink sessions carry a replication origin and the source decodes with origin=none
-- (F-044). What stays, and why:
--   * sync_updated_at and the last-writer-wins rule, now in sync_lww(): a replicated
--     write is applied only if strictly newer than the row we hold; an equal timestamp
--     (our own echo, an identical replay, or an exact microsecond tie) is discarded, so
--     the node keeps what it has. No origin is consulted anywhere.
--   * the sync_origin COLUMN, unstamped from now on: every sink caches the table
--     descriptor (schema.evolution=none) and the cloud keeps its copy, so dropping it
--     is a fleet-wide schema change (one L-005 window), not a local cleanup.
-- NEVER on the hub: the cloud must publish everything it holds to relay.
-- Idempotent. Run as superuser: psql -U odoo -d odoo -f retire-write-origin-guard.sql
CREATE OR REPLACE FUNCTION public.sync_lww() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF session_user IN ('odoo_sink') THEN
    -- Replicated write: keep the originating node's timestamp; apply only if newer.
    IF TG_OP = 'UPDATE' AND NEW.sync_updated_at <= OLD.sync_updated_at THEN
      RETURN NULL;   -- stale, echo, replay or exact tie: write nothing, emit nothing
    END IF;
    RETURN NEW;
  END IF;
  NEW.sync_updated_at := clock_timestamp();   -- local application write
  RETURN NEW;
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom',
                           'sale_order','sale_order_line','stock_move','stock_quant','stock_picking',
                           'account_invoice','account_invoice_line'] LOOP
    IF EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='dbz_odoo_owned' AND tablename=t AND rowfilter IS NOT NULL) THEN
      EXECUTE format('ALTER PUBLICATION dbz_odoo_owned DROP TABLE public.%I', t);
      EXECUTE format('ALTER PUBLICATION dbz_odoo_owned ADD TABLE public.%I', t);
    END IF;
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_origin', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_lww', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sync_lww()', t||'_lww', t);
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS public.stamp_sync_origin();
SELECT 'filtered tables left: '||count(rowfilter)||' of '||count(*) FROM pg_publication_tables WHERE pubname='dbz_odoo_owned';
SELECT 'triggers: '||string_agg(p.proname||'='||n, ', ') FROM (SELECT p.proname, count(*) n FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE NOT t.tgisinternal GROUP BY 1) p;
