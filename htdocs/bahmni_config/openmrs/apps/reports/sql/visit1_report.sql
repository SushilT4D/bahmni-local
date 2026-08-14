
select results.Patient_Identifier AS 'Patient Identifier',
       results.File_Number AS 'File Number',
       results.Patient_Name AS 'Patient Name',
       results.Gender AS 'Gender',
       results.Age AS 'Age',
       results.Birthdate AS 'Birthdate',
       results.Registration_Date AS 'Registration Date',
       results.Visit_Date AS 'Visit Date',
       results.Location AS 'Location',
       results.status AS 'Visit Status',

 CONCAT_WS(',',CSV_FORMS, IE_FORMS ) AS 'Observation Forms'  from
(select
  pi.identifier AS 'Patient_Identifier',pi.patient_id AS 'patient_id',
  pa.value AS 'File_Number',
  CONCAT(pn.given_name, " ", COALESCE(pn.family_name, '')) AS "Patient_Name",
  p.gender AS 'Gender',
  concat(TIMESTAMPDIFF( YEAR, birthdate,v.date_started),'.',TIMESTAMPDIFF( MONTH, birthdate,p.date_created ) % 12) AS 'Age',
  DATE_FORMAT(p.birthdate, "%d-%b-%Y") AS 'Birthdate',
  DATE_FORMAT(p.date_created, "%d-%b-%Y")  AS 'Registration_Date',
  DATE_FORMAT(v.date_started, "%d-%b-%Y") AS 'Visit_Date',
  l.name AS 'Location',
  (
    select
      distinct group_concat(distinct cv.concept_short_name)
      FROM person pin
      Inner join visit vi ON vi.patient_id=pin.person_id AND vi.voided=0
      inner join encounter enc ON enc.visit_id=vi.visit_id
      inner join obs newobs ON newobs.encounter_id=enc.encounter_id
      inner join concept_view cv ON cv.concept_id=newobs.concept_id AND
      (cv.concept_full_name='Treatment_Form'
      or cv.concept_full_name='Admission_Form'
      or cv.concept_full_name='ADULT_Case_Sheet_New'
      or cv.concept_full_name='ADULT_FollowUP_from'
      or cv.concept_full_name='ANC_Obs_Form'
      or cv.concept_full_name='Care of 2 months to 5 years infant'
      or cv.concept_full_name='2MI_Child_Care'
      or cv.concept_full_name='Delivery_Obs_Form'
      or cv.concept_full_name='Immunization_Form'
      or cv.concept_full_name='Lab_Test_Obs_Form'
      or cv.concept_full_name='MTP_FollowUp_Form'
      or cv.concept_full_name='MTP_Form'
      or cv.concept_full_name='PNC_Form'
      or cv.concept_full_name='Referral_Form'
      or cv.concept_full_name='SAM_Form'
      or cv.concept_full_name='TB_Intake_Form'
      or cv.concept_full_name='TB_FollowUP_Form'
      )
      where vi.visit_id=v.visit_id AND pin.person_id=p.person_id
      group by vi.visit_id
  ) AS 'CSV_FORMS',
  (
    select
      distinct group_concat(distinct SUBSTRING(newobs.form_namespace_and_path, (POSITION('^' IN newobs.form_namespace_and_path)+1), (POSITION('.' IN newobs.form_namespace_and_path)-POSITION('^' IN newobs.form_namespace_and_path))-1))
      FROM person pin
      Inner join visit vi ON vi.patient_id=pin.person_id AND vi.voided=0
      inner join encounter enc ON enc.visit_id=vi.visit_id
      inner join obs newobs ON newobs.encounter_id=enc.encounter_id
      where vi.visit_id=v.visit_id AND pin.person_id=p.person_id
  ) AS 'IE_FORMS',
  (
    select
      case
        when count(visit_id)=1
          then "New"
          else "Follow Up"
          end
      from visit where patient_id=p.person_id group by patient_id
  ) AS 'status'

  FROM patient_identifier pi
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 
  left OUTER JOIN person_attribute pa ON pa.person_id=p.person_id AND pa.person_attribute_type_id=29
  Inner JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  Inner JOIN visit v ON v.patient_id=p.person_id AND v.voided=0 AND cast(v.date_started AS DATE) between '#startDate#'AND '#endDate#'
  Inner JOIN location l ON l.location_id=v.location_id
  group by v.visit_id
  order by v.date_started
) AS results