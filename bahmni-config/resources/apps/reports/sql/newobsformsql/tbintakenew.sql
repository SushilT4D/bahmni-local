SELECT
    pi.identifier AS 'Identifier',
    l.name AS 'Location',
    patr.value AS 'File Number',
    pn.given_name AS 'First Name',
    pn.family_name AS 'Last Name',
    p.gender AS 'Gender',
    FLOOR(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365) AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'History of TB in a family member/ close contact', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'History of TB in a family member/ close contact',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_FollowUP_Weight', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Weight',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_HEIGHT', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Height',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'ACS_BMI', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'BMI',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Hemoglobin', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Hemoglobin',
    (
        SELECT GROUP_CONCAT(DISTINCT cn.name SEPARATOR ', ')
        FROM obs o_sub
        JOIN concept_name cn ON o_sub.value_coded = cn.concept_id
        WHERE o_sub.person_id = o.person_id AND o_sub.value_coded IN (61884,61885,61886) AND o_sub.concept_id = 61883 AND o_sub.voided = 0 AND cn.concept_name_type = 'FULLY_SPECIFIED'
    ) AS 'HIV Status',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Sputum_Outcome', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Sputum Outcome',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_2_CBNAAT_Culture_Outcome', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'CBNAAT/ Culture Outcome',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_LPA_Outcome', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'LPA Outcome',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_Primary Site', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Primary Site',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_Location_Extrapulmonary', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Location Extrapulmonary',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_CAT', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'CAT',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_Previous_Treatment', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Type of TB (Previous treatment)',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_ATT_start', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'ATT Start Date',
    (
        SELECT GROUP_CONCAT(DISTINCT cn.name SEPARATOR ', ')
        FROM obs o_sub
        JOIN concept_name cn ON o_sub.value_coded = cn.concept_id
        WHERE o_sub.person_id = o.person_id AND o_sub.value_coded =cn.concept_id AND o_sub.concept_id = 4568 AND o_sub.voided = 0 AND cn.concept_name_type = 'FULLY_SPECIFIED'
    ) AS 'Diagnosis',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Intake_other_diagnosis', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Other-Diagnosis',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'TB_Severe_Illness', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Severe Illness',
    (
        SELECT GROUP_CONCAT(DISTINCT cn.name SEPARATOR ', ')
        FROM obs o_sub
        JOIN concept_name cn ON o_sub.value_coded = cn.concept_id
        WHERE o_sub.person_id = o.person_id AND o_sub.value_coded IN (1, 2) AND o_sub.concept_id = 61887 AND o_sub.voided = 0 AND cn.concept_name_type = 'FULLY_SPECIFIED'
    ) AS 'Patient referred',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'RF_Institute_Name', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Name of the referral hospital',
    (
        SELECT GROUP_CONCAT(DISTINCT cn.name SEPARATOR ', ')
        FROM obs o_sub
        JOIN concept_name cn ON o_sub.value_coded = cn.concept_id
        WHERE o_sub.person_id = o.person_id AND o_sub.value_coded IN (1, 2) AND o_sub.concept_id = 5994 AND o_sub.voided = 0 AND cn.concept_name_type = 'FULLY_SPECIFIED'
    ) AS "Patient admitted",
    (
        SELECT GROUP_CONCAT(DISTINCT cn.name SEPARATOR ', ')
        FROM obs o_sub
        JOIN concept_name cn ON o_sub.value_coded = cn.concept_id
        WHERE o_sub.person_id = o.person_id AND o_sub.value_coded IN (1, 2) AND o_sub.concept_id = 61867 AND o_sub.voided = 0 AND cn.concept_name_type = 'FULLY_SPECIFIED'
    )As "Consulted on call",
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'Receipt_number', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Receipt number',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'Fees_Amount', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Amount Received (rupees)',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'Subscription card', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Subscription Card',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'Subscription card Numbers', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Subscription Card Number',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'GLOBAL_Doctors_Name', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Doctors Name',
    GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'GLOBAL_Nurse_Name', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Nurses Name',
    (
        SELECT cn.name
        FROM concept_name cn
        JOIN person_attribute pa ON cn.concept_id = pa.value
        WHERE pa.person_attribute_type_id = 31 AND pa.person_id = p.person_id AND cn.concept_name_type = 'SHORT'
        LIMIT 1 
    ) AS 'Catchment Area',
    paddress.state_province AS 'State',
    paddress.country AS 'District',
    paddress.Address2 AS 'Tehsil',
    paddress.address1 AS 'Panchyat',
    paddress.city_village AS 'Village',
    paddress.postal_code AS 'Hamlet (Fala)',
    (
            SELECT cn.name
            FROM concept_name cn
            JOIN person_attribute pa ON cn.concept_id = pa.value
            WHERE pa.person_attribute_type_id = 28
            AND pa.person_id = p.person_id and cn.concept_name_type='SHORT'
            LIMIT 1 
        ) As 'Migrant',
        GROUP_CONCAT(DISTINCT IF(obs_fscn.name = 'Nikshay_Id', COALESCE(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL) ORDER BY o.obs_id DESC) AS 'Nikshay Id'
FROM obs o
JOIN concept obs_concept ON obs_concept.concept_id = o.concept_id AND obs_concept.retired IS FALSE AND o.form_namespace_and_path LIKE '%TB Intake Form%'
JOIN concept_name obs_fscn ON o.concept_id = obs_fscn.concept_id AND obs_fscn.concept_name_type = "FULLY_SPECIFIED" AND obs_fscn.voided IS FALSE AND obs_fscn.name IN (
    'History of TB in a family member/ close contact', 'TB_FollowUP_Weight', 'TB_Intake_HEIGHT', 'ACS_BMI', 'TB_Hemoglobin', 'HIV Status new', 'TB_Sputum_Outcome', 'TB_2_CBNAAT_Culture_Outcome', 'TB_LPA_Outcome',
    'TB_Intake_Primary Site', 'TB_Intake_Location_Extrapulmonary', 'TB_Intake_CAT', 'TB_Intake_Previous_Treatment', 'TB_Intake_ATT_start', 'ACS_ADULT_Diagnosis', 'TB_Intake_other_diagnosis', 'TB_Severe_Illness',
    'Patient referred_institute', 'RF_Institute_Name', 'GLOBAL_Patient_Admitted', 'Consulted on Call', 'Receipt_number', 'Fees_Amount', 'Subscription card', 'Subscription card Numbers', 'GLOBAL_Doctors_Name', 'GLOBAL_Nurse_Name','Nikshay_Id'
    )
INNER JOIN concept_name obs_scn ON o.concept_id = obs_scn.concept_id AND obs_scn.concept_name_type = "SHORT" AND obs_scn.voided IS FALSE and cast(o.obs_datetime AS DATE) BETWEEN '#startDate#'AND '#endDate#'
JOIN person p ON p.person_id = o.person_id AND p.voided IS FALSE
JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided IS FALSE
JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired IS FALSE
JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided IS FALSE
INNER JOIN person_attribute patr ON patr.person_id = p.person_id AND patr.person_attribute_type_id = 29
JOIN encounter e ON o.encounter_id = e.encounter_id AND e.voided IS FALSE
JOIN encounter_provider ep ON ep.encounter_id = e.encounter_id
JOIN provider pro ON pro.provider_id = ep.provider_id
LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
JOIN visit v ON v.visit_id = e.visit_id AND v.voided IS FALSE
JOIN visit_type vt ON vt.visit_type_id = v.visit_type_id AND vt.retired IS FALSE
LEFT JOIN location l ON e.location_id = l.location_id AND l.retired IS FALSE
LEFT JOIN obs parent_obs ON parent_obs.obs_id = o.obs_group_id
LEFT JOIN concept_name parent_cn ON parent_cn.concept_id = parent_obs.concept_id AND parent_cn.concept_name_type = "FULLY_SPECIFIED"
LEFT JOIN concept_name coded_fscn ON coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type = "FULLY_SPECIFIED" AND coded_fscn.voided IS FALSE
LEFT JOIN concept_name coded_scn ON coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type = "SHORT" AND coded_scn.voided IS FALSE
LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided IS FALSE
LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired IS FALSE
LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided IS FALSE
LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided IS FALSE
LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided IS FALSE
WHERE o.voided IS FALSE
GROUP BY e.encounter_id;
