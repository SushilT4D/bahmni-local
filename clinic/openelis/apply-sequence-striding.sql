-- Strides this clinic's OpenELIS ids: every clinlims sequence steps by 10 on
-- the clinic's residue, so each id it issues ends in the clinic's number and
-- never meets an id the hub (residue 0) or another clinic issues.
--
-- A sequence restarts at ((greatest(last_value, largest id) / 10) + 1) * 10
-- plus the residue. The largest id is taken over every table OpenELIS numbers
-- from that sequence, not the sequence alone: some lab test catalogue
-- sequences stand below the rows they hold (the rows were loaded with fixed
-- ids), and a sequence restarted from its last value would issue ids this
-- clinic's copy already has, so each such save would fail on the duplicate key.
--
-- A sequence already on this clinic's residue (stepping by 10 from a value
-- ending in the residue) is left as it is, unless the next id it would issue is
-- at or below the largest id of its tables: then it restarts above them, on the
-- same rule. So a second run moves nothing that is already clear of its rows,
-- and on an upgraded clinic it lifts only a sequence that is behind.
--
-- Last, every sequence is checked: step 10, on the residue, and its next id
-- above the largest id of its tables. Any that is not is named and the run
-- fails.
--
-- One summary NOTICE, then one line:
--   clinlims sequences step 10 on residue <r> above their rows: <n> of <total>
-- Usage: psql -d openelis -v residue=3 -f apply-sequence-striding.sql
\set ON_ERROR_STOP on
SELECT set_config('myvars.residue', :'residue', false) \g /dev/null

-- The largest id of the tables OpenELIS numbers from sequence SEQ (0 when they
-- are empty). OpenELIS takes a table's ids from clinlims.<table>_seq, except for
-- the tables listed here, whose sequences its mappings name otherwise (two
-- tables can share one). The same list is in hub/openelis/apply-sequence-striding.sql
-- and hub/openelis/down-sequence-state.sql; a test fails when they differ.
CREATE OR REPLACE FUNCTION pg_temp.clinlims_rows_top(seq text) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT coalesce(max((xpath('/row/m/text()', query_to_xml(format('SELECT max(id) AS m FROM clinlims.%I', c.table_name), false, true, '')))[1]::text::numeric), 0)::bigint
    FROM information_schema.columns c
   WHERE c.table_schema = 'clinlims' AND c.column_name = 'id'
     AND c.data_type IN ('smallint', 'integer', 'bigint', 'numeric')
     AND (c.table_name::text || '_seq' = seq
          OR pg_get_serial_sequence(format('clinlims.%I', c.table_name), 'id') = format('clinlims.%I', seq)
          OR (c.table_name::text, seq) IN (VALUES
-- openelis-sequence-names:begin
            ('external_reference', 'external_reference_id_seq'),
            ('hl7_transmission_sequence', 'messagecontrolidseq'),
            ('lab_order_type', 'lab_order_item_seq'),
            ('patient_relations', 'patient_relation_seq'),
            ('project_organization', 'project_org_seq'),
            ('qa_observation_type', 'qa_observation_seq'),
            ('report_external_export', 'report_queue_seq'),
            ('sample_organization', 'sample_org_seq'),
            ('sample_projects', 'sample_proj_seq'),
            ('sample_source', 'sample_source_id_seq'),
            ('sampletype_panel', 'sample_type_panel_seq'),
            ('sampletype_test', 'sample_type_test_seq'),
            ('source_of_sample', 'src_of_sample_seq'),
            ('system_role_module', 'system_user_module_seq'),
            ('test_code_type', 'hl7_encoding_type_seq')
-- openelis-sequence-names:end
          ))
$f$;

DO $do$
DECLARE
  v_res    text := current_setting('myvars.residue');
  res      int;
  r        record;
  v_last   bigint;
  v_called boolean;
  v_top    bigint;
  v_next   bigint;
  v_done   int := 0;
  v_lifted int := 0;
  v_kept   int := 0;
BEGIN
  IF v_res !~ '^[1-9]$' THEN
    RAISE EXCEPTION 'residue must be this clinic''s number, one digit from 1 to 9, not "%"; nothing was changed', v_res;
  END IF;
  res := v_res::int;
  FOR r IN SELECT schemaname AS s, sequencename AS q, increment_by AS inc
             FROM pg_sequences WHERE schemaname = 'clinlims' ORDER BY sequencename LOOP
    EXECUTE format('SELECT last_value, is_called FROM %I.%I', r.s, r.q) INTO v_last, v_called;
    v_top := pg_temp.clinlims_rows_top(r.q::text);
    IF r.inc = 10 AND v_last % 10 = res THEN
      v_next := CASE WHEN v_called THEN v_last + 10 ELSE v_last END;
      IF v_next > v_top THEN
        v_kept := v_kept + 1;
        CONTINUE;
      END IF;
      v_lifted := v_lifted + 1;
    ELSE
      v_done := v_done + 1;
    END IF;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q,
                   ((greatest(coalesce(v_last, 0), v_top) / 10) + 1) * 10 + res);
  END LOOP;
  RAISE NOTICE 'strided % clinlims sequences; lifted % above their rows; % already on residue % and clear of their rows', v_done, v_lifted, v_kept, res;
END $do$;

DO $check$
DECLARE
  res      int := current_setting('myvars.residue')::int;
  r        record;
  v_last   bigint;
  v_called boolean;
  v_top    bigint;
  v_next   bigint;
  v_bad    text := '';
BEGIN
  FOR r IN SELECT schemaname AS s, sequencename AS q, increment_by AS inc
             FROM pg_sequences WHERE schemaname = 'clinlims' ORDER BY sequencename LOOP
    EXECUTE format('SELECT last_value, is_called FROM %I.%I', r.s, r.q) INTO v_last, v_called;
    v_top := pg_temp.clinlims_rows_top(r.q::text);
    v_next := CASE WHEN v_called THEN v_last + r.inc ELSE v_last END;
    IF r.inc <> 10 OR v_next % 10 <> res OR v_next <= v_top THEN
      v_bad := v_bad || CASE WHEN v_bad = '' THEN '' ELSE ', ' END
               || format('%s (step %s, next %s, largest id %s)', r.q, r.inc, v_next, v_top);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'clinlims sequences not stepping by 10 on residue % above their rows: %', res, v_bad;
  END IF;
END $check$;
SELECT 'clinlims sequences step 10 on residue ' || current_setting('myvars.residue') || ' above their rows: '
       || count(*) FILTER (WHERE increment_by = 10) || ' of ' || count(*)
  FROM pg_sequences WHERE schemaname = 'clinlims';
