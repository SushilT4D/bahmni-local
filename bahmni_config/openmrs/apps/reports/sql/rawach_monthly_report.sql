SELECT 'Total number of clinic visits' as Indicator, round(count(*)) AS 'Rawach'
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
  cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like '%Rawach%'

union all

SELECT 'Total no. of patients' as Indicator,round(count(distinct pi.identifier)) AS 'Rawach'
  FROM patient_identifier pi
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
  cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like '%Rawach%'

union all

select 'Number of female %' as Indicator, concat(Female_patient,' (',round((Female_patient / Total_visit)*100,2),')') as Rawach from (
SELECT 
count(distinct(pi.identifier)) as Female_patient, 
(select count(distinct pi.identifier) AS 'Total_patient_visit' from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ) as Total_visit
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and p.gender = 'F'
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like'%Rawach%'
  order by v.date_created ) as Rawach_visit

union all

select 'Number of children under 5 years (%)' as Indicator, concat(cpatient,' (',round((cpatient / Total_visit)*100,2),')') as Rawach from (
SELECT 
count(distinct(pi.identifier)) as cpatient, 
(
select count(distinct pi.identifier) AS 'Total_patient_visit' from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ) as Total_visit

  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
   concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5 and
   cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like'%Rawach%'
 ) as Rawach

union all

 select 'Number of girls (%)' as Indicator,concat(Female_patient,' (',round((Female_patient / Total_visit)*100,2),')') as Rawach from (
SELECT 
count(distinct(pi.identifier)) as Female_patient, 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
) as Total_visit
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and 
  p.gender = 'F'
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
   concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5 
   and   cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like'%Rawach%'
  order by v.date_created ) as Rawach_visit

union all

SELECT 'No. of new patients registered' as Indicator,round(count(distinct pi.identifier))  AS 'Rawach'
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
  and cast(p.date_created AS DATE) between '#startDate#' AND '#endDate#' and pi.identifier like '%RAW%'



union all
 SELECT 'No. of patients with severe illness/ condition (%)' as Indicator, concat(round(count(distinct(Patient_Identifier))) ,' (',round((count(distinct(Patient_Identifier)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ))*100,2),')'
  ) as Rawach 
 from (
 
 SELECT 
  pi.identifier AS 'Patient_Identifier',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Severe_Illness', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'TB_Severe_Illness',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'ACS_Sever_Illness', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'ACS_Sever_Illness',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Serious_Illness', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS '2M_Serious_Illness',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'ANC_High_risk', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'ANC_High_risk'
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false and 
  cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
   AND obs_fscn.name IN ("TB_Severe_Illness","ACS_Sever_Illness","2M_Serious_Illness","ANC_High_risk")
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  LEFT JOIN location l ON e.location_id = l.location_id AND l.retired is false
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false and l.name like '%Rawach%'
  GROUP BY e.encounter_id )as formquery  where  formquery.TB_Severe_Illness='Yes' or formquery.ACS_Sever_Illness='Yes' or formquery.2M_Serious_Illness='Yes' or formquery.ANC_High_risk='Yes'

union all

 select 'No of patients provided In-patient care' as Indicator,concat(round(count(distinct(Patient_Identifier))) ,' (',round((count(distinct(Patient_Identifier)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ))*100,2),')'
  ) as Bedawal 
 from (
 
 SELECT 
  pi.identifier AS 'Patient_Identifier',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Admitted', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'GLOBAL_Patient_Admitted'
 
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false and 
  cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
   AND obs_fscn.name IN ("GLOBAL_Patient_Admitted")
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  LEFT JOIN location l ON e.location_id = l.location_id AND l.retired is false
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false and l.name like '%Rawach%'
  GROUP BY e.encounter_id )as formquery  where  formquery.GLOBAL_Patient_Admitted='Yes'

union all

