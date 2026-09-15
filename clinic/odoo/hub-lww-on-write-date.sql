-- sync-core, 2026-09-09: HUB only. Last-writer-wins on Odoo's own write_date instead of the
-- custom sync_updated_at column, then drop that column (F-051). The rule applies only to sink
-- sessions: a replicated UPDATE whose write_date is not newer than the row we hold is discarded
-- (an echo, a replay, a snapshot read, or a genuinely older edit). Application sessions are
-- never guarded — Odoo 10 stamps write_date with the transaction time, so two ORM writes in one
-- transaction share it, and guarding them would swallow the second. NULL write_date on either
-- side lets the write through. Idempotent. Run as superuser: psql -U odoo -d odoo -f hub-lww-on-write-date.sql
CREATE OR REPLACE FUNCTION public.sync_lww() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF session_user IN ('odoo_sink') AND TG_OP = 'UPDATE'
     AND NEW.write_date IS NOT NULL AND OLD.write_date IS NOT NULL
     AND NEW.write_date <= OLD.write_date THEN
    RETURN NULL;   -- not newer: write nothing, emit nothing
  END IF;
  RETURN NEW;
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom',
                           'sale_order','sale_order_line','stock_move','stock_quant','stock_picking',
                           'account_invoice','account_invoice_line'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_lww', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sync_lww()', t||'_lww', t);
    EXECUTE format('ALTER TABLE public.%I DROP COLUMN IF EXISTS sync_updated_at', t);
  END LOOP;
END $$;
DELETE FROM ir_model_fields WHERE name IN ('sync_updated_at','sync_origin');
SELECT 'sync_updated_at columns left: '||count(*) FROM information_schema.columns WHERE column_name='sync_updated_at';
SELECT 'lww triggers: '||count(*) FROM pg_trigger WHERE tgname LIKE '%\_lww' AND NOT tgisinternal;
