SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',


     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Type of SAM patient', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Type of SAM patient',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Heart Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Heart Rate',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Respiratory Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory Rate',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Temperature',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Length', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Length',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WHZ', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'WHZ',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WAZ_Color', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'WAZ',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SAM_Chest X Ray', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Chest X Ray',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SAM_Montoux Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Montoux Test',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Appetite_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Appetite Test',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Date of enrollment', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Date of enrollment',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='TB_FollowUP_Treatment_Compliance', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Compliance of treatment',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Present Status', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Present Status',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Any contact with TB in the family', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any contact with TB in the family',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Any_Disease_Condition', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Chornic disease/condition?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_If_Other_Specify', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'If other, specify',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Peanut_Allergy', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Peanut allergy',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Kwashiorkar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Kwashiorkar',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Visible severe wasting', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Visible severe wasting',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Is_SAM_complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SAM with Complications?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Diagnosis',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount received',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Follow up Date', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow up',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'


    FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  
    and o.obs_group_id in (select obs_id from obs where concept_id=5084 or concept_id=5085 and voided is false)
    and o.form_namespace_and_path IS NULL
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ('2MT5Y_Diagnosis','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
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
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',


 	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Type of SAM patient', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Type of SAM patient',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Heart Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Heart Rate',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Respiratory Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory Rate',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Temperature',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Length', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Length',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WHZ', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'WHZ',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='WAZ_Color', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'WAZ',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SAM_Chest X Ray', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Chest X Ray',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SAM_Montoux Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Montoux Test',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Appetite_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Appetite Test',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Date of enrollment', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Date of enrollment',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='TB_FollowUP_Treatment_Compliance', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Compliance of treatment',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Present Status', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Present Status',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Any contact with TB in the family', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any contact with TB in the family',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Any_Disease_Condition', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Chornic disease/condition?',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_If_Other_Specify', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'If other, specify',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Peanut_Allergy', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Peanut allergy',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Kwashiorkar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Kwashiorkar',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Visible severe wasting', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Visible severe wasting',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Is_SAM_complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SAM with Complications?',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='2MT5Y_Diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Diagnosis',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount received',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Follow up Date', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow up',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'


 	FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%SAM Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('Type of SAM patient','Heart Rate','Respiratory Rate',
     	'Temperature','SPO2','WEIGHT','Length','WHZ','WAZ_Color','Lab_Hemoglobin','ANC_Blood_Sugar','SAM_Chest X Ray','SAM_Montoux Test','2MT5Y_Appetite_Test',
     	'Date of enrollment','TB_FollowUP_Treatment_Compliance','Present Status','Any contact with TB in the family','2MT5Y_Any_Disease_Condition',
     	'2MT5Y_If_Other_Specify','2MT5Y_Peanut_Allergy','Kwashiorkar','Visible severe wasting','2MT5Y_Is_SAM_complications','2MT5Y_Diagnosis','Receipt_number',
     	'Fees_Amount','Follow up Date','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')

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
