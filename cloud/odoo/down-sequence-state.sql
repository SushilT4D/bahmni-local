-- The state of each down table's id sequence on the hub, read-only.
--
-- One line per down table with an `id`, in the order passed:
--   <table>|<restart>|<next>|<increment>
-- <restart> is where the hub's striding would restart the sequence if it ran now
-- (residue 0): apply-odoo-sequence-striding.sql's ((max(max id, last_value) / 10)
-- + 1) * 10, and for res_country_state apply-master-sequence-striding.sql's
-- ((max(max id, 1000) / 10) + 1) * 10, which runs after it and wins.
-- <next> is the id the sequence would issue next.
--
-- Refused, naming the table: a down table that does not exist, or one with an
-- `id` and no owning sequence.
--
-- Usage: psql -d odoo -v tables=product_template,uom_uom,... -f down-sequence-state.sql
\set ON_ERROR_STOP on
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
CREATE TEMP TABLE down_seq (n int, t text, restart bigint, nxt bigint, inc bigint);

DO $do$
DECLARE
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_t      text;
  v_n      int := 0;
  v_rel    regclass;
  v_seq    text;
  v_max    bigint;
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
      RAISE EXCEPTION '% has an id column with no owning sequence', v_t;
    END IF;
    EXECUTE format('SELECT coalesce(max(id), 0) FROM public.%I', v_t) INTO v_max;
    EXECUTE format('SELECT last_value, is_called FROM %s', v_seq) INTO v_last, v_called;
    SELECT s.seqincrement INTO v_inc FROM pg_sequence s WHERE s.seqrelid = v_seq::regclass;
    INSERT INTO down_seq VALUES (v_n, v_t,
      CASE WHEN v_t = 'res_country_state' THEN ((greatest(v_max, 1000) / 10) + 1) * 10
           ELSE ((greatest(v_max, v_last) / 10) + 1) * 10 END,
      CASE WHEN v_called THEN v_last + v_inc ELSE v_last END,
      v_inc);
  END LOOP;
END $do$;

SELECT t || '|' || restart || '|' || nxt || '|' || inc FROM down_seq ORDER BY n;
