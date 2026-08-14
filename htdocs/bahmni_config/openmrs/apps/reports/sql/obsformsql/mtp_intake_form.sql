SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_height', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Height',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='BMI', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BMI',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Systolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP Systolic',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Diastolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP Diastolic',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Temperature',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Pulse', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pulse rate',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory rate',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='LMP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'LMP',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Bleeding_Days', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'No of days of menstruation',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Cycle_Intervals', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Interval between cycles',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Regularity', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Regularity',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Flow', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Flow',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Intake_Diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Diagnosis',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Gravida', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gravida',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Para', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Paraity',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Abortion', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Abortion',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Live_Birth', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Live Birth',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Still_Birth', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Still Birth',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Urin_Prgncy_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine pregnancy test',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Gestation_History', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by history',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Pv', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/V examination',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ACS_P_V_Uterus_Size', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/V Uterus Size (In Weeks)',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_P_S', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/S examination',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Eligible_MTP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Eligible for MTP?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Consent', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Consent given?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Reason_For_Prgncy', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Reason for which pregnancy is terminated',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Medication', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Provided Medical Abortion?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Immediate Complications?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount Received',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow Up Date',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'


FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    and o.obs_group_id in (select obs_id from obs where concept_id=4096 and voided is false)
    and o.form_namespace_and_path IS NULL
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
    AND obs_fscn.name IN ('MTP_Intake_Diagnosis','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
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

GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_height', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Height',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='BMI', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BMI',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Systolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP Systolic',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Diastolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP Diastolic',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Temperature',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Pulse', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pulse rate',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory rate',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='LMP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'LMP',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Bleeding_Days', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'No of days of menstruation',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Cycle_Intervals', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Interval between cycles',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Regularity', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Regularity',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Flow', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Flow',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Intake_Diagnosis', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Diagnosis',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Gravida', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gravida',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Para', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Paraity',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Abortion', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Abortion',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Live_Birth', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Live Birth',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Still_Birth', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Still Birth',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Urin_Prgncy_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine pregnancy test',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Gestation_History', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by history',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Pv', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/V examination',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ACS_P_V_Uterus_Size', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/V Uterus Size (In Weeks)',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_P_S', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'P/S examination',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Eligible_MTP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Eligible for MTP?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Consent', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Consent given?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Reason_For_Prgncy', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Reason for which pregnancy is terminated',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Medication', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Provided Medical Abortion?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='MTP_Complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Immediate Complications?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount Received',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow Up Date',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'


FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%MTP Intake Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('Global_weight','Global_height','BMI','Systolic','Diastolic','Temperature','Pulse','RR','SPO2',
    'LMP','MTP_Bleeding_Days','MTP_Cycle_Intervals','MTP_Regularity','MTP_Flow','MTP_Gravida','MTP_Para','MTP_Abortion',
    'MTP_Live_Birth','MTP_Still_Birth','MTP_Hemoglobin','MTP_Urin_Prgncy_Test','MTP_Gestation_History','MTP_Pv',
    'ACS_P_V_Uterus_Size','MTP_P_S','MTP_Eligible_MTP','MTP_Consent','MTP_Reason_For_Prgncy','MTP_Medication',
    'MTP_Complications','Receipt_number','Fees_Amount','GLOBAL_FollowUpDate','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name'
    )
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

