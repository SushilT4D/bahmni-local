-- The state of the id sequence of each OpenELIS down table the hub's
-- publication filters on its floor (sync/hub-down.sh --unrouted clinlims),
-- read-only.
--
-- One line per table, in the order passed:
--   <table>|<restart>|<next>|<increment>
-- <restart> is where striding the hub's OpenELIS ids (residue 0) restarts the
-- sequence if it runs now: ((last_value / 10) + 1) * 10, last_value read from
-- the sequence itself, as the hub's OpenELIS striding reads it. <next> is the id
-- the sequence would issue next.
--
-- The sequence is the id column's own, else clinlims.<table>_seq (OpenELIS
-- assigns ids from it). Refused, naming the table: a table that does not exist,
-- or one with neither.
--
-- Usage: psql -d openelis -v tables=system_user -f down-sequence-state.sql
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
  v_last   bigint;
  v_called boolean;
  v_inc    bigint;
BEGIN
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_t IN ARRAY v_tables LOOP
    v_n := v_n + 1;
    v_rel := to_regclass(format('clinlims.%I', v_t));
    IF v_rel IS NULL THEN
      RAISE EXCEPTION 'down table clinlims.% does not exist in this database', v_t;
    END IF;
    v_seq := pg_get_serial_sequence(format('clinlims.%I', v_t), 'id');
    IF v_seq IS NULL AND to_regclass(format('clinlims.%I', v_t || '_seq')) IS NOT NULL THEN
      v_seq := format('clinlims.%I', v_t || '_seq');
    END IF;
    IF v_seq IS NULL THEN
      RAISE EXCEPTION 'clinlims.% has no id sequence (neither its id column''s own nor clinlims.%_seq)', v_t, v_t;
    END IF;
    EXECUTE format('SELECT last_value, is_called FROM %s', v_seq) INTO v_last, v_called;
    SELECT s.seqincrement INTO v_inc FROM pg_sequence s WHERE s.seqrelid = v_seq::regclass;
    INSERT INTO down_seq VALUES (v_n, v_t, ((coalesce(v_last, 0) / 10) + 1) * 10,
      CASE WHEN v_called THEN v_last + v_inc ELSE v_last END, v_inc);
  END LOOP;
END $do$;

SELECT t || '|' || restart || '|' || nxt || '|' || inc FROM down_seq ORDER BY n;
