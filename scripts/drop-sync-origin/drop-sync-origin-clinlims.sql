-- OpenELIS, any node: drop sync_origin from the 4 clinlims tables (triggers must be gone first).
ALTER TABLE clinlims.sample      DROP COLUMN IF EXISTS sync_origin;
ALTER TABLE clinlims.sample_item DROP COLUMN IF EXISTS sync_origin;
ALTER TABLE clinlims.analysis    DROP COLUMN IF EXISTS sync_origin;
ALTER TABLE clinlims.result      DROP COLUMN IF EXISTS sync_origin;
DROP FUNCTION IF EXISTS clinlims.stamp_sync_origin();
SELECT 'sync_origin columns left: '||count(*) FROM information_schema.columns WHERE column_name='sync_origin';
