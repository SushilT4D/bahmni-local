

 SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_History_Of_Family', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'History of TB in a family member/ close contact',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_HEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Height',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'ACS_BMI', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'BMI',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Hemoglobin',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Sputum_Outcome', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Sputum Outcome',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_2_CBNAAT_Culture_Outcome', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'CBNAAT/ Culture Outcome',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_LPA_Outcome', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'LPA Outcome',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Primary Site', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Primary Site',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Location_Extrapulmonary', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Location Extrapulmonary',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_CAT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'CAT',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Previous_Treatment', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of TB (Previous treatment)',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_ATT_start', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'ATT Start Date',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Any_Other_Diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Diagnosis',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Severe_Illness', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Severe Illness',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Referred', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Patient referred',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Admitted', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Patient admitted',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received (rupees)',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctors Name',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurses Name'
     FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%TB Intake Form%'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('TB_Intake_History_Of_Family','TB_FollowUP_Weight','TB_Intake_HEIGHT','ACS_BMI','TB_Hemoglobin','TB_Sputum_Outcome','TB_2_CBNAAT_Culture_Outcome','TB_LPA_Outcome',
      'TB_Intake_Primary Site','TB_Intake_Location_Extrapulmonary','TB_Intake_CAT','TB_Intake_Previous_Treatment','TB_Intake_ATT_start','TB_Intake_Any_Other_Diagnosis','TB_Severe_Illness',
      'GLOBAL_Patient_Referred','GLOBAL_Patient_Admitted','Receipt_number','Fees_Amount','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
    INNER JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false 
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false 
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    Inner Join person_attribute patr ON patr.person_id=p.person_id and patr.person_attribute_type_id=29
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
    WHERE o.voided is false  
  GROUP BY e.encounter_id
