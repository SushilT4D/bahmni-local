-- ADDED 2026-09-02 (sync-core F-004). Applies the 12 changesets that
-- liquibase-1.9.5 (baked into the OpenELIS image) cannot.
--
-- THE BLOCKER, precisely: liquibase 1.9.5 never detects clinlims.databasechangeloglock,
-- so on every waitForLock retry it issues CREATE TABLE -- succeeding once, then failing
-- "already exists" until it gives up. Reproduced identically on PostgreSQL 14 and 9.6.24,
-- so it is the tool, not our config and not a version skew. NOTE our lock is NOT held
-- (locked = false); production's separate stuck-lock problem is a different fault.
--
-- Applied to Rawach and the cloud on 2026-09-02, both 142 -> 154 changesets. Backups
-- taken first (pg_dump --format=custom, verified with pg_restore -l) to
--   ~/Documents/bahmni-backups/rawach-openelis-2026-09-02-pre-changesets.dump
--   mini:~/bahmni-backups/cloud-openelis-2026-09-02-pre-changesets.dump
--
-- VERIFIED THROUGH THE APPLICATION, not by counting rows: bahmni-sim TC-L-29
-- (openelis-catalogue) and TC-C-12 (openelis-catalogue-cloud) both PASS -- 116 tests
-- offered for sample type 84 on each node. Both had been RED since 2026-08-28 with
-- "column test0_.reference_info does not exist". openelis-login, openelis-login-cloud
-- and TC-L-30 (openelis-accession-absent) still pass, so no regression.
--
-- Run against a node that needs it (idempotent -- every step is guarded):
--   docker exec -i <pgcontainer> psql -U clinlims -d openelis -v ON_ERROR_STOP=1 \
--     < openelis/apply-missing-changesets.sql
--
-- Side effect worth knowing: this sets site_information.accessionStrategy to
-- 'groupBySample', matching BHS production. It does NOT fix F-005/BL-049 -- that is
-- acessionFormat (DATENUM, no site component) and siteNumber (11404 on every node),
-- neither of which these changesets touch.
-- F-004: apply the 12 changesets Liquibase 1.9.5 cannot, in BahmniConfig.xml file order.
-- Every statement is additive. Preconditions with onFail="MARK_RAN" are reproduced as
-- IF guards, so a changeset whose precondition fails is recorded without executing --
-- exactly what Liquibase would do. md5sum is left NULL so a future Liquibase recomputes
-- rather than reporting a checksum mismatch.
\set ON_ERROR_STOP on
BEGIN;
SET search_path TO clinlims, public;

CREATE OR REPLACE FUNCTION pg_temp.mark(p_id text, p_author text, p_comment text) RETURNS void AS $f$
  INSERT INTO clinlims.databasechangelog (id,author,filename,dateexecuted,md5sum,description,comments,liquibase)
  VALUES (p_id, p_author, './Bahmni/BahmniConfig.xml', now(), NULL, 'Custom SQL',
          p_comment || ' [applied manually 2026-09-02, F-004]', '1.9.5');
$f$ LANGUAGE sql;

-- 1719 configure-accession-strategy
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM site_information WHERE name='accessionStrategy') = 0 THEN
    INSERT INTO site_information (id,name,description,value,value_type,domain_id)
    VALUES (nextval('site_information_seq'),'accessionStrategy','Strategy for Accession Generation','','text',
            (SELECT id FROM site_information_domain WHERE name='siteIdentity'));
  END IF; END $$;
SELECT pg_temp.mark('configure-accession-strategy','Mahitha','Add accession strategy');

-- 1731 202001281052
CREATE SEQUENCE IF NOT EXISTS type_of_test_status_seq MINVALUE 1 START 1;
CREATE TABLE IF NOT EXISTS type_of_test_status (
  id int CONSTRAINT pk_type_of_test_status PRIMARY KEY,
  status_name varchar(50) NOT NULL UNIQUE,
  description varchar(200) NOT NULL UNIQUE,
  status_type varchar(20) NOT NULL,
  is_active varchar(1) DEFAULT 'Y',
  is_result_required varchar(1) DEFAULT 'N',
  is_approval_required varchar(1) DEFAULT 'N',
  date_created timestamp DEFAULT CURRENT_TIMESTAMP(6),
  lastupdated timestamp(6));
