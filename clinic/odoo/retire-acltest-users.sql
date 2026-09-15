DELETE FROM res_users WHERE id = 6 AND login LIKE 'acltest_%';
DELETE FROM res_partner WHERE id IN (SELECT partner_id FROM res_users WHERE false);
DO $$
DECLARE r int := (SELECT (last_value % 10) FROM pg_sequences WHERE sequencename='res_partner_id_seq');
BEGIN
  PERFORM setval('res_users_id_seq', ((SELECT greatest(max(id),100) FROM res_users)/10 + 1)*10 + coalesce(r,0), false);
  EXECUTE 'ALTER SEQUENCE res_users_id_seq INCREMENT BY 10';
END $$;
SELECT 'users now: '||string_agg(id||':'||login, ' ' ORDER BY id) FROM res_users;
SELECT 'res_users_id_seq next='||last_value||' inc='||increment_by FROM pg_sequences WHERE sequencename='res_users_id_seq';
