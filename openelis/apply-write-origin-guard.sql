-- SUPERSEDED 2026-09-09 on clinic nodes: the row filters and *_origin triggers this file
-- creates are retired by retire-write-origin-guard.sql once the node runs PG16 with the
-- replication-origin guard (sync-core F-044). The column and sequences it creates stay.
-- ADDED 2026-09-02 (sync-core F-015). Moves the OpenELIS/clinlims lab path off
-- creator-residue (id % 10) onto ADR-003 write-origin, matching the OpenMRS side.
--
-- WHY: residue is fixed at INSERT, so it can only say "this row belongs to one node
-- forever". BHS's workflow has handoffs -- a sample taken at a clinic and resulted at
-- the cloud. Under residue the cloud publishes only rows ending in 0, so that result
-- was silently never delivered: saved locally, every connector RUNNING, no error.
--
-- THE PREREQUISITE that blocked this until now: the MySQL guard works because the sink
-- connects as a distinct user and the trigger branches on USER(). The clinlims sink
-- connected as `clinlims`, the SAME role the OpenELIS application uses, so no trigger
-- could tell a replicated write from a local one. Fixed by a dedicated `clinlims_sink`
-- login role (password in the gitignored .env as OPENELIS_SINK_PASSWORD).
--
-- session_user, NOT current_user: immune to SET ROLE and SECURITY DEFINER. This is the
-- PostgreSQL analogue of the MySQL USER()/CURRENT_USER() trap, where the wrong one
-- returns the trigger's definer and stamps every row identically while looking installed.
--
-- REPLICA IDENTITY must cover the filter column for UPDATE/DELETE row filters. All four
-- tables were already FULL, so nothing to change -- verify before assuming on a new node.
--
-- Usage:  psql -U postgres -d openelis -v node=rawach -f openelis/apply-write-origin-guard.sql
\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE clinlims.sample      ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.sample_item ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.analysis    ADD COLUMN IF NOT EXISTS sync_origin varchar(16);
ALTER TABLE clinlims.result      ADD COLUMN IF NOT EXISTS sync_origin varchar(16);

CREATE OR REPLACE FUNCTION clinlims.stamp_sync_origin() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF session_user = 'clinlims_sink' THEN
    RETURN NEW;                    -- replicated row: keep the far node's stamp
  END IF;
  NEW.sync_origin := TG_ARGV[0];   -- local application write: stamp this node
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS sample_origin      ON clinlims.sample;
DROP TRIGGER IF EXISTS sample_item_origin ON clinlims.sample_item;
DROP TRIGGER IF EXISTS analysis_origin    ON clinlims.analysis;
DROP TRIGGER IF EXISTS result_origin      ON clinlims.result;

CREATE TRIGGER sample_origin      BEFORE INSERT OR UPDATE ON clinlims.sample
  FOR EACH ROW EXECUTE FUNCTION clinlims.stamp_sync_origin(:'node');
CREATE TRIGGER sample_item_origin BEFORE INSERT OR UPDATE ON clinlims.sample_item
  FOR EACH ROW EXECUTE FUNCTION clinlims.stamp_sync_origin(:'node');
CREATE TRIGGER analysis_origin    BEFORE INSERT OR UPDATE ON clinlims.analysis
  FOR EACH ROW EXECUTE FUNCTION clinlims.stamp_sync_origin(:'node');
CREATE TRIGGER result_origin      BEFORE INSERT OR UPDATE ON clinlims.result
  FOR EACH ROW EXECUTE FUNCTION clinlims.stamp_sync_origin(:'node');

-- CORRECTED 2026-09-02, same day. The first version of this block read
--   WHERE (sync_origin IS NULL OR sync_origin = :'node')
-- copied from the MySQL rule, with the comment "NULL is a snapshot-only state and
-- cannot cause a loop". THAT WAS WRONG AND IT CAUSED ONE. With every node allowing
-- NULL on both the publish and the accept side, an unstamped row is published by
-- everyone and accepted by everyone, so it circulates forever. Measured on Ghated:
-- 341,175 messages on bahmni-ghated.clinlims.sample for a 9-row table; the looping
-- records were op=u, id=80 and id=120, sync_origin=None.
--
-- Two-part fix. First backfill every NULL stamp from the RESIDUE -- which is precisely
-- what residue was good for: attributing rows created before the new signal existed.
-- Apply the SAME rule on every node so they agree on who owns each legacy row.
DO $bf$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['sample','sample_item','analysis','result'] LOOP
    EXECUTE format($f$
      UPDATE clinlims.%I SET sync_origin = CASE (id %% 10)
        WHEN 0 THEN 'cloud' WHEN 3 THEN 'ghated' WHEN 4 THEN 'rawach'
        ELSE 'rawach' END
      WHERE sync_origin IS NULL $f$, t);
  END LOOP;
END $bf$;

-- Then publish STRICTLY. An unstamped row is now published by nobody, so it cannot loop.
ALTER PUBLICATION dbz_clinlims_owned SET TABLE
  clinlims.sample      WHERE (sync_origin = :'node'),
  clinlims.sample_item WHERE (sync_origin = :'node'),
  clinlims.analysis    WHERE (sync_origin = :'node'),
  clinlims.result      WHERE (sync_origin = :'node');

COMMIT;
