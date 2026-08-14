Select Distinct
     concat(pi.identifier , '')                                      AS 'Patient Identifier',
     concat(pn.given_name, ' ', ifnull(pn.family_name, ''))          AS 'Patient Name', 
     cast(obs.value_datetime AS DATE)                             AS 'Follow Up Date',
     ifnull(obs_reason.value_text, '')                                      AS 'Follow Up Reason',
     pa.value                                                        AS 'Phone Number' 
     FROM  obs
     join person_name pn on pn.person_id = obs.person_id
     join patient_identifier pi on pi.patient_id = pn.person_id AND pi.voided = 0
     left join obs obs_reason on obs_reason.encounter_id = obs.encounter_id and obs_reason.voided = 0 and obs_reason.concept_id =(select concept_id from concept_name cn1 where 'Reason for visit (text)' = cn1.name 
 and cn1.concept_name_type = "FULLY_SPECIFIED" and cn1.voided=0) and obs.voided=0
     join person_attribute pa on pa.person_id = pn.person_id and pa.person_attribute_type_id = (
          select person_attribute_type_id from person_attribute_type cn1 where cn1.name="phoneNumber" and cn1.retired=0)
     where obs.voided = 0 and obs.concept_id = (select concept_id from concept_name cn1 where 'Return visit date' = cn1.name 
 and cn1.concept_name_type = "FULLY_SPECIFIED" and cn1.voided=0) and cast(CONVERT_TZ(obs.value_datetime,'+00:00','+5:30') AS DATE) BETWEEN '#startDate#' AND '#endDate#';
