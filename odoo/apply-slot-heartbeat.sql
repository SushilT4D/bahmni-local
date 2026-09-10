-- sync-core, 2026-09-10 (F-043): a heartbeat table per captured database so an idle slot
-- keeps confirming WAL. Both databases share one WAL; a slot in the quiet database holds
-- everything the busy one writes (clinlims slot: 3.5 GB on Ghated, 888 MB today; 477 MB cloud).
-- Debezium's heartbeat.action.query upserts this row every heartbeat.interval.ms; the change
-- flows through the publication, the connector commits the LSN, the slot advances.
-- Run against BOTH databases with the right schema:  psql -d odoo -v s=public -v r=odoo ...
--                                                   psql -d openelis -v s=clinlims -v r=clinlims ...
CREATE TABLE IF NOT EXISTS :s.dbz_heartbeat (id int PRIMARY KEY, ts timestamptz NOT NULL);
INSERT INTO :s.dbz_heartbeat (id, ts) VALUES (1, now()) ON CONFLICT (id) DO NOTHING;
GRANT SELECT, INSERT, UPDATE ON :s.dbz_heartbeat TO :r;
SELECT format('ALTER PUBLICATION %I ADD TABLE %I.dbz_heartbeat', :'p', :'s')
 WHERE NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = :'p' AND tablename = 'dbz_heartbeat') \gexec
SELECT :'p' || ' now carries: ' || string_agg(tablename, ',' ORDER BY tablename) FROM pg_publication_tables WHERE pubname = :'p';
