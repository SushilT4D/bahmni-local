-- OpenMRS, any node (MySQL 8.0 or 5.6): triggers first, then the column.
DROP TRIGGER IF EXISTS openmrs.person_origin_ins;      DROP TRIGGER IF EXISTS openmrs.person_origin_upd;
DROP TRIGGER IF EXISTS openmrs.person_name_origin_ins; DROP TRIGGER IF EXISTS openmrs.person_name_origin_upd;
ALTER TABLE openmrs.person      DROP COLUMN sync_origin;
ALTER TABLE openmrs.person_name DROP COLUMN sync_origin;
SELECT CONCAT('sync_origin columns left: ', COUNT(*)) FROM information_schema.columns WHERE table_schema='openmrs' AND column_name='sync_origin';
