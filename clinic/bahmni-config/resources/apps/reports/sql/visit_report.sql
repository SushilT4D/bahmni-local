SELECT results.Patient_Identifier AS 'Patient Identifier',
       results.File_Number AS 'File Number',
       results.Patient_Name AS 'Patient Name',
       results.Gender AS 'Gender',
       results.Age AS 'Age',
       results.Birthdate AS 'Birthdate',
       results.Registration_Date AS 'Registration Date',
       results.Visit_Date AS 'Visit Date',
       results.Location AS 'Location',
       results.status AS 'Visit Status',
       results.Catchment_Area AS 'Catchment Area',
       results.Occupation AS 'Occupation',
       results.state AS 'state',
       results.District AS 'District',
       results.Tehsil AS 'Tehsil',
       results.Panchyat AS 'Panchyat',
       results.Village AS 'Village',
       results.Hamlet  as 'Hamlet (Fala)',
       results.Migrant AS 'Migrant',
       results.Form_Visit_Type AS 'Form Visit Type',
       results.Form_Location AS 'Form Location',
       CONCAT_WS(',', CSV_FORMS, IE_FORMS) AS 'Observation Forms'
FROM (
    SELECT
        pi.identifier AS 'Patient_Identifier',
        pi.patient_id AS 'patient_id',
        pa.value AS 'File_Number',
        (
            SELECT cn.name
            FROM concept_name cn
            JOIN person_attribute pa ON cn.concept_id = pa.value
            WHERE pa.person_attribute_type_id = 31
            AND pa.person_id = p.person_id and cn.concept_name_type='SHORT'
            LIMIT 1 
        ) AS 'Catchment_Area',
        paddress.state_province AS 'State',
        paddress.country AS 'District',
        paddress.Address2 AS 'Tehsil',
        paddress.address1 AS 'Panchyat',
        paddress.city_village AS 'Village',
        paddress.postal_code  As 'Hamlet',
        (
            SELECT cn.name
            FROM concept_name cn
            JOIN person_attribute pa ON cn.concept_id = pa.value
            WHERE pa.person_attribute_type_id = 14
            AND pa.person_id = p.person_id and cn.concept_name_type='SHORT'
            LIMIT 1 
        ) AS 'Occupation',
        cn.name AS 'Visit_Type',
        CONCAT(pn.given_name, " ", COALESCE(pn.family_name, '')) AS "Patient_Name",
        p.gender AS 'Gender',
        CONCAT(TIMESTAMPDIFF(YEAR, birthdate, v.date_started), '.', TIMESTAMPDIFF(MONTH, birthdate, p.date_created) % 12) AS 'Age',
        DATE_FORMAT(p.birthdate, "%d-%b-%Y") AS 'Birthdate',
        DATE_FORMAT(p.date_created, "%d-%b-%Y") AS 'Registration_Date',
        DATE_FORMAT(v.date_started, "%d-%b-%Y") AS 'Visit_Date',
        l.name AS 'Location',
        (
            SELECT DISTINCT GROUP_CONCAT(DISTINCT cv.concept_short_name)
            FROM person pin
            INNER JOIN visit vi ON vi.patient_id = pin.person_id AND vi.voided = 0
            INNER JOIN encounter enc ON enc.visit_id = vi.visit_id
            INNER JOIN obs newobs ON newobs.encounter_id = enc.encounter_id
            INNER JOIN concept_view cv ON cv.concept_id = newobs.concept_id
            WHERE vi.visit_id = v.visit_id AND pin.person_id = p.person_id
              AND cv.concept_full_name IN (
                'Treatment_Form', 'Admission_Form', 'ADULT_Case_Sheet_New',
                'ADULT_FollowUP_from', 'ANC_Obs_Form', 'Care of 2 months to 5 years infant',
                '2MI_Child_Care', 'Delivery_Obs_Form', 'Immunization_Form',
                'Lab_Test_Obs_Form', 'MTP_FollowUp_Form', 'MTP_Form', 'PNC_Form',
                'Referral_Form', 'SAM_Form', 'TB_Intake_Form', 'TB_FollowUP_Form'
              )
            GROUP BY vi.visit_id
        ) AS 'CSV_FORMS',
        (
            SELECT DISTINCT GROUP_CONCAT(DISTINCT SUBSTRING(newobs.form_namespace_and_path,
                (POSITION('^' IN newobs.form_namespace_and_path) + 1),
                (POSITION('.' IN newobs.form_namespace_and_path) - POSITION('^' IN newobs.form_namespace_and_path)) - 1))
            FROM person pin
            INNER JOIN visit vi ON vi.patient_id = pin.person_id AND vi.voided = 0
            INNER JOIN encounter enc ON enc.visit_id = vi.visit_id
            INNER JOIN obs newobs ON newobs.encounter_id = enc.encounter_id
            WHERE vi.visit_id = v.visit_id AND pin.person_id = p.person_id
        ) AS 'IE_FORMS',
        (
            SELECT CASE
                WHEN COUNT(visit_id) = 1 THEN "New"
                ELSE "Follow Up"
            END
            FROM visit WHERE patient_id = p.person_id GROUP BY patient_id
        ) AS 'status',
        (SELECT cn.name
     FROM obs o
     join 
        concept_name cn on o.value_coded = cn.concept_id
     WHERE o.person_id = p.person_id AND o.value_coded IN (4834,4835,4836) AND o.voided = 0 and o.concept_id=4837 and cn.concept_name_type='FULLY_SPECIFIED' LIMIT 1) AS 'Form_Visit_Type',
        (SELECT cn.name
     FROM obs o
     join 
        concept_name cn on o.value_coded = cn.concept_id
     WHERE o.person_id = p.person_id AND o.value_coded IN (4727,4725,4744,61863) AND o.voided = 0 and o.concept_id=61862 and cn.concept_name_type='SHORT' LIMIT 1) AS 'Form_location',
     (
            SELECT cn.name
            FROM concept_name cn
            JOIN person_attribute pa ON cn.concept_id = pa.value
            WHERE pa.person_attribute_type_id = 28
            AND pa.person_id = p.person_id and cn.concept_name_type='SHORT'
            LIMIT 1 
        ) As 'Migrant'
    FROM patient_identifier pi
    JOIN person p ON p.person_id = pi.patient_id AND pi.voided = 0 AND pi.preferred = 1
    LEFT JOIN person_attribute pa ON pa.person_id = p.person_id AND pa.person_attribute_type_id = 29
    LEFT JOIN person_attribute ptr ON ptr.person_id = p.person_id AND ptr.person_attribute_type_id = 14
    LEFT JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided IS FALSE
    LEFT JOIN concept_name cn ON cn.concept_id = pi.patient_identifier_id AND cn.locale = 'en' AND cn.concept_name_type = 'SHORT' AND cn.voided = 0
    INNER JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided = 0
    INNER JOIN visit v ON v.patient_id = p.person_id AND v.voided = 0 AND CAST(v.date_started AS DATE) BETWEEN '#startDate#'AND '#endDate#'
    JOIN encounter enc ON enc.visit_id = v.visit_id
    LEFT JOIN obs obs1 ON enc.encounter_id = obs1.encounter_id AND obs1.concept_id = 4837 AND obs1.voided = 0
    LEFT JOIN concept_name cn1 ON cn1.concept_id = obs1.value_coded AND cn1.locale = 'en' AND cn1.concept_name_type = 'SHORT' AND cn1.voided = 0
    LEFT JOIN obs obs2 ON enc.encounter_id = obs2.encounter_id AND obs2.concept_id = 61862 AND obs2.voided = 0
    LEFT JOIN concept_name cn2 ON cn2.concept_id = obs2.value_coded AND cn2.locale = 'en' AND cn2.concept_name_type = 'SHORT' AND cn2.voided = 0
    LEFT JOIN obs obs3 ON enc.encounter_id = obs3.encounter_id AND obs3.concept_id IN (61865, 61864) AND obs3.voided = 0
    INNER JOIN location l ON l.location_id = v.location_id
    LEFT JOIN visit_type vt ON vt.visit_type_id = pi.patient_identifier_id
    GROUP BY v.visit_id 
    ORDER BY v.date_started
) AS results
;
