SELECT 
    substring_index(obs.form_namespace_and_path, '.', 1) AS "Form",
    DATE_FORMAT(obs.obs_datetime, '%d-%m-%Y') AS "Date",
    pi.identifier AS "Patient ID", 
    CONCAT(pnA.given_name, " ", pnA.family_name) AS "Patient Name", 
    p.gender AS 'Gender', 
    FLOOR(DATEDIFF(DATE(obs.obs_datetime), p.birthdate) / 365) AS 'Age',
    cn2.name AS "Visit Type",
    cn3.name AS "Location Of Visit",
    CASE WHEN obs.concept_id IN (3920, 4204, 5011, 4568) THEN cn.name END AS "Diagnosis",
    (SELECT GROUP_CONCAT(value_text SEPARATOR ', ')
     FROM obs o
     WHERE o.person_id = obs.person_id AND o.concept_id IN (5953, 5951, 5952, 5954) AND o.voided = 0) AS "Other-Diagnosis",
    osub.value_numeric AS "Subscription Card No",
    (SELECT cn.name
    FROM obs o
    join 
        concept_name cn on o.value_coded = cn.concept_id
    WHERE o.person_id = obs.person_id AND o.value_coded IN (1,2) AND o.voided = 0 and o.concept_id=61887 and cn.concept_name_type='FULLY_SPECIFIED'
    ORDER BY o.obs_datetime
    LIMIT 1) AS "Patient referred",
    cn5.name AS "Name of the referral hospital",
   (SELECT cn.name
    FROM obs o
    join 
        concept_name cn on o.value_coded = cn.concept_id
    WHERE o.person_id = obs.person_id AND o.value_coded IN (1,2) AND o.voided = 0 and o.concept_id=5994 and cn.concept_name_type='FULLY_SPECIFIED'
    ORDER BY o.obs_datetime
    LIMIT 1) AS "Patient admitted",
    (SELECT cn.name
    FROM obs o
    join 
        concept_name cn on o.value_coded = cn.concept_id
    WHERE o.person_id = obs.person_id AND o.value_coded IN (1,2) AND o.voided = 0 and o.concept_id=61867 and cn.concept_name_type='FULLY_SPECIFIED'
    ORDER BY o.obs_datetime
    LIMIT 1) AS "Consulted on call",
    obs8.value_numeric AS "Receipt number",
    obs9.value_numeric AS "Amount Received"
FROM obs
JOIN patient_identifier pi ON pi.patient_id = obs.person_id AND pi.preferred = 1 AND pi.voided = 0
JOIN person_name pnA ON pnA.person_id = obs.person_id AND pnA.voided = 0
JOIN person p ON p.person_id = obs.person_id AND p.voided = 0
JOIN concept_name cn ON cn.concept_id = obs.value_coded AND cn.locale = 'en' AND cn.concept_name_type = 'FULLY_SPECIFIED' AND cn.voided = 0
LEFT JOIN obs obs2 ON obs.encounter_id = obs2.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs2.form_namespace_and_path, '.', 1) AND obs2.concept_id = 4837 AND obs2.voided = 0
LEFT JOIN obs osub ON obs.encounter_id = osub.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(osub.form_namespace_and_path, '.', 1) AND osub.concept_id = 5996 AND osub.voided = 0
LEFT JOIN obs obs3 ON obs.encounter_id = obs3.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs3.form_namespace_and_path, '.', 1) AND obs3.concept_id = 61862 AND obs3.voided = 0
LEFT JOIN obs obs4 ON obs.encounter_id = obs4.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs4.form_namespace_and_path, '.', 1) AND obs4.concept_id = 61887 AND obs4.voided = 0
LEFT JOIN obs obs5 ON obs.encounter_id = obs5.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs5.form_namespace_and_path, '.', 1) AND obs5.concept_id = 4264 AND obs5.voided = 0
LEFT JOIN obs obs6 ON obs.encounter_id = obs6.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs6.form_namespace_and_path, '.', 1) AND obs6.concept_id = 5994 AND obs6.voided = 0
LEFT JOIN obs obs7 ON obs.encounter_id = obs7.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs7.form_namespace_and_path, '.', 1) AND obs7.concept_id = 61867 AND obs7.voided = 0
LEFT JOIN obs obs8 ON obs.encounter_id = obs8.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs8.form_namespace_and_path, '.', 1) AND obs8.concept_id = 3922 AND obs8.voided = 0
LEFT JOIN obs obs9 ON obs.encounter_id = obs9.encounter_id AND substring_index(obs.form_namespace_and_path, '.', 1) = substring_index(obs9.form_namespace_and_path, '.', 1) AND obs9.concept_id = 3923 AND obs9.voided = 0
LEFT JOIN concept_name cn2 ON cn2.concept_id = obs2.value_coded AND cn2.locale = 'en' AND cn2.concept_name_type = 'SHORT' AND cn2.voided = 0
LEFT JOIN concept_name cn3 ON cn3.concept_id = obs3.value_coded AND cn3.locale = 'en' AND cn3.concept_name_type = 'SHORT' AND cn3.voided = 0
LEFT JOIN concept_name cn4 ON cn4.concept_id = obs4.value_coded AND cn4.locale = 'en' AND cn4.concept_name_type = 'SHORT' AND cn4.voided = 0
LEFT JOIN concept_name cn5 ON cn5.concept_id = obs5.value_coded AND cn5.locale = 'en' AND cn5.concept_name_type = 'SHORT' AND cn5.voided = 0
LEFT JOIN concept_name cn6 ON cn6.concept_id = obs6.value_coded AND cn6.locale = 'en' AND cn6.concept_name_type = 'SHORT' AND cn6.voided = 0
LEFT JOIN concept_name cn7 ON cn7.concept_id = obs7.value_coded AND cn7.locale = 'en' AND cn7.concept_name_type = 'SHORT' AND cn7.voided = 0
LEFT JOIN concept_name cn8 ON cn8.concept_id = obs8.value_coded AND cn8.locale = 'en' AND cn8.concept_name_type = 'SHORT' AND cn8.voided = 0 And cn8.concept_id = 3922
LEFT JOIN concept_name cn9 ON cn9.concept_id = obs9.value_coded AND cn9.locale = 'en' AND cn9.concept_name_type = 'SHORT' AND cn9.voided = 0 And cn8.concept_id = 3923
WHERE obs.form_namespace_and_path IS NOT NULL
AND obs.concept_id IN (3920, 4204, 5011, 4568) 
AND DATE_FORMAT(obs.obs_datetime, '%Y-%m-%d') BETWEEN '#startDate#'AND '#endDate#'
AND obs.voided = 0 
ORDER BY substring_index(obs.form_namespace_and_path, '.', 1);
 
