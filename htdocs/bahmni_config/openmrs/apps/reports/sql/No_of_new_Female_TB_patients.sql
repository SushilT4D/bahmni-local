select * from 
(select  count(O.person_id) as Suspected_TB_Female_Patients from obs O
inner join concept_name CN on O.concept_id=CN.concept_id and CN.voided=0 and O.voided=0
inner join person P on P.person_id=O.person_id and P.gender='F' and P.voided=0
where CN.name like '%TB_Intake_Form%' and CN.concept_name_type like'%FULLY_SPECIFIED%' AND cast(O.obs_datetime AS DATE) between '#startDate#'AND '#endDate#')Suspected_TB_Female_Patients,
(select count(person_id)  as Suspected_TB_Patient from obs o inner join concept_name CN on o.concept_id=CN.concept_id and CN.voided=0 and o.voided=0
where CN.name like '%TB_Intake_Form%' and CN.concept_name_type like'%FULLY_SPECIFIED%' AND cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#') as Suspected_TB_Patients;

