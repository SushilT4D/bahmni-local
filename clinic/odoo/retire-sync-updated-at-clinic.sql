-- sync-core, 2026-09-09: remove the last custom column from a CLINIC Odoo (F-051).
-- With per-row single-writer ownership (L-008) and the engine loop guards (F-044/F-047),
-- no two nodes write the same row, so a clinic sink can plain-upsert: no last-writer rule,
-- no trigger, no column. The hub keeps a guard on Odoo's own write_date (hub-lww-on-write-date.sql).
-- Precondition: every sink writing to this node carries field.exclude.list=sync_updated_at
-- until all records produced before the drop are consumed (schema.evolution=none).
-- NEVER on the hub. Idempotent. Run as superuser: psql -U odoo -d odoo -f retire-sync-updated-at-clinic.sql
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom',
                           'sale_order','sale_order_line','stock_move','stock_quant','stock_picking',
                           'account_invoice','account_invoice_line'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_lww', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_origin', t);
    EXECUTE format('ALTER TABLE public.%I DROP COLUMN IF EXISTS sync_updated_at', t);
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS public.sync_lww();
DROP FUNCTION IF EXISTS public.stamp_sync_origin();
DELETE FROM ir_model_fields WHERE name IN ('sync_updated_at','sync_origin');
SELECT 'sync_updated_at columns left: '||count(*) FROM information_schema.columns WHERE column_name='sync_updated_at';
SELECT 'custom triggers left: '||count(*) FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE NOT t.tgisinternal AND p.proname IN ('sync_lww','stamp_sync_origin');