select 'No of patient referrals made to a higher facility (%)' as Indicator, 
 concat(round(count(distinct(Patient_Identifier))) ,' (',round((count(distinct(Patient_Identifier)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ))*100,2),')'
  ) as Rawach 
 from (
 
 SELECT 
  pi.identifier AS 'Patient_Identifier',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Referred', coalesce(o.value_numeric,  o.value_text,  DATE_FORMAT(o.value_datetime, "%d-%b-%Y"), coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'GLOBAL_Patient_Referred'
 FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false and 
  cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
   AND obs_fscn.name IN ("GLOBAL_Patient_Referred")
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  LEFT JOIN location l ON e.location_id = l.location_id AND l.retired is false
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false and l.name like '%Rawach%'
  GROUP BY e.encounter_id )as formquery  where  formquery.GLOBAL_Patient_Referred='Yes'

union all

SELECT  'Percentage of patients seen by nurses (%)' as Indicator,concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'))*100,2),')'
) as Rawach
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  INNER join location l on l.location_id=v.location_id and l.name like '%Rawach%'
  where  DAYNAME(v.date_started) NOT like'%Thursday%' 

  union all

  SELECT   'No of children who recovered from SAM' as Indicator,
round(count(distinct(pi.identifier))) as Rawach
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("SAM recovered") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false


union all

SELECT   'No of patients who recovered from TB' as Indicator,
round(count(distinct(pi.identifier))) as Rawach
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn
  where cn.name IN("TB treatment completed") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  and o.form_namespace_and_path like '%TB FollowUP Form%' and o.voided=0
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false

union all

 select 'No of ANC with high risk identified' as Indicator, round(count(distinct(formquery.Identifier))) as Rawach from 
 (
    SELECT
    pi.identifier AS 'Identifier',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

 
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_High_risk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'High_risk'
FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%ANC Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('ANC_High_risk')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false AND p.gender = 'F'
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    Inner Join person_attribute patr ON patr.person_id=p.person_id and patr.person_attribute_type_id=29
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    and o.form_namespace_and_path like '%ANC Form%' and o.voided=0
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false
    GROUP BY e.encounter_id ) as formquery  
 where formquery.High_risk='Yes'

union all

SELECT   'No of women who completed 4 or more ANC visits' as Indicator,
round(count(distinct(pi.identifier))) as Rawach
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ANC_No_Of_Visit") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("ANC_No_Of_Visit_4","ANC_No_Of_Visit_5","ANC_No_Of_Visit_6","ANC_No_Of_Visit_7"
              ,"ANC_No_Of_Visit_8","ANC_No_Of_Visit_9") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false


union all

 select 'No of patients who were operated for Cataract' as Indicator,
 round(count(distinct(pi.identifier))) as Rawach
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ACS_ADULT_Diagnosis","TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn
  where cn.name IN("Cataract Surgery") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
  WHERE o.voided is false

  union all 

select 'Total revenue generated in rupees' as Indicator,round(sum(o.value_numeric)) as Rawach 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('Fees_Amount') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Rawach%'

 union all

SELECT   'No of patients with Cataract' as Indicator,
round(count(distinct(pi.identifier))) as Rawach
FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ACS_ADULT_Diagnosis","TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn
  where cn.name IN("Cataract") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
  WHERE o.voided is false




union all

SELECT   'No. of patients with COPD (%)' as Indicator,
     concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) /
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ))*100,2),')') as Rawach
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Chronic Lung disease") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)>5
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false
   
  
    union all

  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Chronic Lung disease") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)>5
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false


    union all



  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ANC_Any_Other_Problems") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Chronic Lung disease") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)>5
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false


    ) as total

    union all

SELECT   'No.of patients with Enteric Fever (%)' as Indicator,
    concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) /
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Rawach%'
  ))*100,2),')') as Rawach
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Enteric Fever") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false
   
  
    union all

  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Enteric Fever") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false


    union all



  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ANC_Any_Other_Problems") and value_coded in(select concept_id from concept_name cn
    where cn.name IN("Enteric Fever") and cn.voided is false
    and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Rawach%'
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false

    ) as total





;  
