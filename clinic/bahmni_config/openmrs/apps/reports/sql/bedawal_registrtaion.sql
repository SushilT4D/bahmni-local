SELECT  pi.identifier AS 'Patient Identifier',
  pa.value as 'File Number',
  pn.given_name                    AS 'First Name',
  pn.family_name                    AS 'Last Name',
  p.date_created AS 'Registration_Date',
  p.gender as 'Gender', 
  DATE_FORMAT(p.birthdate, "%d-%b-%Y")                          AS 'Birthdate',
  concat(TIMESTAMPDIFF( YEAR, birthdate,p.date_created),'.',TIMESTAMPDIFF( MONTH, birthdate,p.date_created ) % 12) AS 'Age',
  paddress.state_province as 'State',
  paddress.country as 'District' , 
  paddress.Address2 as 'Tehsil' ,
  paddress.address1 as 'Panchyat' , 
  paddress.city_village as 'Village',
  paddress.postal_code  as 'Hamlet (Fala)' , 
  cn1.name as 'Caste',
  ptr2.value as 'Mobile No',
  ptr3.value as 'Mother Name',
  cn.name as 'Migrant',
  'Bedawal' as 'Location'
  FROM patient_identifier pi
  JOIN person p ON p.person_id = pi.patient_id AND pi.voided=0 AND pi.preferred=1 and pi.identifier like '%BED%'
  LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided=0
  LEFT JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided=0
  Inner Join person_attribute pa ON pa.person_id=p.person_id and pa.person_attribute_type_id=29
  Left outer join  person_attribute ptr on ptr.person_id=p.person_id and ptr.person_attribute_type_id=28
  Inner join concept_name cn on cn.concept_id=ptr.value and cn.concept_name_type like 'SHORT'
  Left outer join  person_attribute ptr1 on ptr1.person_id=p.person_id and ptr1.person_attribute_type_id=11
  Inner join concept_name cn1 on cn1.concept_id=ptr1.value and cn1.concept_name_type like 'SHORT'
  Left outer join  person_attribute ptr2 on ptr2.person_id=p.person_id and ptr2.person_attribute_type_id=15
  Left outer join  person_attribute ptr3 on ptr3.person_id=p.person_id and ptr3.person_attribute_type_id=27
  where cast(p.date_created AS DATE) between '#startDate#'AND '#endDate#'
  order by pi.identifier ;
