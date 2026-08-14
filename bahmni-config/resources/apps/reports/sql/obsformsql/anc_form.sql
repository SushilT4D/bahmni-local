 	 SELECT
	    pi.identifier AS 'Identifier',
	    patr.value as 'File Number',
	    pn.given_name                 AS 'First Name',
	    pn.family_name                 AS 'Last Name',
	    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
	    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',


	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_Location_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Location of Visit',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_No_Of_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'No of Visit',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gravida', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gravida',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Parity', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Parity',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Abortions', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Abortions',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Live_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Live Births',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Still_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Still Births',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Neonatal_Deaths', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Neonatal Deaths',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_LMP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'LMP Date',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_EDD', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'EDD Date',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Previous_Pregnancies', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Previous Pregnancies',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gestation_Date_in_Weeks', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by date',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gestation_by_fundal_height_in weeks', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by fundal height',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC-WEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_HEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Height',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_BMI', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BMI',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Systolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP: Systolic',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Diastolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP: Diastolic',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Pulse', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pulse rate',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory rate',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Fetal_Heart_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Fetal heart rate',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Pallor', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pallor',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Edema', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Edema',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_other_sign', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any other sign',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Group', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Group',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_VDRL', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'VDRL',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_HIV', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'HIV',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Urine_Albumin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Albumin',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Urine_LCE', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine LCE',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_High_risk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'High risk ?',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_Complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Complications',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_Other_Problems', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any other diagnosis',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Compliance_to_IFAMVMMCa', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Compliance to IFA/ MV-MM/ Ca',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount Received',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow-up Date',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'



	FROM obs o
	    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  
        and o.obs_group_id in (select obs_id from obs where concept_id=4145 or concept_id=4219 and voided is false)
	    and o.form_namespace_and_path IS NULL
	    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
	    
	    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
	     AND obs_fscn.name IN ('ANC_Any_Other_Problems','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name')
	    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
	    
	    JOIN person p ON p.person_id = o.person_id AND p.voided is false
	    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
	    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
	    Inner Join person_attribute patr ON patr.person_id=p.person_id and patr.person_attribute_type_id=29
	    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
	    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
	    JOIN provider pro ON pro.provider_id=ep.provider_id
	    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
	    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
	    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
	    LEFT JOIN location l ON e.location_id = l.location_id AND l.retired is false
	    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
	    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
	    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
	    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
	    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
	    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
	    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
	    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
	    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
	    WHERE o.voided is false
	    GROUP BY e.encounter_id 

 Union all

 SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',


 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Global_Location_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Location of Visit',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_No_Of_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'No of Visit',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gravida', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gravida',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Parity', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Parity',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Abortions', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Abortions',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Live_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Live Births',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Still_Births', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Still Births',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Neonatal_Deaths', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Neonatal Deaths',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_LMP', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'LMP Date',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_EDD', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'EDD Date',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Previous_Pregnancies', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Previous Pregnancies',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gestation_Date_in_Weeks', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by date',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Gestation_by_fundal_height_in weeks', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Gestation by fundal height',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC-WEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Weight',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_HEIGHT', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Height',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_BMI', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BMI',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Systolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP: Systolic',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Diastolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'BP: Diastolic',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Pulse', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pulse rate',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='RR', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Respiratory rate',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Fetal_Heart_Rate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Fetal heart rate',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Pallor', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Pallor',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Edema', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Edema',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_other_sign', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any other sign',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Group', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Group',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Blood_Sugar', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Blood Sugar',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Hemoglobin',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_VDRL', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'VDRL',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_HIV', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'HIV',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Urine_Albumin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine Albumin',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Urine_LCE', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Urine LCE',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_High_risk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'High risk ?',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_Complications', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any Complications',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Any_Other_Problems', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Any other diagnosis',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='ANC_Compliance_to_IFAMVMMCa', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Compliance to IFA/ MV-MM/ Ca',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Receipt_number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Receipt number',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Fees_Amount', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Amount Received',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_FollowUpDate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Follow-up Date',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Doctors_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Doctors Name',
 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Nurse_Name', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'Nurses Name'



FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%ANC Form%'
    and cast(o.obs_datetime AS DATE) between '#startDate#'AND '#endDate#'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN (

        'Global_Location_Visit','ANC_No_Of_Visit','ANC_Gravida','ANC_Parity','ANC_Abortions','ANC_Live_Births','ANC_Still_Births',
        'ANC_Neonatal_Deaths','ANC_LMP','ANC_EDD','ANC_Previous_Pregnancies','ANC_Gestation_Date_in_Weeks','ANC_Gestation_by_fundal_height_in weeks',
        'ANC-WEIGHT','ANC_HEIGHT','ANC_BMI','Systolic','Diastolic','Pulse','RR','ANC_SPO2','ANC_Fetal_Heart_Rate','ANC_Pallor','ANC_Edema',
        'ANC_Any_other_sign','ANC_Blood_Group','ANC_Blood_Sugar','ANC_Hemoglobin','ANC_VDRL','ANC_HIV','ANC_Urine_Albumin','ANC_Urine_LCE',
        'ANC_High_risk','ANC_Any_Complications','ANC_Any_Other_Problems','ANC_Compliance_to_IFAMVMMCa','Receipt_number','Fees_Amount',
        'GLOBAL_FollowUpDate','GLOBAL_Doctors_Name','GLOBAL_Nurse_Name'


        )
    LEFT JOIN concept_name obs_scn on o.concept_id=obs_scn.concept_id AND obs_scn.concept_name_type="SHORT" AND obs_scn.voided is false
    
    JOIN person p ON p.person_id = o.person_id AND p.voided is false
    JOIN patient_identifier pi ON p.person_id = pi.patient_id AND pi.voided is false
    JOIN patient_identifier_type pit ON pi.identifier_type = pit.patient_identifier_type_id AND pit.retired is false  JOIN person_name pn ON pn.person_id = p.person_id AND pn.voided is false
    Inner Join person_attribute patr ON patr.person_id=p.person_id and patr.person_attribute_type_id=29
    JOIN encounter e ON o.encounter_id=e.encounter_id AND e.voided is false
    JOIN encounter_provider ep ON ep.encounter_id=e.encounter_id
    JOIN provider pro ON pro.provider_id=ep.provider_id
    LEFT OUTER JOIN person_name provider_person ON provider_person.person_id = pro.person_id
    JOIN visit v ON v.visit_id=e.visit_id AND v.voided is false
    JOIN visit_type vt ON vt.visit_type_id=v.visit_type_id AND vt.retired is false
    LEFT JOIN location l ON e.location_id = l.location_id AND l.retired is false
    LEFT JOIN obs parent_obs ON parent_obs.obs_id=o.obs_group_id
    LEFT JOIN concept_name parent_cn ON parent_cn.concept_id=parent_obs.concept_id AND parent_cn.concept_name_type="FULLY_SPECIFIED"
    LEFT JOIN concept_name coded_fscn on coded_fscn.concept_id = o.value_coded AND coded_fscn.concept_name_type="FULLY_SPECIFIED" AND coded_fscn.voided is false
    LEFT JOIN concept_name coded_scn on coded_scn.concept_id = o.value_coded AND coded_scn.concept_name_type="SHORT" AND coded_scn.voided is false
    LEFT OUTER JOIN person_attribute pa ON p.person_id = pa.person_id AND pa.voided is false
    LEFT OUTER JOIN person_attribute_type pat ON pa.person_attribute_type_id = pat.person_attribute_type_id AND pat.retired is false
    LEFT OUTER JOIN concept_name scn ON pat.format = "org.openmrs.Concept" AND pa.value = scn.concept_id AND scn.concept_name_type = "SHORT" AND scn.voided is false
    LEFT OUTER JOIN concept_name fscn ON pat.format = "org.openmrs.Concept" AND pa.value = fscn.concept_id AND fscn.concept_name_type = "FULLY_SPECIFIED" AND fscn.voided is false
    LEFT OUTER JOIN person_address paddress ON p.person_id = paddress.person_id AND paddress.voided is false
    WHERE o.voided is false
    GROUP BY e.encounter_id;

