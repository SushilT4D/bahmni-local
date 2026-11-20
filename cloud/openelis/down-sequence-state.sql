-- Read-only: for each OpenELIS table, where striding would restart its id sequence and the id it issues next.
-- psql -d openelis -v tables=a,b [-v detail=1] -f down-sequence-state.sql  -> <table>|<restart>|<next>|<increment>[|<max id>|<max id not ending in 0>|id]

-- Pass the psql variables; detail defaults to 0.
\set ON_ERROR_STOP on
\if :{?detail}
\else
\set detail 0
\endif
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
SELECT set_config('myvars.detail', :'detail', false) \g /dev/null

-- Refuse a table that does not exist.
DO $do$
DECLARE
  v_tables text[] := string_to_array(nullif(current_setting('myvars.tables'), ''), ',');
  v_t      text;
BEGIN
  IF v_tables IS NULL THEN
    RAISE EXCEPTION 'no down tables passed in (-v tables=...)';
  END IF;
  FOREACH v_t IN ARRAY v_tables LOOP
    IF to_regclass(format('clinlims.%I', v_t)) IS NULL THEN
      RAISE EXCEPTION 'down table clinlims.% does not exist in this database', v_t;
    END IF;
  END LOOP;
END $do$;

-- Sequences OpenELIS names other than clinlims.<table>_seq (kept in step with the striding SQL).
WITH names(t, seq) AS (VALUES
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
-- Find each table's sequence, its largest ids and the sequence's last value, then the restart and next ids.
), t AS (
  SELECT u.n, u.name, to_regclass(format('clinlims.%I', u.name)) AS rel
    FROM unnest(string_to_array(current_setting('myvars.tables'), ',')) WITH ORDINALITY AS u(name, n)
), i AS (
  SELECT t.*, EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = t.rel AND a.attname = 'id' AND NOT a.attisdropped) AS hasid
    FROM t
), s AS (
  SELECT i.*,
         CASE WHEN i.hasid THEN coalesce(
           pg_get_serial_sequence(format('clinlims.%I', i.name), 'id'),
           (SELECT format('clinlims.%I', c.seq)
              FROM (SELECT 1 AS k, nm.seq FROM names nm WHERE nm.t = i.name
                    UNION ALL SELECT 2, i.name || '_seq') AS c
             WHERE to_regclass(format('clinlims.%I', c.seq)) IS NOT NULL
             ORDER BY c.k LIMIT 1)) END AS seq
    FROM i
), x AS (
  SELECT s.*,
         CASE WHEN s.hasid THEN query_to_xml(format('SELECT coalesce(max(id), 0) AS mx, coalesce(max(id) FILTER (WHERE id %% 10 <> 0), 0) AS mxnz FROM clinlims.%I', s.name), false, true, '') END AS rx,
         CASE WHEN s.seq IS NOT NULL THEN query_to_xml(format('SELECT last_value AS lv, is_called AS ic FROM %s', s.seq), false, true, '') END AS sx,
         (SELECT q.seqincrement FROM pg_sequence q WHERE q.seqrelid = s.seq::regclass) AS inc,
         -- the largest id of every table OpenELIS numbers from this sequence
         CASE WHEN s.seq IS NOT NULL THEN (
           SELECT coalesce(max((xpath('/row/m/text()', query_to_xml(format('SELECT max(id) AS m FROM clinlims.%I', c.table_name), false, true, '')))[1]::text::numeric), 0)::bigint
             FROM information_schema.columns c
            WHERE c.table_schema = 'clinlims' AND c.column_name = 'id'
              AND c.data_type IN ('smallint', 'integer', 'bigint', 'numeric')
              AND (c.table_name::text = s.name
                   OR c.table_name::text || '_seq' = (SELECT q.relname FROM pg_class q WHERE q.oid = s.seq::regclass)
                   OR (c.table_name::text, (SELECT q.relname::text FROM pg_class q WHERE q.oid = s.seq::regclass)) IN (SELECT nm.t, nm.seq FROM names nm))) END AS top
    FROM s
), v AS (
  SELECT x.n, x.name, x.hasid, x.seq, x.inc,
         coalesce((xpath('/row/mx/text()', x.rx))[1]::text::bigint, 0) AS mx,
         coalesce((xpath('/row/mxnz/text()', x.rx))[1]::text::bigint, 0) AS mxnz,
         (xpath('/row/lv/text()', x.sx))[1]::text::bigint AS v_last,
         (xpath('/row/ic/text()', x.sx))[1]::text::boolean AS ic,
         coalesce(x.top, 0) AS v_top
    FROM x
), r AS (
  SELECT v.n, v.name, v.hasid, v.mx, v.mxnz,
         CASE WHEN NOT v.hasid THEN 0 WHEN v.seq IS NULL THEN ((v.mx / 10) + 1) * 10 ELSE ((greatest(coalesce(v_last, 0), v_top) / 10) + 1) * 10 END AS restart,
         CASE WHEN NOT v.hasid THEN 0 WHEN v.seq IS NULL THEN ((v.mx / 10) + 1) * 10 WHEN v.ic THEN coalesce(v_last, 0) + v.inc ELSE coalesce(v_last, 0) END AS nxt,
         CASE WHEN v.seq IS NULL THEN 0 ELSE v.inc END AS inc
    FROM v
)
-- One line per table; tables without an id only with detail=1.
SELECT CASE WHEN current_setting('myvars.detail') = '1'
            THEN name || '|' || restart || '|' || nxt || '|' || inc || '|' || mx || '|' || mxnz || '|' || CASE WHEN hasid THEN 'id' ELSE 'noid' END
            ELSE name || '|' || restart || '|' || nxt || '|' || inc END
  FROM r
 WHERE hasid OR current_setting('myvars.detail') = '1'
 ORDER BY n;
