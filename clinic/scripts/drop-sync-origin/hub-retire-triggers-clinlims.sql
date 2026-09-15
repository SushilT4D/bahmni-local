-- Hub only: the clinlims stamp triggers go; nothing replaces them (no conflict rule on clinlims).
DROP TRIGGER IF EXISTS sample_origin      ON clinlims.sample;
DROP TRIGGER IF EXISTS sample_item_origin ON clinlims.sample_item;
DROP TRIGGER IF EXISTS analysis_origin    ON clinlims.analysis;
DROP TRIGGER IF EXISTS result_origin      ON clinlims.result;
SELECT 'clinlims triggers left: '||count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname='clinlims';
