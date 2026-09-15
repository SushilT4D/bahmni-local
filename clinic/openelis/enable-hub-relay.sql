-- ADDED 2026-09-04 (sync-core F-025). Makes the CLOUD relay clinic-authored lab rows
-- onward, which it does not do today.
--
-- THE DEFECT. The hub's dbz_clinlims_owned publication is row-filtered to
-- sync_origin = 'cloud' on all four tables, so the cloud publishes only rows it
-- authored itself. Everything a clinic sends up arrives, is stored, and is never
-- forwarded. Measured 2026-09-04: the cloud holds 6 Rawach samples, 1 Ghated sample and
-- 18 Rawach analyses that it will never publish. A lab result raised at Rawach cannot
-- reach Ghated. Every connector reports RUNNING throughout.
--
-- THE RULE. A spoke publishes only its own rows so it never re-publishes what it
-- received; the hub publishes everything because relaying is its whole job. OpenMRS gets
-- this right only by accident of mechanism (MySQL filters in the SMT, and the cloud's
-- MySQL source has no SMT filter). Odoo was built correct on 2026-09-04 and is the
-- working reference. This brings OpenELIS into line.
--
-- RUN ON THE CLOUD ONLY. Running it on a clinic would make that clinic republish every
-- row it ever received -- two publishers for one row, the L-008 violation the whole
-- mechanism exists to prevent.
--
-- WHY THE BACKFILL COMES FIRST. An unfiltered publication publishes everything the node
-- holds, NULL stamps included. A NULL row is accepted by every clinic (the sink's origin
-- filter compares a value, and NULL never equals a node name), so it would be delivered
-- everywhere as an unowned row. It cannot loop -- the clinic publications are strict
-- equality and NULL matches none of them -- but an unowned row is still wrong. The three
-- NULL rows on the cloud are all residue 0, i.e. cloud-minted (a 2017 seed sample, a
-- CLOUD-SYNC-TEST-1 row, and one result), so 'cloud' is their correct owner.
--
-- MUST RUN AS THE PUBLICATION OWNER, which is `postgres`, not `clinlims`. Running it as
-- clinlims gets through the guard and the backfill and then fails on
-- "must be owner of publication dbz_clinlims_owned" -- harmless, because the whole
-- script is one transaction and rolls back, but it wastes a cycle.
--
-- Usage: psql -U postgres -d openelis -f openelis/enable-hub-relay.sql
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_node text;
  v_null int;
BEGIN
  -- Refuse to run anywhere but the hub. The trigger argument carries the node name, so
  -- it is the authoritative answer to "which node am I" -- not a parameter the operator
  -- can get wrong.
  SELECT (regexp_match(pg_get_triggerdef(t.oid), '''([a-z]+)'''))[1] INTO v_node
  FROM pg_trigger t WHERE t.tgname = 'sample_origin' AND NOT t.tgisinternal LIMIT 1;

  IF v_node IS NULL THEN
    RAISE EXCEPTION 'no sample_origin trigger found -- is the write-origin guard installed?';
  END IF;
  IF v_node <> 'cloud' THEN
    RAISE EXCEPTION 'this node is %, not the hub. Running here would make it republish every row it received.', v_node;
  END IF;
  RAISE NOTICE 'confirmed hub node (trigger stamps %)', v_node;

  -- Backfill unowned rows to the hub, with the triggers off so the UPDATE is not
  -- re-stamped by the very trigger it is compensating for (the ordering bug found in the
  -- Odoo guard on 2026-09-04).
  ALTER TABLE clinlims.sample      DISABLE TRIGGER sample_origin;
  ALTER TABLE clinlims.sample_item DISABLE TRIGGER sample_item_origin;
  ALTER TABLE clinlims.analysis    DISABLE TRIGGER analysis_origin;
  ALTER TABLE clinlims.result      DISABLE TRIGGER result_origin;

  UPDATE clinlims.sample      SET sync_origin = 'cloud' WHERE sync_origin IS NULL;
  UPDATE clinlims.sample_item SET sync_origin = 'cloud' WHERE sync_origin IS NULL;
  UPDATE clinlims.analysis    SET sync_origin = 'cloud' WHERE sync_origin IS NULL;
  UPDATE clinlims.result      SET sync_origin = 'cloud' WHERE sync_origin IS NULL;

  ALTER TABLE clinlims.sample      ENABLE TRIGGER sample_origin;
  ALTER TABLE clinlims.sample_item ENABLE TRIGGER sample_item_origin;
  ALTER TABLE clinlims.analysis    ENABLE TRIGGER analysis_origin;
  ALTER TABLE clinlims.result      ENABLE TRIGGER result_origin;

  SELECT COUNT(*) INTO v_null FROM clinlims.sample WHERE sync_origin IS NULL;
  IF v_null > 0 THEN RAISE EXCEPTION 'backfill left % NULL rows in sample', v_null; END IF;
  RAISE NOTICE 'backfill complete: no unowned rows remain';
END $$;

-- The relay itself. SET TABLE without a WHERE clause replaces the filtered definition.
ALTER PUBLICATION dbz_clinlims_owned SET TABLE
  clinlims.sample, clinlims.sample_item, clinlims.analysis, clinlims.result;

COMMIT;
