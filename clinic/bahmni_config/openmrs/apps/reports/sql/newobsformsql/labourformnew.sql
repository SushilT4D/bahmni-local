SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Date_of_Admission', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Date of Admission',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Gravida', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Gravida',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Parity', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Parity',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Abortions', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Abortions',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Live_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Live Births',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Still_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Still Births',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Neonatal_Death', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Neonatal Death',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Global_weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Height', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Height',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Hemoglobin',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'ANC_High_risk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'High risk?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Any_High_risk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'High Risk',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Outcome', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Outcome',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_specify_reason', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'If Referred, Specify Reason',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Delivery_Date', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Date of Delivery',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Global_Location_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Location of delivery',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_complications_in_delivery', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Were There Complications in Delivery?',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Specify_complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Specify Complications',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Outcome_Delivery', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Outcome of Delivery',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Period_Of_Gestation', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Period of Gestation',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_N_born_sex', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'New born sex',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Newborn_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Newborn Weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Type_of_Birth', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of birth',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_LowBirth_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of low birth weight',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_ANY_Newborn_Compli', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Any newborn complications',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Del_Newborn_complication', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Type of new born complications',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Referred', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Patient referred',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Patient_Admitted', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Patient admitted',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctors Name',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurses Name'

        FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%Labour Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('Del_Date_of_Admission','Del_Gravida','Del_Parity','Del_Abortions','Del_Live_Births','Del_Still_Births','Del_Neonatal_Death','Global_weight','Del_Height','Del_Hemoglobin',
        'ANC_High_risk','Del_Any_High_risk','Del_Outcome','Del_specify_reason','Del_Delivery_Date','Global_Location_Visit','Del_complications_in_delivery','Del_Specify_complications','Del_Outcome_Delivery',
        'Del_Period_Of_Gestation','Del_N_born_sex','Del_Newborn_Weight','Del_Type_of_Birth','Del_LowBirth_Weight','Del_ANY_Newborn_Compli','Del_Newborn_complication','GLOBAL_Patient_Referred',
        'GLOBAL_Patient_Admitted','Receipt_number','Fees_Amount','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
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
