-- Strides the hub's OpenELIS ids (residue 0): every clinlims sequence steps by
-- 10 and restarts at ((last_value / 10) + 1) * 10, the restart
-- hub/openelis/down-sequence-state.sql reports, so a floor recorded just
-- before this run is exactly where its sequence restarts.
--
-- A sequence already stepping by 10 from a multiple of 10 is left as it is, so
-- a second run moves nothing. A sequence stepping by 10 from any other value
-- is another node's striding, not the hub's: refused, naming it, before
-- anything changes (hub/scripts/stride-openelis.sh asks the same question
-- before it records any floor).
--
-- One NOTICE per sequence restarted, one summary NOTICE, then one line:
--   sequences step 10: <n> of <total>
-- Usage: psql -d openelis -f apply-sequence-striding.sql
\set ON_ERROR_STOP on
DO $do$
DECLARE
  r      record;
  v_last bigint;
  v_bad  text := '';
  v_done int := 0;
  v_kept int := 0;
BEGIN
  FOR r IN SELECT schemaname AS s, sequencename AS q, increment_by AS inc
             FROM pg_sequences WHERE schemaname = 'clinlims' ORDER BY sequencename LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO v_last;
    IF r.inc NOT IN (1, 10) OR (r.inc = 10 AND COALESCE(v_last, 0) % 10 <> 0) THEN
      v_bad := v_bad || CASE WHEN v_bad = '' THEN '' ELSE ', ' END
               || format('%s (steps by %s from %s)', r.q, r.inc, v_last);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'not the hub''s striding (residue 0): %; nothing was changed', v_bad;
  END IF;
  FOR r IN SELECT schemaname AS s, sequencename AS q, increment_by AS inc
             FROM pg_sequences WHERE schemaname = 'clinlims' ORDER BY sequencename LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO v_last;
    IF r.inc = 10 THEN
      v_kept := v_kept + 1;
      CONTINUE;
    END IF;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s',
                   r.s, r.q, ((COALESCE(v_last, 0) / 10) + 1) * 10);
    RAISE NOTICE '% : % -> next=%', r.q, v_last, ((COALESCE(v_last, 0) / 10) + 1) * 10;
    v_done := v_done + 1;
  END LOOP;
  RAISE NOTICE 'strided % sequence(s); % already stepped by 10', v_done, v_kept;
END $do$;
SELECT 'sequences step 10: ' || count(*) FILTER (WHERE increment_by = 10) || ' of ' || count(*)
  FROM pg_sequences WHERE schemaname = 'clinlims';
