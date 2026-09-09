-- sync-core, 2026-09-09: HUB. Drop the last sync-specific object anywhere in the fleet: the
-- sync_lww() last-writer guard on the 12 Odoo tables (F-051). Under per-row single-writer
-- ownership no two nodes write the same row, so the hub, like the clinics, plain-upserts and
-- the last arrival wins. Idempotent. Run as superuser: psql -U postgres -d odoo -f hub-retire-lww.sql
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom',
                           'sale_order','sale_order_line','stock_move','stock_quant','stock_picking',
                           'account_invoice','account_invoice_line'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_lww', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_origin', t);
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS public.sync_lww();
DROP FUNCTION IF EXISTS public.stamp_sync_origin();
SELECT 'non-internal triggers on the 12 tables: '||count(*) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text IN ('res_partner','product_template','product_product','product_category','product_uom','sale_order','sale_order_line','stock_move','stock_quant','stock_picking','account_invoice','account_invoice_line');
SELECT 'sync functions left: '||count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN ('sync_lww','stamp_sync_origin');
