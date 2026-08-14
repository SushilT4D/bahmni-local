SELECT
    pi.identifier AS 'Identifier',
    patr.value as 'File Number',
    pn.given_name                 AS 'First Name',
    pn.family_name                 AS 'Last Name',
    floor(DATEDIFF(DATE(o.obs_datetime), p.birthdate) / 365)      AS 'Age',
    DATE_FORMAT(o.obs_datetime, "%d-%m-%Y") as 'Observation Date',
 	 GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Number', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS 'पि. एन. सी. नं.',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_delivery location', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'प्रसव का स्थान',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Date', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'प्रसव की तारीख',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Mother_Birth_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'जन्म के दिन वजन (कि. ग्रा.)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_How many months pregnancy', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'कितने माह का गर्भ',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Delivery_Period_In_Weeks', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'प्रसव की अवधि',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Which_Visit', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'कौनसी विजिट',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_Visit_Date', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'विजिट की तारीख',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Visit_Location', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'विजिट का स्थान',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.concept_id=4746, coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'माँ का वजन (कि. ग्रा.)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_How_are_you_feelling', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'आपको कैसा महसूस हो रहा है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_fever_to_you', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या आपको बुखार है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_there_smelly_discharge', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'PNCM_Is_there_smelly_discharge',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_there_dysuria', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या आपके पेशाब में जलन है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_there_pain_at_bottom_area', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या आपके पेट के निचले भाग में दर्द है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_there_bledding_continuously', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या आपको खून जाना जारी है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Is_there_need_to_change_morethan_5_pad', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या आपको एक दिन में 5 से अधिक PAD की जरुरत है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_from_yesterday_you_have_taken_food', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'कल से आज तक आपने क्या खाया और पिया है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Pulse_motion', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'नब्ज गति (प्रति मिनिट)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Blood_pressure', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'रक्तचाप सिस्टोलिक (mmHg)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Blood_pressure_Distolic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'रक्तचाप डायास्टोलिक (mmHg)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='breathingRate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'सांस की दर (प्रति मिनिट)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_SPO2', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'SpO2 (%)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_anemic', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'खून की कमी (आँख, जीभ, त्वचा देखने पर)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_Hemoglobin', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'हिमोग्लोबिन (gm/dL)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Temprature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'तापमान (F)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_breasts_check_nipple_flap', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'निप्पल चपटे या धँसें',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_breasts_check_nipple_cut', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'निप्पल का कटाव',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_breasts_check_pain on_thrombing_or_pressing_on_breasts', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'स्तनों पर ललाई या दबाने पर दर्द',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNCM_breasts_check_excessive_amount_of_milk', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'दूध का अत्यधिक जमाव',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Consultation_Hindi_Self_care', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'स्वयं की देखभाल, भोजन, आराम',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='Consultation_Hindi_family_planning', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'परिवार नियाजन',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_kangaroo mother care', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'कंगारू मदर केयर की सलाह',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Is need to sent to hospital', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या अस्पताल भेजने की जरुरत है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Infant_Gender', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'लिंग',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Ask Mother - do you have any problems related to the newborn', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'माँ से पूछें- क्या आपको नवजात सम्बन्धी कोई परेशानी है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Temprature', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'तापमान (F)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Birth_Weight', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'वजन (कि. ग्रा.)',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_breathingRate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'सांस प्रति मिनिट',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_See ribs', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'पसली का अत्यधिक धंसना ?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Groan', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'कराहना',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Navel is red or brittle', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'नाभि लाल या पीप है',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Rubbish-pimple On Body', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'बदन पर फोड़ी/फुंसी है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_How is the childs attachment to the breast', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'बच्चे का स्तन से लगाव कैसा है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Is the mother breastfeeding effectively', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या माँ प्रभावी ढंग से स्तनपान करा रही है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Provides only breastfeeding or other diet', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'सिर्फ स्तनपान या ऊपरी आहार भी देते है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Back abscess', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'पीठ में फोड़ा',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Lipped lips or palate', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'फटा हुआ होंठ या तालू',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Breast Feeding', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'स्तनपान',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Immunization', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'टीकाकरण',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Keep the baby warm', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'बच्चे को गर्म रखें',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Child Cleanliness & Care', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'बच्चे की साफ़ सफाई एवं देखबाल',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Danger signs', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'खतरे के लक्षण',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='PNC_C_Is need to sent to hospital', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'क्या अस्पताल भेजने की जरुरत है?',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Follow up after', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'फॉलो-अप',
     GROUP_CONCAT(DISTINCT(IF(obs_fscn.name ='GLOBAL_Name_of_nurse_or_SHW_hindi', coalesce(o.value_numeric, o.value_text, o.value_datetime, coded_scn.name, coded_fscn.name), NULL)) ORDER BY o.obs_id DESC) AS'नर्स का नाम'
 	FROM obs o
    JOIN concept obs_concept ON obs_concept.concept_id=o.concept_id AND obs_concept.retired is false  and o.form_namespace_and_path like '%PNC Form%'
    JOIN concept_name obs_fscn on o.concept_id=obs_fscn.concept_id AND obs_fscn.concept_name_type="FULLY_SPECIFIED" AND obs_fscn.voided is false
     AND obs_fscn.name IN ('PNCM_Number','GLOBAL_delivery location','PNC_C_Date','PNC_C_Mother_Birth_Weight','PNC_C_How many months pregnancy','PNC_C_Delivery_Period_In_Weeks','PNC_C_Which_Visit','PNC_Visit_Date','PNC_C_Visit_Location',
     ,'PNCM_How_are_you_feelling','PNCM_Is_fever_to_you','PNCM_Is_there_smelly_discharge','PNCM_Is_there_dysuria','PNCM_Is_there_pain_at_bottom_area','PNCM_Is_there_bledding_continuously','PNCM_Is_there_need_to_change_morethan_5_pad',
     'PNCM_from_yesterday_you_have_taken_food','Pulse_motion','PNC_Systolic_Data','PNC_Distolic_Data','breathingRate','PNC_SPO2','PNCM_anemic','PNCM_Hemoglobin','PNC_C_Temprature','PNCM_breasts_check_nipple_flap','PNCM_breasts_check_nipple_cut',
     'PNCM_breasts_check_pain on_thrombing_or_pressing_on_breasts','PNCM_breasts_check_excessive_amount_of_milk','Consultation_Hindi_Self_care','Consultation_Hindi_family_planning','PNC_C_kangaroo mother care','PNC_C_Is need to sent to hospital',
     'PNC_C_Infant_Gender','PNC_C_Ask Mother - do you have any problems related to the newborn','PNC_C_Temprature','PNC_C_Birth_Weight','GLOBAL_breathingRate','GLOBAL_See ribs','GLOBAL_Groan','PNC_C_Navel is red or brittle','PNC_C_Rubbish-pimple On Body',
     'PNC_C_How is the childs attachment to the breast','PNC_C_Is the mother breastfeeding effectively','PNC_C_Provides only breastfeeding or other diet','PNC_C_Back abscess','PNC_C_Lipped lips or palate','PNC_C_Breast Feeding','PNC_C_Immunization',
     'PNC_C_Keep the baby warm','PNC_C_Child Cleanliness & Care','PNC_C_Danger signs','PNC_C_Is need to sent to hospital','GLOBAL_Follow up after','GLOBAL_Name_of_nurse_or_SHW_hindi')
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
    GROUP BY e.encounter_id limit 2;
