-- The state of the id sequence of each OpenELIS down table the hub's
-- publication filters on its floor (sync/hub-down.sh --unrouted clinlims),
-- read-only: it creates nothing, so it runs in a read-only session too.
--
-- One line per table, in the order passed:
--   <table>|<restart>|<next>|<increment>
-- <restart> is where striding the hub's OpenELIS ids (residue 0) restarts the
-- sequence if it runs now: ((last_value / 10) + 1) * 10, last_value read from
-- the sequence itself, as the hub's OpenELIS striding reads it. <next> is the id
-- the sequence would issue next.
--
-- With -v detail=1 each line also carries what the table holds:
--   <table>|<restart>|<next>|<increment>|<max id>|<max id not ending in 0>|id
-- (0 for an empty table), so a floor can be judged against the rows as well
-- as the sequence: rows on another residue than 0 above a floor would not
-- pass the publication's filter.
--
-- The sequence is the id column's own, else clinlims.<table>_seq, else the name
-- OpenELIS gives it where that differs (sampletype_test and sampletype_panel
-- take ids from sample_type_test_seq and sample_type_panel_seq). A table with
-- an id and no sequence at all (OpenELIS never issues ids for it) reads
-- <restart> and <next> as the first multiple of 10 above its largest id and
-- <increment> as 0. A table with no id column (a link table, keyed otherwise)
-- takes no floor: it prints no line, or with detail=1
--   <table>|0|0|0|0|0|noid
-- Refused, naming the table: a table that does not exist.
--
-- Usage: psql -d openelis -v tables=system_user -f down-sequence-state.sql
--        psql -d openelis -v tables=system_user,test -v detail=1 -f down-sequence-state.sql
\set ON_ERROR_STOP on
\if :{?detail}
\else
\set detail 0
\endif
SELECT set_config('myvars.tables', :'tables', false) \g /dev/null
SELECT set_config('myvars.detail', :'detail', false) \g /dev/null

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

WITH t AS (
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
              FROM (VALUES (1, i.name || '_seq'),
                           (2, CASE i.name WHEN 'sampletype_test' THEN 'sample_type_test_seq'
                                           WHEN 'sampletype_panel' THEN 'sample_type_panel_seq' END)) AS c(k, seq)
             WHERE c.seq IS NOT NULL AND to_regclass(format('clinlims.%I', c.seq)) IS NOT NULL
             ORDER BY c.k LIMIT 1)) END AS seq
    FROM i
), x AS (
  SELECT s.*,
         CASE WHEN s.hasid THEN query_to_xml(format('SELECT coalesce(max(id), 0) AS mx, coalesce(max(id) FILTER (WHERE id %% 10 <> 0), 0) AS mxnz FROM clinlims.%I', s.name), false, true, '') END AS rx,
         CASE WHEN s.seq IS NOT NULL THEN query_to_xml(format('SELECT last_value AS lv, is_called AS ic FROM %s', s.seq), false, true, '') END AS sx,
         (SELECT q.seqincrement FROM pg_sequence q WHERE q.seqrelid = s.seq::regclass) AS inc
    FROM s
), v AS (
  SELECT x.n, x.name, x.hasid, x.seq, x.inc,
         coalesce((xpath('/row/mx/text()', x.rx))[1]::text::bigint, 0) AS mx,
         coalesce((xpath('/row/mxnz/text()', x.rx))[1]::text::bigint, 0) AS mxnz,
         (xpath('/row/lv/text()', x.sx))[1]::text::bigint AS v_last,
         (xpath('/row/ic/text()', x.sx))[1]::text::boolean AS ic
    FROM x
), r AS (
  SELECT v.n, v.name, v.hasid, v.mx, v.mxnz,
         CASE WHEN NOT v.hasid THEN 0 WHEN v.seq IS NULL THEN ((v.mx / 10) + 1) * 10 ELSE ((coalesce(v_last, 0) / 10) + 1) * 10 END AS restart,
         CASE WHEN NOT v.hasid THEN 0 WHEN v.seq IS NULL THEN ((v.mx / 10) + 1) * 10 WHEN v.ic THEN coalesce(v_last, 0) + v.inc ELSE coalesce(v_last, 0) END AS nxt,
         CASE WHEN v.seq IS NULL THEN 0 ELSE v.inc END AS inc
    FROM v
)
SELECT CASE WHEN current_setting('myvars.detail') = '1'
            THEN name || '|' || restart || '|' || nxt || '|' || inc || '|' || mx || '|' || mxnz || '|' || CASE WHEN hasid THEN 'id' ELSE 'noid' END
            ELSE name || '|' || restart || '|' || nxt || '|' || inc END
  FROM r
 WHERE hasid OR current_setting('myvars.detail') = '1'
 ORDER BY n;
