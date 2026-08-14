SELECT   'No of children with SAM (%)' as Indicator,
(SELECT   
     concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("SAM New","SAM On Treatment") and cn.voided is false
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
  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
  LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
  LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
  LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
  LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
  LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
  LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
  LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
  LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false 
  WHERE o.voided is false) as 'Kojawada'

union all

SELECT   'No of children Severe undernutrition (%)' as Indicator,
concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Severe undernutrition") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Severe undernutrition") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of  children with Pneumonia/ ALRI (%)' as Indicator,
concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Pneumonia","Severe pneumonia") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Pneumonia","Severe pneumonia") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of children with Severe Anemia (%)' as Indicator,
concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Severe anemia") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Severe anemia") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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


	 
	

	SELECT  'No of children with Diarrhea (%)' as Indicator,
     concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Diarrhea with severe dehydration","Diarrhea with some dehydration","Diarrhea with dehydration","Diarrhea with no dehydration","Persistent diarrhea","Dysentery") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Diarrhea with severe dehydration","Diarrhea with some dehydration","Diarrhea with dehydration","Diarrhea with no dehydration","Persistent diarrhea","Dysentry") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of children with malaria (%)' as Indicator,
concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Clinical Malaria","Malaria -mixed","Malaria falciparum","Malaria Vivax") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Clinical Malaria","Malaria -mixed","Malaria falciparum","Malaria Vivax") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

  select  'No of children Immunized' as Indicator, 
  concat(round(count(distinct(2M5Y))) ,' (',round((count(distinct(2M5Y)) / 
(

select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)<=5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'

  ))*100,2),')') as Kojawada

	from

	(
	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("2MT5Y_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Child Immunised") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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



	SELECT   pi.identifier as 2M5Y
	FROM obs o
	  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
	  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	  AND obs_fscn.name IN ("TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
	  where cn.name IN("Child Immunised") and cn.voided is false
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
	  and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_created ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_created ) % 12)<=5
	  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of new patients with TB (%)' as Indicator,

concat(patient,' (',round((patient / Total_visit)*100,2),')') as Kojawada from (
SELECT 
count(distinct(pi.identifier)) as patient, 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
) as Total_visit

  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0
  Inner join encounter e on v.visit_id=e.visit_id
  Inner join  obs o on e.encounter_id=o.encounter_id and cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
  and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
  INNER join location l on l.location_id=v.location_id and l.name like'%Kojawada%'
  order by v.date_created 
) as Kojawada_visit

union all


SELECT  'No of patients with PID (%)' as Indicator,
     concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Pelvic Inflammatory Disease") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Pelvic Inflammatory Disease") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Pelvic Inflammatory Disease") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT  'No of patients with LRI (%)' as Indicator,
     concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Lower Respiratory Tract Infection") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Lower Respiratory Tract Infection") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Lower Respiratory Tract Infection") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT  'No of patients with Diarrhea (%)' as Indicator,
     concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Diarrhea with no dehydration","Diarrhea with some dehydration","Diarrhea with severe dehydration","Dysentry","Diarrhea with dehydration") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Diarrhea with no dehydration","Diarrhea with some dehydration","Diarrhea with severe dehydration","Dysentry","Diarrhea with dehydration") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Diarrhea with no dehydration","Diarrhea with some dehydration","Diarrhea with severe dehydration","Dysentry","Diarrhea with dehydration") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT  'No of patients with Skin conditions (%)' as Indicator,
     concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Skin diseases-Fungal","Skin Disease - Impetigo","Skin Disease - Scabies","Skin disease- Dermatitis","Skin disease - Tinea","Skin Disease - Others","Leprosy, Template") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Skin diseases-Fungal","Skin Disease - Impetigo","Skin Disease - Scabies","Skin disease- Dermatitis","Skin Disease - Tinea","Skin Disease - Others","Leprosy, Template") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Skin diseases-Fungal","Skin Disease - Impetigo","Skin Disease - Scabies","Skin disease- Dermatitis","Skin Disease - Tinea","Skin Disease - Others","Leprosy, Template") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of patients with Malaria (%)' as Indicator,
concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Confirmed Malaria Falciparum","Confirmed Malaria Vivax","Confirmed Malaria Mixed","Clinical Malaria") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Confirmed Malaria Falciparum","Confirmed Malaria Vivax","Confirmed Malaria Mixed","Clinical Malaria") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Confirmed Malaria Falciparum","Confirmed Malaria Vivax","Confirmed Malaria Mixed","Clinical Malaria") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of patients with Diabetes Mellitus (%)' as Indicator,
concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Diabetes Type 1","Diabetes Type 2") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Diabetes Type 1","Diabetes Type 2") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Diabetes Type 1","Diabetes Type 2") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of patients with Hypertension (%)' as Indicator,
concat(round(count(distinct(patient))) ,' (',round((count(distinct(patient)) / 
(
select count(distinct pi.identifier) AS `Total_patient` from patient_identifier pi
join person p on p.person_id = pi.patient_id and pi.voided = 0 and pi.preferred = 1
join visit v on v.patient_id = p.person_id and v.voided = 0 and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
and concat(TIMESTAMPDIFF( YEAR, birthdate, v.date_started ),'.',TIMESTAMPDIFF( MONTH, birthdate, v.date_started ) % 12)>5
join location l on l.location_id = v.location_id and l.name like '%Kojawada%'
  ))*100,2),')') as Kojawada
  from
  (
  SELECT   pi.identifier as patient
  FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ("ACS_ADULT_Diagnosis") and value_coded in(select concept_id from concept_name cn 
    where cn.name IN("Hypertension") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Hypertension") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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
    where cn.name IN("Hypertension") and cn.voided is false
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
    JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No of women provided ANC' as Indicator,
  count(distinct pi.identifier) AS `Kojawada` 
  FROM patient_identifier pi 
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
  Inner join encounter e on v.visit_id=e.visit_id
  Inner join  obs o on e.encounter_id=o.encounter_id and cast(o.obs_datetime AS DATE) between '#startDate#' AND '#endDate#'
  and o.form_namespace_and_path like '%ANC Form%' and o.voided=0
  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
  INNER join location l on l.location_id=v.location_id and l.name like'%Kojawada%'


union all

SELECT   'No of women provided MTP' as Indicator,
  count(distinct(pi.identifier)) as 'Kojawada'

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ACS_ADULT_Diagnosis","TB_Intake_Any_Other_Diagnosis","ANC_Any_Other_Problems") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("Medical method of abortion") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false AND p.gender = 'F'
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

  SELECT   'No of women provided DMPA' as Indicator,
count(distinct(pi.identifier)) as 'Kojawada'

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ACS_ADULT_Diagnosis","TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("DMPA First","DMPA Subsequent") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false AND p.gender = 'F'
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No. of deliveries' as Indicator,
  count(distinct(pi.identifier)) as 'Kojawada'

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("Global_Location_Visit") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("Global_Location_Visit_Clinic") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false AND p.gender = 'F'
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  and o.form_namespace_and_path like '%Delivery Form%' and o.voided=0
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

SELECT   'No. of women new born provided PNC' as Indicator,
  count(distinct(pi.identifier)) as 'Kojawada'

FROM obs o
  JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
  JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
  AND obs_fscn.name IN ("ACS_ADULT_Diagnosis","TB_Intake_Any_Other_Diagnosis") and value_coded in(select concept_id from concept_name cn 
  where cn.name IN("PNC 1","PNC 2","PNC 3","PNC-1 Complications","PNC-2 Complications","PNC-3 Complications") and cn.voided is false
  and cn.concept_name_type='FULLY_SPECIFIED' and cn.locale='en')
  LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
  JOIN person p ON p.person_id = o.person_id AND p.voided is false AND p.gender = 'F'
  JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
  JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
  JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
  JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
  JOIN provider pro ON pro.provider_id=ep.provider_id
  LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
  JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false 
  and cast(v.date_started AS DATE) between '#startDate#' AND '#endDate#'
  JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
  JOIN location l ON e.location_id = l.location_id AND l.retired is false and l.name like'%Kojawada%'
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

 

 


    
;
