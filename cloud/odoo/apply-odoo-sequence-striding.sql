-- Strides the hub's Odoo id sequences: increment 10, restarting above the largest id on this node's residue.
-- psql -U postgres -d odoo -v residue=0 -f apply-odoo-sequence-striding.sql

\set ON_ERROR_STOP on
BEGIN;

-- Pass the residue into the DO block.
SELECT set_config('myvars.residue', :'residue', false);

DO $do$
DECLARE
  v_residue int := current_setting('myvars.residue')::int;
  v_tbl     text;
  v_seq     text;
  v_max     bigint;
  v_last    bigint;
  v_next    bigint;
  -- The synced Odoo 16 business tables.
  v_tables  text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','uom_uom',
    'sale_order','sale_order_line',
    'stock_move','stock_quant','stock_picking',
    'account_move','account_move_line'
  ];
BEGIN
  -- Refuse a residue outside 0..9.
  IF v_residue < 0 OR v_residue > 9 THEN
    RAISE EXCEPTION 'residue must be 0..9, got %', v_residue;
  END IF;

  -- Restart each owning sequence at the first id above max(id, last value) that ends in the residue.
  FOREACH v_tbl IN ARRAY v_tables LOOP
    v_seq := pg_get_serial_sequence('public.' || v_tbl, 'id');
    IF v_seq IS NULL THEN
      RAISE NOTICE '  % : no serial sequence on id -- SKIPPED', v_tbl;
      CONTINUE;
    END IF;

    EXECUTE format('SELECT COALESCE(MAX(id),0) FROM public.%I', v_tbl) INTO v_max;
    EXECUTE format('SELECT COALESCE(last_value,0) FROM %s', v_seq) INTO v_last;

    v_next := ((GREATEST(v_max, v_last) / 10) + 1) * 10 + v_residue;

    EXECUTE format('ALTER SEQUENCE %s INCREMENT BY 10 RESTART WITH %s', v_seq, v_next);
    RAISE NOTICE '  % : max=% -> next=% (incr 10, residue %)', v_tbl, v_max, v_next, v_residue;
  END LOOP;
END $do$;

COMMIT;
