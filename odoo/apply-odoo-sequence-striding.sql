-- ADDED 2026-09-04 (sync-core, D7 Odoo full-replication build).
--
-- WHY THIS EXISTS. OpenMRS avoids cross-node primary-key collisions with MySQL's
-- auto_increment_increment=10 plus a per-node auto_increment_offset, so Rawach mints
-- 4, 14, 24 ... and the cloud mints 10, 20, 30 .... clinlims does the same with
-- PostgreSQL sequences at increment_by=10 (verified 2026-09-04: sample_*_seq all
-- carry incr=10). Odoo ships every sequence at increment_by=1 starting at 1, so two
-- nodes both mint sale_order id=1 for different orders. Under an idempotent upsert
-- keyed on the PK (L-010) that is not a loud failure -- it is silent data loss: the
-- second node's order OVERWRITES the first node's. This script closes that.
--
-- SCOPE. Only the 12 synced business tables plus the join/child tables that hang off
-- them. Framework sequences (ir_*) are deliberately untouched: they never travel, and
-- striding them would desynchronise module installation across nodes.
--
-- THE RESTART FORMULA. A sequence cannot simply RESTART WITH <residue>; existing rows
-- already occupy low ids. We restart at the first value ABOVE the current maximum that
-- carries this node's residue:
--     next := ((max(current_max_id, last_value) / 10) + 1) * 10 + residue
-- Integer division floors, so the +1 guarantees strictly-greater, and the * 10 + residue
-- guarantees the residue. For residue 0 the cloud mints 10, 20, 30 ...; id 0 is never
-- minted, which is correct -- Odoo treats 0 as a false id in several ORM paths.
--
-- IDEMPOTENT. Re-running moves sequences forward only, never backward, so it is safe
-- to re-apply after a restore or a resync.
--
-- NOT COVERED, ON PURPOSE: Odoo's ir_sequence table, which mints the human-facing
-- document numbers (SO0001, WH/OUT/0001). Those are business identifiers, not the sync
-- key, so L-010 does not protect them -- exactly the MRN/accession exposure recorded as
-- F-005. Two clinics WILL both mint SO0001. That needs a per-node prefix and is filed
-- separately; this script does not pretend to fix it.
--
-- Usage: psql -U postgres -d odoo -v residue=4 -f odoo/apply-odoo-sequence-striding.sql
\set ON_ERROR_STOP on
BEGIN;

-- psql does NOT interpolate :variables inside a dollar-quoted block (they are string
-- literals to the lexer), so the residue is handed in through a GUC set out here, where
-- interpolation does happen, and read back with current_setting() inside.
SELECT set_config('myvars.residue', :'residue', false);

DO $do$
DECLARE
  v_residue int := current_setting('myvars.residue')::int;
  v_tbl     text;
  v_seq     text;
  v_max     bigint;
  v_last    bigint;
  v_next    bigint;
  v_tables  text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','product_uom',
    'sale_order','sale_order_line',
    'stock_move','stock_quant','stock_picking',
    'account_invoice','account_invoice_line'
  ];
BEGIN
  IF v_residue < 0 OR v_residue > 9 THEN
    RAISE EXCEPTION 'residue must be 0..9, got %', v_residue;
  END IF;

  FOREACH v_tbl IN ARRAY v_tables LOOP
    -- pg_get_serial_sequence resolves the real owning sequence, which is not always
    -- <table>_id_seq (inherited and renamed tables differ). NULL means no serial PK.
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
