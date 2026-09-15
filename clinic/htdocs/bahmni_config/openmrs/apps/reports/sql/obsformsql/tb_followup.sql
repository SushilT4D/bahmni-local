 SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',
    
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Global_weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Change_In_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Change in weight since last visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Temperature',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Pulse_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Pulse rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Respiratory rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_RR_Since_Last_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'RR since last visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'SpO2',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Treatment_Compliance', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Treatment Compliance',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Reason_For_Not_Adhering', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Reason for not adhering',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Cough', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Cough',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Breathlessness',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Breathlessness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Hemoptysis',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoptysis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Loss_Of_Appetite',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Loss of Appetite',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Fever',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Fever',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Vomiting',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Vomiting',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUp_Add_More_Symp',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Add more Symptoms',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Symp_Status',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Status of Symptoms',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Hemoglobin',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Blood_Sugar',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_SGPT',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SGPT',  

   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Sputum_Outcome',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Sputum Outcome',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_2_CBNAAT_Culture_Outcome',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'CBNAAT/ Culture Outcome',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Consolidation',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Consolidation',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Cavity',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Cavity',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Effusion_Right',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Effusion',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Collapse',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Collapse',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Creps',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Creps',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Wheeze',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Wheeze',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Bronchial_breathing',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Bronchial breathing',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Air_entry_decreased',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Air entry decreased',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Treatment_Status',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Treatment Status',
   
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Any_Other_Diagnosis',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Other Diagnosis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Visit_Impresion',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Visit Impresion',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Severe_Illness',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Severe Illness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Linked_To_Other_Services',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Linked to other services',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Follow Up Date',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctor Name',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurse Name'

   FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  
    and o.obs_group_id in (select obs_id from obs where concept_id=4568 or concept_id=4678 or concept_id=4677 and voided is false)
    and o.form_namespace_and_path IS NULL
     and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('TB_Intake_Any_Other_Diagnosis','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
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

union all

 SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',

   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Global_weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Weight',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Change_In_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Change in weight since last visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Temperature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Temperature',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Pulse_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Pulse rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Respiratory rate',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_RR_Since_Last_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'RR since last visit',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'SpO2',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Treatment_Compliance', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Treatment Compliance',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Reason_For_Not_Adhering', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Reason for not adhering',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Cough', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Cough',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Breathlessness',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Breathlessness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Hemoptysis',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoptysis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Loss_Of_Appetite',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Loss of Appetite',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Fever',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Fever',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Vomiting',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Vomiting',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUp_Add_More_Symp',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Add more Symptoms',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Symp_Status',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Status of Symptoms',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Hemoglobin',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Blood_Sugar',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_SGPT',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SGPT',  

 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Sputum_Outcome',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Sputum Outcome',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_2_CBNAAT_Culture_Outcome',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'CBNAAT/ Culture Outcome',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Consolidation',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Consolidation',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Cavity',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Cavity',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Effusion_Right',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Effusion',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Collapse',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Collapse',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Creps',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Creps',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Wheeze',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Wheeze',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Bronchial_breathing',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Bronchial breathing',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_CS_Air_entry_decreased',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Air entry decreased',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Treatment_Status',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Treatment Status',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Intake_Any_Other_Diagnosis',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Other Diagnosis',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_FollowUP_Visit_Impresion',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Visit Impresion',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Severe_Illness',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Severe Illness',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'TB_Linked_To_Other_Services',coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Linked to other services',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Receipt number',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Amount Received',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Follow Up Date',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Doctor Name',
   GROUP_CONCAT(DISTINCT(IF(obs_fscn.name = 'GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'Nurse Name'

   FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%TB FollowUP Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('Global_weight','TB_FollowUP_Change_In_Weight','TB_Temperature','TB_FollowUP_Pulse_Rate','TB_RR','TB_FollowUP_RR_Since_Last_Visit','TB_FollowUP_SPO2','TB_FollowUP_Treatment_Compliance',
     'TB_FollowUP_Reason_For_Not_Adhering','TB_FollowUP_Cough','TB_FollowUP_Breathlessness','TB_FollowUP_Hemoptysis','TB_FollowUP_Loss_Of_Appetite','TB_FollowUP_Fever','TB_FollowUP_Vomiting',
     'TB_FollowUp_Add_More_Symp','TB_FollowUP_Symp_Status','TB_Hemoglobin','TB_Blood_Sugar','TB_SGPT','TB_Sputum_Outcome','TB_2_CBNAAT_Culture_Outcome','TB_Intake_Consolidation','TB_Intake_Cavity','TB_Effusion_Right','TB_Collapse','TB_CS_Creps','TB_CS_Wheeze','TB_CS_Bronchial_breathing','TB_CS_Air_entry_decreased','TB_FollowUP_Treatment_Status','TB_Intake_Any_Other_Diagnosis','TB_FollowUP_Visit_Impresion','TB_Severe_Illness','Receipt_number','Fees_Amount','GLOBAL_FollowUpDate','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
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
  GROUP BY e.encounter_id ;

