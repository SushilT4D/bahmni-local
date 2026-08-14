select 'No of Suspected TB patients identified at clinic' as Indicator, round(Tb_patient)  as Bedawal,
	(
	select round(count(distinct(Tb_patient))) as Manpur
	from (
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%' 			
       union
              SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%'
			  ) sqlquery) as Manpur,
    (
	
	select round(count(distinct(Tb_patient))) as Ghated
	from (
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%' 
           Union
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%'
			  )sqlquery) as Ghated
			from
		(
		select 
		count(distinct(Tb_patient)) as Tb_patient
		from (
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'        
       union
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'
  ) sqlquery) as Bedawal_Patients
  
   Union all

   select 'No. of new patients diagnosed with TB' as Indicator, round(Tb_patient)  as Bedawal,
	(
	select round(count(distinct(pi.identifier))) as Manpur
			  from patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%'
	) as Manpur,
    (
	select round(count(distinct(pi.identifier))) as Ghated
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%' 
    ) as Ghated
			from
	(
	select round(count(distinct(pi.identifier))) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
			  and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'        
	) as Bedawal_Patients

Union all

select 'No of new Female TB patients (%)' as Indicator, 
 
  (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')'))as Bedwal, 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0

Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur , 
 and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')as Ghated
  
  
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and  cn.name in ('TB_Intake_Form') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'
 ;