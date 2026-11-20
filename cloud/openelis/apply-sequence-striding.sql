-- Strides the hub's OpenELIS id sequences (residue 0): step 10, restarting above the largest id of their tables.
-- psql -d openelis -f apply-sequence-striding.sql

\set ON_ERROR_STOP on

-- The largest id of the tables OpenELIS numbers from a sequence (0 when empty).
CREATE OR REPLACE FUNCTION pg_temp.clinlims_rows_top(seq text) RETURNS bigint LANGUAGE sql STABLE AS $f$
  SELECT coalesce(max((xpath('/row/m/text()', query_to_xml(format('SELECT max(id) AS m FROM clinlims.%I', c.table_name), false, true, '')))[1]::text::numeric), 0)::bigint
    FROM information_schema.columns c
   WHERE c.table_schema = 'clinlims' AND c.column_name = 'id'
     AND c.data_type IN ('smallint', 'integer', 'bigint', 'numeric')
     AND (c.table_name::text || '_seq' = seq
          -- CASE keeps pg_get_serial_sequence off tables without an id column
          OR CASE WHEN c.column_name = 'id' THEN pg_get_serial_sequence(format('clinlims.%I', c.table_name), 'id') END = format('clinlims.%I', seq)
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

-- Refuse another node's striding; then restart unstrided sequences, and lift strided ones that fell behind their rows.
DO $do$
DECLARE
  r        record;
  v_last   bigint;
  v_called boolean;
  v_top    bigint;
  v_next   bigint;
  v_new    bigint;
  v_bad    text := '';
  v_done   int := 0;
  v_lifted int := 0;
  v_kept   int := 0;
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
    EXECUTE format('SELECT last_value, is_called FROM %I.%I', r.s, r.q) INTO v_last, v_called;
    v_top := pg_temp.clinlims_rows_top(r.q::text);
    v_new := ((greatest(coalesce(v_last, 0), v_top) / 10) + 1) * 10;
    IF r.inc = 10 THEN
      v_next := CASE WHEN v_called THEN v_last + 10 ELSE v_last END;
      IF v_next > v_top THEN
        v_kept := v_kept + 1;
        CONTINUE;
      END IF;
      EXECUTE format('ALTER SEQUENCE %I.%I RESTART WITH %s', r.s, r.q, v_new);
      RAISE NOTICE '% : next % was at or below its rows (largest id %) -> next=%', r.q, v_next, v_top, v_new;
      v_lifted := v_lifted + 1;
      CONTINUE;
    END IF;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q, v_new);
    RAISE NOTICE '% : % -> next=%', r.q, v_last, v_new;
    v_done := v_done + 1;
  END LOOP;
  RAISE NOTICE 'strided % sequence(s); lifted % above their rows; % already stepped by 10 and clear of their rows', v_done, v_lifted, v_kept;
END $do$;

-- Check every sequence: step 10, on residue 0, next id above its rows.
DO $check$
DECLARE
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
    IF r.inc <> 10 OR v_next % 10 <> 0 OR v_next <= v_top THEN
      v_bad := v_bad || CASE WHEN v_bad = '' THEN '' ELSE ', ' END
               || format('%s (step %s, next %s, largest id %s)', r.q, r.inc, v_next, v_top);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'sequences not stepping by 10 on residue 0 above their rows: %', v_bad;
  END IF;
END $check$;
SELECT 'sequences step 10: ' || count(*) FILTER (WHERE increment_by = 10) || ' of ' || count(*)
  FROM pg_sequences WHERE schemaname = 'clinlims';
