select '1.No of Suspected TB patients identified at clinic' as Indicator, round(Tb_patient)  as Bedawal,
	(
	select round(count(distinct(Tb_patient))) as Manpur
	from (
			  SELECT distinct(pi.identifier) as Tb_patient
			  FROM patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
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
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0
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
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
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
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0
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
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Case Sheet%' and o.voided=0
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
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Adult Follow Up%' and o.voided=0 and
			  cast(v.date_created AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'
  ) sqlquery) as Bedawal_Patients

union all

select '2.No. of new patients diagnosed with TB' as Indicator, round(Tb_patient)  as Bedawal,
	(
	select round(count(distinct(pi.identifier))) as Manpur
			  from patient_identifier pi 
			  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
			  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0 
			  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
			  INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
			  Inner join encounter e on v.visit_id=e.visit_id
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
			  cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
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
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
			  cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
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
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
			  cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'        
	) as Bedawal_Patients

   union all
   
   select  '3.No of new Female TB patients (%)' as Indicator,
(select concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(select round(count(distinct(pi.identifier))) as Bedawal 
from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%')
)*100,2),')'))as Bedawal,
(select
concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(select round(count(distinct(pi.identifier))) as Manpur 
from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%')
)*100,2),')')as Manpur

from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and p.gender = 'F'
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' 
and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%') as Manpur,
(select
concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(select round(count(distinct(pi.identifier))) as Ghated 
from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%')
)*100,2),')')as Ghated

from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and p.gender = 'F'
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' 
and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%') as Ghated

from patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and p.gender = 'F'
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%TB Intake Form%' 
and o.voided=0 and
cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'

 Union all
 
 select '4.No of new CAT 1 patients (%)' as Indicator, 
 
  (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')'))as Bedwal, 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_1') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur , 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_1') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')as Ghated
  
  
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_1') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'
 
 Union all
 
 select '5.No. of new CAT 2 patients (%)' as Indicator, 
 
  (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')'))as Bedwal, 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_2') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur , 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_2') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')as Ghated
  
  
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_CAT_2') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'
 
Union all
 
 select '6.No of new Extra pulmonary TB patients (%)' as Indicator, 
 
  (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')'))as Bedwal, 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_Extrapulmonary') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur , 
  
   
(select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and o.form_namespace_and_path like '%TB Intake Form%'
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_Extrapulmonary') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')as Ghated
  
  
from obs o 
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Intake_Extrapulmonary') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'
 
 union all

 select '7.No of new TB patients with Sputum positve (%)' as Indicator,
(select concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
( SELECT count(distinct(pi.identifier)) as Tb_patienta
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Intake_Primary Site')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Intake_Pulmonary')
 ))*100,2),')')as Bedawal
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Bedawal%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Sputum_Outcome')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Sputum_Scanty','TB_Sputum_+','TB_Sputum_++','TB_Sputum_+++')) as 'Bedawal',
(select concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(SELECT count(distinct(pi.identifier)) as Tb_patienta
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Intake_Primary Site')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Intake_Pulmonary')
 ))*100,2),')')as Manpur
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Sputum_Outcome')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Sputum_Scanty','TB_Sputum_+','TB_Sputum_++','TB_Sputum_+++')) as 'Manpur',
(select concat(round(count(distinct(pi.identifier))) ,' (',round((count(distinct(pi.identifier)) / 
(SELECT count(distinct(pi.identifier)) as Tb_patienta
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0 
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Intake_Primary Site')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Intake_Pulmonary')
 ))*100,2),')')as Ghated
FROM patient_identifier pi 
JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1
INNER join visit v on v.patient_id=p.person_id AND v.voided=0
Inner join encounter e on v.visit_id=e.visit_id
Inner join  obs o on e.encounter_id=o.encounter_id 
and o.form_namespace_and_path like '%TB Intake Form%' and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
INNER join location l on l.location_id=o.location_id and l.name like'%Ghated%'
Inner JOIN concept_name cn on cn.concept_id = o.concept_id 
AND cn.concept_name_type="FULLY_SPECIFIED" 
AND cn.voided is false and cn.name  in ('TB_Sputum_Outcome')
Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded 
AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
AND coded_fscn.voided is false and coded_fscn.name  in ('TB_Sputum_Scanty','TB_Sputum_+','TB_Sputum_++','TB_Sputum_+++')) as 'Ghated'

union all

select '8.Total no of TB patients' as Indicator,round(count(distinct(o.person_id))) as Bedawal,
(select 
round(count(distinct(o.person_id))) as Manpur
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%'
 ) as Manpur,
(select 
round(count(distinct(o.person_id))) as Ghated
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%'
 ) as Ghated
 from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'


 union all

  select '9.No of female TB patients (%)' as Indicator,concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')')as Bedawal,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%') as Manpur,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%') as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and p.gender = 'F'
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'

 union all

  select  '10.No of CAT 1 patients (%)' as Indicator,concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')')as Bedawal,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_1') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%') as Manpur,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_1') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%') as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_1') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'

 union all

  select  '11.No of CAT 2 patients (%)' as Indicator,concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')')as Bedawal,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_2') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%') as Manpur,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_2') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%') as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_CAT_2') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'

 Union all
 
  select  '12.No of extra-pulmonary TB patients (%)' as Indicator,concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Bedawal 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%')
  )*100,2),')')as Bedawal,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Manpur 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')
  )*100,2),')')as Manpur
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_Extrapulmonary') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%') as Manpur,
   (select concat(round(count(distinct(o.person_id))) ,' (',round((count(distinct(o.person_id)) / 
(select round(count(distinct(o.person_id))) as Ghated 
from obs o 
inner join concept_name cn on cn.concept_id=o.concept_id and (o.form_namespace_and_path like '%TB Intake Form%' or o.form_namespace_and_path like '%TB FollowUP Form.%')
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%')
  )*100,2),')')as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_Extrapulmonary') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Ghated%') as Ghated
from obs o 
inner join concept_name cn on cn.concept_id=o.value_coded and  cn.name in ('TB_Intake_Extrapulmonary') 
and cn.concept_name_type='FULLY_SPECIFIED' and cn.voided=0 and o.voided=0
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#' 
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false
 INNER join location l on l.location_id=o.location_id and l.name like '%Bedawal%'

 
;