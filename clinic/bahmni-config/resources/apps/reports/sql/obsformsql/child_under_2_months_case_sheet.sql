SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Type_Of_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Heart_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Heart Rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Breath_rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Breath Rate', 
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_CFT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'CFT',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'SpO2',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Hindi_Temprature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Temprature',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Infant_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Infant_Height', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Height',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Diagnosis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Serious_Illness', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Severe illness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Follow up after', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Follow Up Date',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Hindi_Name_of_Doctor', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctor Name',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Name_of_nurse_or_SHW_hindi', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurse Name'

    FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  
    and o.obs_group_id in (select obs_id from obs where concept_id=4915 or concept_id=4916 and voided is false)
    and o.form_namespace_and_path IS NULL
   and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ('2M_diagnosis','GLOBAL_Hindi_Name_of_Doctor','GLOBAL_Name_of_nurse_or_SHW_hindi')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
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

Union all

SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Type_Of_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Heart_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Heart Rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Breath_rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Breath Rate', 
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_CFT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'CFT',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'SpO2',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Hindi_Temprature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Temprature',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Infant_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Infant_Height', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Height',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Diagnosis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = '2M_Serious_Illness', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Severe illness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Follow up after', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Follow Up Date',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Hindi_Name_of_Doctor', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctor Name',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Name_of_nurse_or_SHW_hindi', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurse Name'



     FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%Child Under 2 Months Case Sheet%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ('GLOBAL_Type_Of_Visit','2M_Heart_Rate','2M_Breath_rate','2M_CFT','2M_SPO2','GLOBAL_Hindi_Temprature','GLOBAL_Infant_Weight','GLOBAL_Infant_Height','2M_diagnosis',
      '2M_Serious_Illness','Receipt_number','Fees_Amount','GLOBAL_Follow up after','GLOBAL_Hindi_Name_of_Doctor','GLOBAL_Name_of_nurse_or_SHW_hindi')
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
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
  GROUP BY e.encounter_id;
