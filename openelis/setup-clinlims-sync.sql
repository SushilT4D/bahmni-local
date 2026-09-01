-- Module 28 — clinlims sync setup for one node. Parameterised by :residue
-- (4 = Rawach clinic, 0 = cloud) via psql -v. Idempotent.

-- psql does not substitute :vars inside dollar-quoted bodies, so stash the residue
-- in a GUC (substitution here is outside the $$ block) and read it back inside.
SELECT set_config('sync.residue', :'residue', false);

-- 1. Stride every sequence: increment 10, given residue, above its seed range.
DO $$
DECLARE r record; lv bigint; ns bigint; res int := current_setting('sync.residue')::int; n int := 0;
BEGIN
  FOR r IN SELECT schemaname s, sequencename q FROM pg_sequences WHERE schemaname='clinlims' LOOP
    EXECUTE format('SELECT last_value FROM %I.%I', r.s, r.q) INTO lv;
    ns := ((COALESCE(lv,0) / 10) + 1) * 10 + res;
    EXECUTE format('ALTER SEQUENCE %I.%I INCREMENT BY 10 RESTART WITH %s', r.s, r.q, ns);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'strided % sequences (increment 10, residue %)', n, res;
END $$;

-- 2. REPLICA IDENTITY FULL on the synced operational tables, so Debezium/pgoutput
--    publishes the whole row (needed for the sink's UUID/PK upsert and for the
--    publication row filter to see the id on UPDATE/DELETE).
-- sync_origin must exist before the publication filter references it.
ALTER TABLE clinlims.sample      ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.sample_item ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.analysis    ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.result      ADD COLUMN IF NOT EXISTS sync_origin varchar(16);

ALTER TABLE clinlims.sample        REPLICA IDENTITY FULL;
ALTER TABLE clinlims.sample_item   REPLICA IDENTITY FULL;
ALTER TABLE clinlims.analysis      REPLICA IDENTITY FULL;
ALTER TABLE clinlims.result        REPLICA IDENTITY FULL;

-- 3. The row-filtered publication — THIS is Module 28's per-row single-writer (L-001).
--    Each node publishes ONLY the rows it owns (id % 10 = its residue), so a row
--    written by the sink (carrying the OTHER residue) is never re-captured here.
--    No loop, enforced by the database rather than an SMT.
--    Feed tables (event_records, event_records_queue, markers, failed_events) are
--    NEVER in this list — Gate 1 of the double-fire defence (BL-050).
-- SUPERSEDED 2026-09-02 (sync-core F-015). The residue filter below is what this
-- publication used to carry:
--   FOR TABLE clinlims.sample WHERE (id % 10 = :residue), ...
-- It could only express "this row belongs to one node forever", so an edit made at
-- one node to another node's row was silently never published -- measured, and it is
-- exactly BHS's send-out workflow (sample taken at a clinic, resulted at the cloud).
-- Ownership now comes from sync_origin, stamped by a trigger, per ADR-003.
-- Striding above is RETAINED but demoted: it prevents id collisions, it is no longer
-- the ownership signal.
DROP PUBLICATION IF EXISTS dbz_clinlims_owned;
CREATE PUBLICATION dbz_clinlims_owned
  FOR TABLE clinlims.sample      WHERE (sync_origin IS NULL OR sync_origin = :'node'),
            clinlims.sample_item WHERE (sync_origin IS NULL OR sync_origin = :'node'),
            clinlims.analysis    WHERE (sync_origin IS NULL OR sync_origin = :'node'),
            clinlims.result      WHERE (sync_origin IS NULL OR sync_origin = :'node');

-- 4. Report
SELECT 'publication ' || pubname AS created FROM pg_publication WHERE pubname='dbz_clinlims_owned';
SELECT 'published: ' || string_agg(schemaname||'.'||tablename, ', ') FROM pg_publication_tables WHERE pubname='dbz_clinlims_owned';
