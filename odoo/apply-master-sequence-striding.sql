-- sync-core, 2026-09-10 (F-053): master tables that clinics DO write (Odoo creates a
-- res_country_state per new spelling it sees in patient addresses) must mint ids on the same
-- stride as everything else, or two nodes coin the same id for different rows. Not synced yet
-- (decision open); this only makes the ids collision-free. Run on every node AFTER the node's
-- residue is set in the other sequences (apply-odoo-sequence-striding.sql), as odoo superuser.
DO $$
DECLARE r int := (SELECT (nextval('res_partner_id_seq') % 10)); -- borrow the node residue from res_partner
BEGIN
  PERFORM setval('res_country_state_id_seq', (SELECT ((greatest(max(id), 1000) / 10) + 1) * 10 + r FROM res_country_state), false);
  EXECUTE 'ALTER SEQUENCE res_country_state_id_seq INCREMENT BY 10';
END $$;
SELECT 'res_country_state_id_seq: next='||last_value||' inc='||increment_by FROM pg_sequences WHERE sequencename='res_country_state_id_seq';
