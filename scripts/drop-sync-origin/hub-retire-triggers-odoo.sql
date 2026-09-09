-- Hub only: keep last-writer-wins on sync_updated_at, drop the origin stamp and tie-break.
CREATE OR REPLACE FUNCTION public.sync_lww() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF session_user IN ('odoo_sink') THEN
    IF TG_OP = 'UPDATE' AND NEW.sync_updated_at <= OLD.sync_updated_at THEN RETURN NULL; END IF;
    RETURN NEW;
  END IF;
  NEW.sync_updated_at := clock_timestamp(); RETURN NEW;
END $$;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom','sale_order','sale_order_line','stock_move','stock_quant','stock_picking','account_invoice','account_invoice_line'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_origin', t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_lww', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.sync_lww()', t||'_lww', t);
  END LOOP; END $$;
DROP FUNCTION IF EXISTS public.stamp_sync_origin();
SELECT 'triggers: '||string_agg(p.proname||'='||n, ', ') FROM (SELECT p.proname, count(*) n FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid WHERE NOT t.tgisinternal GROUP BY 1) p;