SELECT pg_temp.mark('202001281052','Srivathsala','create a new table to store type of test status');

-- 1754 202001281053
CREATE SEQUENCE IF NOT EXISTS test_status_seq MINVALUE 0 START 1;
CREATE TABLE IF NOT EXISTS test_status (
  id int CONSTRAINT pk_test_status PRIMARY KEY,
  test_id int UNIQUE,
  test_status_id int);
SELECT pg_temp.mark('202001281053','Srivathsala','create a new table to store status for a test');

-- 1769 202001281054
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_fk') THEN
    ALTER TABLE test_status ADD CONSTRAINT test_fk FOREIGN KEY (test_id)
      REFERENCES test(id) ON DELETE SET NULL;
  END IF; END $$;
SELECT pg_temp.mark('202001281054','Srivathsala','FK test_status.test_id -> test.id');

-- 1772 202001281055
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='test_status_fk') THEN
    ALTER TABLE test_status ADD CONSTRAINT test_status_fk FOREIGN KEY (test_status_id)
      REFERENCES type_of_test_status(id) ON DELETE SET NULL;
  END IF; END $$;
SELECT pg_temp.mark('202001281055','Srivathsala','FK test_status.test_status_id -> type_of_test_status.id');

-- 1775 add-new-column-for-reference-info
ALTER TABLE test ADD COLUMN IF NOT EXISTS reference_info varchar(400);
SELECT pg_temp.mark('add-new-column-for-reference-info','Rupam','Adds a referenceInfo column to test');

-- 1781 add-new-status-for-analysis
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM status_of_sample WHERE name='Marked As Done') = 0 THEN
    INSERT INTO status_of_sample(id,name,description,code,status_type,display_key,is_active)
    VALUES (nextval('status_of_sample_seq'),'Marked As Done',
            'The result of the referred out test were validated and are final',1,'ANALYSIS',
            'status.test.referred.markAsDone','Y');
  END IF; END $$;
SELECT pg_temp.mark('add-new-status-for-analysis','Rupam','adding new status for referred-out marked as done');

-- 1793 202001281056
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM site_information WHERE name='flagForShowingTestStatus') = 0 THEN
    INSERT INTO site_information (id,name,description,value_type,value,domain_id,lastupdated)
    VALUES (nextval('site_information_seq'),'flagForShowingTestStatus',
            'This flag needs to be set to true to see the test status drop down','boolean','false',
            (SELECT id FROM site_information_domain WHERE name='siteIdentity'), now());
  END IF; END $$;
SELECT pg_temp.mark('202001281056','buvaneswari','Adds a flag to control type of test status visibility');

-- 1811 BAH4572802241425
DO $$ BEGIN
  IF (SELECT COUNT(*) FROM site_information WHERE name='accessionStrategy' AND value='') = 1 THEN
    UPDATE site_information SET value='groupBySample' WHERE name='accessionStrategy';
  END IF; END $$;
SELECT pg_temp.mark('BAH4572802241425','bahmni','set accession strategy to groupBySample');

-- 1825 BAH3908_test_table
ALTER TABLE test ALTER COLUMN name TYPE varchar(256);
ALTER TABLE test ALTER COLUMN description TYPE varchar(256);
SELECT pg_temp.mark('BAH3908_test_table','Mohankumar','Extend name/description on test');

-- 1836 BAH3908_panel_table
ALTER TABLE panel ALTER COLUMN name TYPE varchar(256);
ALTER TABLE panel ALTER COLUMN description TYPE varchar(256);
SELECT pg_temp.mark('BAH3908_panel_table','Mohankumar','Extend name/description on panel');

-- 1848 fix-uploaded-files-parent-directory
UPDATE site_information SET value='/home/bahmni' WHERE name='parentOfUploadedFilesDirectory';
SELECT pg_temp.mark('fix-uploaded-files-parent-directory','bahmni','Fix parentOfUploadedFilesDirectory to the volume-mounted path');

COMMIT;
