select 'No of Suspected TB patients identified at clinic' as Indicator, 
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
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%Child Case Sheet%' and o.voided=0
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
			  Inner join  obs o on e.encounter_id=o.encounter_id and o.form_namespace_and_path like '%ANC Form%' and o.voided=0
			  Inner join obs obs_parent on  e.encounter_id= obs_parent.encounter_id
			  Inner JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" 
			  AND coded_fscn.voided is false and coded_fscn.name  in ('Suspected TB')
			  INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%'	

			  ) sqlquery) as Manpur

  union all

select 'No. of new patients diagnosed with TB' as Indicator,
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
	) as Manpur

 union all
   
   select  'No of new Female TB patients (%)' as Indicator,
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
INNER join location l on l.location_id=o.location_id and l.name like'%Manpur%') as Manpur

Union all
 
 select 'No of newly detected patients (%)' as Indicator, 
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
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_New_Case') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur

 Union all
 
 select 'No. of previously treated patients (%)' as Indicator, 
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
inner join concept_name cn2 on cn2.concept_id=o.value_coded and  cn2.name in ('TB_Previously_Treated') 
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur

Union all
 
 select 'No of new Extra pulmonary TB patients (%)' as Indicator, 
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
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur 

 union all




 
select 'No of TB patients who are severely underweight(%)' as Indicator, 
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
inner join concept_name cn2 on cn2.concept_id=o.concept_id and  cn2.name in ('ACS_BMI') and o.form_namespace_and_path like '%TB Intake Form%'
and cn2.concept_name_type='FULLY_SPECIFIED' and cn2.voided=0 and o.voided=0 and o.value_numeric < 16
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false 
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur
 
 union all

select 'No of TB patients from migrant households (%)' as Indicator, 
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
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and o.form_namespace_and_path like '%TB Intake Form%'
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
Inner Join person_attribute pa ON pa.person_id=p.person_id and pa.person_attribute_type_id=28
Inner join concept_name cn on cn.concept_id=pa.value and cn.concept_name_type like 'SHORT' and cn.name = 'Yes'
 INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur
  
 union all

select 'Area wise distribution of prevalence of TB (in catchment area)' as Indicator, 
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
Inner JOIN person p ON p.person_id = o.person_id AND p.voided is false and o.form_namespace_and_path like '%TB Intake Form%'
and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
inner join person_address pd on pd.person_id=p.person_id and pd.address1='Manpur' or  pd.address1= 'Budel' or pd.address1 = 'Lohagarh' 
INNER join location l on l.location_id=o.location_id and l.name like '%Manpur%')as Manpur

;