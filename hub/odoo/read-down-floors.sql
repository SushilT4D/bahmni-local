-- The floor of each down table with an `id`, read from its sequence right after
-- the hub's Odoo ids are strided (apply-odoo-sequence-striding.sql, then
-- apply-master-sequence-striding.sql).
--
-- A strided sequence is restarted at its floor and has not been called yet, so
-- its last_value IS the floor. Once the hub has minted an id from it the floor
-- can no longer be read from the sequence, and this refuses rather than record
-- a later value: a floor recorded too high lets a clinic's rows that reached
-- the hub below it through the hub's down filter.
--
-- Refused, naming the table: a table with `id` whose sequence is not strided
-- (increment 10), has been called since its restart, or does not end in 0.
--
-- Usage: psql -d odoo -v tables=product_template,uom_uom,... -f read-down-floors.sql
-- Prints "<table> <floor>" for each down table with an `id`, in the order passed.
\set ON_ERROR_STOP on
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
CREATE TEMP TABLE down_floor (n int, t text, floor bigint);

DO $do$
DECLARE
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_t      text;
  v_n      int := 0;
  v_rel    regclass;
  v_seq    text;
  v_last   bigint;
  v_called boolean;
  v_inc    bigint;
BEGIN
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_t IN ARRAY v_tables LOOP
    v_n := v_n + 1;
    v_rel := to_regclass(format('public.%I', v_t));
    IF v_rel IS NULL THEN
      RAISE EXCEPTION 'down table public.% does not exist in this database', v_t;
    END IF;
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = v_rel AND attname = 'id' AND NOT attisdropped);
    v_seq := pg_get_serial_sequence(format('public.%I', v_t), 'id');
    IF v_seq IS NULL THEN
      RAISE EXCEPTION '% has an id column with no owning sequence: no floor can be read', v_t;
    END IF;
    EXECUTE format('SELECT last_value, is_called FROM %s', v_seq) INTO v_last, v_called;
    SELECT s.seqincrement INTO v_inc FROM pg_sequence s WHERE s.seqrelid = v_seq::regclass;
    IF v_inc <> 10 THEN
      RAISE EXCEPTION '% (%) steps by %, not 10: stride the hub''s ids first', v_t, v_seq, v_inc;
    END IF;
    IF v_called THEN
      RAISE EXCEPTION '% (%) has minted ids since it was strided (last_value %), so its floor can no longer be read from the sequence', v_t, v_seq, v_last;
    END IF;
    IF v_last % 10 <> 0 THEN
      RAISE EXCEPTION '% (%) restarts at %, which is not residue 0', v_t, v_seq, v_last;
    END IF;
    INSERT INTO down_floor VALUES (v_n, v_t, v_last);
  END LOOP;
END $do$;

SELECT t || ' ' || floor FROM down_floor ORDER BY n;
