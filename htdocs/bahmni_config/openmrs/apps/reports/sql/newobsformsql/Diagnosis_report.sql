select 
    substring_index(obs.form_namespace_and_path,'.',1) "Form",
    DATE_FORMAT(obs.obs_datetime,'%d-%m-%Y')  "Date",
    pi.identifier "Patient ID", 
    concat(pnA.given_name," ", pnA.family_name) "Patient Name", 
    cn2.name AS "Visit Type",
        case when obs.concept_id in (3920,4204,5011,4568)  then cn.name end "Diagnosis",
    osub.value_numeric "Subscription Card No"
	from obs 
	join patient_identifier pi on pi.patient_id = obs.person_id and pi.preferred = 1 and pi.voided = 0
	join person_name pnA on pnA.person_id = obs.person_id and pnA.voided = 0
	join concept_name cn on cn.concept_id = obs.value_coded and cn.locale = 'en'  and cn.concept_name_type ='FULLY_SPECIFIED' and cn.voided = 0
	left join obs obs2 on obs.encounter_id = obs2.encounter_id AND substring_index(obs.form_namespace_and_path,'.',1) = substring_index(obs2.form_namespace_and_path,'.',1) and obs2.concept_id = 4837 and obs2.voided = 0
	left join obs osub on obs.encounter_id = osub.encounter_id and substring_index(obs.form_namespace_and_path,'.',1) = substring_index(osub.form_namespace_and_path,'.',1) and osub.concept_id = 5996 and osub.voided = 0
	left join concept_name cn2 on cn2.concept_id = obs2.value_coded and cn2.locale = 'en'  and cn2.concept_name_type ='SHORT' and cn2.voided = 0
	where obs.form_namespace_and_path is not null and obs.concept_id in (3920,4204,5011,4568)  and  DATE_FORMAT(obs.obs_datetime,'%Y-%m-%d') between '#startDate#' and '#endDate#' and obs.voided = 0
	order by  substring_index(obs.form_namespace_and_path,'.',1);



