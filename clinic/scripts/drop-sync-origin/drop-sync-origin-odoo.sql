-- Odoo, any node: drop sync_origin from the 12 synced tables and the stale ORM metadata.
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['res_partner','product_template','product_product','product_category','product_uom','sale_order','sale_order_line','stock_move','stock_quant','stock_picking','account_invoice','account_invoice_line'] LOOP
    EXECUTE format('ALTER TABLE public.%I DROP COLUMN IF EXISTS sync_origin', t);
  END LOOP; END $$;
-- Odoo's own bookkeeping for the field (the module no longer declares it; -u all leaves these rows behind).
DELETE FROM ir_model_data WHERE model='ir.model.fields' AND res_id IN (SELECT id FROM ir_model_fields WHERE name='sync_origin');
DELETE FROM ir_model_fields WHERE name='sync_origin';
SELECT 'sync_origin columns left: '||count(*) FROM information_schema.columns WHERE column_name='sync_origin';
SELECT 'sync_updated_at columns: '||count(*) FROM information_schema.columns WHERE column_name='sync_updated_at';
