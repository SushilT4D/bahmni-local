    SELECT
        pi.identifier AS 'Identifier',
        patr.value as 'File Number',
        pn.given_name                 AS 'First Name',
        pn.family_name                 AS 'Last Name',
        floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',

    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Random_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Random Blood Sugar',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Fasting_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Fasting Blood Sugar',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_PP_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'PP Blood Sugar',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_RDK_For_MP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'RDK for MP test',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Typhoid_RDK_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Typhoid (RDK)',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_HIV', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'HIV',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_VDRL', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'VDRL',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Pregnancy_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Pregnancy test',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Leucocyte', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine leucocyte',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Nitrite', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Nitrite',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Blood', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Blood',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Sugar',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Urine_Albumin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Albumin',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Sputum_For_AFB_Test', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Sputum for AFB Test',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_OS_test_ordered', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Lab tests ordered',
    GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Lab_Test_Result', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Lab Test Results'


    FROM obs o
        JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%Lab Test Form%'
        and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
        JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
         AND obs_fscn.name IN ('Lab_Hemoglobin','Lab_Random_Blood_Sugar','Lab_Fasting_Blood_Sugar','Lab_PP_Blood_Sugar','Lab_RDK_For_MP','Lab_Typhoid_RDK_Test',	
         'Lab_HIV','Lab_VDRL','Lab_Urine_Pregnancy_Test','Lab_Urine_Leucocyte','Lab_Urine_Nitrite','Lab_Urine_Blood','Lab_Urine_Sugar','Lab_Urine_Albumin',
         'Lab_Sputum_For_AFB_Test','Lab_OS_test_ordered','Lab_Test_Result')

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
