select 
    substring_index(obs.form_namespace_and_path,'.',1) "Form",
    
    pi.identifier As "Patient ID",
    l.name As 'Location',
    concat(pnA.given_name," ", pnA.family_name) "Patient Name",
    p.gender AS 'Gender', 
    DATE_FORMAT(obs.obs_datetime,'%d-%m-%Y')  "Date",
    cn2.name AS "Visit Type",
        case when obs.concept_id in (3920,4204,5011,4568)  then cn.name end "Diagnosis",
        (SELECT GROUP_CONCAT(value_text SEPARATOR ', ')
     FROM obs o
     WHERE o.person_id = obs.person_id AND o.concept_id IN (5953, 5951, 5952, 5954) AND o.voided = 0) "Other-Diagnosis",
        drug.name As 'Drug Name',
        do.dose As 'Dose',
        cnf.name As 'Frequency',
        cnr.name As 'Route',
        orders.date_activated As 'Start Date',
        concat(do.duration, ' ', cndu.name) As 'Duration',
        do.quantity As 'Total Quantity'


    
    from obs 
    join patient_identifier pi on pi.patient_id = obs.person_id and pi.preferred = 1 and pi.voided = 0
    JOIN person p ON p.person_id = obs.person_id AND p.voided is false
    LEFT JOIN location l ON obs.location_id = l.location_id AND l.retired is false
    join person_name pnA on pnA.person_id = obs.person_id and pnA.voided = 0
    LEFT JOIN drug_order do on do.order_id = obs.value_coded
    JOIN drug ON drug.drug_id = do.drug_inventory_id
  AND drug.retired = FALSE
     
     JOIN order_frequency orf ON orf.order_frequency_id = do.frequency
  AND orf.retired = FALSE 
  LEFT JOIN concept_name cnf ON cnf.concept_id = orf.concept_id
  AND cnf.voided = 0
  AND cnf.concept_name_type = 'FULLY_SPECIFIED'
  AND cnf.locale = 'en'
  LEFT JOIN concept_name cnr ON cnr.concept_id = do.route
  AND cnr.voided = 0
  AND cnr.concept_name_type = 'FULLY_SPECIFIED'
  AND cnr.locale = 'en'
    JOIN orders ON orders.order_id = obs.value_coded AND orders.voided = FALSE
    LEFT JOIN concept_name cndu ON cndu.concept_id = do.duration_units AND cndu.voided = 0 AND cndu.concept_name_type = 'FULLY_SPECIFIED' AND cndu.locale = 'en'
    join concept_name cn on cn.concept_id = obs.value_coded and cn.locale = 'en'  and cn.concept_name_type ='FULLY_SPECIFIED' and cn.voided = 0
    left join obs obs2 on obs.encounter_id = obs2.encounter_id AND substring_index(obs.form_namespace_and_path,'.',1) = substring_index(obs2.form_namespace_and_path,'.',1) and obs2.concept_id = 4837 and obs2.voided = 0
    left join obs osub on obs.encounter_id = osub.encounter_id and substring_index(obs.form_namespace_and_path,'.',1) = substring_index(osub.form_namespace_and_path,'.',1) and osub.concept_id = 5996 and osub.voided = 0
    left join concept_name cn2 on cn2.concept_id = obs2.value_coded and cn2.locale = 'en'  and cn2.concept_name_type ='SHORT' and cn2.voided = 0
    where obs.form_namespace_and_path is not null and obs.concept_id in (3920,4204,5011,4568) and 
    DATE_FORMAT(obs.obs_datetime,'%Y-%m-%d') BETWEEN '#startDate#'AND '#endDate#' and obs.voided = 0
    order by  substring_index(obs.form_namespace_and_path,'.',1);