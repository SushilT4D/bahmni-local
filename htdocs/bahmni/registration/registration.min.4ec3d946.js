'use strict';

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};

(function () {
    var hostUrl = localStorage.getItem('host') ? ("https://" + localStorage.getItem('host')) : "";
    var rootDir = localStorage.getItem('rootDir') || "";
    var RESTWS = hostUrl + "/openmrs/ws/rest";
    var RESTWS_V1 = hostUrl + "/openmrs/ws/rest/v1";
    var BAHMNI_CORE = RESTWS_V1 + "/bahmnicore";
    var BAHMNI_COMMONS = RESTWS_V1 + "/bahmni";
    var EMRAPI = RESTWS + "/emrapi";
    var BACTERIOLOGY = RESTWS_V1;
    var BASE_URL = hostUrl + "/bahmni_config/openmrs/apps/";
    var CUSTOM_URL = hostUrl + "/implementation_config/openmrs/apps/";
    var IE_APPS_API = RESTWS_V1 + "/bahmniie";
    var IPD = RESTWS_V1 + "/ipd";
    var FHIR_BASE_URL = hostUrl + "/openmrs/ws/fhir2/R4";

    var serverErrorMessages = [
        {
            serverMessage: "Cannot have more than one active order for the same orderable and care setting at same time",
            clientMessage: "One or more drugs you are trying to order are already active. Please change the start date of the conflicting drug or remove them from the new prescription."
        },
        {
            serverMessage: "[Order.cannot.have.more.than.one]",
            clientMessage: "One or more drugs you are trying to order are already active. Please change the start date of the conflicting drug or remove them from the new prescription."
        }
    ];

    var representation = "custom:(uuid,name,names,conceptClass," +
        "setMembers:(uuid,name,names,conceptClass," +
        "setMembers:(uuid,name,names,conceptClass," +
        "setMembers:(uuid,name,names,conceptClass))))";

    var unAuthenticatedReferenceDataMap = {
        "/openmrs/ws/rest/v1/location?tags=Login+Location&s=byTags&v=default": "LoginLocations",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=locale.allowed.list": "LocaleList"
    };

    var authenticatedReferenceDataMap = {
        "/openmrs/ws/rest/v1/idgen/identifiertype": "IdentifierTypes",
        "/openmrs/module/addresshierarchy/ajax/getOrderedAddressHierarchyLevels.form": "AddressHierarchyLevels",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=mrs.genders": "Genders",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=bahmni.encountersession.duration": "encounterSessionDuration",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=bahmni.relationshipTypeMap": "RelationshipTypeMap",
        "/openmrs/ws/rest/v1/bahmnicore/config/bahmniencounter?callerContext=REGISTRATION_CONCEPTS": "RegistrationConcepts",
        "/openmrs/ws/rest/v1/relationshiptype?v=custom:(aIsToB,bIsToA,uuid)": "RelationshipType",
        "/openmrs/ws/rest/v1/personattributetype?v=custom:(uuid,name,sortWeight,description,format,concept)": "PersonAttributeType",
        "/openmrs/ws/rest/v1/entitymapping?mappingType=loginlocation_visittype&s=byEntityAndMappingType": "LoginLocationToVisitTypeMapping",
        "/openmrs/ws/rest/v1/bahmnicore/config/patient": "PatientConfig",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Consultation+Note&v=custom:(uuid,name,answers)": "ConsultationNote",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Lab+Order+Notes&v=custom:(uuid,name)": "LabOrderNotes",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Impression&v=custom:(uuid,name)": "RadiologyImpressionConfig",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=All_Tests_and_Panels&v=custom:(uuid,name:(uuid,name),setMembers:(uuid,name:(uuid,name)))": "AllTestsAndPanelsConcept",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Dosage+Frequency&v=custom:(uuid,name,answers)": "DosageFrequencyConfig",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Dosage+Instructions&v=custom:(uuid,name,answers)": "DosageInstructionConfig",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=bahmni.encounterType.default": "DefaultEncounterType",
        "/openmrs/ws/rest/v1/concept?s=byFullySpecifiedName&name=Stopped+Order+Reason&v=custom:(uuid,name,answers)": "StoppedOrderReasonConfig",
        "/openmrs/ws/rest/v1/ordertype": "OrderType",
        "/openmrs/ws/rest/v1/bahmnicore/config/drugOrders": "DrugOrderConfig",
        "/openmrs/ws/rest/v1/bahmnicore/sql/globalproperty?property=drugOrder.drugOther": "NonCodedDrugConcept"
    };

    authenticatedReferenceDataMap["/openmrs/ws/rest/v1/entitymapping?mappingType=location_encountertype&s=byEntityAndMappingType&entityUuid=" + (localStorage.getItem("LoginInformation") ? JSON.parse(localStorage.getItem("LoginInformation")).currentLocation.uuid : "")] = "LoginLocationToEncounterTypeMapping";

    Bahmni.Common.Constants = {
        hostURL: hostUrl,
        dateFormat: "dd/mm/yyyy",
        dateDisplayFormat: "DD-MMM-YYYY",
        timeDisplayFormat: "hh:mm",
        clientTimeDisplayFormat: "h:mm a",
        clientDateDisplayFormat: "DD MMM YYYY",
        emrapiDiagnosisUrl: EMRAPI + "/diagnosis",
        bahmniDiagnosisUrl: BAHMNI_CORE + "/diagnosis/search",
        emrapiDiagnosisLimit: Bahmni.Common.Constants && Bahmni.Common.Constants.emrapiDiagnosisLimit || 20,
        bahmniDeleteDiagnosisUrl: BAHMNI_CORE + "/diagnosis/delete",
        diseaseTemplateUrl: BAHMNI_CORE + "/diseaseTemplates",
        AllDiseaseTemplateUrl: BAHMNI_CORE + "/diseaseTemplate",
        emrapiConceptUrl: EMRAPI + "/concept",
        bahmniapiConceptUrl: BAHMNI_COMMONS + "/terminologies/concepts",
        encounterConfigurationUrl: BAHMNI_CORE + "/config/bahmniencounter",
        patientConfigurationUrl: BAHMNI_CORE + "/config/patient",
        drugOrderConfigurationUrl: BAHMNI_CORE + "/config/drugOrders",
        emrEncounterUrl: EMRAPI + "/encounter",
        encounterUrl: RESTWS_V1 + "/encounter",
        cdssUrl: RESTWS_V1 + "/cdss",
        fhirExportPrivilege: "Export Patient Data",
        plainFhirExportPrivilege: "Export Non Anonymised Patient Data",
        fhirExportUrl: RESTWS_V1 + "/fhirexport",
        fhirTasks: FHIR_BASE_URL + "/Task",
        fhirMedicationsUrl: FHIR_BASE_URL + "/Medication",
        locationUrl: RESTWS_V1 + "/location",
        bahmniVisitLocationUrl: BAHMNI_CORE + "/visitLocation",
        bahmniFacilityLocationUrl: BAHMNI_CORE + "/facilityLocation",
        bahmniOrderUrl: BAHMNI_CORE + "/orders",
        bahmniDrugOrderUrl: BAHMNI_CORE + "/drugOrders",
        bahmniDispositionByVisitUrl: BAHMNI_CORE + "/disposition/visitWithLocale",
        bahmniDispositionByPatientUrl: BAHMNI_CORE + "/disposition/patientWithLocale",
        bahmniSearchUrl: BAHMNI_CORE + "/search",
        bahmniCommonsSearchUrl: BAHMNI_COMMONS + "/search",
        bahmniCommonsPatientSearchUrl: BAHMNI_CORE + "/distro",
        bahmniLabOrderResultsUrl: BAHMNI_CORE + "/labOrderResults",
        bahmniEncounterUrl: BAHMNI_CORE + "/distro/bahmniencounter",
        conceptUrl: RESTWS_V1 + "/concept",
        bahmniConceptAnswerUrl: RESTWS_V1 + "/bahmniconceptanswer",
        conceptSearchByFullNameUrl: RESTWS_V1 + "/concept?s=byFullySpecifiedName",
        visitUrl: RESTWS_V1 + "/visit",
        endVisitUrl: BAHMNI_CORE + "/visit/endVisit",
        endVisitAndCreateEncounterUrl: BAHMNI_CORE + "/visit/endVisitAndCreateEncounter",
        visitTypeUrl: RESTWS_V1 + "/visittype",
        patientImageUrlByPatientUuid: RESTWS_V1 + "/patientImage?patientUuid=",
        labResultUploadedFileNameUrl: "/uploaded_results/",
        visitSummaryUrl: BAHMNI_CORE + "/visit/summary",
        encounterModifierUrl: BAHMNI_CORE + "/bahmniencountermodifier",
        openmrsUrl: hostUrl + "/openmrs",
        loggingUrl: hostUrl + "/log/",
        idgenConfigurationURL: RESTWS_V1 + "/idgen/identifiertype",
        bahmniRESTBaseURL: BAHMNI_CORE + "",
        observationsUrl: BAHMNI_CORE + "/observations",
        obsRelationshipUrl: BAHMNI_CORE + "/obsrelationships",
        encounterImportUrl: BAHMNI_CORE + "/admin/upload/encounter",
        form2encounterImportUrl: BAHMNI_CORE + "/admin/upload/form2encounter",
        programImportUrl: BAHMNI_CORE + "/admin/upload/program",
        conceptImportUrl: BAHMNI_CORE + "/admin/upload/concept",
        conceptSetImportUrl: BAHMNI_CORE + "/admin/upload/conceptset",
        drugImportUrl: BAHMNI_CORE + "/admin/upload/drug",
        labResultsImportUrl: BAHMNI_CORE + "/admin/upload/labResults",
        referenceTermsImportUrl: BAHMNI_CORE + "/admin/upload/referenceterms",
        updateReferenceTermsImportUrl: BAHMNI_CORE + "/admin/upload/referenceterms/new",
        relationshipImportUrl: BAHMNI_CORE + "/admin/upload/relationship",
        conceptSetExportUrl: BAHMNI_CORE + "/admin/export/conceptset?conceptName=:conceptName",
        patientImportUrl: BAHMNI_CORE + "/admin/upload/patient",
        adminImportStatusUrl: BAHMNI_CORE + "/admin/upload/status",
        programUrl: RESTWS_V1 + "/program",
        programEnrollPatientUrl: RESTWS_V1 + "/bahmniprogramenrollment",
        programStateDeletionUrl: RESTWS_V1 + "/programenrollment",
        programEnrollmentDefaultInformation: "default",
        programEnrollmentFullInformation: "full",
        programAttributeTypes: RESTWS_V1 + "/programattributetype",
        relationshipTypesUrl: RESTWS_V1 + "/relationshiptype",
        personAttributeTypeUrl: RESTWS_V1 + "/personattributetype",
        diseaseSummaryPivotUrl: BAHMNI_CORE + "/diseaseSummaryData",
        allTestsAndPanelsConceptName: 'All_Tests_and_Panels',
        dosageFrequencyConceptName: 'Dosage Frequency',
        dosageInstructionConceptName: 'Dosage Instructions',
        stoppedOrderReasonConceptName: 'Stopped Order Reason',
        consultationNoteConceptName: 'Consultation Note',
        diagnosisConceptSet: 'Diagnosis Concept Set',
        radiologyOrderType: 'Radiology Order',
        radiologyResultConceptName: "Radiology Result",
        investigationEncounterType: "INVESTIGATION",
        validationNotesEncounterType: "VALIDATION NOTES",
        labOrderNotesConcept: "Lab Order Notes",
        impressionConcept: "Impression",
        qualifiedByRelationshipType: "qualified-by",
        dispositionConcept: "Disposition",
        dispositionGroupConcept: "Disposition Set",
        dispositionNoteConcept: "Disposition Note",
        ruledOutDiagnosisConceptName: 'Ruled Out Diagnosis',
        emrapiConceptMappingSource: "org.openmrs.module.emrapi",
        abbreviationConceptMappingSource: "Abbreviation",
        includeAllObservations: false,
        openmrsObsUrl: RESTWS_V1 + "/obs",
        openmrsObsRepresentation: "custom:(uuid,obsDatetime,value:(uuid,name:(uuid,name)))",
        admissionCode: 'ADMIT',
        dischargeCode: 'DISCHARGE',
        transferCode: 'TRANSFER',
        undoDischargeCode: 'UNDO_DISCHARGE',
        vitalsConceptName: "Vitals",
        heightConceptName: "HEIGHT",
        weightConceptName: "WEIGHT",
        bmiConceptName: "BMI", // TODO : shruthi : revove this when this logic moved to server side
        bmiStatusConceptName: "BMI STATUS", // TODO : shruthi : revove this when this logic moved to server side
        abnormalObservationConceptName: "IS_ABNORMAL",
        documentsPath: '/document_images',
        documentsConceptName: 'Document',
        miscConceptClassName: 'Misc',
        abnormalConceptClassName: 'Abnormal',
        unknownConceptClassName: 'Unknown',
        durationConceptClassName: 'Duration',
        conceptDetailsClassName: 'Concept Details',
        admissionEncounterTypeName: 'ADMISSION',
        dischargeEncounterTypeName: 'DISCHARGE',
        imageClassName: 'Image',
        videoClassName: 'Video',
        locationCookieName: 'bahmni.user.location',
        retrospectiveEntryEncounterDateCookieName: 'bahmni.clinical.retrospectiveEncounterDate',
        JSESSIONID: "JSESSIONID",
        rootScopeRetrospectiveEntry: 'retrospectiveEntry.encounterDate',
        patientFileConceptName: 'Patient file',
        serverErrorMessages: serverErrorMessages,
        currentUser: 'bahmni.user',
        retrospectivePrivilege: 'app:clinical:retrospective',
        locationPickerPrivilege: 'app:clinical:locationpicker',
        onBehalfOfPrivilege: 'app:clinical:onbehalf',
        nutritionalConceptName: 'Nutritional Values',
        messageForNoObservation: "NO_OBSERVATIONS_CAPTURED",
        messageForNoDisposition: "NO_DISPOSTIONS_AVAILABLE_MESSAGE_KEY",
        messageForNoFulfillment: "NO_FULFILMENT_MESSAGE",
        reportsUrl: "/bahmnireports",
        uploadReportTemplateUrl: "/bahmnireports/upload",
        ruledOutdiagnosisStatus: "Ruled Out Diagnosis",
        registartionConsultationPrivilege: 'app:common:registration_consultation_link',
        manageIdentifierSequencePrivilege: "Manage Identifier Sequence",
        closeVisitPrivilege: 'app:common:closeVisit',
        deleteDiagnosisPrivilege: 'app:clinical:deleteDiagnosis',
        viewPatientsPrivilege: 'View Patients',
        editPatientsPrivilege: 'Edit Patients',
        addVisitsPrivilege: 'Add Visits',
        deleteVisitsPrivilege: 'Delete Visits',
        grantProviderAccess: "app:clinical:grantProviderAccess",
        grantProviderAccessDataCookieName: "app.clinical.grantProviderAccessData",
        globalPropertyUrl: BAHMNI_CORE + "/sql/globalproperty",
        passwordPolicyUrl: BAHMNI_CORE + "/globalProperty/passwordPolicyProperties",
        fulfillmentConfiguration: "fulfillment",
        fulfillmentFormSuffix: " Fulfillment Form",
        noNavigationLinksMessage: "NO_NAVIGATION_LINKS_AVAILABLE_MESSAGE",
        conceptSetRepresentationForOrderFulfillmentConfig: representation,
        entityMappingUrl: RESTWS_V1 + "/entitymapping",
        encounterTypeUrl: RESTWS_V1 + "/encountertype",
        defaultExtensionName: "default",
        orderSetMemberAttributeTypeUrl: RESTWS_V1 + "/ordersetmemberattributetype",
        orderSetUrl: RESTWS_V1 + "/bahmniorderset",
        storageUrl: hostUrl + "/storage/container/",
        contactURL: "support@iplit.in",
        salesURL: "sales@iplit.in",
        primaryOrderSetMemberAttributeTypeName: "Primary",
        bahmniBacteriologyResultsUrl: BACTERIOLOGY + "/specimen",
        bedFromVisit: RESTWS_V1 + "/beds",
        sendViaEmailUrl: RESTWS_V1 + "/patient/{{patientUuid}}/send/email",
        ordersUrl: RESTWS_V1 + "/order",
        formDataUrl: RESTWS_V1 + "/obs",
        providerUrl: RESTWS_V1 + "/provider",
        providerAttributeUrl: RESTWS_V1 + "/provider/{{providerUuid}}/attribute",
        drugUrl: RESTWS_V1 + "/drug",
        orderTypeUrl: RESTWS_V1 + "/ordertype",
        userUrl: RESTWS_V1 + "/user",
        passwordUrl: RESTWS_V1 + "/password",
        formUrl: RESTWS_V1 + "/form",
        // formUrl: BAHMNI_CORE + "/distro/meta/getFormDetail",
        allFormsUrl: RESTWS_V1 + "/bahmniie/form/allForms",
        medicationSchedulesForOrders: IPD + "/schedule/type/medication",
        patientAllergiesURL: FHIR_BASE_URL + "/AllergyIntolerance?patient={{patientUuid}}&_summary=data",
        latestPublishedForms: RESTWS_V1 + "/bahmniie/form/latestPublishedForms",
        formTranslationsUrl: RESTWS_V1 + "/bahmniie/form/translations",
        sqlUrl: BAHMNI_CORE + "/sql",
        patientAttributeDateFieldFormat: "org.openmrs.util.AttributableDate",
        platform: "user.platform",
        RESTWS_V1: RESTWS_V1,
        baseUrl: BASE_URL,
        customUrl: CUSTOM_URL,
        faviconUrl: hostUrl + "/bahmni/favicon.ico",
        platformType: {
            other: 'other'
        },
        numericDataType: "Numeric",
        encryptionType: {
            SHA3: 'SHA3'
        },
        LoginInformation: 'LoginInformation',
        // orderSetSpecialUnits:["mg/kg","mg/m2"],
        ServerDateTimeFormat: 'YYYY-MM-DDTHH:mm:ssZZ',
        calculateDose: BAHMNI_CORE + "/calculateDose",
        unAuthenticatedReferenceDataMap: unAuthenticatedReferenceDataMap,
        authenticatedReferenceDataMap: authenticatedReferenceDataMap,
        rootDir: rootDir,
        dischargeUrl: BAHMNI_CORE + "/discharge",
        uuidRegex: "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        eventlogFilterUrl: hostUrl + "/openmrs/ws/rest/v1/eventlog/filter",
        bahmniConnectMetaDataDb: "metaData",
        serverDateTimeUrl: "/cgi-bin/systemdate",
        loginText: "/bahmni_config/openmrs/apps/home/whiteLabel.json",
        auditLogUrl: RESTWS_V1 + "/auditlog",
        appointmentServiceUrl: RESTWS_V1 + "/appointmentService",
        conditionUrl: EMRAPI + '/condition',
        conditionHistoryUrl: EMRAPI + '/conditionhistory',
        followUpConditionConcept: 'Follow-up Condition',
        localeLangs: "/bahmni_config/openmrs/apps/home/locale_languages.json",
        privilegeRequiredErrorMessage: "PRIVILEGE_REQUIRED",
        patientFormsUrl: BAHMNI_CORE + "/patient/{patientUuid}/forms",
        defaultPossibleRelativeSearchLimit: 10,
        formBuilderDisplayControlType: "formsV2",
        formBuilderType: "v2",
        formsV2ReactDisplayControlType: "formsV2React",
        formBuilderTranslationApi: IE_APPS_API + '/form/translate',
        disposition: "DISPOSITION",
        registration: "REGISTRATION",
        clinical: "CLINICAL",
        diagnosis: "DIAGNOSIS",
        ot: "OT",
        maxStorageLimit: 100,
        patientAttribute: "PATIENT_ATTRIBUTE",
        program: "PROGRAM",
        visitType: "VISIT_TYPE",
        bedmanagement: "BEDMANAGEMENT",
        bedmanagementDisposition: "BEDMANAGEMENT_DISPOSITION",
        loginConfig: "/bahmni_config/openmrs/apps/home/login_config.json",
        visit: "VISIT",
        defaultImageUploadSize: 500000, // Default patient profile photo size
        maxImageUploadSize: 9000000, // to ensure, extreme max size and prevent choking up server capacity (max size is 9MB)
        adhocTeleconsultationLinkServiceUrl: RESTWS_V1 + "/adhocTeleconsultation/generateAdhocTeleconsultationLink",
        distroAuthenticateUserUrl: BAHMNI_CORE + "/distro/filters/authenticateUser",
        distroLoginUserLocationsUrl: BAHMNI_CORE + "/distro/filters/loginUserLocations",
        distroLocVisitUrl: BAHMNI_CORE + "/distro/filters/visit/searchByLocation",
        bahmniDistroDrugOrderUrl: BAHMNI_CORE + "/distro/filters/drugOrders",
        bahmniDistroOrderUrl: BAHMNI_CORE + "/distro/filters/orders",
        bahmniDistroLabOrderResultsUrl: BAHMNI_CORE + "/distro/filters/labOrderResults",
        bahmniDistroDiagnosisUrl: BAHMNI_CORE + "/distro/filters/diagnosis/search",
        bahmniDistroObservationsUrl: BAHMNI_CORE + "/distro/filters/observations",
        bahmniDistroUserLocationValidUrl: BAHMNI_CORE + "/distro/filters/userLocationValid",
        bahmniDistroVisitPrintUrl: BAHMNI_CORE + "/distro/report/visit",
        bahmniDistroDispositionByPatientUrl: BAHMNI_CORE + "/distro/filters/disposition/patientWithLocale",
        fetchExpiryDate: hostUrl + "/license/api/license/getExpiryDate",
        implementationId: RESTWS_V1 + "/implementationid"
    };
})();


/**
 * @license
 * lodash 4.3.0 (Custom Build) lodash.com/license | Underscore.js 1.8.3 underscorejs.org/LICENSE
 * Build: `lodash -o ./dist/lodash.js`
 */
;(function(){function n(n,t){return n.set(t[0],t[1]),n}function t(n,t){return n.add(t),n}function r(n,t,r){switch(r.length){case 0:return n.call(t);case 1:return n.call(t,r[0]);case 2:return n.call(t,r[0],r[1]);case 3:return n.call(t,r[0],r[1],r[2])}return n.apply(t,r)}function e(n,t,r,e){for(var u=-1,o=n.length;++u<o;){var i=n[u];t(e,i,r(i),n)}return e}function u(n,t){for(var r=-1,e=n.length;++r<e&&false!==t(n[r],r,n););return n}function o(n,t){for(var r=-1,e=n.length;++r<e;)if(!t(n[r],r,n))return false;
return true}function i(n,t){for(var r=-1,e=n.length,u=-1,o=[];++r<e;){var i=n[r];t(i,r,n)&&(o[++u]=i)}return o}function f(n,t){return!!n.length&&-1<d(n,t,0)}function c(n,t,r){for(var e=-1,u=n.length;++e<u;)if(r(t,n[e]))return true;return false}function a(n,t){for(var r=-1,e=n.length,u=Array(e);++r<e;)u[r]=t(n[r],r,n);return u}function l(n,t){for(var r=-1,e=t.length,u=n.length;++r<e;)n[u+r]=t[r];return n}function s(n,t,r,e){var u=-1,o=n.length;for(e&&o&&(r=n[++u]);++u<o;)r=t(r,n[u],u,n);return r}function h(n,t,r,e){
var u=n.length;for(e&&u&&(r=n[--u]);u--;)r=t(r,n[u],u,n);return r}function p(n,t){for(var r=-1,e=n.length;++r<e;)if(t(n[r],r,n))return true;return false}function _(n,t,r){for(var e=-1,u=n.length;++e<u;){var o=n[e],i=t(o);if(null!=i&&(f===Z?i===i:r(i,f)))var f=i,c=o}return c}function g(n,t,r,e){var u;return r(n,function(n,r,o){return t(n,r,o)?(u=e?r:n,false):void 0}),u}function v(n,t,r){for(var e=n.length,u=r?e:-1;r?u--:++u<e;)if(t(n[u],u,n))return u;return-1}function d(n,t,r){if(t!==t)return B(n,r);--r;for(var e=n.length;++r<e;)if(n[r]===t)return r;
return-1}function y(n,t,r,e,u){return u(n,function(n,u,o){r=e?(e=false,n):t(r,n,u,o)}),r}function b(n,t){var r=n.length;for(n.sort(t);r--;)n[r]=n[r].c;return n}function x(n,t){for(var r,e=-1,u=n.length;++e<u;){var o=t(n[e]);o!==Z&&(r=r===Z?o:r+o)}return r}function j(n,t){for(var r=-1,e=Array(n);++r<n;)e[r]=t(r);return e}function m(n,t){return a(t,function(t){return[t,n[t]]})}function w(n){return function(t){return n(t)}}function A(n,t){return a(t,function(t){return n[t]})}function O(n,t){for(var r=-1,e=n.length;++r<e&&-1<d(t,n[r],0););
return r}function k(n,t){for(var r=n.length;r--&&-1<d(t,n[r],0););return r}function E(n){return n&&n.Object===Object?n:null}function I(n,t){if(n!==t){var r=null===n,e=n===Z,u=n===n,o=null===t,i=t===Z,f=t===t;if(n>t&&!o||!u||r&&!i&&f||e&&f)return 1;if(t>n&&!r||!f||o&&!e&&u||i&&u)return-1}return 0}function S(n){return Un[n]}function R(n){return zn[n]}function W(n){return"\\"+$n[n]}function B(n,t,r){var e=n.length;for(t+=r?0:-1;r?t--:++t<e;){var u=n[t];if(u!==u)return t}return-1}function C(n){var t=false;
if(null!=n&&typeof n.toString!="function")try{t=!!(n+"")}catch(r){}return t}function U(n,t){return n=typeof n=="number"||yn.test(n)?+n:-1,n>-1&&0==n%1&&(null==t?9007199254740991:t)>n}function z(n){for(var t,r=[];!(t=n.next()).done;)r.push(t.value);return r}function M(n){var t=-1,r=Array(n.size);return n.forEach(function(n,e){r[++t]=[e,n]}),r}function L(n,t){for(var r=-1,e=n.length,u=-1,o=[];++r<e;)n[r]===t&&(n[r]="__lodash_placeholder__",o[++u]=r);return o}function $(n){var t=-1,r=Array(n.size);return n.forEach(function(n){
r[++t]=n}),r}function F(n){if(!n||!En.test(n))return n.length;for(var t=kn.lastIndex=0;kn.test(n);)t++;return t}function N(n){return Mn[n]}function D(E){function yn(n){if(je(n)&&!No(n)&&!(n instanceof An)){if(n instanceof wn)return n;if(cu.call(n,"__wrapped__"))return Zr(n)}return new wn(n)}function mn(){}function wn(n,t){this.__wrapped__=n,this.__actions__=[],this.__chain__=!!t,this.__index__=0,this.__values__=Z}function An(n){this.__wrapped__=n,this.__actions__=[],this.__dir__=1,this.__filtered__=false,
this.__iteratees__=[],this.__takeCount__=4294967295,this.__views__=[]}function Un(){}function zn(n){var t=-1,r=n?n.length:0;for(this.clear();++t<r;){var e=n[t];this.set(e[0],e[1])}}function Mn(n){var t=-1,r=n?n.length:0;for(this.__data__=new zn;++t<r;)this.push(n[t])}function Ln(n,t){var r=n.__data__;return Ur(t)?(r=r.__data__,"__lodash_hash_undefined__"===(typeof t=="string"?r.string:r.hash)[t]):r.has(t)}function $n(n){var t=-1,r=n?n.length:0;for(this.clear();++t<r;){var e=n[t];this.set(e[0],e[1]);
}}function Dn(n,t){var r=qn(n,t);return 0>r?false:(r==n.length-1?n.pop():Ou.call(n,r,1),true)}function Zn(n,t){var r=qn(n,t);return 0>r?Z:n[r][1]}function qn(n,t){for(var r=n.length;r--;)if(se(n[r][0],t))return r;return-1}function Pn(n,t,r){var e=qn(n,t);0>e?n.push([t,r]):n[e][1]=r}function Tn(n,t,r,e){return n===Z||se(n,iu[r])&&!cu.call(e,r)?t:n}function Gn(n,t,r){(r!==Z&&!se(n[t],r)||typeof t=="number"&&r===Z&&!(t in n))&&(n[t]=r)}function Yn(n,t,r){var e=n[t];(!se(e,r)||se(e,iu[t])&&!cu.call(n,t)||r===Z&&!(t in n))&&(n[t]=r);
}function Hn(n,t,r,e){return Ju(n,function(n,u,o){t(e,n,r(n),o)}),e}function Qn(n,t){return n&&Ht(t,Fe(t),n)}function Xn(n,t){for(var r=-1,e=null==n,u=t.length,o=Array(u);++r<u;)o[r]=e?Z:Me(n,t[r]);return o}function nt(n,t,r){return n===n&&(r!==Z&&(n=n>r?r:n),t!==Z&&(n=t>n?t:n)),n}function tt(n,t,r,e,o,i){var f;if(r&&(f=o?r(n,e,o,i):r(n)),f!==Z)return f;if(!xe(n))return n;if(e=No(n)){if(f=Ir(n),!t)return Yt(n,f)}else{var c=kr(n),a="[object Function]"==c||"[object GeneratorFunction]"==c;if(Do(n))return Kt(n,t);
if("[object Object]"!=c&&"[object Arguments]"!=c&&(!a||o))return Cn[c]?Rr(n,c,t):o?n:{};if(C(n))return o?n:{};if(f=Sr(a?{}:n),!t)return Xt(n,Qn(f,n))}return i||(i=new $n),(o=i.get(n))?o:(i.set(n,f),(e?u:at)(n,function(e,u){Yn(f,u,tt(e,t,r,u,n,i))}),e?f:Xt(n,f))}function rt(n){var t=Fe(n),r=t.length;return function(e){if(null==e)return!r;for(var u=r;u--;){var o=t[u],i=n[o],f=e[o];if(f===Z&&!(o in Object(e))||!i(f))return false}return true}}function et(n,t,r){if(typeof n!="function")throw new uu("Expected a function");
return Au(function(){n.apply(Z,r)},t)}function ut(n,t,r,e){var u=-1,o=f,i=true,l=n.length,s=[],h=t.length;if(!l)return s;r&&(t=a(t,w(r))),e?(o=c,i=false):t.length>=200&&(o=Ln,i=false,t=new Mn(t));n:for(;++u<l;){var p=n[u],_=r?r(p):p;if(i&&_===_){for(var g=h;g--;)if(t[g]===_)continue n;s.push(p)}else o(t,_,e)||s.push(p)}return s}function ot(n,t){var r=true;return Ju(n,function(n,e,u){return r=!!t(n,e,u)}),r}function it(n,t){var r=[];return Ju(n,function(n,e,u){t(n,e,u)&&r.push(n)}),r}function ft(n,t,r,e){e||(e=[]);
for(var u=-1,o=n.length;++u<o;){var i=n[u];ge(i)&&(r||No(i)||pe(i))?t?ft(i,t,r,e):l(e,i):r||(e[e.length]=i)}return e}function ct(n,t){return null==n?n:Hu(n,t,Ne)}function at(n,t){return n&&Hu(n,t,Fe)}function lt(n,t){return n&&Qu(n,t,Fe)}function st(n,t){return i(t,function(t){return de(n[t])})}function ht(n,t){t=Cr(t,n)?[t+""]:Nt(t);for(var r=0,e=t.length;null!=n&&e>r;)n=n[t[r++]];return r&&r==e?n:Z}function pt(n,t){return cu.call(n,t)||typeof n=="object"&&t in n&&null===xu(n)}function _t(n,t){return t in Object(n);
}function gt(n,t,r){for(var e=r?c:f,u=n.length,o=u,i=Array(u),l=[];o--;){var s=n[o];o&&t&&(s=a(s,w(t))),i[o]=r||!t&&120>s.length?Z:new Mn(o&&s)}var s=n[0],h=-1,p=s.length,_=i[0];n:for(;++h<p;){var g=s[h],v=t?t(g):g;if(_?!Ln(_,v):!e(l,v,r)){for(o=u;--o;){var d=i[o];if(d?!Ln(d,v):!e(n[o],v,r))continue n}_&&_.push(v),l.push(g)}}return l}function vt(n,t,r,e){return at(n,function(n,u,o){t(e,r(n),u,o)}),e}function dt(n,t,e){return Cr(t,n)||(t=Nt(t),n=$r(n,t),t=Kr(t)),t=null==n?n:n[t],null==t?Z:r(t,n,e);
}function yt(n,t,r,e,u){if(n===t)return true;if(null==n||null==t||!xe(n)&&!je(t))return n!==n&&t!==t;n:{var o=No(n),i=No(t),f="[object Array]",c="[object Array]";o||(f=kr(n),"[object Arguments]"==f?f="[object Object]":"[object Object]"!=f&&(o=Ie(n))),i||(c=kr(t),"[object Arguments]"==c?c="[object Object]":"[object Object]"!=c&&Ie(t));var a="[object Object]"==f&&!C(n),i="[object Object]"==c&&!C(t),c=f==c;if(!c||o||a){if(!(2&e)&&(f=a&&cu.call(n,"__wrapped__"),i=i&&cu.call(t,"__wrapped__"),f||i)){n=yt(f?n.value():n,i?t.value():t,r,e,u);
break n}c?(u||(u=new $n),n=(o?br:jr)(n,t,yt,r,e,u)):n=false}else n=xr(n,t,f,yt,r,e)}return n}function bt(n,t,r,e){var u=r.length,o=u,i=!e;if(null==n)return!o;for(n=Object(n);u--;){var f=r[u];if(i&&f[2]?f[1]!==n[f[0]]:!(f[0]in n))return false}for(;++u<o;){var f=r[u],c=f[0],a=n[c],l=f[1];if(i&&f[2]){if(a===Z&&!(c in n))return false}else if(f=new $n,c=e?e(a,l,c,n,t,f):Z,c===Z?!yt(l,a,e,3,f):!c)return false}return true}function xt(n){var t=typeof n;return"function"==t?n:null==n?Ve:"object"==t?No(n)?At(n[0],n[1]):wt(n):Qe(n);
}function jt(n){n=null==n?n:Object(n);var t,r=[];for(t in n)r.push(t);return r}function mt(n,t){var r=-1,e=_e(n)?Array(n.length):[];return Ju(n,function(n,u,o){e[++r]=t(n,u,o)}),e}function wt(n){var t=Ar(n);if(1==t.length&&t[0][2]){var r=t[0][0],e=t[0][1];return function(n){return null==n?false:n[r]===e&&(e!==Z||r in Object(n))}}return function(r){return r===n||bt(r,n,t)}}function At(n,t){return function(r){var e=Me(r,n);return e===Z&&e===t?$e(r,n):yt(t,e,Z,3)}}function Ot(n,t,r,e,o){if(n!==t){var i=No(t)||Ie(t)?Z:Ne(t);
u(i||t,function(u,f){if(i&&(f=u,u=t[f]),xe(u)){o||(o=new $n);var c=f,a=o,l=n[c],s=t[c],h=a.get(s);if(!h){var h=e?e(l,s,c+"",n,t,a):Z,p=h===Z;p&&(h=s,No(s)||Ie(s)?No(l)?h=r?Yt(l):l:ge(l)?h=Yt(l):(p=false,h=tt(s)):Ae(s)||pe(s)?pe(l)?h=Ue(l):!xe(l)||r&&de(l)?(p=false,h=tt(s)):h=r?tt(l):l:p=false),a.set(s,h),p&&Ot(h,s,r,e,a)}Gn(n,c,h)}else c=e?e(n[f],u,f+"",n,t,o):Z,c===Z&&(c=u),Gn(n,f,c)})}}function kt(n,t,r){var e=-1,u=wr();return t=a(t.length?t:Array(1),function(n){return u(n)}),n=mt(n,function(n,r,u){return{
a:a(t,function(t){return t(n)}),b:++e,c:n}}),b(n,function(n,t){var e;n:{e=-1;for(var u=n.a,o=t.a,i=u.length,f=r.length;++e<i;){var c=I(u[e],o[e]);if(c){if(e>=f){e=c;break n}e=c*("desc"==r[e]?-1:1);break n}}e=n.b-t.b}return e})}function Et(n,t){return n=Object(n),s(t,function(t,r){return r in n&&(t[r]=n[r]),t},{})}function It(n,t){var r={};return ct(n,function(n,e){t(n,e)&&(r[e]=n)}),r}function St(n){return function(t){return null==t?Z:t[n]}}function Rt(n){return function(t){return ht(t,n)}}function Wt(n,t,r){
var e=-1,u=t.length,o=n;for(r&&(o=a(n,function(n){return r(n)}));++e<u;)for(var i=0,f=t[e],f=r?r(f):f;-1<(i=d(o,f,i));)o!==n&&Ou.call(o,i,1),Ou.call(n,i,1);return n}function Bt(n,t){for(var r=n?t.length:0,e=r-1;r--;){var u=t[r];if(e==r||u!=o){var o=u;if(U(u))Ou.call(n,u,1);else if(Cr(u,n))delete n[u];else{var u=Nt(u),i=$r(n,u);null!=i&&delete i[Kr(u)]}}}return n}function Ct(n,t){return n+Eu(Uu()*(t-n+1))}function Ut(n,t,r,e){t=Cr(t,n)?[t+""]:Nt(t);for(var u=-1,o=t.length,i=o-1,f=n;null!=f&&++u<o;){
var c=t[u];if(xe(f)){var a=r;if(u!=i){var l=f[c],a=e?e(l,c,f):Z;a===Z&&(a=null==l?U(t[u+1])?[]:{}:l)}Yn(f,c,a)}f=f[c]}return n}function zt(n,t,r){var e=-1,u=n.length;for(0>t&&(t=-t>u?0:u+t),r=r>u?u:r,0>r&&(r+=u),u=t>r?0:r-t>>>0,t>>>=0,r=Array(u);++e<u;)r[e]=n[e+t];return r}function Mt(n,t){var r;return Ju(n,function(n,e,u){return r=t(n,e,u),!r}),!!r}function Lt(n,t,r){var e=0,u=n?n.length:e;if(typeof t=="number"&&t===t&&2147483647>=u){for(;u>e;){var o=e+u>>>1,i=n[o];(r?t>=i:t>i)&&null!==i?e=o+1:u=o;
}return u}return $t(n,t,Ve,r)}function $t(n,t,r,e){t=r(t);for(var u=0,o=n?n.length:0,i=t!==t,f=null===t,c=t===Z;o>u;){var a=Eu((u+o)/2),l=r(n[a]),s=l!==Z,h=l===l;(i?h||e:f?h&&s&&(e||null!=l):c?h&&(e||s):null==l?0:e?t>=l:t>l)?u=a+1:o=a}return Bu(o,4294967294)}function Ft(n,t){for(var r=0,e=n.length,u=n[0],o=t?t(u):u,i=o,f=0,c=[u];++r<e;)u=n[r],o=t?t(u):u,se(o,i)||(i=o,c[++f]=u);return c}function Nt(n){return No(n)?n:Fr(n)}function Dt(n,t,r){var e=-1,u=f,o=n.length,i=true,a=[],l=a;if(r)i=false,u=c;else if(o<200)l=t?[]:a;else{
if(u=t?null:no(n))return $(u);i=false,u=Ln,l=new Mn}n:for(;++e<o;){var s=n[e],h=t?t(s):s;if(i&&h===h){for(var p=l.length;p--;)if(l[p]===h)continue n;t&&l.push(h),a.push(s)}else u(l,h,r)||(l!==a&&l.push(h),a.push(s))}return a}function Zt(n,t,r,e){for(var u=n.length,o=e?u:-1;(e?o--:++o<u)&&t(n[o],o,n););return r?zt(n,e?0:o,e?o+1:u):zt(n,e?o+1:0,e?u:o)}function qt(n,t){var r=n;return r instanceof An&&(r=r.value()),s(t,function(n,t){return t.func.apply(t.thisArg,l([n],t.args))},r)}function Pt(n,t,r){for(var e=-1,u=n.length;++e<u;)var o=o?l(ut(o,n[e],t,r),ut(n[e],o,t,r)):n[e];
return o&&o.length?Dt(o,t,r):[]}function Tt(n,t,r){for(var e=-1,u=n.length,o=t.length,i={};++e<u;)r(i,n[e],o>e?t[e]:Z);return i}function Kt(n,t){if(t)return n.slice();var r=new n.constructor(n.length);return n.copy(r),r}function Gt(n){var t=new n.constructor(n.byteLength);return new du(t).set(new du(n)),t}function Vt(n,t,r){for(var e=r.length,u=-1,o=Wu(n.length-e,0),i=-1,f=t.length,c=Array(f+o);++i<f;)c[i]=t[i];for(;++u<e;)c[r[u]]=n[u];for(;o--;)c[i++]=n[u++];return c}function Jt(n,t,r){for(var e=-1,u=r.length,o=-1,i=Wu(n.length-u,0),f=-1,c=t.length,a=Array(i+c);++o<i;)a[o]=n[o];
for(i=o;++f<c;)a[i+f]=t[f];for(;++e<u;)a[i+r[e]]=n[o++];return a}function Yt(n,t){var r=-1,e=n.length;for(t||(t=Array(e));++r<e;)t[r]=n[r];return t}function Ht(n,t,r){return Qt(n,t,r)}function Qt(n,t,r,e){r||(r={});for(var u=-1,o=t.length;++u<o;){var i=t[u],f=e?e(r[i],n[i],i,r,n):n[i];Yn(r,i,f)}return r}function Xt(n,t){return Ht(n,eo(n),t)}function nr(n,t){return function(r,u){var o=No(r)?e:Hn,i=t?t():{};return o(r,n,wr(u),i)}}function tr(n){return le(function(t,r){var e=-1,u=r.length,o=u>1?r[u-1]:Z,i=u>2?r[2]:Z,o=typeof o=="function"?(u--,
o):Z;for(i&&Br(r[0],r[1],i)&&(o=3>u?Z:o,u=1),t=Object(t);++e<u;)(i=r[e])&&n(t,i,e,o);return t})}function rr(n,t){return function(r,e){if(null==r)return r;if(!_e(r))return n(r,e);for(var u=r.length,o=t?u:-1,i=Object(r);(t?o--:++o<u)&&false!==e(i[o],o,i););return r}}function er(n){return function(t,r,e){var u=-1,o=Object(t);e=e(t);for(var i=e.length;i--;){var f=e[n?i:++u];if(false===r(o[f],f,o))break}return t}}function ur(n,t,r){function e(){return(this&&this!==Vn&&this instanceof e?o:n).apply(u?r:this,arguments);
}var u=1&t,o=fr(n);return e}function or(n){return function(t){t=ze(t);var r=En.test(t)?t.match(kn):Z,e=r?r[0]:t.charAt(0);return t=r?r.slice(1).join(""):t.slice(1),e[n]()+t}}function ir(n){return function(t){return s(Ke(Pe(t)),n,"")}}function fr(n){return function(){var t=arguments;switch(t.length){case 0:return new n;case 1:return new n(t[0]);case 2:return new n(t[0],t[1]);case 3:return new n(t[0],t[1],t[2]);case 4:return new n(t[0],t[1],t[2],t[3]);case 5:return new n(t[0],t[1],t[2],t[3],t[4]);case 6:
return new n(t[0],t[1],t[2],t[3],t[4],t[5]);case 7:return new n(t[0],t[1],t[2],t[3],t[4],t[5],t[6])}var r=Vu(n.prototype),t=n.apply(r,t);return xe(t)?t:r}}function cr(n,t,e){function u(){for(var i=arguments.length,f=i,c=Array(i),a=this&&this!==Vn&&this instanceof u?o:n,l=yn.placeholder||u.placeholder;f--;)c[f]=arguments[f];return f=3>i&&c[0]!==l&&c[i-1]!==l?[]:L(c,l),i-=f.length,e>i?vr(n,t,lr,l,Z,c,f,Z,Z,e-i):r(a,this,c)}var o=fr(n);return u}function ar(n){return le(function(t){t=ft(t);var r=t.length,e=r,u=wn.prototype.thru;
for(n&&t.reverse();e--;){var o=t[e];if(typeof o!="function")throw new uu("Expected a function");if(u&&!i&&"wrapper"==mr(o))var i=new wn([],true)}for(e=i?e:r;++e<r;)var o=t[e],u=mr(o),f="wrapper"==u?to(o):Z,i=f&&zr(f[0])&&424==f[1]&&!f[4].length&&1==f[9]?i[mr(f[0])].apply(i,f[3]):1==o.length&&zr(o)?i[u]():i.thru(o);return function(){var n=arguments,e=n[0];if(i&&1==n.length&&No(e)&&e.length>=200)return i.plant(e).value();for(var u=0,n=r?t[u].apply(this,n):e;++u<r;)n=t[u].call(this,n);return n}})}function lr(n,t,r,e,u,o,i,f,c,a){
function l(){for(var y=arguments.length,b=y,x=Array(y);b--;)x[b]=arguments[b];if(e&&(x=Vt(x,e,u)),o&&(x=Jt(x,o,i)),_||g){var b=yn.placeholder||l.placeholder,j=L(x,b),y=y-j.length;if(a>y)return vr(n,t,lr,b,r,x,j,f,c,a-y)}if(y=h?r:this,b=p?y[n]:n,f)for(var j=x.length,m=Bu(f.length,j),w=Yt(x);m--;){var A=f[m];x[m]=U(A,j)?w[A]:Z}else v&&x.length>1&&x.reverse();return s&&x.length>c&&(x.length=c),this&&this!==Vn&&this instanceof l&&(b=d||fr(b)),b.apply(y,x)}var s=128&t,h=1&t,p=2&t,_=8&t,g=16&t,v=512&t,d=p?Z:fr(n);
return l}function sr(n,t){return function(r,e){return vt(r,n,t(e),{})}}function hr(n){return le(function(t){return t=a(ft(t),wr()),le(function(e){var u=this;return n(t,function(n){return r(n,u,e)})})})}function pr(n,t,r){return t=We(t),n=F(n),t&&t>n?(t-=n,r=r===Z?" ":r+"",n=Te(r,ku(t/F(r))),En.test(r)?n.match(kn).slice(0,t).join(""):n.slice(0,t)):""}function _r(n,t,e,u){function o(){for(var t=-1,c=arguments.length,a=-1,l=u.length,s=Array(l+c),h=this&&this!==Vn&&this instanceof o?f:n;++a<l;)s[a]=u[a];
for(;c--;)s[a++]=arguments[++t];return r(h,i?e:this,s)}var i=1&t,f=fr(n);return o}function gr(n){return function(t,r,e){e&&typeof e!="number"&&Br(t,r,e)&&(r=e=Z),t=Ce(t),t=t===t?t:0,r===Z?(r=t,t=0):r=Ce(r)||0,e=e===Z?r>t?1:-1:Ce(e)||0;var u=-1;r=Wu(ku((r-t)/(e||1)),0);for(var o=Array(r);r--;)o[n?r:++u]=t,t+=e;return o}}function vr(n,t,r,e,u,o,i,f,c,a){var l=8&t;f=f?Yt(f):Z;var s=l?i:Z;i=l?Z:i;var h=l?o:Z;return o=l?Z:o,t=(t|(l?32:64))&~(l?64:32),4&t||(t&=-4),t=[n,t,u,h,s,o,i,f,c,a],r=r.apply(Z,t),
zr(n)&&uo(r,t),r.placeholder=e,r}function dr(n){var t=ru[n];return function(n,r){if(n=Ce(n),r=We(r)){var e=(ze(n)+"e").split("e"),e=t(e[0]+"e"+(+e[1]+r)),e=(ze(e)+"e").split("e");return+(e[0]+"e"+(+e[1]-r))}return t(n)}}function yr(n,t,r,e,u,o,i,f){var c=2&t;if(!c&&typeof n!="function")throw new uu("Expected a function");var a=e?e.length:0;if(a||(t&=-97,e=u=Z),i=i===Z?i:Wu(We(i),0),f=f===Z?f:We(f),a-=u?u.length:0,64&t){var l=e,s=u;e=u=Z}var h=c?Z:to(n);return o=[n,t,r,e,u,l,s,o,i,f],h&&(r=o[1],n=h[1],
t=r|n,e=128==n&&8==r||128==n&&256==r&&h[8]>=o[7].length||384==n&&h[8]>=h[7].length&&8==r,131>t||e)&&(1&n&&(o[2]=h[2],t|=1&r?0:4),(r=h[3])&&(e=o[3],o[3]=e?Vt(e,r,h[4]):Yt(r),o[4]=e?L(o[3],"__lodash_placeholder__"):Yt(h[4])),(r=h[5])&&(e=o[5],o[5]=e?Jt(e,r,h[6]):Yt(r),o[6]=e?L(o[5],"__lodash_placeholder__"):Yt(h[6])),(r=h[7])&&(o[7]=Yt(r)),128&n&&(o[8]=null==o[8]?h[8]:Bu(o[8],h[8])),null==o[9]&&(o[9]=h[9]),o[0]=h[0],o[1]=t),n=o[0],t=o[1],r=o[2],e=o[3],u=o[4],f=o[9]=null==o[9]?c?0:n.length:Wu(o[9]-a,0),
!f&&24&t&&(t&=-25),c=t&&1!=t?8==t||16==t?cr(n,t,f):32!=t&&33!=t||u.length?lr.apply(Z,o):_r(n,t,r,e):ur(n,t,r),(h?Xu:uo)(c,o)}function br(n,t,r,e,u,o){var i=-1,f=2&u,c=1&u,a=n.length,l=t.length;if(!(a==l||f&&l>a))return false;if(l=o.get(n))return l==t;for(l=true,o.set(n,t);++i<a;){var s=n[i],h=t[i];if(e)var _=f?e(h,s,i,t,n,o):e(s,h,i,n,t,o);if(_!==Z){if(_)continue;l=false;break}if(c){if(!p(t,function(n){return s===n||r(s,n,e,u,o)})){l=false;break}}else if(s!==h&&!r(s,h,e,u,o)){l=false;break}}return o["delete"](n),
l}function xr(n,t,r,e,u,o){switch(r){case"[object ArrayBuffer]":if(n.byteLength!=t.byteLength||!e(new du(n),new du(t)))break;return true;case"[object Boolean]":case"[object Date]":return+n==+t;case"[object Error]":return n.name==t.name&&n.message==t.message;case"[object Number]":return n!=+n?t!=+t:n==+t;case"[object RegExp]":case"[object String]":return n==t+"";case"[object Map]":var i=M;case"[object Set]":return i||(i=$),(2&o||n.size==t.size)&&e(i(n),i(t),u,1|o);case"[object Symbol]":return!!vu&&Tu.call(n)==Tu.call(t);
}return false}function jr(n,t,r,e,u,o){var i=2&u,f=Fe(n),c=f.length,a=Fe(t).length;if(c!=a&&!i)return false;for(var l=c;l--;){var s=f[l];if(!(i?s in t:pt(t,s)))return false}if(a=o.get(n))return a==t;a=true,o.set(n,t);for(var h=i;++l<c;){var s=f[l],p=n[s],_=t[s];if(e)var g=i?e(_,p,s,t,n,o):e(p,_,s,n,t,o);if(g===Z?p!==_&&!r(p,_,e,u,o):!g){a=false;break}h||(h="constructor"==s)}return a&&!h&&(r=n.constructor,e=t.constructor,r!=e&&"constructor"in n&&"constructor"in t&&!(typeof r=="function"&&r instanceof r&&typeof e=="function"&&e instanceof e)&&(a=false)),
o["delete"](n),a}function mr(n){for(var t=n.name+"",r=Gu[t],e=cu.call(Gu,t)?r.length:0;e--;){var u=r[e],o=u.func;if(null==o||o==n)return u.name}return t}function wr(){var n=yn.iteratee||Je,n=n===Je?xt:n;return arguments.length?n(arguments[0],arguments[1]):n}function Ar(n){n=De(n);for(var t=n.length;t--;){var r,e=n[t];r=n[t][1],r=r===r&&!xe(r),e[2]=r}return n}function Or(n,t){var r=null==n?Z:n[t];return me(r)?r:Z}function kr(n){return su.call(n)}function Er(n,t,r){if(null==n)return false;var e=r(n,t);return e||Cr(t)||(t=Nt(t),
n=$r(n,t),null!=n&&(t=Kr(t),e=r(n,t))),r=n?n.length:Z,e||!!r&&be(r)&&U(t,r)&&(No(n)||ke(n)||pe(n))}function Ir(n){var t=n.length,r=n.constructor(t);return t&&"string"==typeof n[0]&&cu.call(n,"index")&&(r.index=n.index,r.input=n.input),r}function Sr(n){return Mr(n)?{}:(n=n.constructor,Vu(de(n)?n.prototype:Z))}function Rr(r,e,u){var o=r.constructor;switch(e){case"[object ArrayBuffer]":return Gt(r);case"[object Boolean]":case"[object Date]":return new o(+r);case"[object Float32Array]":case"[object Float64Array]":
case"[object Int8Array]":case"[object Int16Array]":case"[object Int32Array]":case"[object Uint8Array]":case"[object Uint8ClampedArray]":case"[object Uint16Array]":case"[object Uint32Array]":return e=r.buffer,new r.constructor(u?Gt(e):e,r.byteOffset,r.length);case"[object Map]":return u=r.constructor,s(M(r),n,new u);case"[object Number]":case"[object String]":return new o(r);case"[object RegExp]":return u=new r.constructor(r.source,hn.exec(r)),u.lastIndex=r.lastIndex,u;case"[object Set]":return u=r.constructor,
s($(r),t,new u);case"[object Symbol]":return vu?Object(Tu.call(r)):{}}}function Wr(n){var t=n?n.length:Z;return be(t)&&(No(n)||ke(n)||pe(n))?j(t,String):null}function Br(n,t,r){if(!xe(r))return false;var e=typeof t;return("number"==e?_e(r)&&U(t,r.length):"string"==e&&t in r)?se(r[t],n):false}function Cr(n,t){return typeof n=="number"?true:!No(n)&&(rn.test(n)||!tn.test(n)||null!=t&&n in Object(t))}function Ur(n){var t=typeof n;return"number"==t||"boolean"==t||"string"==t&&"__proto__"!==n||null==n}function zr(n){
var t=mr(n),r=yn[t];return typeof r=="function"&&t in An.prototype?n===r?true:(t=to(r),!!t&&n===t[0]):false}function Mr(n){var t=n&&n.constructor;return n===(typeof t=="function"&&t.prototype||iu)}function Lr(n,t,r,e,u,o){return xe(n)&&xe(t)&&(o.set(t,n),Ot(n,t,Z,Lr,o)),n}function $r(n,t){return 1==t.length?n:Me(n,zt(t,0,-1))}function Fr(n){var t=[];return ze(n).replace(en,function(n,r,e,u){t.push(e?u.replace(ln,"$1"):r||n)}),t}function Nr(n){return ge(n)?n:[]}function Dr(n){return typeof n=="function"?n:Ve;
}function Zr(n){if(n instanceof An)return n.clone();var t=new wn(n.__wrapped__,n.__chain__);return t.__actions__=Yt(n.__actions__),t.__index__=n.__index__,t.__values__=n.__values__,t}function qr(n,t,r){var e=n?n.length:0;return e?(t=r||t===Z?1:We(t),zt(n,0>t?0:t,e)):[]}function Pr(n,t,r){var e=n?n.length:0;return e?(t=r||t===Z?1:We(t),t=e-t,zt(n,0,0>t?0:t)):[]}function Tr(n){return n?n[0]:Z}function Kr(n){var t=n?n.length:0;return t?n[t-1]:Z}function Gr(n,t){return n&&n.length&&t&&t.length?Wt(n,t):n;
}function Vr(n){return n?zu.call(n):n}function Jr(n){if(!n||!n.length)return[];var t=0;return n=i(n,function(n){return ge(n)?(t=Wu(n.length,t),true):void 0}),j(t,function(t){return a(n,St(t))})}function Yr(n,t){if(!n||!n.length)return[];var e=Jr(n);return null==t?e:a(e,function(n){return r(t,Z,n)})}function Hr(n){return n=yn(n),n.__chain__=true,n}function Qr(n,t){return t(n)}function Xr(){return this}function ne(n,t){return typeof t=="function"&&No(n)?u(n,t):Ju(n,Dr(t))}function te(n,t){var r;if(typeof t=="function"&&No(n)){
for(r=n.length;r--&&false!==t(n[r],r,n););r=n}else r=Yu(n,Dr(t));return r}function re(n,t){return(No(n)?a:mt)(n,wr(t,3))}function ee(n,t){var r=-1,e=Re(n),u=e.length,o=u-1;for(t=nt(We(t),0,u);++r<t;){var u=Ct(r,o),i=e[u];e[u]=e[r],e[r]=i}return e.length=t,e}function ue(n,t,r){return t=r?Z:t,t=n&&null==t?n.length:t,yr(n,128,Z,Z,Z,Z,t)}function oe(n,t){var r;if(typeof t!="function")throw new uu("Expected a function");return n=We(n),function(){return 0<--n&&(r=t.apply(this,arguments)),1>=n&&(t=Z),r}}function ie(n,t,r){
return t=r?Z:t,n=yr(n,8,Z,Z,Z,Z,Z,t),n.placeholder=yn.placeholder||ie.placeholder,n}function fe(n,t,r){return t=r?Z:t,n=yr(n,16,Z,Z,Z,Z,Z,t),n.placeholder=yn.placeholder||fe.placeholder,n}function ce(n,t,r){function e(){p&&yu(p),a&&yu(a),g=0,c=a=h=p=_=Z}function u(t,r){r&&yu(r),a=p=_=Z,t&&(g=Wo(),l=n.apply(h,c),p||a||(c=h=Z))}function o(){var n=t-(Wo()-s);0>=n||n>t?u(_,a):p=Au(o,n)}function i(){u(y,p)}function f(){if(c=arguments,s=Wo(),h=this,_=y&&(p||!v),false===d)var r=v&&!p;else{g||a||v||(g=s);var e=d-(s-g),u=0>=e||e>d;
u?(a&&(a=yu(a)),g=s,l=n.apply(h,c)):a||(a=Au(i,e))}return u&&p?p=yu(p):p||t===d||(p=Au(o,t)),r&&(u=true,l=n.apply(h,c)),!u||p||a||(c=h=Z),l}var c,a,l,s,h,p,_,g=0,v=false,d=false,y=true;if(typeof n!="function")throw new uu("Expected a function");return t=Ce(t)||0,xe(r)&&(v=!!r.leading,d="maxWait"in r&&Wu(Ce(r.maxWait)||0,t),y="trailing"in r?!!r.trailing:y),f.cancel=e,f.flush=function(){return(p&&_||a&&y)&&(l=n.apply(h,c)),e(),l},f}function ae(n,t){if(typeof n!="function"||t&&typeof t!="function")throw new uu("Expected a function");
var r=function(){var e=arguments,u=t?t.apply(this,e):e[0],o=r.cache;return o.has(u)?o.get(u):(e=n.apply(this,e),r.cache=o.set(u,e),e)};return r.cache=new ae.Cache,r}function le(n,t){if(typeof n!="function")throw new uu("Expected a function");return t=Wu(t===Z?n.length-1:We(t),0),function(){for(var e=arguments,u=-1,o=Wu(e.length-t,0),i=Array(o);++u<o;)i[u]=e[t+u];switch(t){case 0:return n.call(this,i);case 1:return n.call(this,e[0],i);case 2:return n.call(this,e[0],e[1],i)}for(o=Array(t+1),u=-1;++u<t;)o[u]=e[u];
return o[t]=i,r(n,this,o)}}function se(n,t){return n===t||n!==n&&t!==t}function he(n,t){return n>t}function pe(n){return ge(n)&&cu.call(n,"callee")&&(!wu.call(n,"callee")||"[object Arguments]"==su.call(n))}function _e(n){return null!=n&&!(typeof n=="function"&&de(n))&&be(ro(n))}function ge(n){return je(n)&&_e(n)}function ve(n){return je(n)&&typeof n.message=="string"&&"[object Error]"==su.call(n)}function de(n){return n=xe(n)?su.call(n):"","[object Function]"==n||"[object GeneratorFunction]"==n}function ye(n){
return typeof n=="number"&&n==We(n)}function be(n){return typeof n=="number"&&n>-1&&0==n%1&&9007199254740991>=n}function xe(n){var t=typeof n;return!!n&&("object"==t||"function"==t)}function je(n){return!!n&&typeof n=="object"}function me(n){return null==n?false:de(n)?pu.test(fu.call(n)):je(n)&&(C(n)?pu:vn).test(n)}function we(n){return typeof n=="number"||je(n)&&"[object Number]"==su.call(n)}function Ae(n){if(!je(n)||"[object Object]"!=su.call(n)||C(n))return false;var t=iu;return typeof n.constructor=="function"&&(t=xu(n)),
null===t?true:(n=t.constructor,typeof n=="function"&&n instanceof n&&fu.call(n)==lu)}function Oe(n){return xe(n)&&"[object RegExp]"==su.call(n)}function ke(n){return typeof n=="string"||!No(n)&&je(n)&&"[object String]"==su.call(n)}function Ee(n){return typeof n=="symbol"||je(n)&&"[object Symbol]"==su.call(n)}function Ie(n){return je(n)&&be(n.length)&&!!Bn[su.call(n)]}function Se(n,t){return t>n}function Re(n){if(!n)return[];if(_e(n))return ke(n)?n.match(kn):Yt(n);if(mu&&n[mu])return z(n[mu]());var t=kr(n);
return("[object Map]"==t?M:"[object Set]"==t?$:Ze)(n)}function We(n){if(!n)return 0===n?n:0;if(n=Ce(n),n===q||n===-q)return 1.7976931348623157e308*(0>n?-1:1);var t=n%1;return n===n?t?n-t:n:0}function Be(n){return n?nt(We(n),0,4294967295):0}function Ce(n){if(xe(n)&&(n=de(n.valueOf)?n.valueOf():n,n=xe(n)?n+"":n),typeof n!="string")return 0===n?n:+n;n=n.replace(fn,"");var t=gn.test(n);return t||dn.test(n)?Nn(n.slice(2),t?2:8):_n.test(n)?P:+n}function Ue(n){return Ht(n,Ne(n))}function ze(n){if(typeof n=="string")return n;
if(null==n)return"";if(Ee(n))return vu?Ku.call(n):"";var t=n+"";return"0"==t&&1/n==-q?"-0":t}function Me(n,t,r){return n=null==n?Z:ht(n,t),n===Z?r:n}function Le(n,t){return Er(n,t,pt)}function $e(n,t){return Er(n,t,_t)}function Fe(n){var t=Mr(n);if(!t&&!_e(n))return Ru(Object(n));var r,e=Wr(n),u=!!e,e=e||[],o=e.length;for(r in n)!pt(n,r)||u&&("length"==r||U(r,o))||t&&"constructor"==r||e.push(r);return e}function Ne(n){for(var t=-1,r=Mr(n),e=jt(n),u=e.length,o=Wr(n),i=!!o,o=o||[],f=o.length;++t<u;){
var c=e[t];i&&("length"==c||U(c,f))||"constructor"==c&&(r||!cu.call(n,c))||o.push(c)}return o}function De(n){return m(n,Fe(n))}function Ze(n){return n?A(n,Fe(n)):[]}function qe(n){return ii(ze(n).toLowerCase())}function Pe(n){return(n=ze(n))&&n.replace(bn,S).replace(On,"")}function Te(n,t){n=ze(n),t=We(t);var r="";if(!n||1>t||t>9007199254740991)return r;do t%2&&(r+=n),t=Eu(t/2),n+=n;while(t);return r}function Ke(n,t,r){return n=ze(n),t=r?Z:t,t===Z&&(t=Rn.test(n)?Sn:In),n.match(t)||[]}function Ge(n){
return function(){return n}}function Ve(n){return n}function Je(n){return xt(typeof n=="function"?n:tt(n,true))}function Ye(n,t,r){var e=Fe(t),o=st(t,e);null!=r||xe(t)&&(o.length||!e.length)||(r=t,t=n,n=this,o=st(t,Fe(t)));var i=xe(r)&&"chain"in r?r.chain:true,f=de(n);return u(o,function(r){var e=t[r];n[r]=e,f&&(n.prototype[r]=function(){var t=this.__chain__;if(i||t){var r=n(this.__wrapped__);return(r.__actions__=Yt(this.__actions__)).push({func:e,args:arguments,thisArg:n}),r.__chain__=t,r}return e.apply(n,l([this.value()],arguments));
})}),n}function He(){}function Qe(n){return Cr(n)?St(n):Rt(n)}function Xe(n){return n&&n.length?x(n,Ve):0}E=E?Jn.defaults({},E,Jn.pick(Vn,Wn)):Vn;var nu=E.Date,tu=E.Error,ru=E.Math,eu=E.RegExp,uu=E.TypeError,ou=E.Array.prototype,iu=E.Object.prototype,fu=E.Function.prototype.toString,cu=iu.hasOwnProperty,au=0,lu=fu.call(Object),su=iu.toString,hu=Vn._,pu=eu("^"+fu.call(cu).replace(un,"\\$&").replace(/hasOwnProperty|(function).*?(?=\\\()| for .+?(?=\\\])/g,"$1.*?")+"$"),_u=Kn?E.Buffer:Z,gu=E.Reflect,vu=E.Symbol,du=E.Uint8Array,yu=E.clearTimeout,bu=gu?gu.enumerate:Z,xu=Object.getPrototypeOf,ju=Object.getOwnPropertySymbols,mu=typeof(mu=vu&&vu.iterator)=="symbol"?mu:Z,wu=iu.propertyIsEnumerable,Au=E.setTimeout,Ou=ou.splice,ku=ru.ceil,Eu=ru.floor,Iu=E.isFinite,Su=ou.join,Ru=Object.keys,Wu=ru.max,Bu=ru.min,Cu=E.parseInt,Uu=ru.random,zu=ou.reverse,Mu=Or(E,"Map"),Lu=Or(E,"Set"),$u=Or(E,"WeakMap"),Fu=Or(Object,"create"),Nu=$u&&new $u,Du=Mu?fu.call(Mu):"",Zu=Lu?fu.call(Lu):"",qu=$u?fu.call($u):"",Pu=vu?vu.prototype:Z,Tu=vu?Pu.valueOf:Z,Ku=vu?Pu.toString:Z,Gu={};
yn.templateSettings={escape:Q,evaluate:X,interpolate:nn,variable:"",imports:{_:yn}};var Vu=function(){function n(){}return function(t){if(xe(t)){n.prototype=t;var r=new n;n.prototype=Z}return r||{}}}(),Ju=rr(at),Yu=rr(lt,true),Hu=er(),Qu=er(true);bu&&!wu.call({valueOf:1},"valueOf")&&(jt=function(n){return z(bu(n))});var Xu=Nu?function(n,t){return Nu.set(n,t),n}:Ve,no=Lu&&2===new Lu([1,2]).size?function(n){return new Lu(n)}:He,to=Nu?function(n){return Nu.get(n)}:He,ro=St("length"),eo=ju||function(){return[];
};(Mu&&"[object Map]"!=kr(new Mu)||Lu&&"[object Set]"!=kr(new Lu)||$u&&"[object WeakMap]"!=kr(new $u))&&(kr=function(n){var t=su.call(n);if(n="[object Object]"==t?n.constructor:null,n=typeof n=="function"?fu.call(n):"")switch(n){case Du:return"[object Map]";case Zu:return"[object Set]";case qu:return"[object WeakMap]"}return t});var uo=function(){var n=0,t=0;return function(r,e){var u=Wo(),o=16-(u-t);if(t=u,o>0){if(150<=++n)return r}else n=0;return Xu(r,e)}}(),oo=le(function(n,t){No(n)||(n=null==n?[]:[Object(n)]),
t=ft(t);for(var r=n,e=t,u=-1,o=r.length,i=-1,f=e.length,c=Array(o+f);++u<o;)c[u]=r[u];for(;++i<f;)c[u++]=e[i];return c}),io=le(function(n,t){return ge(n)?ut(n,ft(t,false,true)):[]}),fo=le(function(n,t){var r=Kr(t);return ge(r)&&(r=Z),ge(n)?ut(n,ft(t,false,true),wr(r)):[]}),co=le(function(n,t){var r=Kr(t);return ge(r)&&(r=Z),ge(n)?ut(n,ft(t,false,true),Z,r):[]}),ao=le(function(n){var t=a(n,Nr);return t.length&&t[0]===n[0]?gt(t):[]}),lo=le(function(n){var t=Kr(n),r=a(n,Nr);return t===Kr(r)?t=Z:r.pop(),r.length&&r[0]===n[0]?gt(r,wr(t)):[];
}),so=le(function(n){var t=Kr(n),r=a(n,Nr);return t===Kr(r)?t=Z:r.pop(),r.length&&r[0]===n[0]?gt(r,Z,t):[]}),ho=le(Gr),po=le(function(n,t){t=a(ft(t),String);var r=Xn(n,t);return Bt(n,t.sort(I)),r}),_o=le(function(n){return Dt(ft(n,false,true))}),go=le(function(n){var t=Kr(n);return ge(t)&&(t=Z),Dt(ft(n,false,true),wr(t))}),vo=le(function(n){var t=Kr(n);return ge(t)&&(t=Z),Dt(ft(n,false,true),Z,t)}),yo=le(function(n,t){return ge(n)?ut(n,t):[]}),bo=le(function(n){return Pt(i(n,ge))}),xo=le(function(n){var t=Kr(n);
return ge(t)&&(t=Z),Pt(i(n,ge),wr(t))}),jo=le(function(n){var t=Kr(n);return ge(t)&&(t=Z),Pt(i(n,ge),Z,t)}),mo=le(Jr),wo=le(function(n){var t=n.length,t=t>1?n[t-1]:Z,t=typeof t=="function"?(n.pop(),t):Z;return Yr(n,t)}),Ao=le(function(n){n=ft(n);var t=n.length,r=t?n[0]:0,e=this.__wrapped__,u=function(t){return Xn(t,n)};return 1>=t&&!this.__actions__.length&&e instanceof An&&U(r)?(e=e.slice(r,+r+(t?1:0)),e.__actions__.push({func:Qr,args:[u],thisArg:Z}),new wn(e,this.__chain__).thru(function(n){return t&&!n.length&&n.push(Z),
n})):this.thru(u)}),Oo=nr(function(n,t,r){cu.call(n,r)?++n[r]:n[r]=1}),ko=nr(function(n,t,r){cu.call(n,r)?n[r].push(t):n[r]=[t]}),Eo=le(function(n,t,e){var u=-1,o=typeof t=="function",i=Cr(t),f=_e(n)?Array(n.length):[];return Ju(n,function(n){var c=o?t:i&&null!=n?n[t]:Z;f[++u]=c?r(c,n,e):dt(n,t,e)}),f}),Io=nr(function(n,t,r){n[r]=t}),So=nr(function(n,t,r){n[r?0:1].push(t)},function(){return[[],[]]}),Ro=le(function(n,t){if(null==n)return[];var r=t.length;return r>1&&Br(n,t[0],t[1])?t=[]:r>2&&Br(t[0],t[1],t[2])&&(t.length=1),
kt(n,ft(t),[])}),Wo=nu.now,Bo=le(function(n,t,r){var e=1;if(r.length)var u=L(r,yn.placeholder||Bo.placeholder),e=32|e;return yr(n,e,t,r,u)}),Co=le(function(n,t,r){var e=3;if(r.length)var u=L(r,yn.placeholder||Co.placeholder),e=32|e;return yr(t,e,n,r,u)}),Uo=le(function(n,t){return et(n,1,t)}),zo=le(function(n,t,r){return et(n,Ce(t)||0,r)}),Mo=le(function(n,t){t=a(ft(t),wr());var e=t.length;return le(function(u){for(var o=-1,i=Bu(u.length,e);++o<i;)u[o]=t[o].call(this,u[o]);return r(n,this,u)})}),Lo=le(function(n,t){
var r=L(t,yn.placeholder||Lo.placeholder);return yr(n,32,Z,t,r)}),$o=le(function(n,t){var r=L(t,yn.placeholder||$o.placeholder);return yr(n,64,Z,t,r)}),Fo=le(function(n,t){return yr(n,256,Z,Z,Z,ft(t))}),No=Array.isArray,Do=_u?function(n){return n instanceof _u}:Ge(false),Zo=tr(function(n,t){Ht(t,Fe(t),n)}),qo=tr(function(n,t){Ht(t,Ne(t),n)}),Po=tr(function(n,t,r,e){Qt(t,Ne(t),n,e)}),To=tr(function(n,t,r,e){Qt(t,Fe(t),n,e)}),Ko=le(function(n,t){return Xn(n,ft(t))}),Go=le(function(n){return n.push(Z,Tn),
r(Po,Z,n)}),Vo=le(function(n){return n.push(Z,Lr),r(Xo,Z,n)}),Jo=sr(function(n,t,r){n[t]=r},Ge(Ve)),Yo=sr(function(n,t,r){cu.call(n,t)?n[t].push(r):n[t]=[r]},wr),Ho=le(dt),Qo=tr(function(n,t,r){Ot(n,t,r)}),Xo=tr(function(n,t,r,e){Ot(n,t,r,e)}),ni=le(function(n,t){return null==n?{}:(t=a(ft(t),String),Et(n,ut(Ne(n),t)))}),ti=le(function(n,t){return null==n?{}:Et(n,ft(t))}),ri=ir(function(n,t,r){return t=t.toLowerCase(),n+(r?qe(t):t)}),ei=ir(function(n,t,r){return n+(r?"-":"")+t.toLowerCase()}),ui=ir(function(n,t,r){
return n+(r?" ":"")+t.toLowerCase()}),oi=or("toLowerCase"),ii=or("toUpperCase"),fi=ir(function(n,t,r){return n+(r?"_":"")+t.toLowerCase()}),ci=ir(function(n,t,r){return n+(r?" ":"")+qe(t)}),ai=ir(function(n,t,r){return n+(r?" ":"")+t.toUpperCase()}),li=le(function(n,t){try{return r(n,Z,t)}catch(e){return xe(e)?e:new tu(e)}}),si=le(function(n,t){return u(ft(t),function(t){n[t]=Bo(n[t],n)}),n}),hi=ar(),pi=ar(true),_i=le(function(n,t){return function(r){return dt(r,n,t)}}),gi=le(function(n,t){return function(r){
return dt(n,r,t)}}),vi=hr(a),di=hr(o),yi=hr(p),bi=gr(),xi=gr(true),ji=dr("ceil"),mi=dr("floor"),wi=dr("round");return yn.prototype=mn.prototype,wn.prototype=Vu(mn.prototype),wn.prototype.constructor=wn,An.prototype=Vu(mn.prototype),An.prototype.constructor=An,Un.prototype=Fu?Fu(null):iu,zn.prototype.clear=function(){this.__data__={hash:new Un,map:Mu?new Mu:[],string:new Un}},zn.prototype["delete"]=function(n){var t=this.__data__;return Ur(n)?(t=typeof n=="string"?t.string:t.hash,(Fu?t[n]!==Z:cu.call(t,n))&&delete t[n]):Mu?t.map["delete"](n):Dn(t.map,n);
},zn.prototype.get=function(n){var t=this.__data__;return Ur(n)?(t=typeof n=="string"?t.string:t.hash,Fu?(n=t[n],n="__lodash_hash_undefined__"===n?Z:n):n=cu.call(t,n)?t[n]:Z,n):Mu?t.map.get(n):Zn(t.map,n)},zn.prototype.has=function(n){var t=this.__data__;return Ur(n)?(t=typeof n=="string"?t.string:t.hash,n=Fu?t[n]!==Z:cu.call(t,n)):n=Mu?t.map.has(n):-1<qn(t.map,n),n},zn.prototype.set=function(n,t){var r=this.__data__;return Ur(n)?(typeof n=="string"?r.string:r.hash)[n]=Fu&&t===Z?"__lodash_hash_undefined__":t:Mu?r.map.set(n,t):Pn(r.map,n,t),
this},Mn.prototype.push=function(n){var t=this.__data__;Ur(n)?(t=t.__data__,(typeof n=="string"?t.string:t.hash)[n]="__lodash_hash_undefined__"):t.set(n,"__lodash_hash_undefined__")},$n.prototype.clear=function(){this.__data__={array:[],map:null}},$n.prototype["delete"]=function(n){var t=this.__data__,r=t.array;return r?Dn(r,n):t.map["delete"](n)},$n.prototype.get=function(n){var t=this.__data__,r=t.array;return r?Zn(r,n):t.map.get(n)},$n.prototype.has=function(n){var t=this.__data__,r=t.array;return r?-1<qn(r,n):t.map.has(n);
},$n.prototype.set=function(n,t){var r=this.__data__,e=r.array;return e&&(199>e.length?Pn(e,n,t):(r.array=null,r.map=new zn(e))),(r=r.map)&&r.set(n,t),this},ae.Cache=zn,yn.after=function(n,t){if(typeof t!="function")throw new uu("Expected a function");return n=We(n),function(){return 1>--n?t.apply(this,arguments):void 0}},yn.ary=ue,yn.assign=Zo,yn.assignIn=qo,yn.assignInWith=Po,yn.assignWith=To,yn.at=Ko,yn.before=oe,yn.bind=Bo,yn.bindAll=si,yn.bindKey=Co,yn.chain=Hr,yn.chunk=function(n,t){t=Wu(We(t),0);
var r=n?n.length:0;if(!r||1>t)return[];for(var e=0,u=-1,o=Array(ku(r/t));r>e;)o[++u]=zt(n,e,e+=t);return o},yn.compact=function(n){for(var t=-1,r=n?n.length:0,e=-1,u=[];++t<r;){var o=n[t];o&&(u[++e]=o)}return u},yn.concat=oo,yn.cond=function(n){var t=n?n.length:0,e=wr();return n=t?a(n,function(n){if("function"!=typeof n[1])throw new uu("Expected a function");return[e(n[0]),n[1]]}):[],le(function(e){for(var u=-1;++u<t;){var o=n[u];if(r(o[0],this,e))return r(o[1],this,e)}})},yn.conforms=function(n){
return rt(tt(n,true))},yn.constant=Ge,yn.countBy=Oo,yn.create=function(n,t){var r=Vu(n);return t?Qn(r,t):r},yn.curry=ie,yn.curryRight=fe,yn.debounce=ce,yn.defaults=Go,yn.defaultsDeep=Vo,yn.defer=Uo,yn.delay=zo,yn.difference=io,yn.differenceBy=fo,yn.differenceWith=co,yn.drop=qr,yn.dropRight=Pr,yn.dropRightWhile=function(n,t){return n&&n.length?Zt(n,wr(t,3),true,true):[]},yn.dropWhile=function(n,t){return n&&n.length?Zt(n,wr(t,3),true):[]},yn.fill=function(n,t,r,e){var u=n?n.length:0;if(!u)return[];for(r&&typeof r!="number"&&Br(n,t,r)&&(r=0,
e=u),u=n.length,r=We(r),0>r&&(r=-r>u?0:u+r),e=e===Z||e>u?u:We(e),0>e&&(e+=u),e=r>e?0:Be(e);e>r;)n[r++]=t;return n},yn.filter=function(n,t){return(No(n)?i:it)(n,wr(t,3))},yn.flatMap=function(n,t){return ft(re(n,t))},yn.flatten=function(n){return n&&n.length?ft(n):[]},yn.flattenDeep=function(n){return n&&n.length?ft(n,true):[]},yn.flip=function(n){return yr(n,512)},yn.flow=hi,yn.flowRight=pi,yn.fromPairs=function(n){for(var t=-1,r=n?n.length:0,e={};++t<r;){var u=n[t];e[u[0]]=u[1]}return e},yn.functions=function(n){
return null==n?[]:st(n,Fe(n))},yn.functionsIn=function(n){return null==n?[]:st(n,Ne(n))},yn.groupBy=ko,yn.initial=function(n){return Pr(n,1)},yn.intersection=ao,yn.intersectionBy=lo,yn.intersectionWith=so,yn.invert=Jo,yn.invertBy=Yo,yn.invokeMap=Eo,yn.iteratee=Je,yn.keyBy=Io,yn.keys=Fe,yn.keysIn=Ne,yn.map=re,yn.mapKeys=function(n,t){var r={};return t=wr(t,3),at(n,function(n,e,u){r[t(n,e,u)]=n}),r},yn.mapValues=function(n,t){var r={};return t=wr(t,3),at(n,function(n,e,u){r[e]=t(n,e,u)}),r},yn.matches=function(n){
return wt(tt(n,true))},yn.matchesProperty=function(n,t){return At(n,tt(t,true))},yn.memoize=ae,yn.merge=Qo,yn.mergeWith=Xo,yn.method=_i,yn.methodOf=gi,yn.mixin=Ye,yn.negate=function(n){if(typeof n!="function")throw new uu("Expected a function");return function(){return!n.apply(this,arguments)}},yn.nthArg=function(n){return n=We(n),function(){return arguments[n]}},yn.omit=ni,yn.omitBy=function(n,t){return t=wr(t,2),It(n,function(n,r){return!t(n,r)})},yn.once=function(n){return oe(2,n)},yn.orderBy=function(n,t,r,e){
return null==n?[]:(No(t)||(t=null==t?[]:[t]),r=e?Z:r,No(r)||(r=null==r?[]:[r]),kt(n,t,r))},yn.over=vi,yn.overArgs=Mo,yn.overEvery=di,yn.overSome=yi,yn.partial=Lo,yn.partialRight=$o,yn.partition=So,yn.pick=ti,yn.pickBy=function(n,t){return null==n?{}:It(n,wr(t,2))},yn.property=Qe,yn.propertyOf=function(n){return function(t){return null==n?Z:ht(n,t)}},yn.pull=ho,yn.pullAll=Gr,yn.pullAllBy=function(n,t,r){return n&&n.length&&t&&t.length?Wt(n,t,wr(r)):n},yn.pullAt=po,yn.range=bi,yn.rangeRight=xi,yn.rearg=Fo,
yn.reject=function(n,t){var r=No(n)?i:it;return t=wr(t,3),r(n,function(n,r,e){return!t(n,r,e)})},yn.remove=function(n,t){var r=[];if(!n||!n.length)return r;var e=-1,u=[],o=n.length;for(t=wr(t,3);++e<o;){var i=n[e];t(i,e,n)&&(r.push(i),u.push(e))}return Bt(n,u),r},yn.rest=le,yn.reverse=Vr,yn.sampleSize=ee,yn.set=function(n,t,r){return null==n?n:Ut(n,t,r)},yn.setWith=function(n,t,r,e){return e=typeof e=="function"?e:Z,null==n?n:Ut(n,t,r,e)},yn.shuffle=function(n){return ee(n,4294967295)},yn.slice=function(n,t,r){
var e=n?n.length:0;return e?(r&&typeof r!="number"&&Br(n,t,r)?(t=0,r=e):(t=null==t?0:We(t),r=r===Z?e:We(r)),zt(n,t,r)):[]},yn.sortBy=Ro,yn.sortedUniq=function(n){return n&&n.length?Ft(n):[]},yn.sortedUniqBy=function(n,t){return n&&n.length?Ft(n,wr(t)):[]},yn.split=function(n,t,r){return ze(n).split(t,r)},yn.spread=function(n,t){if(typeof n!="function")throw new uu("Expected a function");return t=t===Z?0:Wu(We(t),0),le(function(e){var u=e[t];return e=e.slice(0,t),u&&l(e,u),r(n,this,e)})},yn.tail=function(n){
return qr(n,1)},yn.take=function(n,t,r){return n&&n.length?(t=r||t===Z?1:We(t),zt(n,0,0>t?0:t)):[]},yn.takeRight=function(n,t,r){var e=n?n.length:0;return e?(t=r||t===Z?1:We(t),t=e-t,zt(n,0>t?0:t,e)):[]},yn.takeRightWhile=function(n,t){return n&&n.length?Zt(n,wr(t,3),false,true):[]},yn.takeWhile=function(n,t){return n&&n.length?Zt(n,wr(t,3)):[]},yn.tap=function(n,t){return t(n),n},yn.throttle=function(n,t,r){var e=true,u=true;if(typeof n!="function")throw new uu("Expected a function");return xe(r)&&(e="leading"in r?!!r.leading:e,
u="trailing"in r?!!r.trailing:u),ce(n,t,{leading:e,maxWait:t,trailing:u})},yn.thru=Qr,yn.toArray=Re,yn.toPairs=De,yn.toPairsIn=function(n){return m(n,Ne(n))},yn.toPath=function(n){return No(n)?a(n,String):Fr(n)},yn.toPlainObject=Ue,yn.transform=function(n,t,r){var e=No(n)||Ie(n);if(t=wr(t,4),null==r)if(e||xe(n)){var o=n.constructor;r=e?No(n)?new o:[]:Vu(de(o)?o.prototype:Z)}else r={};return(e?u:at)(n,function(n,e,u){return t(r,n,e,u)}),r},yn.unary=function(n){return ue(n,1)},yn.union=_o,yn.unionBy=go,
yn.unionWith=vo,yn.uniq=function(n){return n&&n.length?Dt(n):[]},yn.uniqBy=function(n,t){return n&&n.length?Dt(n,wr(t)):[]},yn.uniqWith=function(n,t){return n&&n.length?Dt(n,Z,t):[]},yn.unset=function(n,t){var r;if(null==n)r=true;else{r=n;var e=t,e=Cr(e,r)?[e+""]:Nt(e);r=$r(r,e),e=Kr(e),r=null!=r&&Le(r,e)?delete r[e]:true}return r},yn.unzip=Jr,yn.unzipWith=Yr,yn.values=Ze,yn.valuesIn=function(n){return null==n?A(n,Ne(n)):[]},yn.without=yo,yn.words=Ke,yn.wrap=function(n,t){return t=null==t?Ve:t,Lo(t,n);
},yn.xor=bo,yn.xorBy=xo,yn.xorWith=jo,yn.zip=mo,yn.zipObject=function(n,t){return Tt(n||[],t||[],Yn)},yn.zipObjectDeep=function(n,t){return Tt(n||[],t||[],Ut)},yn.zipWith=wo,yn.extend=qo,yn.extendWith=Po,Ye(yn,yn),yn.add=function(n,t){var r;return n===Z&&t===Z?0:(n!==Z&&(r=n),t!==Z&&(r=r===Z?t:r+t),r)},yn.attempt=li,yn.camelCase=ri,yn.capitalize=qe,yn.ceil=ji,yn.clamp=function(n,t,r){return r===Z&&(r=t,t=Z),r!==Z&&(r=Ce(r),r=r===r?r:0),t!==Z&&(t=Ce(t),t=t===t?t:0),nt(Ce(n),t,r)},yn.clone=function(n){
return tt(n)},yn.cloneDeep=function(n){return tt(n,true)},yn.cloneDeepWith=function(n,t){return tt(n,true,t)},yn.cloneWith=function(n,t){return tt(n,false,t)},yn.deburr=Pe,yn.endsWith=function(n,t,r){n=ze(n),t=typeof t=="string"?t:t+"";var e=n.length;return r=r===Z?e:nt(We(r),0,e),r-=t.length,r>=0&&n.indexOf(t,r)==r},yn.eq=se,yn.escape=function(n){return(n=ze(n))&&H.test(n)?n.replace(J,R):n},yn.escapeRegExp=function(n){return(n=ze(n))&&on.test(n)?n.replace(un,"\\$&"):n},yn.every=function(n,t,r){var e=No(n)?o:ot;
return r&&Br(n,t,r)&&(t=Z),e(n,wr(t,3))},yn.find=function(n,t){if(t=wr(t,3),No(n)){var r=v(n,t);return r>-1?n[r]:Z}return g(n,t,Ju)},yn.findIndex=function(n,t){return n&&n.length?v(n,wr(t,3)):-1},yn.findKey=function(n,t){return g(n,wr(t,3),at,true)},yn.findLast=function(n,t){if(t=wr(t,3),No(n)){var r=v(n,t,true);return r>-1?n[r]:Z}return g(n,t,Yu)},yn.findLastIndex=function(n,t){return n&&n.length?v(n,wr(t,3),true):-1},yn.findLastKey=function(n,t){return g(n,wr(t,3),lt,true)},yn.floor=mi,yn.forEach=ne,yn.forEachRight=te,
yn.forIn=function(n,t){return null==n?n:Hu(n,Dr(t),Ne)},yn.forInRight=function(n,t){return null==n?n:Qu(n,Dr(t),Ne)},yn.forOwn=function(n,t){return n&&at(n,Dr(t))},yn.forOwnRight=function(n,t){return n&&lt(n,Dr(t))},yn.get=Me,yn.gt=he,yn.gte=function(n,t){return n>=t},yn.has=Le,yn.hasIn=$e,yn.head=Tr,yn.identity=Ve,yn.includes=function(n,t,r,e){return n=_e(n)?n:Ze(n),r=r&&!e?We(r):0,e=n.length,0>r&&(r=Wu(e+r,0)),ke(n)?e>=r&&-1<n.indexOf(t,r):!!e&&-1<d(n,t,r)},yn.indexOf=function(n,t,r){var e=n?n.length:0;
return e?(r=We(r),0>r&&(r=Wu(e+r,0)),d(n,t,r)):-1},yn.inRange=function(n,t,r){return t=Ce(t)||0,r===Z?(r=t,t=0):r=Ce(r)||0,n=Ce(n),n>=Bu(t,r)&&n<Wu(t,r)},yn.invoke=Ho,yn.isArguments=pe,yn.isArray=No,yn.isArrayBuffer=function(n){return je(n)&&"[object ArrayBuffer]"==su.call(n)},yn.isArrayLike=_e,yn.isArrayLikeObject=ge,yn.isBoolean=function(n){return true===n||false===n||je(n)&&"[object Boolean]"==su.call(n)},yn.isBuffer=Do,yn.isDate=function(n){return je(n)&&"[object Date]"==su.call(n)},yn.isElement=function(n){
return!!n&&1===n.nodeType&&je(n)&&!Ae(n)},yn.isEmpty=function(n){if(_e(n)&&(No(n)||ke(n)||de(n.splice)||pe(n)))return!n.length;for(var t in n)if(cu.call(n,t))return false;return true},yn.isEqual=function(n,t){return yt(n,t)},yn.isEqualWith=function(n,t,r){var e=(r=typeof r=="function"?r:Z)?r(n,t):Z;return e===Z?yt(n,t,r):!!e},yn.isError=ve,yn.isFinite=function(n){return typeof n=="number"&&Iu(n)},yn.isFunction=de,yn.isInteger=ye,yn.isLength=be,yn.isMap=function(n){return je(n)&&"[object Map]"==kr(n)},yn.isMatch=function(n,t){
return n===t||bt(n,t,Ar(t))},yn.isMatchWith=function(n,t,r){return r=typeof r=="function"?r:Z,bt(n,t,Ar(t),r)},yn.isNaN=function(n){return we(n)&&n!=+n},yn.isNative=me,yn.isNil=function(n){return null==n},yn.isNull=function(n){return null===n},yn.isNumber=we,yn.isObject=xe,yn.isObjectLike=je,yn.isPlainObject=Ae,yn.isRegExp=Oe,yn.isSafeInteger=function(n){return ye(n)&&n>=-9007199254740991&&9007199254740991>=n},yn.isSet=function(n){return je(n)&&"[object Set]"==kr(n)},yn.isString=ke,yn.isSymbol=Ee,
yn.isTypedArray=Ie,yn.isUndefined=function(n){return n===Z},yn.isWeakMap=function(n){return je(n)&&"[object WeakMap]"==kr(n)},yn.isWeakSet=function(n){return je(n)&&"[object WeakSet]"==su.call(n)},yn.join=function(n,t){return n?Su.call(n,t):""},yn.kebabCase=ei,yn.last=Kr,yn.lastIndexOf=function(n,t,r){var e=n?n.length:0;if(!e)return-1;var u=e;if(r!==Z&&(u=We(r),u=(0>u?Wu(e+u,0):Bu(u,e-1))+1),t!==t)return B(n,u,true);for(;u--;)if(n[u]===t)return u;return-1},yn.lowerCase=ui,yn.lowerFirst=oi,yn.lt=Se,
yn.lte=function(n,t){return t>=n},yn.max=function(n){return n&&n.length?_(n,Ve,he):Z},yn.maxBy=function(n,t){return n&&n.length?_(n,wr(t),he):Z},yn.mean=function(n){return Xe(n)/(n?n.length:0)},yn.min=function(n){return n&&n.length?_(n,Ve,Se):Z},yn.minBy=function(n,t){return n&&n.length?_(n,wr(t),Se):Z},yn.noConflict=function(){return Vn._===this&&(Vn._=hu),this},yn.noop=He,yn.now=Wo,yn.pad=function(n,t,r){n=ze(n),t=We(t);var e=F(n);return t&&t>e?(e=(t-e)/2,t=Eu(e),e=ku(e),pr("",t,r)+n+pr("",e,r)):n;
},yn.padEnd=function(n,t,r){return n=ze(n),n+pr(n,t,r)},yn.padStart=function(n,t,r){return n=ze(n),pr(n,t,r)+n},yn.parseInt=function(n,t,r){return r||null==t?t=0:t&&(t=+t),n=ze(n).replace(fn,""),Cu(n,t||(pn.test(n)?16:10))},yn.random=function(n,t,r){if(r&&typeof r!="boolean"&&Br(n,t,r)&&(t=r=Z),r===Z&&(typeof t=="boolean"?(r=t,t=Z):typeof n=="boolean"&&(r=n,n=Z)),n===Z&&t===Z?(n=0,t=1):(n=Ce(n)||0,t===Z?(t=n,n=0):t=Ce(t)||0),n>t){var e=n;n=t,t=e}return r||n%1||t%1?(r=Uu(),Bu(n+r*(t-n+Fn("1e-"+((r+"").length-1))),t)):Ct(n,t);
},yn.reduce=function(n,t,r){var e=No(n)?s:y,u=3>arguments.length;return e(n,wr(t,4),r,u,Ju)},yn.reduceRight=function(n,t,r){var e=No(n)?h:y,u=3>arguments.length;return e(n,wr(t,4),r,u,Yu)},yn.repeat=Te,yn.replace=function(){var n=arguments,t=ze(n[0]);return 3>n.length?t:t.replace(n[1],n[2])},yn.result=function(n,t,r){if(Cr(t,n))e=null==n?Z:n[t];else{t=Nt(t);var e=Me(n,t);n=$r(n,t)}return e===Z&&(e=r),de(e)?e.call(n):e},yn.round=wi,yn.runInContext=D,yn.sample=function(n){n=_e(n)?n:Ze(n);var t=n.length;
return t>0?n[Ct(0,t-1)]:Z},yn.size=function(n){if(null==n)return 0;if(_e(n)){var t=n.length;return t&&ke(n)?F(n):t}return Fe(n).length},yn.snakeCase=fi,yn.some=function(n,t,r){var e=No(n)?p:Mt;return r&&Br(n,t,r)&&(t=Z),e(n,wr(t,3))},yn.sortedIndex=function(n,t){return Lt(n,t)},yn.sortedIndexBy=function(n,t,r){return $t(n,t,wr(r))},yn.sortedIndexOf=function(n,t){var r=n?n.length:0;if(r){var e=Lt(n,t);if(r>e&&se(n[e],t))return e}return-1},yn.sortedLastIndex=function(n,t){return Lt(n,t,true)},yn.sortedLastIndexBy=function(n,t,r){
return $t(n,t,wr(r),true)},yn.sortedLastIndexOf=function(n,t){if(n&&n.length){var r=Lt(n,t,true)-1;if(se(n[r],t))return r}return-1},yn.startCase=ci,yn.startsWith=function(n,t,r){return n=ze(n),r=nt(We(r),0,n.length),n.lastIndexOf(t,r)==r},yn.subtract=function(n,t){var r;return n===Z&&t===Z?0:(n!==Z&&(r=n),t!==Z&&(r=r===Z?t:r-t),r)},yn.sum=Xe,yn.sumBy=function(n,t){return n&&n.length?x(n,wr(t)):0},yn.template=function(n,t,r){var e=yn.templateSettings;r&&Br(n,t,r)&&(t=Z),n=ze(n),t=Po({},t,e,Tn),r=Po({},t.imports,e.imports,Tn);
var u,o,i=Fe(r),f=A(r,i),c=0;r=t.interpolate||xn;var a="__p+='";r=eu((t.escape||xn).source+"|"+r.source+"|"+(r===nn?sn:xn).source+"|"+(t.evaluate||xn).source+"|$","g");var l="sourceURL"in t?"//# sourceURL="+t.sourceURL+"\n":"";if(n.replace(r,function(t,r,e,i,f,l){return e||(e=i),a+=n.slice(c,l).replace(jn,W),r&&(u=true,a+="'+__e("+r+")+'"),f&&(o=true,a+="';"+f+";\n__p+='"),e&&(a+="'+((__t=("+e+"))==null?'':__t)+'"),c=l+t.length,t}),a+="';",(t=t.variable)||(a="with(obj){"+a+"}"),a=(o?a.replace(T,""):a).replace(K,"$1").replace(G,"$1;"),
a="function("+(t||"obj")+"){"+(t?"":"obj||(obj={});")+"var __t,__p=''"+(u?",__e=_.escape":"")+(o?",__j=Array.prototype.join;function print(){__p+=__j.call(arguments,'')}":";")+a+"return __p}",t=li(function(){return Function(i,l+"return "+a).apply(Z,f)}),t.source=a,ve(t))throw t;return t},yn.times=function(n,t){if(n=We(n),1>n||n>9007199254740991)return[];var r=4294967295,e=Bu(n,4294967295);for(t=Dr(t),n-=4294967295,e=j(e,t);++r<n;)t(r);return e},yn.toInteger=We,yn.toLength=Be,yn.toLower=function(n){
return ze(n).toLowerCase()},yn.toNumber=Ce,yn.toSafeInteger=function(n){return nt(We(n),-9007199254740991,9007199254740991)},yn.toString=ze,yn.toUpper=function(n){return ze(n).toUpperCase()},yn.trim=function(n,t,r){return(n=ze(n))?r||t===Z?n.replace(fn,""):(t+="")?(n=n.match(kn),t=t.match(kn),n.slice(O(n,t),k(n,t)+1).join("")):n:n},yn.trimEnd=function(n,t,r){return(n=ze(n))?r||t===Z?n.replace(an,""):(t+="")?(n=n.match(kn),n.slice(0,k(n,t.match(kn))+1).join("")):n:n},yn.trimStart=function(n,t,r){return(n=ze(n))?r||t===Z?n.replace(cn,""):(t+="")?(n=n.match(kn),
n.slice(O(n,t.match(kn))).join("")):n:n},yn.truncate=function(n,t){var r=30,e="...";if(xe(t))var u="separator"in t?t.separator:u,r="length"in t?We(t.length):r,e="omission"in t?ze(t.omission):e;n=ze(n);var o=n.length;if(En.test(n))var i=n.match(kn),o=i.length;if(r>=o)return n;if(o=r-F(e),1>o)return e;if(r=i?i.slice(0,o).join(""):n.slice(0,o),u===Z)return r+e;if(i&&(o+=r.length-o),Oe(u)){if(n.slice(o).search(u)){var f=r;for(u.global||(u=eu(u.source,ze(hn.exec(u))+"g")),u.lastIndex=0;i=u.exec(f);)var c=i.index;
r=r.slice(0,c===Z?o:c)}}else n.indexOf(u,o)!=o&&(u=r.lastIndexOf(u),u>-1&&(r=r.slice(0,u)));return r+e},yn.unescape=function(n){return(n=ze(n))&&Y.test(n)?n.replace(V,N):n},yn.uniqueId=function(n){var t=++au;return ze(n)+t},yn.upperCase=ai,yn.upperFirst=ii,yn.each=ne,yn.eachRight=te,yn.first=Tr,Ye(yn,function(){var n={};return at(yn,function(t,r){cu.call(yn.prototype,r)||(n[r]=t)}),n}(),{chain:false}),yn.VERSION="4.3.0",u("bind bindKey curry curryRight partial partialRight".split(" "),function(n){yn[n].placeholder=yn;
}),u(["drop","take"],function(n,t){An.prototype[n]=function(r){var e=this.__filtered__;if(e&&!t)return new An(this);r=r===Z?1:Wu(We(r),0);var u=this.clone();return e?u.__takeCount__=Bu(r,u.__takeCount__):u.__views__.push({size:Bu(r,4294967295),type:n+(0>u.__dir__?"Right":"")}),u},An.prototype[n+"Right"]=function(t){return this.reverse()[n](t).reverse()}}),u(["filter","map","takeWhile"],function(n,t){var r=t+1,e=1==r||3==r;An.prototype[n]=function(n){var t=this.clone();return t.__iteratees__.push({
iteratee:wr(n,3),type:r}),t.__filtered__=t.__filtered__||e,t}}),u(["head","last"],function(n,t){var r="take"+(t?"Right":"");An.prototype[n]=function(){return this[r](1).value()[0]}}),u(["initial","tail"],function(n,t){var r="drop"+(t?"":"Right");An.prototype[n]=function(){return this.__filtered__?new An(this):this[r](1)}}),An.prototype.compact=function(){return this.filter(Ve)},An.prototype.find=function(n){return this.filter(n).head()},An.prototype.findLast=function(n){return this.reverse().find(n);
},An.prototype.invokeMap=le(function(n,t){return typeof n=="function"?new An(this):this.map(function(r){return dt(r,n,t)})}),An.prototype.reject=function(n){return n=wr(n,3),this.filter(function(t){return!n(t)})},An.prototype.slice=function(n,t){n=We(n);var r=this;return r.__filtered__&&(n>0||0>t)?new An(r):(0>n?r=r.takeRight(-n):n&&(r=r.drop(n)),t!==Z&&(t=We(t),r=0>t?r.dropRight(-t):r.take(t-n)),r)},An.prototype.takeRightWhile=function(n){return this.reverse().takeWhile(n).reverse()},An.prototype.toArray=function(){
return this.take(4294967295)},at(An.prototype,function(n,t){var r=/^(?:filter|find|map|reject)|While$/.test(t),e=/^(?:head|last)$/.test(t),u=yn[e?"take"+("last"==t?"Right":""):t],o=e||/^find/.test(t);u&&(yn.prototype[t]=function(){var t=this.__wrapped__,i=e?[1]:arguments,f=t instanceof An,c=i[0],a=f||No(t),s=function(n){return n=u.apply(yn,l([n],i)),e&&h?n[0]:n};a&&r&&typeof c=="function"&&1!=c.length&&(f=a=false);var h=this.__chain__,p=!!this.__actions__.length,c=o&&!h,f=f&&!p;return!o&&a?(t=f?t:new An(this),
t=n.apply(t,i),t.__actions__.push({func:Qr,args:[s],thisArg:Z}),new wn(t,h)):c&&f?n.apply(this,i):(t=this.thru(s),c?e?t.value()[0]:t.value():t)})}),u("pop push shift sort splice unshift".split(" "),function(n){var t=ou[n],r=/^(?:push|sort|unshift)$/.test(n)?"tap":"thru",e=/^(?:pop|shift)$/.test(n);yn.prototype[n]=function(){var n=arguments;return e&&!this.__chain__?t.apply(this.value(),n):this[r](function(r){return t.apply(r,n)})}}),at(An.prototype,function(n,t){var r=yn[t];if(r){var e=r.name+"";(Gu[e]||(Gu[e]=[])).push({
name:t,func:r})}}),Gu[lr(Z,2).name]=[{name:"wrapper",func:Z}],An.prototype.clone=function(){var n=new An(this.__wrapped__);return n.__actions__=Yt(this.__actions__),n.__dir__=this.__dir__,n.__filtered__=this.__filtered__,n.__iteratees__=Yt(this.__iteratees__),n.__takeCount__=this.__takeCount__,n.__views__=Yt(this.__views__),n},An.prototype.reverse=function(){if(this.__filtered__){var n=new An(this);n.__dir__=-1,n.__filtered__=true}else n=this.clone(),n.__dir__*=-1;return n},An.prototype.value=function(){
var n,t=this.__wrapped__.value(),r=this.__dir__,e=No(t),u=0>r,o=e?t.length:0;n=0;for(var i=o,f=this.__views__,c=-1,a=f.length;++c<a;){var l=f[c],s=l.size;switch(l.type){case"drop":n+=s;break;case"dropRight":i-=s;break;case"take":i=Bu(i,n+s);break;case"takeRight":n=Wu(n,i-s)}}if(n={start:n,end:i},i=n.start,f=n.end,n=f-i,u=u?f:i-1,i=this.__iteratees__,f=i.length,c=0,a=Bu(n,this.__takeCount__),!e||200>o||o==n&&a==n)return qt(t,this.__actions__);e=[];n:for(;n--&&a>c;){for(u+=r,o=-1,l=t[u];++o<f;){var h=i[o],s=h.type,h=(0,
h.iteratee)(l);if(2==s)l=h;else if(!h){if(1==s)continue n;break n}}e[c++]=l}return e},yn.prototype.at=Ao,yn.prototype.chain=function(){return Hr(this)},yn.prototype.commit=function(){return new wn(this.value(),this.__chain__)},yn.prototype.flatMap=function(n){return this.map(n).flatten()},yn.prototype.next=function(){this.__values__===Z&&(this.__values__=Re(this.value()));var n=this.__index__>=this.__values__.length,t=n?Z:this.__values__[this.__index__++];return{done:n,value:t}},yn.prototype.plant=function(n){
for(var t,r=this;r instanceof mn;){var e=Zr(r);e.__index__=0,e.__values__=Z,t?u.__wrapped__=e:t=e;var u=e,r=r.__wrapped__}return u.__wrapped__=n,t},yn.prototype.reverse=function(){var n=this.__wrapped__;return n instanceof An?(this.__actions__.length&&(n=new An(this)),n=n.reverse(),n.__actions__.push({func:Qr,args:[Vr],thisArg:Z}),new wn(n,this.__chain__)):this.thru(Vr)},yn.prototype.toJSON=yn.prototype.valueOf=yn.prototype.value=function(){return qt(this.__wrapped__,this.__actions__)},mu&&(yn.prototype[mu]=Xr),
yn}var Z,q=1/0,P=NaN,T=/\b__p\+='';/g,K=/\b(__p\+=)''\+/g,G=/(__e\(.*?\)|\b__t\))\+'';/g,V=/&(?:amp|lt|gt|quot|#39|#96);/g,J=/[&<>"'`]/g,Y=RegExp(V.source),H=RegExp(J.source),Q=/<%-([\s\S]+?)%>/g,X=/<%([\s\S]+?)%>/g,nn=/<%=([\s\S]+?)%>/g,tn=/\.|\[(?:[^[\]]*|(["'])(?:(?!\1)[^\\]|\\.)*?\1)\]/,rn=/^\w*$/,en=/[^.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]/g,un=/[\\^$.*+?()[\]{}|]/g,on=RegExp(un.source),fn=/^\s+|\s+$/g,cn=/^\s+/,an=/\s+$/,ln=/\\(\\)?/g,sn=/\$\{([^\\}]*(?:\\.[^\\}]*)*)\}/g,hn=/\w*$/,pn=/^0x/i,_n=/^[-+]0x[0-9a-f]+$/i,gn=/^0b[01]+$/i,vn=/^\[object .+?Constructor\]$/,dn=/^0o[0-7]+$/i,yn=/^(?:0|[1-9]\d*)$/,bn=/[\xc0-\xd6\xd8-\xde\xdf-\xf6\xf8-\xff]/g,xn=/($^)/,jn=/['\n\r\u2028\u2029\\]/g,mn="[\\ufe0e\\ufe0f]?(?:[\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0]|\\ud83c[\\udffb-\\udfff])?(?:\\u200d(?:[^\\ud800-\\udfff]|(?:\\ud83c[\\udde6-\\uddff]){2}|[\\ud800-\\udbff][\\udc00-\\udfff])[\\ufe0e\\ufe0f]?(?:[\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0]|\\ud83c[\\udffb-\\udfff])?)*",wn="(?:[\\u2700-\\u27bf]|(?:\\ud83c[\\udde6-\\uddff]){2}|[\\ud800-\\udbff][\\udc00-\\udfff])"+mn,An="(?:[^\\ud800-\\udfff][\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0]?|[\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0]|(?:\\ud83c[\\udde6-\\uddff]){2}|[\\ud800-\\udbff][\\udc00-\\udfff]|[\\ud800-\\udfff])",On=RegExp("[\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0]","g"),kn=RegExp("\\ud83c[\\udffb-\\udfff](?=\\ud83c[\\udffb-\\udfff])|"+An+mn,"g"),En=RegExp("[\\u200d\\ud800-\\udfff\\u0300-\\u036f\\ufe20-\\ufe23\\u20d0-\\u20f0\\ufe0e\\ufe0f]"),In=/[a-zA-Z0-9]+/g,Sn=RegExp(["[A-Z\\xc0-\\xd6\\xd8-\\xde]?[a-z\\xdf-\\xf6\\xf8-\\xff]+(?=[\\xac\\xb1\\xd7\\xf7\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf\\u2018\\u2019\\u201c\\u201d \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000]|[A-Z\\xc0-\\xd6\\xd8-\\xde]|$)|(?:[A-Z\\xc0-\\xd6\\xd8-\\xde]|[^\\ud800-\\udfff\\xac\\xb1\\xd7\\xf7\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf\\u2018\\u2019\\u201c\\u201d \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000\\d+\\u2700-\\u27bfa-z\\xdf-\\xf6\\xf8-\\xffA-Z\\xc0-\\xd6\\xd8-\\xde])+(?=[\\xac\\xb1\\xd7\\xf7\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf\\u2018\\u2019\\u201c\\u201d \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000]|[A-Z\\xc0-\\xd6\\xd8-\\xde](?:[a-z\\xdf-\\xf6\\xf8-\\xff]|[^\\ud800-\\udfff\\xac\\xb1\\xd7\\xf7\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf\\u2018\\u2019\\u201c\\u201d \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000\\d+\\u2700-\\u27bfa-z\\xdf-\\xf6\\xf8-\\xffA-Z\\xc0-\\xd6\\xd8-\\xde])|$)|[A-Z\\xc0-\\xd6\\xd8-\\xde]?(?:[a-z\\xdf-\\xf6\\xf8-\\xff]|[^\\ud800-\\udfff\\xac\\xb1\\xd7\\xf7\\x00-\\x2f\\x3a-\\x40\\x5b-\\x60\\x7b-\\xbf\\u2018\\u2019\\u201c\\u201d \\t\\x0b\\f\\xa0\\ufeff\\n\\r\\u2028\\u2029\\u1680\\u180e\\u2000\\u2001\\u2002\\u2003\\u2004\\u2005\\u2006\\u2007\\u2008\\u2009\\u200a\\u202f\\u205f\\u3000\\d+\\u2700-\\u27bfa-z\\xdf-\\xf6\\xf8-\\xffA-Z\\xc0-\\xd6\\xd8-\\xde])+|[A-Z\\xc0-\\xd6\\xd8-\\xde]+|\\d+",wn].join("|"),"g"),Rn=/[a-z][A-Z]|[0-9][a-zA-Z]|[a-zA-Z][0-9]|[^a-zA-Z0-9 ]/,Wn="Array Buffer Date Error Float32Array Float64Array Function Int8Array Int16Array Int32Array Map Math Object Reflect RegExp Set String Symbol TypeError Uint8Array Uint8ClampedArray Uint16Array Uint32Array WeakMap _ clearTimeout isFinite parseInt setTimeout".split(" "),Bn={};
Bn["[object Float32Array]"]=Bn["[object Float64Array]"]=Bn["[object Int8Array]"]=Bn["[object Int16Array]"]=Bn["[object Int32Array]"]=Bn["[object Uint8Array]"]=Bn["[object Uint8ClampedArray]"]=Bn["[object Uint16Array]"]=Bn["[object Uint32Array]"]=true,Bn["[object Arguments]"]=Bn["[object Array]"]=Bn["[object ArrayBuffer]"]=Bn["[object Boolean]"]=Bn["[object Date]"]=Bn["[object Error]"]=Bn["[object Function]"]=Bn["[object Map]"]=Bn["[object Number]"]=Bn["[object Object]"]=Bn["[object RegExp]"]=Bn["[object Set]"]=Bn["[object String]"]=Bn["[object WeakMap]"]=false;
var Cn={};Cn["[object Arguments]"]=Cn["[object Array]"]=Cn["[object ArrayBuffer]"]=Cn["[object Boolean]"]=Cn["[object Date]"]=Cn["[object Float32Array]"]=Cn["[object Float64Array]"]=Cn["[object Int8Array]"]=Cn["[object Int16Array]"]=Cn["[object Int32Array]"]=Cn["[object Map]"]=Cn["[object Number]"]=Cn["[object Object]"]=Cn["[object RegExp]"]=Cn["[object Set]"]=Cn["[object String]"]=Cn["[object Symbol]"]=Cn["[object Uint8Array]"]=Cn["[object Uint8ClampedArray]"]=Cn["[object Uint16Array]"]=Cn["[object Uint32Array]"]=true,
Cn["[object Error]"]=Cn["[object Function]"]=Cn["[object WeakMap]"]=false;var Un={"\xc0":"A","\xc1":"A","\xc2":"A","\xc3":"A","\xc4":"A","\xc5":"A","\xe0":"a","\xe1":"a","\xe2":"a","\xe3":"a","\xe4":"a","\xe5":"a","\xc7":"C","\xe7":"c","\xd0":"D","\xf0":"d","\xc8":"E","\xc9":"E","\xca":"E","\xcb":"E","\xe8":"e","\xe9":"e","\xea":"e","\xeb":"e","\xcc":"I","\xcd":"I","\xce":"I","\xcf":"I","\xec":"i","\xed":"i","\xee":"i","\xef":"i","\xd1":"N","\xf1":"n","\xd2":"O","\xd3":"O","\xd4":"O","\xd5":"O","\xd6":"O",
"\xd8":"O","\xf2":"o","\xf3":"o","\xf4":"o","\xf5":"o","\xf6":"o","\xf8":"o","\xd9":"U","\xda":"U","\xdb":"U","\xdc":"U","\xf9":"u","\xfa":"u","\xfb":"u","\xfc":"u","\xdd":"Y","\xfd":"y","\xff":"y","\xc6":"Ae","\xe6":"ae","\xde":"Th","\xfe":"th","\xdf":"ss"},zn={"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;","`":"&#96;"},Mn={"&amp;":"&","&lt;":"<","&gt;":">","&quot;":'"',"&#39;":"'","&#96;":"`"},Ln={"function":true,object:true},$n={"\\":"\\","'":"'","\n":"n","\r":"r","\u2028":"u2028","\u2029":"u2029"
},Fn=parseFloat,Nn=parseInt,Dn=Ln[typeof exports]&&exports&&!exports.nodeType?exports:null,Zn=Ln[typeof module]&&module&&!module.nodeType?module:null,qn=E(Dn&&Zn&&typeof global=="object"&&global),Pn=E(Ln[typeof self]&&self),Tn=E(Ln[typeof window]&&window),Kn=Zn&&Zn.exports===Dn?Dn:null,Gn=E(Ln[typeof this]&&this),Vn=qn||Tn!==(Gn&&Gn.window)&&Tn||Pn||Gn||Function("return this")(),Jn=D();(Tn||Pn||{})._=Jn,typeof define=="function"&&typeof define.amd=="object"&&define.amd? define(function(){return Jn;
}):Dn&&Zn?(Kn&&((Zn.exports=Jn)._=Jn),Dn._=Jn):Vn._=Jn}).call(this);
'use strict';

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Util = Bahmni.Common.Util || {};

angular.module('bahmni.common.util', [])
    .provider('$bahmniCookieStore', [function () {
        var self = this;
        self.defaultOptions = {};
        var fixedEncodeURIComponent = function (str) {
            return encodeURIComponent(str).replace(/[!'()*]/g, function (c) {
                return '%' + c.charCodeAt(0).toString(16);
            });
        };

        self.setDefaultOptions = function (options) {
            self.defaultOptions = options;
        };

        self.$get = function () {
            return {
                get: function (name) {
                    var jsonCookie = $.cookie(name);
                    if (jsonCookie) {
                        return angular.fromJson(decodeURIComponent(jsonCookie));
                    }
                    return null;
                },
                put: function (name, value, options) {
                    options = $.extend({}, self.defaultOptions, options);
                    $.cookie.raw = true;
                    $.cookie(name, fixedEncodeURIComponent(angular.toJson(value)), options);
                },
                remove: function (name, options) {
                    options = $.extend({}, self.defaultOptions, options);
                    $.removeCookie(name, options);
                }
            };
        };
    }])
;

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Models = Bahmni.Common.Models || {};

angular.module('bahmni.common.models', []);

'use strict';

angular.module('bahmni.common.models')
    .factory('age', [function () {
        var dateUtil = Bahmni.Common.Util.DateUtil;

        var fromBirthDate = function (birthDate) {
            var today = dateUtil.now();
            var period = dateUtil.diffInYearsMonthsDays(birthDate, today);
            return create(period.years, period.months, period.days);
        };

        var create = function (years, months, days) {
            var isEmpty = function () {
                return !(this.years || this.months || this.days);
            };

            return {
                years: years,
                months: months,
                days: days,
                isEmpty: isEmpty
            };
        };

        var calculateBirthDate = function (age) {
            var birthDate = dateUtil.now();
            birthDate = dateUtil.subtractYears(birthDate, age.years);
            birthDate = dateUtil.subtractMonths(birthDate, age.months);
            birthDate = dateUtil.subtractDays(birthDate, age.days);
            return birthDate;
        };

        return {
            fromBirthDate: fromBirthDate,
            create: create,
            calculateBirthDate: calculateBirthDate
        };
    }]
);

Bahmni.Common.AuditLogEventDetails = {
    "USER_LOGIN_SUCCESS": {eventType: "USER_LOGIN_SUCCESS", message: "USER_LOGIN_SUCCESS_MESSAGE"},
    "USER_LOGIN_FAILED": {eventType: "USER_LOGIN_FAILED", message: "USER_LOGIN_FAILED_MESSAGE"},
    "USER_LOGOUT_SUCCESS": {eventType: "USER_LOGOUT_SUCCESS", message: "USER_LOGOUT_SUCCESS_MESSAGE"},
    "OPEN_VISIT": {eventType: "OPEN_VISIT", message: "OPEN_VISIT_MESSAGE"},
    "EDIT_VISIT": {eventType: "EDIT_VISIT", message: "EDIT_VISIT_MESSAGE"},
    "CLOSE_VISIT": {eventType: "CLOSE_VISIT", message: "CLOSE_VISIT_MESSAGE"},
    "CLOSE_VISIT_FAILED": {eventType: "CLOSE_VISIT_FAILED", message: "CLOSE_VISIT_FAILED_MESSAGE"},
    "EDIT_ENCOUNTER": {eventType: "EDIT_ENCOUNTER", message: "EDIT_ENCOUNTER_MESSAGE"},

    "VIEWED_REGISTRATION_PATIENT_SEARCH": {eventType: "VIEWED_REGISTRATION_PATIENT_SEARCH", message: "VIEWED_REGISTRATION_PATIENT_SEARCH_MESSAGE"},
    "VIEWED_NEW_PATIENT_PAGE": {eventType: "VIEWED_NEW_PATIENT_PAGE", message: "VIEWED_NEW_PATIENT_PAGE_MESSAGE"},
    "REGISTER_NEW_PATIENT": {eventType: "REGISTER_NEW_PATIENT", message: "REGISTER_NEW_PATIENT_MESSAGE"},
    "EDIT_PATIENT_DETAILS": {eventType: "EDIT_PATIENT_DETAILS", message: "EDIT_PATIENT_DETAILS_MESSAGE"},
    "ACCESSED_REGISTRATION_SECOND_PAGE": {eventType: "ACCESSED_REGISTRATION_SECOND_PAGE", message: "ACCESSED_REGISTRATION_SECOND_PAGE_MESSAGE"},
    "VIEWED_PATIENT_DETAILS": {eventType: "VIEWED_PATIENT_DETAILS", message: "VIEWED_PATIENT_DETAILS_MESSAGE"},
    "PRINT_PATIENT_STICKER": {eventType: "PRINT_PATIENT_STICKER", message: "PRINT_PATIENT_STICKER_MESSAGE"},

    "VIEWED_CLINICAL_PATIENT_SEARCH": {eventType: "VIEWED_CLINICAL_PATIENT_SEARCH", message: "VIEWED_PATIENT_SEARCH_MESSAGE"},
    "VIEWED_CLINICAL_DASHBOARD": {eventType: "VIEWED_CLINICAL_DASHBOARD", message: "VIEWED_CLINICAL_DASHBOARD_MESSAGE"},
    "VIEWED_OBSERVATIONS_TAB": {eventType: "VIEWED_OBSERVATIONS_TAB", message: "VIEWED_OBSERVATIONS_TAB_MESSAGE"},
    "VIEWED_DIAGNOSIS_TAB": {eventType: "VIEWED_DIAGNOSIS_TAB", message: "VIEWED_DIAGNOSIS_TAB_MESSAGE"},
    "VIEWED_TREATMENT_TAB": {eventType: "VIEWED_TREATMENT_TAB", message: "VIEWED_TREATMENT_TAB_MESSAGE"},
    "VIEWED_DISPOSITION_TAB": {eventType: "VIEWED_DISPOSITION_TAB", message: "VIEWED_DISPOSITION_TAB_MESSAGE"},
    "VIEWED_DASHBOARD_SUMMARY": {eventType: "VIEWED_DASHBOARD_SUMMARY", message: "VIEWED_DASHBOARD_SUMMARY_MESSAGE"},
    "VIEWED_ORDERS_TAB": {eventType: "VIEWED_ORDERS_TAB", message: "VIEWED_ORDERS_TAB_MESSAGE"},
    "VIEWED_FOLLOWUP_TAB": {eventType: "VIEWED_FOLLOWUP_TAB", message: "VIEWED_FOLLOWUPVIEWED_ORDERS_TAB_TAB_MESSAGE"},
    "VIEWED_BACTERIOLOGY_TAB": {eventType: "VIEWED_BACTERIOLOGY_TAB", message: "VIEWED_BACTERIOLOGY_TAB_MESSAGE"},
    "VIEWED_INVESTIGATION_TAB": {eventType: "VIEWED_INVESTIGATION_TAB", message: "VIEWED_INVESTIGATION_TAB_MESSAGE"},
    "VIEWED_SUMMARY_PRINT": {eventType: "VIEWED_SUMMARY_PRINT", message: "VIEWED_SUMMARY_PRINT_MESSAGE"},
    "VIEWED_VISIT_DASHBOARD": {eventType: "VIEWED_VISIT_DASHBOARD", message: "VIEWED_VISIT_DASHBOARD_MESSAGE"},
    "VIEWED_VISIT_PRINT": {eventType: "VIEWED_VISIT_PRINT", message: "VIEWED_VISIT_PRINT_MESSAGE"},
    "VIEWED_DASHBOARD_OBSERVATION": {eventType: "VIEWED_DASHBOARD_OBSERVATION", message: "VIEWED_DASHBOARD_OBSERVATION_MESSAGE"},
    "VIEWED_PATIENTPROGRAM": {eventType: "VIEWED_PATIENTPROGRAM", message: "VIEWED_PATIENTPROGRAM_MESSAGE"},

    "RUN_REPORT": {eventType: "RUN_REPORT", message: "RUN_REPORT_MESSAGE"},

    // IPD Events
    "VIEWED_WARD_LEVEL_DASHBOARD": {eventType: "VIEWED_WARD_LEVEL_DASHBOARD", message: "VIEWED_WARD_LEVEL_DASHBOARD_MESSAGE"},
    "CREATE_SCHEDULED_MEDICATION_TASK": {eventType: "CREATE_SCHEDULED_MEDICATION_TASK", message: "CREATE_SCHEDULED_MEDICATION_TASK_MESSAGE"},
    "EDIT_SCHEDULED_MEDICATION_TASK": {eventType: "EDIT_SCHEDULED_MEDICATION_TASK", message: "EDIT_SCHEDULED_MEDICATION_TASK_MESSAGE"},
    "ADMINISTER_MEDICATION_TASK": {eventType: "ADMINISTER_MEDICATION_TASK", message: "ADMINISTER_MEDICATION_TASK_MESSAGE"},
    "STOP_SCHEDULED_MEDICATION_TASK": {eventType: "STOP_SCHEDULED_MEDICATION_TASK", message: "STOP_SCHEDULED_MEDICATION_TASK_MESSAGE"},
    "SKIP_SCHEDULED_MEDICATION_TASK": {eventType: "SKIP_SCHEDULED_MEDICATION_TASK", message: "SKIP_SCHEDULED_MEDICATION_TASK_MESSAGE"},
    "CREATE_EMERGENCY_MEDICATION_TASK": {eventType: "CREATE_EMERGENCY_MEDICATION_TASK", message: "CREATE_EMERGENCY_MEDICATION_TASK_MESSAGE"},
    "CREATE_NON_MEDICATION_TASK": {eventType: "CREATE_NON_MEDICATION_TASK", message: "CREATE_NON_MEDICATION_TASK_MESSAGE"},
    "SKIP_SCHEDULED_NON_MEDICATION_TASK": {eventType: "SKIP_SCHEDULED_NON_MEDICATION_TASK", message: "SKIP_SCHEDULED_NON_MEDICATION_TASK_MESSAGE"},
    "NON_MEDICATION_TASK_COMPLETED": {eventType: "NON_MEDICATION_TASK_COMPLETED", message: "NON_MEDICATION_TASK_COMPLETED_MESSAGE"}
};

angular.module('FredrikSandell.worker-pool', []).service('WorkerService', [
    '$q',
    function ($q) {
        var that = {};
        //this should be configured from the app in the future
        var urlToAngular = 'http://localhost:9876/base/bower_components/angular/angular.js';
        var serviceToUrlMap = {};
        var storage = {};
        var scriptsToLoad = [];
        that.setAngularUrl = function (urlToAngularJs) {
            urlToAngular = urlToAngularJs;
        };
        function createAngularWorkerTemplate() {
            /*jshint laxcomma:true */
            /*jshint quotmark: false */
            var workerTemplate = [
                '',
                '//try {',
                'var window = self;',
                'self.history = {};',
                'var Node = function() {};',
                'var app',
                'var localStorage = {storage: <STORAGE>, getItem: function(key) {return this.storage[key]}, setItem: function(key, value) {this.storage[key]=value}}',
                'var document = {',
                '      readyState: \'complete\',',
                '      cookie: \'\',',
                '      querySelector: function () {},',
                '      createElement: function () {',
                '          return {',
                '              pathname: \'\',',
                '              setAttribute: function () {}',
                '          };',
                '      }',
                '};',
                'importScripts(\'<URL_TO_ANGULAR>\');',
                '<CUSTOM_DEP_INCLUDES>',
                'angular = window.angular;',
                'var workerApp = angular.module(\'WorkerApp\', [<DEP_MODULES>]);',
                'workerApp.run([\'$q\'<STRING_DEP_NAMES>, function ($q<DEP_NAMES>) {',
                '  self.addEventListener(\'message\', function(e) {',
                '    var input = e.data;',
                '    var output = $q.defer();',
                '    var promise = output.promise;',
                '    promise.then(function(success) {',
                '      self.postMessage({event:\'success\', data : success});',
                '    }, function(reason) {',
                '      self.postMessage({event:\'failure\', data : reason});',
                '    }, function(update) {',
                '      self.postMessage({event:\'update\', data : update});',
                '    });',
                '    <WORKER_FUNCTION>;',
                '  });',
                '  self.postMessage({event:\'initDone\'});',
                '}]);',
                'angular.bootstrap(null, [\'WorkerApp\']);',
                '//} catch(e) {self.postMessage(JSON.stringify(e));}'
            ];
            return workerTemplate.join('\n');
        }
        var workerTemplate = createAngularWorkerTemplate();
        that.addDependency = function (serviceName, moduleName, url) {
            serviceToUrlMap[serviceName] = {
                url: url,
                moduleName: moduleName
            };
            return that;
        };
        that.includeScripts = function(url) {
            scriptsToLoad.push(url);
        };
        that.addToLocalStorage = function(key, value) {
            storage[key] = value;
        };
        function createIncludeStatements(listOfServiceNames) {
            var includeString = '';
            angular.forEach(scriptsToLoad, function(script) {
                includeString += 'importScripts(\'' + script + '\');';
            });

            angular.forEach(listOfServiceNames, function (serviceName) {
                if (serviceToUrlMap[serviceName]) {
                    includeString += 'importScripts(\'' + serviceToUrlMap[serviceName].url + '\');';
                }
            });
            return includeString;
        }
        function createModuleList(listOfServiceNames) {
            var moduleNameList = [];
            angular.forEach(listOfServiceNames, function (serviceName) {
                if (serviceToUrlMap[serviceName]) {
                    moduleNameList.push('\'' + serviceToUrlMap[serviceName].moduleName + '\'');
                }
            });
            return moduleNameList.join(',');
        }
        function createDependencyMetaData(dependencyList) {
            var dependencyServiceNames = dependencyList.filter(function (dep) {
                return dep !== 'input' && dep !== 'output' && dep !== '$q';
            });
            var depMetaData = {
                dependencies: dependencyServiceNames,
                moduleList: createModuleList(dependencyServiceNames),
                angularDepsAsStrings: dependencyServiceNames.length > 0 ? ',' + dependencyServiceNames.map(function (dep) {
                    return '\'' + dep + '\'';
                }).join(',') : '',
                angularDepsAsParamList: dependencyServiceNames.length > 0 ? ',' + dependencyServiceNames.join(',') : '',
                servicesIncludeStatements: createIncludeStatements(dependencyServiceNames)
            };
            depMetaData.workerFuncParamList = 'input,output' + depMetaData.angularDepsAsParamList;
            return depMetaData;
        }
        function populateWorkerTemplate(workerFunc, dependencyMetaData) {
            return workerTemplate
                .replace('<URL_TO_ANGULAR>', urlToAngular)
                .replace('<CUSTOM_DEP_INCLUDES>', dependencyMetaData.servicesIncludeStatements)
                .replace('<DEP_MODULES>', dependencyMetaData.moduleList)
                .replace('<STRING_DEP_NAMES>', dependencyMetaData.angularDepsAsStrings)
                .replace('<DEP_NAMES>', dependencyMetaData.angularDepsAsParamList)
                .replace('<STORAGE>', JSON.stringify(storage))
                .replace('<WORKER_FUNCTION>', workerFunc.toString());
        }
        var buildAngularWorker = function (initializedWorker) {
            var that = {};
            that.worker = initializedWorker;
            that.run = function (input) {
                var deferred = $q.defer();
                initializedWorker.addEventListener('message', function (e) {
                    var eventId = e.data.event;
                    //console.log(e.data);
                    if (eventId === 'initDone') {
                        throw 'Received worker initialization in run method. This should already have occurred!';
                    } else if (eventId === 'success') {
                        deferred.resolve(e.data.data);
                    } else if (eventId === 'failure') {
                        deferred.reject(e.data.data);
                    } else if (eventId === 'update') {
                        deferred.notify(e.data.data);
                    } else {
                        deferred.reject(e);
                    }
                });
                initializedWorker.postMessage(input);
                return deferred.promise;
            };
            that.terminate = function () {
                initializedWorker.terminate();
            };
            return that;
        };
        var extractDependencyList = function (depFuncList) {
            return depFuncList.slice(0, depFuncList.length - 1);
        };
        var workerFunctionToString = function (func, paramList) {
            return '(' + func.toString() + ')(' + paramList + ')';
        };
        /**
         * example call:
         * WorkerService.createAngularWorker(['input', 'output', '$http', function(input, output, $http)
         * {body of function}]);
         * Parameters "input" and "output" is required. Not defining them will cause a runtime error.
         * Declaring services to be injected, as '$http' is above, requires the web worker to be able to resolve them.
         * '$http' service is a part of the standard angular package which means it will resolve without additional information
         * since angular source is always loaded in the web worker.
         * But if a custom service was to be injected the WorkerService would need be be informed on how to resolve the.
         * @param depFuncList
         */
        that.createAngularWorker = function (depFuncList) {
            //validate the input
            if (!Array.isArray(depFuncList) || depFuncList.length < 3 || typeof depFuncList[depFuncList.length - 1] !== 'function') {
                throw 'Input needs to be: [\'workerInput\',\'deferredOutput\'/*optional additional dependencies*/,\n' + '    function(workerInput, deferredOutput /*optional additional dependencies*/)\n' + '        {/*worker body*/}' + ']';
            }
            var deferred = $q.defer();
            var dependencyMetaData = createDependencyMetaData(extractDependencyList(depFuncList));
            var blobURL = (window.webkitURL ? webkitURL : URL).createObjectURL(new Blob([populateWorkerTemplate(workerFunctionToString(depFuncList[depFuncList.length - 1], dependencyMetaData.workerFuncParamList), dependencyMetaData)], { type: 'application/javascript' }));
            var worker = new Worker(blobURL);
            //wait for the worker to load resources
            worker.addEventListener('message', function (e) {
                var eventId = e.data.event;
                console.log(e.data);
                if (eventId === 'initDone') {
                    deferred.resolve(buildAngularWorker(worker));
                } else {
                    deferred.reject(e);
                }
            });
            return deferred.promise;
        };
        return that;
    }
]);
'use strict';

angular.module('bahmni.common.routeErrorHandler', ['ui.router'])
    .run(['$rootScope', function ($rootScope) {
        $rootScope.$on('$stateChangeError', function (event) {
            event.preventDefault();
        });
    }]);

'use strict';

const clientTimeDisplayFormat = Bahmni.Common.Constants.clientTimeDisplayFormat;
const clientDateDisplayFormat = Bahmni.Common.Constants.clientDateDisplayFormat;

Bahmni.Common.Util.DateUtil = {
    diffInDays: function (dateFrom, dateTo) {
        return Math.floor((this.parse(dateTo) - this.parse(dateFrom)) / (60 * 1000 * 60 * 24));
    },

    diffInMinutes: function (dateFrom, dateTo) {
        return moment(dateTo).diff(moment(dateFrom), 'minutes');
    },

    diffInSeconds: function (dateFrom, dateTo) {
        return moment(dateFrom).diff(moment(dateTo), 'seconds');
    },

    isInvalid: function (date) {
        return date == "Invalid Date";
    },

    diffInDaysRegardlessOfTime: function (dateFrom, dateTo) {
        var from = new Date(dateFrom);
        var to = new Date(dateTo);
        from.setHours(0, 0, 0, 0);
        to.setHours(0, 0, 0, 0);
        return Math.floor((to - from) / (60 * 1000 * 60 * 24));
    },

    addSeconds: function (date, seconds) {
        return moment(date).add(seconds, 'seconds').toDate();
    },

    addMinutes: function (date, minutes) {
        return this.addSeconds(date, minutes * 60);
    },

    addDays: function (date, days) {
        return moment(date).add(days, 'day').toDate();
    },
    addMonths: function (date, months) {
        return moment(date).add(months, 'month').toDate();
    },
    addYears: function (date, years) {
        return moment(date).add(years, 'year').toDate();
    },

    subtractSeconds: function (date, seconds) {
        return moment(date).subtract(seconds, 'seconds').toDate();
    },
    subtractDays: function (date, days) {
        return this.addDays(date, -1 * days);
    },
    subtractISOWeekDays: function (date, days) {
        if (days == null) {
            return moment(date).isoWeekday();
        }
        return moment(date).isoWeekday() >= days ? moment(date).isoWeekday() - days
            : 7 + moment(date).isoWeekday() - days;
    },
    subtractMonths: function (date, months) {
        return this.addMonths(date, -1 * months);
    },
    subtractYears: function (date, years) {
        return this.addYears(date, -1 * years);
    },

    createDays: function (startDate, endDate) {
        var startDate = this.getDate(startDate);
        var endDate = this.getDate(endDate);
        var numberOfDays = this.diffInDays(startDate, endDate);
        var days = [];
        for (var i = 0; i <= numberOfDays; i++) {
            days.push({dayNumber: i + 1, date: this.addDays(startDate, i)});
        }
        return days;
    },

    getDayNumber: function (referenceDate, date) {
        return this.diffInDays(this.getDate(referenceDate), this.getDate(date)) + 1;
    },

    getDateWithoutTime: function (datetime) {
        return datetime ? moment(datetime).format("YYYY-MM-DD") : null;
    },

    getDateInMonthsAndYears: function (date, format) {
        var format = format || "MMM YYYY";
        var dateRepresentation = isNaN(Number(date)) ? date : Number(date);
        if (!moment(dateRepresentation).isValid()) {
            return date;
        }
        return dateRepresentation ? moment(dateRepresentation).format(format) : null;
    },

    formatDateWithTime: function (datetime) {
        var dateRepresentation = isNaN(Number(datetime)) ? datetime : Number(datetime);
        if (!moment(dateRepresentation).isValid()) {
            return datetime;
        }
        return dateRepresentation ? moment(dateRepresentation).format(clientDateDisplayFormat + " " + clientTimeDisplayFormat) : null;
    },

    formatDateWithoutTime: function (dateTime) {
        var dateRepresentation = isNaN(Number(dateTime)) ? dateTime : Number(dateTime);
        if (!moment(dateRepresentation).isValid()) {
            return dateTime;
        }
        return dateRepresentation ? moment(dateRepresentation).format(clientDateDisplayFormat) : null;
    },

    formatDateWithoutTimeToLocal: function (dateTime) {
        var dateRepresentation = isNaN(Number(dateTime)) ? dateTime : Number(dateTime);
        if (!moment(dateRepresentation).isValid()) {
            return dateTime;
        }
        return dateRepresentation ? moment.utc(dateTime).local().format(clientDateDisplayFormat) : null;
    },

    formatDateInStrictMode: function (date) {
        var dateRepresentation = isNaN(Number(date)) ? date : Number(date);
        if (moment(dateRepresentation, 'YYYY-MM-DD', true).isValid()) {
            return moment(dateRepresentation).format(clientDateDisplayFormat);
        }
        if (moment(dateRepresentation, 'YYYY-MM-DDTHH:mm:ss.SSSZZ', true).isValid()) {
            return moment(dateRepresentation).format(clientDateDisplayFormat);
        }
        return date;
    },

    formatTime: function (dateTime) {
        var dateRepresentation = isNaN(Number(dateTime)) ? dateTime : Number(dateTime);
        if (!moment(dateRepresentation).isValid()) {
            return dateTime;
        }
        return dateRepresentation ? moment(dateRepresentation).format(clientTimeDisplayFormat) : null;
    },

    formatTimeToLocal: function (dateTime) {
        var dateRepresentation = isNaN(Number(dateTime)) ? dateTime : Number(dateTime);
        if (!moment(dateRepresentation).isValid()) {
            return dateTime;
        }
        return dateRepresentation ? moment.utc(dateTime).local().format(clientTimeDisplayFormat) : null;
    },

    getDate: function (dateTime) {
        return moment(this.parse(dateTime)).startOf('day').toDate();
    },

    parse: function (dateString) {
        return dateString ? moment(dateString).toDate() : null;
    },

    parseDatetime: function (dateTimeString) {
        return dateTimeString ? moment(dateTimeString) : null;
    },

    now: function () {
        return new Date();
    },

    today: function () {
        return this.getDate(this.now());
    },
    endOfToday: function () {
        return moment(this.parse(this.now())).endOf('day').toDate();
    },

    getDateWithoutHours: function (dateString) {
        return moment(dateString).toDate().setHours(0, 0, 0, 0);
    },

    getDateTimeWithoutSeconds: function (dateString) {
        return moment(dateString).toDate().setSeconds(0, 0);
    },

    isSameDateTime: function (date1, date2) {
        if (date1 == null || date2 == null) {
            return false;
        }
        var dateOne = this.parse(date1);
        var dateTwo = this.parse(date2);
        return dateOne.getTime() == dateTwo.getTime();
    },

    isBeforeDate: function (date1, date2) {
        return moment(date1).isBefore(moment(date2));
    },
    isSameDate: function (date1, date2) {
        if (date1 == null || date2 == null) {
            return false;
        }
        var dateOne = this.parse(date1);
        var dateTwo = this.parse(date2);
        return dateOne.getFullYear() === dateTwo.getFullYear() &&
            dateOne.getMonth() === dateTwo.getMonth() &&
            dateOne.getDate() === dateTwo.getDate();
    },

    diffInYearsMonthsDays: function (dateFrom, dateTo) {
        dateFrom = this.parse(dateFrom);
        dateTo = this.parse(dateTo);

        var from = {
            d: dateFrom.getDate(),
            m: dateFrom.getMonth(),
            y: dateFrom.getFullYear()
        };

        var to = {
            d: dateTo.getDate(),
            m: dateTo.getMonth(),
            y: dateTo.getFullYear()
        };

        var age = {
            d: 0,
            m: 0,
            y: 0
        };

        var daysFebruary = (from.y % 4 === 0 && from.y % 100 !== 0) || from.y % 400 === 0 ? 29 : 28;
        var daysInMonths = [31, daysFebruary, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        age.y = to.y - from.y;
        age.m = to.m - from.m;

        if (from.m > to.m) {
            age.y = age.y - 1;
            age.m = to.m - from.m + 12;
        }
        age.d = to.d - from.d;

        if (from.d > to.d) {
            age.m = age.m - 1;

            if (from.m == to.m) {
                age.y = age.y - 1;
                age.m = age.m + 12;
            }
            age.d = to.d - from.d + daysInMonths[parseInt(from.m)];
        }
        return {
            days: age.d,
            months: age.m,
            years: age.y
        };
    },

    convertToUnits: function (minutes) {
        var allUnits = {"Years": 365 * 24 * 60, "Months": 30 * 24 * 60, "Weeks": 7 * 24 * 60, "Days": 24 * 60, "Hours": 60, "Minutes": 1};

        var durationRepresentation = function (value, unitName, unitValueInMinutes) {
            return {"value": value, "unitName": unitName, "unitValueInMinutes": unitValueInMinutes, "allUnits": allUnits };
        };

        for (var unitName in allUnits) {
            var unitValueInMinutes = allUnits[unitName];
            if (minutes || minutes !== 0) {
                if (minutes >= unitValueInMinutes && minutes % unitValueInMinutes === 0) {
                    return durationRepresentation(minutes / unitValueInMinutes, unitName, unitValueInMinutes);
                }
            }
        }
        return durationRepresentation(undefined, undefined, undefined);
    },

    getEndDateFromDuration: function (dateFrom, value, unit) {
        dateFrom = this.parse(dateFrom);
        var from = {
            h: dateFrom.getHours(),
            d: dateFrom.getDate(),
            m: dateFrom.getMonth(),
            y: dateFrom.getFullYear()
        };
        var to = new Date(from.y, from.m, from.d, from.h);

        if (unit === "Months") {
            to.setMonth(from.m + value);
        } else if (unit === "Weeks") {
            to.setDate(from.d + (value * 7));
        } else if (unit === "Days") {
            to.setDate(from.d + value);
        } else if (unit === "Hours") {
            to.setHours(from.h + value);
        }
        return to;
    },

    parseLongDateToServerFormat: function (longDate) {
        return longDate ? moment(longDate).format("YYYY-MM-DDTHH:mm:ss.SSSZZ") : null;
    },

    parseServerDateToDate: function (longDate) {
        return longDate ? moment(longDate, "YYYY-MM-DDTHH:mm:ss.SSSZZ").toDate() : null;
    },
    getDateTimeInSpecifiedFormat: function (date, format) {
        return date ? moment(date).format(format) : null;
    },
    getISOString: function (date) {
        return date ? moment(date).toDate().toISOString() : null;
    },
    isBeforeTime: function (time, otherTime) {
        return moment(time, clientTimeDisplayFormat).format('YYYY-MM-DD');
    },
    getWeekStartDate: function (date, startOfWeek) {
        var daysToBeSubtracted = this.subtractISOWeekDays(date, startOfWeek);
        return moment(date).subtract(daysToBeSubtracted, 'days').toDate();
    },
    getWeekEndDate: function (weekStartDate) {
        return moment(weekStartDate).add(6, 'days').toDate();
    }
};

'use strict';

Bahmni.Common.Util.ValidationUtil = (function () {
    var isAcceptableType = function (propertyToCheck) {
        return _.includes(["string", "boolean", "number", "object"], typeof propertyToCheck);
    };

    var flattenObject = function (ob) {
        var toReturn = {};
        for (var i in ob) {
            if (!ob.hasOwnProperty(i) || !isAcceptableType(ob[i])) {
                continue;
            }
            if ((typeof ob[i]) == 'object' && !(ob[i] instanceof Date)) {
                var flatObject = flattenObject(ob[i]);
                for (var x in flatObject) {
                    if (!flatObject.hasOwnProperty(x) || !isAcceptableType(flatObject[x])) {
                        continue;
                    }
                    toReturn[i + '.' + x] = flatObject[x];
                }
            } else {
                toReturn[i] = ob[i];
            }
        }
        return toReturn;
    };

    // This will work only for patient attributes, since we are passing concept behind the attribute.
    // To have a generic one, we need to remove the concept dependency.. And concept will be null for non concept fields
    var validate = function (complexObject, objectConfiguration) {
        var allCustomValidators = Bahmni.Registration.customValidator;
        if (!allCustomValidators) {
            return [];
        }

        var dataArray = flattenObject(complexObject);
        var errorMessages = [];
        _.every(dataArray, function (value, field) {
            var isValid = true;
            var fieldSpecificValidator = allCustomValidators[field];
            if (!fieldSpecificValidator) {
                return isValid;
            }
            if (typeof fieldSpecificValidator.method == 'function' && value) {
                var personAttributeTypeConfig = _.find(objectConfiguration, {name: field});
                isValid = fieldSpecificValidator.method(field, value, personAttributeTypeConfig);
                if (!isValid) {
                    errorMessages.push(fieldSpecificValidator.errorMessage);
                    isValid = true;
                }
            }
            return isValid;
        });
        return errorMessages;
    };
    return {
        validate: validate
    };
})();

'use strict';

Bahmni.Common.Util.DynamicResourceLoader = (function () {
    return {
        includeJs: function (script) {
            var element = document.createElement('script');
            element.setAttribute('src', script);
            document.body.appendChild(element);
        },
        includeCss: function (url) {
            var element = document.createElement('link');
            element.setAttribute('href', url);
            element.setAttribute('rel', "stylesheet");
            element.setAttribute('type', "text/css");
            document.head.appendChild(element);
        }
    };
})();

'use strict';

Bahmni.Common.Util.ArrayUtil = {
    chunk: function (array, chunkSize) {
        var chunks = [];
        for (var i = 0; i < array.length; i += chunkSize) {
            chunks.push(array.slice(i, i + chunkSize));
        }
        return chunks;
    },

    groupByPreservingOrder: function (records, groupingFunction, keyName, valueName) {
        var groups = [];
        records.forEach(function (record) {
            var recordKey = groupingFunction(record);
            var existingGroup = _.find(groups, function (group) { return group[keyName] === recordKey; });
            if (existingGroup) {
                existingGroup[valueName].push(record);
            } else {
                var newGroup = {};
                newGroup[keyName] = recordKey;
                newGroup[valueName] = [record];
                groups.push(newGroup);
            }
        });
        return groups;
    }
};

'use strict';
Bahmni.Common.Util.FormFieldPathUtil = {
    getFormNameAndVersion: function (path) {
        var formNameAndVersion = (path.split("/")[0]).split('.');
        return {
            formName: formNameAndVersion[0],
            formVersion: formNameAndVersion[1]
        };
    }
};

'use strict';

angular.module('httpErrorInterceptor', [])
    .config(['$httpProvider', function ($httpProvider) {
        var interceptor = ['$rootScope', '$q', function ($rootScope, $q) {
            var serverErrorMessages = Bahmni.Common.Constants.serverErrorMessages;

            var showError = function (errorMessage) {
                var result = _.find(serverErrorMessages, function (listItem) {
                    return listItem.serverMessage === errorMessage;
                });
                if (_.isEmpty(result)) {
                    $rootScope.$broadcast('event:serverError', errorMessage);
                }
            };

            function stringAfter (value, searchString) {
                var indexOfFirstColon = value.indexOf(searchString);
                return value.substr(indexOfFirstColon + 1).trim();
            }

            function getServerError (message) {
                return stringAfter(message, ':');
            }

            function success (response) {
                return response;
            }

            function shouldRedirectToLogin (response) {
                var errorMessage = response.data.error ? response.data.error.message : response.data;
                if (errorMessage.search("Session timed out") > 0) {
                    return true;
                }
            }

            function error (response) {
                var data = response.data;
                var unexpectedError = "There was an unexpected issue on the server. Please try again";
                if (response.status === 500) {
                    var errorMessage = data.error && data.error.message ? getServerError(data.error.message) : unexpectedError;
                    showError(errorMessage);
                } else if (response.status === 409) {
                    var errorMessage = data.error && data.error.message ? getServerError(data.error.message) : "Duplicate entry error";
                    showError(errorMessage);
                } else if (response.status === 0) {
                    showError("Could not connect to the server. Please check your connection and try again");
                } else if (response.status === 405) {
                    showError(unexpectedError);
                } else if (response.status === 400) {
                    var errorMessage = data.error && data.error.message ? data.error.message : data.error ? data.error : (data.localizedMessage || "Bad request. Please try again");
                    showError(errorMessage);
                } else if (response.status === 403) {
                    var errorMessage = data.error && data.error.message ? data.error.message : unexpectedError;
                    if (shouldRedirectToLogin(response)) {
                        $rootScope.$broadcast('event:auth-loginRequired');
                    } else {
                        showError(errorMessage);
                    }
                } else if (response.status === 404) {
                    if (!_.includes(response.config.url, "implementation_config") && !_.includes(response.config.url, "locale_") &&
                        !_.includes(response.config.url, "offlineMetadata")) {
                        showError("The requested information does not exist");
                    }
                }
                return $q.reject(response);
            }

            return {
                response: success,
                responseError: error
            };
        }];
        $httpProvider.interceptors.push(interceptor);
    }]);

'use strict';

Bahmni.Common.VisitControl = function (visitTypes, defaultVisitTypeName, encounterService,
    $translate, visitService) {
    var self = this;
    self.visitTypes = visitTypes;
    self.defaultVisitTypeName = defaultVisitTypeName;
    self.defaultVisitType = visitTypes.filter(function (visitType) {
        return visitType.name === defaultVisitTypeName;
    })[0];

    self.startButtonText = function (visitType) {
        return $translate.instant('REGISTRATION_START_VISIT', {visitType: visitType.name});
    };

    self.startVisit = function (visitType) {
        self.onStartVisit();
        self.selectedVisitType = visitType;
    };

    self.checkIfActiveVisitExists = function (patientUuid, visitLocationUuid) {
        return visitService.checkIfActiveVisitExists(patientUuid, visitLocationUuid);
    };

    self.createVisitOnly = function (patientUuid, visitLocationUuid) {
        var visitType = self.selectedVisitType || self.defaultVisitType;
        var visitDetails = {patient: patientUuid, visitType: visitType.uuid, location: visitLocationUuid};
        return visitService.createVisit(visitDetails);
    };
};


'use strict';
Bahmni.Common.Util.TranslationUtil = {
    translateAttribute: function (attribute, moduleName, $translate) {
        if (typeof attribute != 'undefined') {
            if ((moduleName == null) || (typeof moduleName == 'undefined')) {
                var keyPrefix = " ";
            } else {
                keyPrefix = moduleName;
            }

            var keyName = attribute.toUpperCase().replace(/\s\s+/g, ' ').replace(/[^a-zA-Z0-9 _]/g, "").trim().replace(/ /g, "_");
            var translationKey = keyPrefix + "_" + keyName;
            var translation = $translate.instant(translationKey);
            if (translation != translationKey) {
                attribute = translation;
            }
        }
        return attribute;
    }
};

'use strict';

Bahmni.Common.Util.GenderUtil = {
    translateGender: function (genderMap, $translate) {
        _.forEach(genderMap, function (value, key) {
            var translationKey = "GENDER_" + key.toUpperCase();
            var translatedGender = $translate.instant(translationKey);
            if (translatedGender != translationKey) {
                genderMap[key] = translatedGender;
            }
        });
    }
};

'use strict';

angular.module('bahmni.common.util')
    .factory('providerInfoService', [ '$rootScope', function ($rootScope) {
        $rootScope.provider = null;
        var setProvider = function (obs) {
            if ($rootScope.provider === null) {
                if (obs.length > 0) {
                    $rootScope.provider = obs[0].providers;
                }
            }
        };
        return {
            setProvider: setProvider
        };
    }]);

angular.module('bahmni.common.config', []);

'use strict';

angular.module('bahmni.common.config')
    .service('configurations', ['configurationService', function (configurationService) {
        this.configs = {};

        this.load = function (configNames) {
            var self = this;
            return configurationService.getConfigurations(_.difference(configNames, Object.keys(this.configs))).then(function (configurations) {
                angular.extend(self.configs, configurations);
            });
        };

        this.dosageInstructionConfig = function () {
            return this.configs.dosageInstructionConfig || [];
        };

        this.stoppedOrderReasonConfig = function () {
            return this.configs.stoppedOrderReasonConfig || [];
        };

        this.dosageFrequencyConfig = function () {
            return this.configs.dosageFrequencyConfig || [];
        };

        this.allTestsAndPanelsConcept = function () {
            return this.configs.allTestsAndPanelsConcept && this.configs.allTestsAndPanelsConcept.results && this.configs.allTestsAndPanelsConcept.results[0] ? this.configs.allTestsAndPanelsConcept.results[0] : [];
        };

        this.impressionConcept = function () {
            return this.configs.radiologyImpressionConfig && this.configs.radiologyImpressionConfig.results && this.configs.radiologyImpressionConfig.results[0] ? this.configs.radiologyImpressionConfig.results[0] : [];
        };

        this.labOrderNotesConcept = function () {
            return this.configs.labOrderNotesConfig && this.configs.labOrderNotesConfig.results && this.configs.labOrderNotesConfig.results[0] ? this.configs.labOrderNotesConfig.results[0] : [];
        };

        this.consultationNoteConcept = function () {
            return this.configs.consultationNoteConfig && this.configs.consultationNoteConfig.results && this.configs.consultationNoteConfig.results[0] ? this.configs.consultationNoteConfig.results[0] : [];
        };

        this.patientConfig = function () {
            return this.configs.patientConfig ? this.configs.patientConfig : {};
        };

        this.encounterConfig = function () {
            return angular.extend(new EncounterConfig(), this.configs.encounterConfig || []);
        };

        this.patientAttributesConfig = function () {
            return this.configs.patientAttributesConfig.results;
        };

        this.identifierTypesConfig = function () {
            return this.configs.identifierTypesConfig;
        };

        this.genderMap = function () {
            return this.configs.genderMap;
        };

        this.addressLevels = function () {
            return this.configs.addressLevels;
        };

        this.relationshipTypes = function () {
            return this.configs.relationshipTypeConfig && this.configs.relationshipTypeConfig.results ? this.configs.relationshipTypeConfig.results : [];
        };

        this.relationshipTypeMap = function () {
            return this.configs.relationshipTypeMap ? this.configs.relationshipTypeMap : {};
        };

        this.loginLocationToVisitTypeMapping = function () {
            return this.configs.loginLocationToVisitTypeMapping || {};
        };

        this.defaultEncounterType = function () {
            return this.configs.defaultEncounterType;
        };

        this.helpDeskNumber = function () {
            return this.configs.helpDeskNumber;
        };

        this.maxStorageSpace = function () {
            return this.configs.maxStorageSpace;
        };

        this.prescriptionEmailToggle = function () {
            return this.configs.prescriptionEmailToggle;
        };

        this.quickLogoutComboKey = function () {
            return this.configs.quickLogoutComboKey;
        };

        this.contextCookieExpirationTimeInMinutes = function () {
            return this.configs.contextCookieExpirationTimeInMinutes;
        };
    }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Domain = Bahmni.Common.Domain || {};
Bahmni.Common.Domain.Helper = Bahmni.Common.Domain.Helper || {};

angular.module('bahmni.common.domain', []);

'use strict';

(function () {
    Bahmni.Common.Domain.ObservationFilter = function () {
        var self = this;

        var voidExistingObservationWithOutValue = function (observations) {
            observations.forEach(function (observation) {
                voidExistingObservationWithOutValue(observation.groupMembers);
                observation.voided = observation.voided || observation.canBeVoided();

                if (observation.voided) {
                    voidAllChildren(observation);
                }
            });
        };

        var voidAllChildren = function (voidedObservation) {
            voidedObservation.groupMembers.forEach(function (childWithVoidedParent) {
                childWithVoidedParent.voided = true;

                voidAllChildren(childWithVoidedParent);
            });
        };

        var removeNewObservationsWithoutValue = function (observations) {
            observations.forEach(function (observation) {
                observation.groupMembers = removeNewObservationsWithoutValue(observation.groupMembers);
            });
            return observations.filter(function (observation) {
                var validObs = observation.isExisting() || observation.hasValue() || observation.hasMemberWithValue();
                return (validObs && !observation.voided) || (observation.isExisting() && observation.voided);
            });
        };

        var removeNewObservationsWhichAreVoided = function (observations) {
            observations.forEach(function (observation) {
                observation.groupMembers = removeNewObservationsWhichAreVoided(observation.groupMembers);
            });
            return _.reject(observations, function (observation) {
                return observation.isNew() && observation.voided;
            });
        };

        self.filter = function (observations) {
            var wrappedObservations = observations.map(Observation.wrap);
            var filteredObservations = removeNewObservationsWithoutValue(wrappedObservations);
            filteredObservations = removeNewObservationsWhichAreVoided(filteredObservations);
            voidExistingObservationWithOutValue(filteredObservations);
            return filteredObservations;
        };
    };

    var Observation = function (observationData) {
        angular.extend(this, observationData);

        this.isNew = function () {
            return !this.uuid;
        };

        this.isExisting = function () {
            return !this.isNew();
        };

        this.hasValue = function () {
            return this.value !== undefined && this.value !== null && this.value !== '';
        };

        this.hasMemberWithValue = function () {
            return this.groupMembers.some(function (groupMember) {
                return groupMember.hasValue() || groupMember.hasMemberWithValue();
            });
        };

        this.isGroup = function () {
            return this.groupMembers.length > 0;
        };

        this.isLeaf = function () {
            return !this.isGroup();
        };

        this.isGroupWithOnlyVoidedMembers = function () {
            return this.isGroup() && this.groupMembers.every(function (groupMember) {
                return groupMember.voided;
            });
        };

        this.isLeafNodeWithOutValue = function () {
            return this.isLeaf() && !this.hasValue();
        };

        this.canBeVoided = function () {
            return this.isExisting() && (this.isLeafNodeWithOutValue() || this.isGroupWithOnlyVoidedMembers());
        };
    };

    Observation.wrap = function (observationData) {
        var observation = new Observation(observationData);
        observation.groupMembers = observation.groupMembers ? observation.groupMembers.map(Observation.wrap) : [];
        return observation;
    };
})();


'use strict';

Bahmni.Common.Domain.Helper.getHintForNumericConcept = function (concept) {
    if (!concept) {
        return;
    }
    if (concept.hiNormal != null && concept.lowNormal != null) {
        return '(' + concept.lowNormal + ' - ' + concept.hiNormal + ')';
    }
    if (concept.hiNormal != null && concept.lowNormal == null) {
        return '(< ' + concept.hiNormal + ')';
    }
    if (concept.hiNormal == null && concept.lowNormal != null) {
        return '(> ' + concept.lowNormal + ')';
    }
    return '';
};

'use strict';

Bahmni.Common.Domain.ConceptMapper = function () {
    this.map = function (openMrsConcept) {
        if (!openMrsConcept) {
            return null;
        }
        if (alreadyMappedConcept(openMrsConcept)) {
            return openMrsConcept;
        } // TODO: Clean up: God knows why people are passing already mapped concept. Keeping this non sense check in this one line alone to avoid confusion
        var openMrsDescription = openMrsConcept.descriptions ? openMrsConcept.descriptions[0] : null;
        var shortConceptName = _.find(openMrsConcept.names, {conceptNameType: "SHORT"});
        return {
            uuid: openMrsConcept.uuid,
            name: openMrsConcept.name.name,
            shortName: shortConceptName ? shortConceptName.name : null,
            description: openMrsDescription ? openMrsDescription.description : null,
            set: openMrsConcept.set,
            dataType: openMrsConcept.datatype ? openMrsConcept.datatype.name : null,
            hiAbsolute: openMrsConcept.hiAbsolute,
            lowAbsolute: openMrsConcept.lowAbsolute,
            hiNormal: openMrsConcept.hiNormal,
            handler: openMrsConcept.handler,
            allowDecimal: openMrsConcept.allowDecimal,
            lowNormal: openMrsConcept.lowNormal,
            conceptClass: openMrsConcept.conceptClass ? openMrsConcept.conceptClass.name : null,
            answers: openMrsConcept.answers,
            units: openMrsConcept.units,
            displayString: shortConceptName ? shortConceptName.name : openMrsConcept.name.name,
            names: openMrsConcept.names
        };
    };

    var alreadyMappedConcept = function (concept) {
        return !concept.name.name;
    };
};

'use strict';

angular.module('bahmni.common.domain')
    .factory('providerService', ['$http', 'appService', function ($http, appService) {
        var search = function (fieldValue) {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                params: {q: fieldValue, v: "full"},
                withCredentials: true
            });
        };

        var searchByUuid = function (uuid) {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                params: {
                    user: uuid
                },
                cache: false
            });
        };

        var list = function (params) {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                cache: false,
                params: params
            });
        };

        var getAttributesForProvider = function (providerUuid) {
            var providerAttributeUrl = appService.getAppDescriptor().formatUrl(Bahmni.Common.Constants.providerAttributeUrl, {'providerUuid': providerUuid});
            return $http.get(providerAttributeUrl, {
                method: "GET",
                withCredentials: true,
                cache: false
            });
        };

        return {
            search: search,
            searchByUuid: searchByUuid,
            list: list,
            getAttributesForProvider: getAttributesForProvider
        };
    }]);

'use strict';

/* exported EncounterConfig */
var EncounterConfig = (function () {
    function EncounterConfig (encounterTypes) {
        this.encounterTypes = encounterTypes;
    }
    EncounterConfig.prototype = {
        getConsultationEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("Consultation");
        },
        getAdmissionEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("ADMISSION");
        },
        getDischargeEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("DISCHARGE");
        },
        getTransferEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("TRANSFER");
        },
        getRadiologyEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("RADIOLOGY");
        },
        getPatientDocumentEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid("Patient Document");
        },
        getValidationEncounterTypeUuid: function () {
            return this.getEncounterTypeUuid(Bahmni.Common.Constants.validationNotesEncounterType);
        },
        getEncounterTypeUuid: function (encounterTypeName) {
            return this.encounterTypes[encounterTypeName];
        },
        getVisitTypes: function () {
            var visitTypesArray = [];
            for (var name in this.visitTypes) {
                visitTypesArray.push({name: name, uuid: this.visitTypes[name]});
            }
            return visitTypesArray;
        },
        getEncounterTypes: function () {
            var encounterTypesArray = [];
            for (var name in this.encounterTypes) {
                encounterTypesArray.push({name: name, uuid: this.encounterTypes[name]});
            }
            return encounterTypesArray;
        },
        getVisitTypeByUuid: function (uuid) {
            var visitTypes = this.getVisitTypes();
            return visitTypes.filter(function (visitType) {
                return visitType.uuid === uuid;
            })[0];
        },
        getEncounterTypeByUuid: function (uuid) {
            var encounterType = this.getEncounterTypes();
            return encounterType.filter(function (encounterType) {
                return encounterType.uuid === uuid;
            })[0];
        }
    };
    return EncounterConfig;
})();

'use strict';

(function () {
    var nameFor = {
        "Date": function (obs) {
            return moment(obs.value).format('D-MMM-YYYY');
        },
        "Datetime": function (obs) {
            var date = Bahmni.Common.Util.DateUtil.parseDatetime(obs.value);
            return date != null ? Bahmni.Common.Util.DateUtil.formatDateWithTime(date) : "";
        },
        "Boolean": function (obs) {
            return obs.value === true ? "Yes" : obs.value === false ? "No" : obs.value;
        },
        "Coded": function (obs) {
            return obs.value.shortName || obs.value.name || obs.value;
        },
        "Object": function (obs) {
            return nameFor.Coded(obs);
        },
        "MultiSelect": function (obs) {
            return obs.getValues().join(", ");
        },
        "Default": function (obs) {
            return obs.value;
        }
    };

    Bahmni.Common.Domain.ObservationValueMapper = {
        getNameFor: nameFor,
        map: function (obs) {
            var type = (obs.concept && obs.concept.dataType) || obs.type;
            if (!(type in nameFor)) {
                type = (typeof obs.value === "object" && "Object") || (obs.isMultiSelect && "MultiSelect") || "Default";
            }
            return (nameFor[type])(obs);
        }
    };
})();


angular.module('bahmni.common.uiHelper', ['ngClipboard']);

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('nonBlank', function () {
        return function ($scope, element, attrs) {
            var addNonBlankAttrs = function () {
                element.attr({'required': 'required'});
            };

            var removeNonBlankAttrs = function () {
                element.removeAttr('required');
            };

            if (!attrs.nonBlank) {
                return addNonBlankAttrs(element);
            }

            $scope.$watch(attrs.nonBlank, function (value) {
                return value ? addNonBlankAttrs() : removeNonBlankAttrs();
            });
        };
    })
    .directive('datepicker', function () {
        var link = function ($scope, element, attrs, ngModel) {
            var maxDate = attrs.maxDate;
            var minDate = attrs.minDate || "-120y";
            var format = attrs.dateFormat || 'dd-mm-yyyy';
            element.datepicker({
                changeYear: true,
                changeMonth: true,
                maxDate: maxDate,
                minDate: minDate,
                yearRange: 'c-120:c+120',
                dateFormat: format,
                onSelect: function (dateText) {
                    $scope.$apply(function () {
                        ngModel.$setViewValue(dateText);
                    });
                }
            });
        };

        return {
            require: 'ngModel',
            link: link
        };
    })
    .directive('myAutocomplete', ['$parse', function ($parse) {
        var link = function (scope, element, attrs, ngModelCtrl) {
            var ngModel = $parse(attrs.ngModel);
            var source = scope.source();
            var responseMap = scope.responseMap();
            var onSelect = scope.onSelect();

            element.autocomplete({
                autofocus: true,
                minLength: 2,
                source: function (request, response) {
                    source(attrs.id, request.term, attrs.itemType).then(function (data) {
                        var results = responseMap ? responseMap(data.data) : data.data;
                        response(results);
                    });
                },
                select: function (event, ui) {
                    scope.$apply(function (scope) {
                        ngModelCtrl.$setViewValue(ui.item.value);
                        scope.$eval(attrs.ngChange);
                        if (onSelect != null) {
                            onSelect(ui.item);
                        }
                    });
                    return true;
                },
                search: function (event) {
                    var searchTerm = $.trim(element.val());
                    if (searchTerm.length < 2) {
                        event.preventDefault();
                    }
                }
            });
        };
        return {
            link: link,
            require: 'ngModel',
            scope: {
                source: '&',
                responseMap: '&',
                onSelect: '&'
            }
        };
    }])
    .directive('bmForm', ['$timeout', function ($timeout) {
        var link = function (scope, elem, attrs) {
            $timeout(function () {
                $(elem).unbind('submit').submit(function (e) {
                    var formScope = scope.$parent;
                    var formName = attrs.name;
                    e.preventDefault();
                    if (scope.autofillable) {
                        $(elem).find('input').trigger('change');
                    }
                    if (formScope[formName].$valid) {
                        formScope.$apply(attrs.ngSubmit);
                        $(elem).removeClass('submitted-with-error');
                    } else {
                        $(elem).addClass('submitted-with-error');
                    }
                });
            }, 0);
        };
        return {
            link: link,
            require: 'form',
            scope: {
                autofillable: "="
            }
        };
    }])
    .directive('patternValidate', ['$timeout', function ($timeout) {
        return function ($scope, element, attrs) {
            var addPatternToElement = function () {
                if ($scope.fieldValidation && $scope.fieldValidation[attrs.id]) {
                    element.attr({"pattern": $scope.fieldValidation[attrs.id].pattern, "title": $scope.fieldValidation[attrs.id].errorMessage, "type": "text"});
                }
            };

            $timeout(addPatternToElement);
        };
    }])
    .directive('validateOn', function () {
        var link = function (scope, element, attrs, ngModelCtrl) {
            var validationMessage = attrs.validationMessage || 'Please enter a valid detail';

            var setValidity = function (value) {
                var valid = value ? true : false;
                ngModelCtrl.$setValidity('blank', valid);
                element[0].setCustomValidity(!valid ? validationMessage : '');
            };
            scope.$watch(attrs.validateOn, setValidity, true);
        };

        return {
            link: link,
            require: 'ngModel'
        };
    });

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('toggle', function () {
        var link = function ($scope, element) {
            $scope.toggle = $scope.toggle === undefined ? false : $scope.toggle;
            $(element).click(function () {
                $scope.$apply(function () {
                    $scope.toggle = !$scope.toggle;
                });
            });

            $scope.$watch('toggle', function () {
                $(element).toggleClass('active', $scope.toggle);
            });

            $scope.$on("$destroy", function () {
                element.off('click');
            });
        };

        return {
            scope: {
                toggle: "="
            },
            link: link
        };
    });

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('bmPopOver', function () {
        var controller = function ($scope) {
            $scope.targetElements = [];

            var hideTargetElements = function () {
                $scope.targetElements.forEach(function (el) { el.hide(); });
            };

            var showTargetElements = function () {
                $scope.targetElements.forEach(function (el) { el.show(); });
            };

            this.registerTriggerElement = function (triggerElement) {
                $scope.triggerElement = triggerElement;

                var docClickHandler = function () {
                    if (!$scope.autoclose) {
                        return;
                    }
                    hideTargetElements();
                    $scope.isTargetOpen = false;
                    $(document).off('click', docClickHandler);
                };

                $scope.triggerElement.on('click', function (event) {
                    if ($scope.isTargetOpen) {
                        $scope.isTargetOpen = false;
                        hideTargetElements(0);
                        $(document).off('click', docClickHandler);
                    } else {
                        $('.tooltip').hide();
                        $scope.isTargetOpen = true;
                        showTargetElements();
                        $(document).on('click', docClickHandler);
                        event.stopImmediatePropagation();
                    }
                });

                $scope.$on('$destroy', function () {
                    $(document).off('click', docClickHandler);
                });
            };

            this.registerTargetElement = function (targetElement) {
                targetElement.hide();
                $scope.targetElements.push(targetElement);
            };
            var hideOrShowTargetElements = function () {
                if ($scope.isTargetOpen) {
                    $scope.isTargetOpen = false;
                    hideTargetElements(0);
                }
            };

            $(document).on('click', '.reg-wrapper', hideOrShowTargetElements);

            $scope.$on('$destroy', function () {
                $(document).off('click', '.reg-wrapper', hideOrShowTargetElements);
            });
        };

        return {
            restrict: 'A',
            controller: controller,
            scope: {
                autoclose: "="
            }
        };
    })
    .directive('bmPopOverTarget', function () {
        var link = function ($scope, element, attrs, popOverController) {
            popOverController.registerTargetElement(element);
        };

        return {
            restrict: 'A',
            require: '^bmPopOver',
            link: link
        };
    })
    .directive('bmPopOverTrigger', function () {
        var link = function ($scope, element, attrs, popOverController) {
            popOverController.registerTriggerElement(element);
        };

        return {
            restrict: 'A',
            require: '^bmPopOver',
            link: link
        };
    });

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('splitButton', ['$timeout', function ($timeout) {
        var controller = function ($scope) {
            $scope.primaryOption = $scope.primaryOption || $scope.options[0];
            $scope.secondaryOptions = _.without($scope.options, $scope.primaryOption);
            $scope.hasMultipleOptions = function () {
                return $scope.secondaryOptions.length > 0;
            };
        };

        var link = function (scope, element) {
            var shouldScroll = function (elementPosition, elementHeight) {
                var windowHeight = window.innerHeight + $(window).scrollTop();
                return windowHeight < (elementHeight + elementPosition);
            };

            scope.scrollToBottom = function () {
                var timeout = $timeout(function () {
                    var scrollHeight = $(element)[0].scrollHeight;
                    if (shouldScroll(element.position().top, scrollHeight)) {
                        window.scrollBy(0, scrollHeight);
                        $timeout.cancel(timeout);
                    }
                });
            };
        };
        return {
            restrict: 'A',
            template: '<div class="split-button" bm-pop-over>' +
                        '<button bm-pop-over-trigger class="toggle-button fa fa-caret-down" ng-show="::hasMultipleOptions()" ng-click="scrollToBottom()" ng-disabled="optionDisabled" type="button"></button>' +
                        '<ul class="options">' +
                            '<li class="primaryOption">' +
                                '<button class="buttonClass" ng-click="optionClick()(primaryOption)" accesskey="{{::primaryOption.shortcutKey}}" ng-disabled="optionDisabled" ng-bind-html="::optionText()(primaryOption,\'primary\') | translate "></button>' +
                            '</li>' +
                            '<ul class="hidden-options">' +
                            '<li bm-pop-over-target ng-repeat="option in ::secondaryOptions" class="secondaryOption">' +
                                '<button class="buttonClass" ng-click="optionClick()(option)" accesskey="{{::option.shortcutKey}}" ng-disabled="optionDisabled" ng-bind-html="::optionText()(option) | translate"></button>' +
                            '</li>' +
                            '</ul>' +
                        '</ul>' +
                      '</div>',
            controller: controller,
            link: link,
            scope: {
                options: '=',
                primaryOption: '=',
                optionText: '&',
                optionClick: '&',
                optionDisabled: '='
            }
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
.directive('focusOn', ['$timeout', function ($timeout) {
    return function (scope, elem, attrs) {
        if (Modernizr.ios) {
            return;
        }
        scope.$watch(attrs.focusOn, function (value) {
            if (value) {
                $timeout(function () {
                    $(elem).focus();
                });
            }
        });
    };
}]);

(function () {
    'use strict';

    var constructSearchResult = function (concept, searchString) {
        var matchingName = null;
        var conceptName = concept.name;
        if (!_.includes(_.toLower(conceptName), _.toLower(searchString))) {
            var synonyms = _.map(concept.names, 'name');
            matchingName = _.find(synonyms, function (name) {
                return (name !== conceptName) && name.search(new RegExp(searchString, "i")) !== -1;
            });
        }
        return {
            label: matchingName ? matchingName + " => " + conceptName : conceptName,
            value: conceptName,
            concept: concept,
            uuid: concept.uuid,
            name: conceptName
        };
    };

    var searchWithDefaultConcept = function (searchMethod, request, response) {
        var searchTerm = _.toLower(request.term.trim());
        var searchString = searchTerm.split(" ");
        var isMatching = function (answer) {
            var nestedConceptNameFound = _.find(answer.names, function (name) {
                return _.includes(_.toLower(name.name), searchTerm);
            });
            var flag = true, conceptNameFound;
            searchString.forEach(function (string) {
                conceptNameFound = _.includes(_.toLower(answer.name), string);
                flag = (flag && conceptNameFound);
            });
            return nestedConceptNameFound || (conceptNameFound && flag);
        };
        var responseMap = _.partial(constructSearchResult, _, searchTerm);

        searchMethod()
            .then(_.partial(_.filter, _, isMatching))// == .then(function(value){return _.filter(value,isMatching);})
            .then(_.partial(_.map, _, responseMap))
            .then(response);
    };

    var searchWithGivenConcept = function (searchMethod, request, response) {
        var searchTerm = request.term.trim();
        var responseMap = _.partial(constructSearchResult, _, searchTerm);
        searchMethod()
            .then(_.partial(_.map, _, responseMap))
            .then(response);
    };

    var toBeInjected = ['$parse', '$http', 'conceptService'];
    var conceptAutocomplete = function ($parse, $http, conceptService) {
        var link = function (scope, element, attrs, ngModelCtrl) {
            var minLength = scope.minLength || 2;
            var previousValue = scope.previousValue;

            var validator = function (searchTerm) {
                if (!scope.strictSelect) {
                    return;
                }
                if (!scope.illegalValue && (_.isEmpty(searchTerm) || searchTerm === previousValue)) {
                    element.removeClass('illegalValue');
                    return;
                }
                element.addClass('illegalValue');
            };

            element.autocomplete({
                autofocus: true,
                minLength: minLength,
                source: function (request, response) {
                    var searchMethod;
                    if (!scope.answersConceptName && scope.defaultConcept) {
                        searchMethod = _.partial(conceptService.getAnswers, scope.defaultConcept);
                        searchWithDefaultConcept(searchMethod, request, response);
                    } else {
                        searchMethod = _.partial(conceptService.getAnswersForConceptName, {
                            term: request.term,
                            answersConceptName: scope.answersConceptName
                        });
                        searchWithGivenConcept(searchMethod, request, response);
                    }
                },
                select: function (event, ui) {
                    scope.$apply(function (scope) {
                        ngModelCtrl.$setViewValue(ui.item);
                        if (scope.blurOnSelect) {
                            element.blur();
                        }
                        previousValue = ui.item.value;
                        validator(previousValue);
                        scope.$eval(attrs.ngChange);
                    });
                    return true;
                },
                search: function (event) {
                    var searchTerm = $.trim(element.val());
                    if (searchTerm.length < minLength) {
                        event.preventDefault();
                    }
                    previousValue = null;
                }
            });

            var blurHandler = function () {
                var searchTerm = $.trim(element.val());
                validator(searchTerm);
            };

            element.on('blur', blurHandler);

            scope.$on("$destroy", function () {
                element.off('blur', blurHandler);
            });
        };

        return {
            link: link,
            require: 'ngModel',
            scope: {
                illegalValue: '=',
                defaultConcept: '=',
                answersConceptName: '=',
                minLength: '=',
                blurOnSelect: '=',
                strictSelect: '=?',
                previousValue: '='
            }
        };
    };

    conceptAutocomplete.$inject = toBeInjected;
    angular.module('bahmni.common.uiHelper').directive('conceptAutocomplete', conceptAutocomplete);
})();

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('focusMe', ['$timeout', '$parse', function ($timeout, $parse) {
        return {
            link: function (scope, element, attrs) {
                var model = $parse(attrs.focusMe);
                scope.$watch(model, function (value) {
                    if (value === true) {
                        $timeout(function () {
                            element[0].focus();
                        });
                    }
                });
            }
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
.directive('bahmniAutocomplete', ['$translate', function ($translate) {
    var link = function (scope, element, attrs, ngModelCtrl) {
        var source = scope.source();
        var responseMap = scope.responseMap && scope.responseMap();
        var onSelect = scope.onSelect();
        var onEdit = scope.onEdit && scope.onEdit();
        var minLength = scope.minLength || 2;
        var formElement = element[0];
        var validationMessage = scope.validationMessage || $translate.instant("SELECT_VALUE_FROM_AUTOCOMPLETE_DEFAULT_MESSAGE");

        var validateIfNeeded = function (value) {
            if (!scope.strictSelect) {
                return;
            }
            scope.isInvalid = (value !== scope.selectedValue);
            if (_.isEmpty(value)) {
                scope.isInvalid = false;
            }
        };

        scope.$watch('initialValue', function () {
            if (scope.initialValue) {
                scope.selectedValue = scope.initialValue;
                scope.isInvalid = false;
            }
        });

        element.autocomplete({
            autofocus: true,
            minLength: minLength,
            source: function (request, response) {
                source({elementId: attrs.id, term: request.term, elementType: attrs.type}).then(function (data) {
                    var results = responseMap ? responseMap(data) : data;
                    response(results);
                });
            },
            select: function (event, ui) {
                scope.selectedValue = ui.item.value;
                ngModelCtrl.$setViewValue(ui.item.value);
                if (onSelect != null) {
                    onSelect(ui.item);
                }
                validateIfNeeded(ui.item.value);
                if (scope.blurOnSelect) {
                    element.blur();
                }
                scope.$apply();
                scope.$eval(attrs.ngDisabled);
                scope.$apply();
                return true;
            },
            search: function (event, ui) {
                if (onEdit != null) {
                    onEdit(ui.item);
                }
                var searchTerm = $.trim(element.val());
                validateIfNeeded(searchTerm);
                if (searchTerm.length < minLength) {
                    event.preventDefault();
                }
            }
        });
        var changeHanlder = function (e) {
            validateIfNeeded(element.val());
        };

        var keyUpHandler = function (e) {
            validateIfNeeded(element.val());
            scope.$apply();
        };

        element.on('change', changeHanlder);
        element.on('keyup', keyUpHandler);

        scope.$watch('isInvalid', function () {
            ngModelCtrl.$setValidity('selection', !scope.isInvalid);
            formElement.setCustomValidity(scope.isInvalid ? validationMessage : '');
        });

        scope.$on("$destroy", function () {
            element.off('change', changeHanlder);
            element.off('keyup', keyUpHandler);
        });
    };

    return {
        link: link,
        require: 'ngModel',
        scope: {
            source: '&',
            responseMap: '&?',
            onSelect: '&',
            onEdit: '&?',
            minLength: '=?',
            blurOnSelect: '=?',
            strictSelect: '=?',
            validationMessage: '@',
            isInvalid: "=?",
            initialValue: "=?"
        }
    };
}]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .factory('spinner', ['messagingService', '$timeout', function (messagingService, $timeout) {
        var tokens = [];

        var topLevelDiv = function (element) {
            return $(element).find("div").eq(0);
        };

        var showSpinnerForElement = function (element) {
            if ($(element).find(".dashboard-section-loader").length === 0) {
                topLevelDiv(element)
                    .addClass('spinnable')
                    .append('<div class="dashboard-section-loader"></div>');
            }
            return {
                element: $(element).find(".dashboard-section-loader")
            };
        };

        var showSpinnerForOverlay = function () {
            var token = Math.random();
            tokens.push(token);

            if ($('#overlay').length === 0) {
                $('body').prepend('<div id="overlay"><div></div></div>');
            }

            var spinnerElement = $('#overlay');
            spinnerElement.stop().show();

            return {
                element: spinnerElement,
                token: token
            };
        };

        var show = function (element) {
            if (element !== undefined) {
                return showSpinnerForElement(element);
            }

            return showSpinnerForOverlay();
        };

        var hide = function (spinner, parentElement) {
            var spinnerElement = spinner.element;
            if (spinner.token) {
                _.pull(tokens, spinner.token);
                if (tokens.length === 0) {
                    spinnerElement.fadeOut(300);
                }
            } else {
                topLevelDiv(parentElement).removeClass('spinnable');
                spinnerElement && spinnerElement.remove();
            }
        };

        var forPromise = function (promise, element) {
            return $timeout(function () {
                // Added timeout to push a new event into event queue. So that its callback will be invoked once DOM is completely rendered
                var spinner = show(element);                      // Don't inline this element
                promise['finally'](function () {
                    hide(spinner, element);
                });
                return promise;
            });
        };

        var forAjaxPromise = function (promise, element) {
            var spinner = show(element);
            promise.always(function () {
                hide(spinner, element);
            });
            return promise;
        };

        return {
            forPromise: forPromise,
            forAjaxPromise: forAjaxPromise,
            show: show,
            hide: hide
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .factory('printer', ['$rootScope', '$compile', '$http', '$timeout', '$q', 'spinner',
        function ($rootScope, $compile, $http, $timeout, $q, spinner) {
            var printHtml = function (html) {
                var deferred = $q.defer();
                var hiddenFrame = $('<iframe style="visibility: hidden"></iframe>').appendTo('body')[0];
                hiddenFrame.contentWindow.printAndRemove = function () {
                    hiddenFrame.contentWindow.print();
                    $(hiddenFrame).remove();
                    deferred.resolve();
                };
                var htmlContent = "<!doctype html>" +
                        "<html>" +
                            '<body onload="printAndRemove();">' +
                                html +
                            '</body>' +
                        "</html>";
                var doc = hiddenFrame.contentWindow.document.open("text/html", "replace");
                doc.write(htmlContent);
                doc.close();
                return deferred.promise;
            };

            var openNewWindow = function (html) {
                var newWindow = window.open("printTest.html");
                newWindow.addEventListener('load', function () {
                    $(newWindow.document.body).html(html);
                }, false);
            };

            var print = function (templateUrl, data, pageTitle) {
                pageTitle = pageTitle || null;
                $rootScope.isBeingPrinted = true;
                $http.get(templateUrl).then(function (templateData) {
                    var template = templateData.data;
                    var printScope = $rootScope.$new();
                    angular.extend(printScope, data);
                    var element = $compile($('<div>' + template + '</div>'))(printScope);
                    var renderAndPrintPromise = $q.defer();
                    var originalTitle = angular.element(document).prop('title');
                    pageTitle ? angular.element(document).prop('title', pageTitle) : angular.element(document).prop('title', originalTitle);
                    var waitForRenderAndPrint = function () {
                        if (printScope.$$phase || $http.pendingRequests.length) {
                            $timeout(waitForRenderAndPrint, 1000);
                        } else {
                        // Replace printHtml with openNewWindow for debugging
                            printHtml(element.html()).then(function () {
                                $rootScope.isBeingPrinted = false;
                                renderAndPrintPromise.resolve();
                                angular.element(document).prop('title', originalTitle);
                            });
                            printScope.$destroy();
                        }
                        return renderAndPrintPromise.promise;
                    };
                    spinner.forPromise(waitForRenderAndPrint());
                });
            };

            var printFromScope = function (templateUrl, scope, afterPrint) {
                $rootScope.isBeingPrinted = true;
                $http.get(templateUrl).then(function (response) {
                    var template = response.data;
                    var printScope = scope;
                    var element = $compile($('<div>' + template + '</div>'))(printScope);
                    var renderAndPrintPromise = $q.defer();
                    var originalTitle = angular.element(document).prop('title');
                    printScope.pageTitle ? angular.element(document).prop('title', printScope.pageTitle) : angular.element(document).prop('title', originalTitle);
                    var waitForRenderAndPrint = function () {
                        if (printScope.$$phase || $http.pendingRequests.length) {
                            $timeout(waitForRenderAndPrint);
                        } else {
                            printHtml(element.html()).then(function () {
                                $rootScope.isBeingPrinted = false;
                                if (afterPrint) {
                                    afterPrint();
                                }
                                renderAndPrintPromise.resolve();
                                angular.element(document).prop('title', originalTitle);
                            });
                        }
                        return renderAndPrintPromise.promise;
                    };
                    spinner.forPromise(waitForRenderAndPrint());
                });
            };
            return {
                print: print,
                printFromScope: printFromScope
            };
        }]);

'use strict';

angular.module('bahmni.common.uiHelper')
 .service('contextChangeHandler', ['$rootScope', function ($rootScope) {
     var callbacks = [];
     var self = this;

     $rootScope.$on('$stateChangeSuccess', function () {
         self.reset();
     });

     this.reset = function () {
         callbacks = [];
     };

     this.add = function (callback) {
         callbacks.push(callback);
     };

     this.execute = function () {
         var allow = true;
         var callBackReturn = null;
         var errorMessage = null;
         callbacks.forEach(function (callback) {
             callBackReturn = callback();
             allow = allow && callBackReturn["allow"];
             if (_.isEmpty(errorMessage)) {
                 errorMessage = callBackReturn["errorMessage"];
             }
         });
         if (callBackReturn && errorMessage) {
             return {allow: allow, errorMessage: errorMessage};
         }
         return {allow: allow};
     };
 }]);

"use strict";

angular.module("bahmni.common.uiHelper").controller("MessageController", [ "$scope", "messagingService", "$translate", "$state", "$location",
    function ($scope, messagingService, $translate, $state, $location) {
        $scope.messages = messagingService.messages;

        $scope.getMessageText = function (level) {
            var string = "";
            $scope.messages[level].forEach(function (message) {
                string = string.concat(message.value);
            });
            var translatedMessage = $translate.instant(string);

            navigator.clipboard.writeText(translatedMessage);

            return translatedMessage;
        };

        $scope.hideMessage = function (level) {
            messagingService.hideMessages(level);
        };

        $scope.isErrorMessagePresent = function () {
            return $scope.messages.error.length > 0;
        };

        $scope.isInfoMessagePresent = function () {
            return $scope.messages.info.length > 0;
        };

        $scope.isAlertMessagePresent = function () {
            return $scope.messages.alert.length > 0;
        };

        $scope.discardChanges = function (level) {
            $state.discardChanges = true;
            $scope.hideMessage(level);
            return $state.isPatientSearch ? $location.path('/default/patient/search') : $location.path('/default/patient/' + $state.newPatientUuid + "/dashboard");
        };
    }
]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .service('messagingService', ['$rootScope', '$timeout', function ($rootScope, $timeout) {
        this.messages = {error: [], info: [], alert: []};
        var self = this;

        $rootScope.$on('event:serverError', function (event, errorMessage) {
            self.showMessage('error', errorMessage, 'serverError');
        });

        this.showMessage = function (level, message, errorEvent) {
            var messageObject = {'value': '', 'isServerError': false};
            messageObject.value = message ? message.replace(/\[|\]|null/g, '') : " ";
            if (errorEvent) {
                messageObject.isServerError = true;
                if (!self.messages[level].length) {
                    this.createTimeout('error', 6000);
                }
            } else if (level == 'info') {
                this.createTimeout('info', 4000);
            }

            var index = _.findIndex(this.messages[level], function (msg) {
                return msg.value == messageObject.value;
            });

            if (index >= 0) {
                this.messages[level].splice(index, 1);
            }
            if (messageObject.value) {
                this.messages[level].push(messageObject);
            }
        };

        this.createTimeout = function (level, time) {
            $timeout(function () {
                self.messages[level] = [];
            }, time, true);
        };

        this.hideMessages = function (level) {
            self.messages[level].length = 0;
        };

        this.clearAll = function () {
            self.messages["error"] = [];
            self.messages["info"] = [];
            self.messages["alert"] = [];
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('ngConfirmClick', function () {
        var link = function (scope, element, attr) {
            var msg = attr.confirmMessage || "Are you sure?";
            var clickAction = attr.ngConfirmClick;
            element.bind('click', function () {
                if (window.confirm(msg)) {
                    scope.$apply(clickAction);
                }
            });
        };
        return {
            restrict: 'A',
            link: link
        };
    });

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('bmShow', ['$rootScope', function ($rootScope) {
        var link = function ($scope, element) {
            $scope.$watch('bmShow', function () {
                if ($rootScope.isBeingPrinted || $scope.bmShow) {
                    element.removeClass('ng-hide');
                } else {
                    element.addClass('ng-hide');
                }
            });
        };

        return {
            scope: {
                bmShow: "="
            },
            link: link
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('monthyearpicker', ['$translate', function ($translate) {
        var link = function ($scope) {
            var monthNames = $translate.instant('MONTHS');
            $scope.monthNames = monthNames.split(",");

            var getYearList = function () {
                var minYear = $scope.minYear ? $scope.minYear : moment().toDate().getFullYear() - 15;
                var maxYear = $scope.maxYear ? $scope.maxYear : moment().toDate().getFullYear() + 5;
                var yearList = [];
                for (var i = maxYear; i >= minYear; i--) {
                    yearList.push(i);
                }
                return yearList;
            };
            $scope.years = getYearList();

            var valueCompletelyFilled = function () {
                return ($scope.selectedMonth != null && $scope.selectedYear != null);
            };
            var valueNotFilled = function () {
                return $scope.selectedMonth == null && $scope.selectedYear == null;
            };

            var getCompleteDate = function () {
                var month = $scope.selectedMonth + 1;
                return $scope.selectedYear + "-" + month + "-01";
            };

            $scope.updateModel = function () {
                if (valueCompletelyFilled()) {
                    $scope.model = getCompleteDate();
                } else if (!$scope.isValid()) {
                    $scope.model = "Invalid Date";
                } else {
                    $scope.model = "";
                }
            };
            $scope.isValid = function () {
                return valueNotFilled() || valueCompletelyFilled();
            };

            $scope.illegalMonth = function () {
                return ($scope.selectedMonth === undefined || $scope.selectedMonth === null) && ($scope.selectedYear !== null && $scope.selectedYear !== undefined);
            };

            $scope.illegalYear = function () {
                return ($scope.selectedMonth !== null && $scope.selectedMonth !== undefined) && ($scope.selectedYear === undefined || $scope.selectedYear === null);
            };

            if ($scope.model) {
                var date = moment($scope.model).toDate();
                $scope.selectedMonth = date.getMonth();
                $scope.selectedYear = date.getFullYear();
            }
        };

        return {
            restrict: 'E',
            link: link,
            scope: {
                observation: "=",
                minYear: "=",
                maxYear: "=",
                illegalValue: '=',
                model: "="
            },
            template: '<span><select ng-model=\'selectedMonth\'  ng-class=\"{\'illegalValue\': illegalMonth() || illegalValue}\" ng-change="updateModel()" ng-options="monthNames.indexOf(month) as month for month in monthNames" ><option value="">{{\'CHOOSE_MONTH_KEY\' | translate}}</option>>' +
            '</select></span>' +
            '<span><select ng-model=\'selectedYear\'   ng-class=\"{\'illegalValue\': illegalYear() || illegalValue}\" ng-change="updateModel()" ng-options="year as year for year in years"><option value="">{{\'CHOOSE_YEAR_KEY\' | translate}}</option>>' +
            '</select></span>'
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('singleClick', function () {
        var ignoreClick = false;
        var link = function (scope, element) {
            var clickHandler = function () {
                if (ignoreClick) {
                    return;
                }
                ignoreClick = true;
                scope.singleClick().finally(function () {
                    ignoreClick = false;
                });
            };

            element.on('click', clickHandler);

            scope.$on("$destroy", function () {
                element.off('click', clickHandler);
            });
        };
        return {
            scope: {
                singleClick: '&'
            },
            restrict: 'A',
            link: link
        };
    });

'use strict';

angular.module('bahmni.common.uiHelper')
    .directive('singleSubmit', function () {
        var ignoreSubmit = false;
        var link = function (scope, element) {
            var submitHandler = function () {
                if (ignoreSubmit) {
                    return;
                }
                ignoreSubmit = true;
                scope.singleSubmit().finally(function () {
                    ignoreSubmit = false;
                });
            };

            element.on('submit', submitHandler);

            scope.$on("$destroy", function () {
                element.off('submit', submitHandler);
            });
        };
        return {
            scope: {
                singleSubmit: '&'
            },
            restrict: 'A',
            link: link
        };
    });

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.UIControls = Bahmni.Common.UIControls || {};

angular.module('bahmni.common.uicontrols', []);

(function () {
    'use strict';

    var constructSearchResult = function (concept) {
        var conceptName = concept.shortName || concept.name.name || concept.name;
        return {
            label: conceptName,
            value: conceptName,
            concept: concept,
            uuid: concept.uuid,
            name: conceptName
        };
    };

    var find = function (allAnswers, savedAnswer) {
        return _.find(allAnswers, function (answer) {
            return savedAnswer && (savedAnswer.uuid === answer.concept.uuid);
        });
    };

    var toBeInjected = ['conceptService'];
    var conceptDropdown = function (conceptService) {
        var controller = function ($scope) {
            $scope.onChange = $scope.onChange();

            var response = function (answers) {
                $scope.answers = answers;
                $scope.selectedAnswer = find(answers, $scope.selectedAnswer);
            };
            if (!$scope.answersConceptName && $scope.defaultConcept) {
                conceptService.getAnswers($scope.defaultConcept).then(function (results) {
                    return _.map(results, constructSearchResult);
                }).then(response);
                return;
            }

            conceptService.getAnswersForConceptName({
                answersConceptName: $scope.answersConceptName
            }).then(function (results) {
                return _.map(results, constructSearchResult);
            }).then(response);
        };

        return {
            controller: controller,
            restrict: 'E',
            scope: {
                selectedAnswer: '=model',
                answersConceptName: '=?',
                defaultConcept: '=',
                onChange: '&',
                onInvalidClass: '@',
                isValid: '=',
                ngDisabled: '='
            },
            templateUrl: '../common/uicontrols/concept-dropdown/views/conceptDropdown.html'
        };
    };

    conceptDropdown.$inject = toBeInjected;
    angular.module('bahmni.common.uicontrols').directive('conceptDropdown', conceptDropdown);
})();

'use strict';

angular.module('bahmni.common.attributeTypes', []).directive('attributeTypes', [function () {
    return {
        scope: {
            targetModel: '=',
            attribute: '=',
            fieldValidation: '=',
            isAutoComplete: '&',
            getAutoCompleteList: '&',
            getDataResults: '&',
            handleUpdate: '&',
            isReadOnly: '&',
            isForm: '=?'
        },
        templateUrl: '../common/attributeTypes/views/attributeInformation.html',
        restrict: 'E',
        controller: function ($scope, $translate) {
            $scope.getAutoCompleteList = $scope.getAutoCompleteList();
            $scope.getDataResults = $scope.getDataResults();
            // to avoid watchers in one way binding
            $scope.isAutoComplete = $scope.isAutoComplete() || function () { return false; };
            $scope.isReadOnly = $scope.isReadOnly() || function () { return false; };
            $scope.handleUpdate = $scope.handleUpdate() || function () { return false; };

            $scope.appendConceptNameToModel = function (attribute) {
                var attributeValueConceptType = $scope.targetModel[attribute.name];
                var concept = _.find(attribute.answers, function (answer) {
                    return answer.conceptId === attributeValueConceptType.conceptUuid;
                });
                attributeValueConceptType.value = concept && concept.fullySpecifiedName;
            };
            $scope.getTranslatedAttributeTypes = function (attribute) {
                var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(attribute, Bahmni.Common.Constants.patientAttribute, $translate);
                return translatedName;
            };

            $scope.handleConceptChange = function (attribute) {
                if (attribute.name === "Subscription card") {
                    var subscriptionCardNumber = document.getElementById("Subscription card Numbers");
                    var isSubscriptionReadOnly = isSubscriptionCardNumberReadOnly(attribute);
                    subscriptionCardNumber.disabled = isSubscriptionReadOnly;
                    if (isSubscriptionReadOnly) {
                        $scope.targetModel["Subscription card Numbers"] = null;
                    }
                }
                $scope.appendConceptNameToModel(attribute);
                $scope.handleUpdate(attribute);
            };

            var isSubscriptionCardNumberReadOnly = function (attribute) {
                var subscriptionAttr = $scope.targetModel["Subscription card"];
                if (!subscriptionAttr || !subscriptionAttr.conceptUuid) return true;
                var selected = attribute.answers.find(a =>
                    a.conceptId === subscriptionAttr.conceptUuid
                );
                return !(selected && selected.description.toLowerCase().includes("yes"));
            };
        }
    };
}]);

angular.module('bahmni.common.photoCapture', []);

'use strict';

angular.module('bahmni.common.photoCapture')
    .directive('capturePhoto', ['appService', '$parse', '$window', '$translate', function factory (appService, $parse, $window, $translate) {
        var link = function (scope, iElement, iAttrs) {
            var captureDialogElement = iElement.find(".photoCaptureDialog"),
                captureVideo = captureDialogElement.find("video")[0],
                captureActiveStream,
                captureCanvas = captureDialogElement.find("canvas")[0],
                captureContext = captureCanvas.getContext("2d"),
                captureConfirmImageButton = captureDialogElement.find(".confirmImage"),
                uploadDialogElement = iElement.find(".photoUploadDialog"),
                uploadCanvas = uploadDialogElement.find("canvas")[0],
                uploadContext = uploadCanvas.getContext("2d"),
                uploadConfirmImageButton = uploadDialogElement.find(".confirmImage"),
                uploadField = iElement.find(".fileUpload")[0],
                dialogOpen = false,
                pixelRatio = window.devicePixelRatio,
                imageUploadSize = appService.getAppDescriptor().getConfigValue("imageUploadSize") || Bahmni.Common.Constants.defaultImageUploadSize;
            if (imageUploadSize > Bahmni.Common.Constants.maxImageUploadSize) {
                imageUploadSize = Bahmni.Common.Constants.maxImageUploadSize;
            }
            captureContext.scale(pixelRatio, pixelRatio);
            uploadContext.scale(pixelRatio, pixelRatio);

            var confirmImage = function (canvas, dialogElement) {
                var image = canvas.toDataURL("image/jpeg");
                var onConfirmationSuccess = function (image) {
                    var ngModel = $parse(iAttrs.ngModel);
                    ngModel.assign(scope, image);
                    dialogElement.dialog('close');
                };
                if (iAttrs.capturePhoto) {
                    var onConfirmationPromise = scope[iAttrs.capturePhoto](image);
                    onConfirmationPromise.then(function () {
                        onConfirmationSuccess(image);
                    }, function () {
                        alert("Failed to save image. Please try again later");
                    });
                } else {
                    onConfirmationSuccess(image);
                }
            };

            var drawImage = function (canvas, context, image, imageWidth, imageHeight) {
                var sourceX = 0;
                var sourceY = 0;
                var destX = 0;
                var destY = 0;
                var stretchRatio, sourceWidth, sourceHeight;
                if (canvas.width > canvas.height) {
                    stretchRatio = (imageWidth / canvas.width);
                    sourceWidth = imageWidth;
                    sourceHeight = Math.floor(canvas.height * stretchRatio);
                    sourceY = Math.floor((imageHeight - sourceHeight) / 2);
                } else {
                    stretchRatio = (imageHeight / canvas.height);
                    sourceWidth = Math.floor(canvas.width * stretchRatio);
                    sourceHeight = imageHeight;
                    sourceX = Math.floor((imageWidth - sourceWidth) / 2);
                }
                var destWidth = Math.floor(canvas.width / pixelRatio);
                var destHeight = Math.floor(canvas.height / pixelRatio);
                context.drawImage(image, sourceX, sourceY, sourceWidth, sourceHeight, destX, destY, destWidth, destHeight);
            };

            scope.launchPhotoCapturePopup = function () {
                if (dialogOpen) {
                    alert("Please allow access to web camera and wait for photo capture dialog to be launched");
                    return;
                }
                dialogOpen = true;
                var navigatorUserMedia = navigator.getUserMedia || navigator.webkitGetUserMedia || navigator.mozGetUserMedia || navigator.msGetUserMedia;
                if (navigator.mediaDevices) {
                    navigator.mediaDevices.getUserMedia({video: true, audio: false})
                        .then(function (localMediaStream) {
                            captureVideo.srcObject = localMediaStream;
                            captureActiveStream = localMediaStream;
                            captureDialogElement.dialog('open');
                        }).catch(function (e) {
                            alert("Could not get access to web camera. Please allow access to web camera");
                        });
                } else if (navigatorUserMedia) {
                    navigatorUserMedia(
                        {video: true, audio: false},
                        function (localMediaStream) {
                            captureVideo.src = $window.URL.createObjectURL(localMediaStream);
                            captureActiveStream = localMediaStream;
                            captureDialogElement.dialog('open');
                        },
                        function () {
                            alert("Could not get access to web camera. Please allow access to web camera");
                        }
                    );
                } else {
                    alert('Photo capture is not supported in your browser. Please use chrome');
                }
            };

            scope.captureConfirmImage = function () {
                confirmImage(captureCanvas, captureDialogElement);
            };

            scope.captureClickImage = function () {
                drawImage(captureCanvas, captureContext, captureVideo, captureVideo.videoWidth, captureVideo.videoHeight);
                captureConfirmImageButton.prop('disabled', false);
                captureConfirmImageButton.focus();
            };

            captureDialogElement.dialog({
                autoOpen: false, height: 300, width: 500, modal: true, dialogClass: 'photo-capture-dialog',
                close: function () {
                    dialogOpen = false;
                    if (captureActiveStream) {
                        var captureActiveStreamTrack = captureActiveStream.getTracks();
                        if (captureActiveStreamTrack) {
                            captureActiveStreamTrack[0].stop();
                        }
                    }
                }
            });

            scope.uploadConfirmImage = function () {
                confirmImage(uploadCanvas, uploadDialogElement);
            };

            scope.launchPhotoUploadPopup = function () {
                if (dialogOpen) {
                    alert("Please wait for photo upload dialog to be launched");
                    return;
                }
                dialogOpen = true;
                uploadDialogElement.dialog('open');
            };

            scope.uploadImage = function () {
                if (this.files && this.files[0] && this.files[0].type) {
                    var fileType = this.files[0].type;
                    if (!fileType.startsWith('image/')) {
                        uploadConfirmImageButton.prop('disabled', true);
                        alert($translate.instant("FILE_UPLOAD_MUST_BE_IMAGE"));
                        return;
                    }
                } else {
                    uploadConfirmImageButton.prop('disabled', true);
                    alert($translate.instant("FILE_UPLOAD_MUST_BE_IMAGE"));
                    uploadContext.clearRect(0, 0, uploadCanvas.width, uploadCanvas.height);
                    return;
                }
                if (this.files[0] && this.files[0].size <= imageUploadSize) {
                    var fileReader = new FileReader();
                    fileReader.onload = function (e) {
                        var image = new Image();
                        image.onload = function () {
                            drawImage(uploadCanvas, uploadContext, image, image.width, image.height);
                        };
                        image.src = e.target.result;
                    };
                    fileReader.readAsDataURL(this.files[0]);
                    uploadConfirmImageButton.prop('disabled', false);
                    uploadConfirmImageButton.focus();
                } else {
                    uploadConfirmImageButton.prop('disabled', true);
                    var imageUploadSizeInKb = imageUploadSize / 1000;
                    var displayMessage = '';
                    if (imageUploadSizeInKb >= 1000) {
                        displayMessage = Math.floor(imageUploadSizeInKb / 1000) + "MB";
                    } else {
                        displayMessage = Math.floor(imageUploadSizeInKb) + "KB";
                    }
                    alert($translate.instant("FILE_UPLOAD_MUST_BE_LESS_THAN") + ' ' + displayMessage);
                    uploadField.value = "";
                    uploadContext.clearRect(0, 0, uploadCanvas.width, uploadCanvas.height);
                }
            };

            uploadDialogElement.dialog({
                autoOpen: false, height: 350, width: 350, modal: true, dialogClass: 'photo-upload-dialog',
                close: function () {
                    dialogOpen = false;
                }
            });

            iElement.bind("$destroy", function () {
                captureDialogElement.dialog("destroy");
                uploadDialogElement.dialog("destroy");
            });

            uploadField.addEventListener("change", scope.uploadImage, false);
        };

        return {
            templateUrl: '../common/photo-capture/views/photo.html',
            restrict: 'A',
            scope: true,
            link: link
        };
    }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Auth = Bahmni.Auth || {};

angular.module('authentication', ['ui.router']);

'use strict';

Bahmni.Auth.User = function (user) {
    angular.extend(this, user);

    this.userProperties = user.userProperties || {};
    this.favouriteObsTemplates = this.userProperties.favouriteObsTemplates ? this.userProperties.favouriteObsTemplates.split("###") : [];
    this.favouriteWards = this.userProperties.favouriteWards ? this.userProperties.favouriteWards.split("###") : [];
    this.recentlyViewedPatients = this.userProperties.recentlyViewedPatients ? JSON.parse(this.userProperties.recentlyViewedPatients) : [];

    this.toContract = function () {
        var user = angular.copy(this);
        user.userProperties.favouriteObsTemplates = this.favouriteObsTemplates.join("###");
        user.userProperties.favouriteWards = this.favouriteWards.join("###");
        user.userProperties.recentlyViewedPatients = JSON.stringify(this.recentlyViewedPatients);
        delete user.favouriteObsTemplates;
        delete user.favouriteWards;
        delete user.recentlyViewedPatients;
        return user;
    };

    this.addDefaultLocale = function (locale) {
        this.userProperties['defaultLocale'] = locale;
    };

    this.addToRecentlyViewed = function (patient, maxPatients) {
        if (!_.some(this.recentlyViewedPatients, {'uuid': patient.uuid})) {
            this.recentlyViewedPatients.unshift({
                uuid: patient.uuid,
                name: patient.name,
                identifier: patient.identifier
            });
            if (_.size(this.recentlyViewedPatients) >= maxPatients) {
                this.recentlyViewedPatients = _.take(this.recentlyViewedPatients, maxPatients);
            }
        }
    };

    this.isFavouriteObsTemplate = function (conceptName) {
        return _.includes(this.favouriteObsTemplates, conceptName);
    };

    this.toggleFavoriteObsTemplate = function (conceptName) {
        if (this.isFavouriteObsTemplate(conceptName)) {
            this.favouriteObsTemplates = _.without(this.favouriteObsTemplates, conceptName);
        } else {
            this.favouriteObsTemplates.push(conceptName);
        }
    };

    this.isFavouriteWard = function (wardName) {
        return _.includes(this.favouriteWards, wardName);
    };

    this.toggleFavoriteWard = function (wardName) {
        if (this.isFavouriteWard(wardName)) {
            this.favouriteWards = _.without(this.favouriteWards, wardName);
        } else {
            this.favouriteWards.push(wardName);
        }
    };
};


'use strict';

angular.module('authentication')
    .service('userService', ['$rootScope', '$http', '$q', function ($rootScope, $http, $q) {
        var getUserFromServer = function (userName) {
            return $http.get(Bahmni.Common.Constants.userUrl, {
                method: "GET",
                params: {
                    username: userName,
                    v: "custom:(username,uuid,person:(uuid,),privileges:(name,retired),userProperties)"
                },
                cache: false
            });
        };

        this.getUser = function (userName) {
            var deferrable = $q.defer();
            getUserFromServer(userName).success(function (data) {
                deferrable.resolve(data);
            }).error(function () {
                deferrable.reject('Unable to get user data');
            });

            return deferrable.promise;
        };

        this.savePreferences = function () {
            var deferrable = $q.defer();
            var user = $rootScope.currentUser.toContract();
            $http.post(Bahmni.Common.Constants.userUrl + "/" + user.uuid, {"uuid": user.uuid, "userProperties": user.userProperties}, {
                withCredentials: true
            }).then(function (response) {
                $rootScope.currentUser.userProperties = response.data.userProperties;
                deferrable.resolve();
            });
            return deferrable.promise;
        };

        var getProviderFromServer = function (uuid) {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                params: {
                    user: uuid,
                    v: 'custom:(uuid,display,attributes)'
                },
                cache: false
            });
        };

        this.getProviderForUser = function (uuid) {
            var deferrable = $q.defer();

            getProviderFromServer(uuid).success(function (data) {
                if (data.results.length > 0) {
                    var providerName = data.results[0].display.split("-")[1];
                    data.results[0].name = providerName ? providerName.trim() : providerName;
                    deferrable.resolve(data);
                } else {
                    deferrable.reject("UNABLE_TO_GET_PROVIDER_DATA");
                }
            }).error(function () {
                deferrable.reject("UNABLE_TO_GET_PROVIDER_DATA");
            });

            return deferrable.promise;
        };

        this.getPasswordPolicies = function () {
            return $http.get(Bahmni.Common.Constants.passwordPolicyUrl, {
                method: "GET",
                withCredentials: true
            });
        };

        this.allowedDomains = function (redirectUrl) {
            var deferrable = $q.defer();
            $http.get(Bahmni.Common.Constants.loginConfig, {
                method: "GET",
                cache: true
            }).success(function (data) {
                deferrable.resolve(data.whiteListedDomains);
            }).error(function () {
                deferrable.resolve([]);
            });
            return deferrable.promise;
        };
    }]);

'use strict';

angular.module('authentication')
    .config(['$httpProvider', function ($httpProvider) {
        var interceptor = ['$rootScope', '$q', function ($rootScope, $q) {
            function success (response) {
                return response;
            }

            function error (response) {
                if (response.status === 401) {
                    $rootScope.$broadcast('event:auth-loginRequired');
                }
                return $q.reject(response);
            }

            return {
                response: success,
                responseError: error
            };
        }];
        $httpProvider.interceptors.push(interceptor);
    }]).run(['$rootScope', '$window', '$timeout', function ($rootScope, $window, $timeout) {
        $rootScope.$on('event:auth-loginRequired', function () {
            $timeout(function () {
                $window.location = "../home/index.html#/login";
            });
        });
    }]).service('sessionService', ['$rootScope', '$http', '$q', '$bahmniCookieStore', 'userService', '$window', function ($rootScope, $http, $q, $bahmniCookieStore, userService, $window) {
        var sessionResourcePath = Bahmni.Common.Constants.RESTWS_V1 + '/session?v=custom:(uuid)';

        var getAuthFromServer = function (username, password, otp, restrictLoginLocationToUser, location) {
            var btoa = otp ? username + ':' + password + ':' + otp : username + ':' + password;
            if (restrictLoginLocationToUser) {
                return $http.get(Bahmni.Common.Constants.bahmniDistroUserLocationValidUrl + "?loginLocationUuid=" + location.uuid, {
                    headers: {'Authorization': 'Basic ' + window.btoa(btoa)},
                    cache: false
                }).then(function (response) {
                    if (response.status == 200) {
                        return $http.get(sessionResourcePath, {
                            headers: {'Authorization': 'Basic ' + window.btoa(btoa)},
                            cache: false
                        });
                    }
                    return response;
                });
            } else {
                return $http.get(sessionResourcePath, {
                    headers: {'Authorization': 'Basic ' + window.btoa(btoa)},
                    cache: false
                });
            }
        };

        this.resendOTP = function (username, password) {
            var btoa = username + ':' + password;
            return $http.get(sessionResourcePath + '&resendOTP=true', {
                headers: {'Authorization': 'Basic ' + window.btoa(btoa)},
                cache: false
            });
        };

        var createSession = function (username, password, otp, restrictLoginLocationToUser, location) {
            var deferrable = $q.defer();

            getAuthFromServer(username, password, otp, restrictLoginLocationToUser, location).then(function (response) {
                if (response.status == 204) {
                    deferrable.resolve({"firstFactAuthorization": true});
                }
                deferrable.resolve(response.data);
            }, function (response) {
                if (response.status == 401) {
                    deferrable.reject('LOGIN_LABEL_WRONG_OTP_MESSAGE_KEY');
                } else if (response.status == 410) {
                    deferrable.reject('LOGIN_LABEL_OTP_EXPIRED');
                } else if (response.status == 429) { // Too many requests
                    deferrable.reject('LOGIN_LABEL_MAX_FAILED_ATTEMPTS');
                }
                deferrable.reject('LOGIN_LABEL_LOGIN_ERROR_MESSAGE_KEY');
            });
            return deferrable.promise;
        };

        var hasAnyActiveProvider = function (providers) {
            return _.filter(providers, function (provider) {
                return (provider.retired == undefined || provider.retired == "false");
            }).length > 0;
        };

        var self = this;

        var destroySessionFromServer = function () {
            if ($rootScope.cookieExpiryTime && $rootScope.cookieExpiryTime > 0) {
                var currentTime = new Date();
                var expiryTime = new Date(currentTime.getTime() + $rootScope.cookieExpiryTime * 60000);
                var params = (decodeURIComponent($window.location.search.substring(1)));
                $bahmniCookieStore.put($rootScope.currentProvider.uuid, $window.location.pathname + (params ? '?' + params : '') + $window.location.hash, {path: '/', expires: expiryTime});
            }
            return $http.delete(sessionResourcePath);
        };

        var sessionCleanup = function () {
            delete $.cookie(Bahmni.Common.Constants.currentUser, null, {path: "/"});
            delete $.cookie(Bahmni.Common.Constants.currentUser, null, {path: "/"});
            delete $.cookie(Bahmni.Common.Constants.retrospectiveEntryEncounterDateCookieName, null, {path: "/"});
            delete $.cookie(Bahmni.Common.Constants.grantProviderAccessDataCookieName, null, {path: "/"});
            $rootScope.currentUser = undefined;
        };

        this.destroy = function () {
            var deferrable = $q.defer();
            destroySessionFromServer().then(function () {
                sessionCleanup();
                deferrable.resolve();
            });
            return deferrable.promise;
        };

        this.loginUser = function (username, password, location, otp, restrictLoginLocationToUser) {
            var deferrable = $q.defer();
            createSession(username, password, otp, restrictLoginLocationToUser, location).then(function (data) {
                if (data.authenticated) {
                    $bahmniCookieStore.put(Bahmni.Common.Constants.currentUser, username, {path: '/', expires: 7});
                    if (location != undefined) {
                        $bahmniCookieStore.remove(Bahmni.Common.Constants.locationCookieName);
                        $bahmniCookieStore.put(Bahmni.Common.Constants.locationCookieName, {name: location.display, uuid: location.uuid}, {path: '/', expires: 7});
                    }
                    deferrable.resolve(data);
                } else if (data.firstFactAuthorization) {
                    deferrable.resolve(data);
                } else {
                    deferrable.reject('LOGIN_LABEL_LOGIN_ERROR_MESSAGE_KEY');
                }
            }, function (errorInfo) {
                deferrable.reject(errorInfo);
            });
            return deferrable.promise;
        };

        this.get = function () {
            return $http.get(sessionResourcePath, { cache: false });
        };

        this.loadCredentials = function () {
            var deferrable = $q.defer();
            var currentUser = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (!currentUser) {
                this.destroy().finally(function () {
                    $rootScope.$broadcast('event:auth-loginRequired');
                    deferrable.reject("No User in session. Please login again.");
                });
                return deferrable.promise;
            }
            userService.getUser(currentUser).then(function (data) {
                userService.getProviderForUser(data.results[0].uuid).then(function (providers) {
                    if (!_.isEmpty(providers.results) && hasAnyActiveProvider(providers.results)) {
                        $rootScope.currentUser = new Bahmni.Auth.User(data.results[0]);
                        $rootScope.currentUser.provider = providers.results[0];
                        var location = $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName);
                        if (location) {
                            $rootScope.currentUser.currentLocation = location.name;
                        }
                        $rootScope.$broadcast('event:user-credentialsLoaded', data.results[0]);
                        deferrable.resolve(data.results[0]);
                    } else {
                        self.destroy();
                        deferrable.reject("YOU_HAVE_NOT_BEEN_SETUP_PROVIDER");
                    }
                },
               function () {
                   self.destroy();
                   deferrable.reject("COULD_NOT_GET_PROVIDER");
               });
            }, function () {
                self.destroy();
                deferrable.reject('Could not get roles for the current user.');
            });
            return deferrable.promise;
        };

        this.getLoginLocationUuid = function () {
            return $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName) ? $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName).uuid : null;
        };

        this.changePassword = function (currentUserUuid, oldPassword, newPassword) {
            return $http({
                method: 'POST',
                url: Bahmni.Common.Constants.passwordUrl,
                data: {
                    "oldPassword": oldPassword,
                    "newPassword": newPassword
                },
                headers: {'Content-Type': 'application/json'}
            });
        };

        this.loadProviders = function (userInfo) {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                params: {
                    user: userInfo.uuid
                },
                cache: false
            }).success(function (data) {
                var providerUuid = (data.results.length > 0) ? data.results[0].uuid : undefined;
                $rootScope.currentProvider = { uuid: providerUuid };
            });
        };

        this.updateSession = function (location, locale) {
            var requestData = {
                "sessionLocation": location.uuid
            };
            if (locale) {
                requestData.locale = locale;
            }
            return $http({
                method: 'POST',
                url: Bahmni.Common.Constants.RESTWS_V1 + '/session',
                data: requestData,
                headers: {'Content-Type': 'application/json'}
            }).then(function (response) {
                $bahmniCookieStore.remove(Bahmni.Common.Constants.locationCookieName);
                $bahmniCookieStore.put(Bahmni.Common.Constants.locationCookieName, {name: location.display, uuid: location.uuid}, {path: '/', expires: 7});
            });
        };
    }]).factory('authenticator', ['$rootScope', '$q', '$window', 'sessionService', function ($rootScope, $q, $window, sessionService) {
        var authenticateUser = function () {
            var defer = $q.defer();
            var sessionDetails = sessionService.get();
            sessionDetails.then(function (response) {
                if (response.data.authenticated) {
                    defer.resolve();
                } else {
                    defer.reject('User not authenticated');
                    $rootScope.$broadcast('event:auth-loginRequired');
                }
            });
            return defer.promise;
        };

        return {
            authenticateUser: authenticateUser
        };
    }]).directive('logOut', ['$rootScope', 'sessionService', '$window', 'configurationService', 'auditLogService', function ($rootScope, sessionService, $window, configurationService, auditLogService) {
        function logoutUser () {
            auditLogService.log(undefined, 'USER_LOGOUT_SUCCESS', undefined, 'MODULE_LABEL_LOGOUT_KEY').then(function () {
                sessionService.destroy().then(function () {
                    $window.location = "../home/index.html#/login";
                });
            });
        }

        function handleKeyPress (event) {
            if ((event.metaKey || event.ctrlKey) && event.key === $rootScope.quickLogoutComboKey) {
                logoutUser();
            }
        }
        return {
            link: function (scope, element) {
                element.bind('click', function () {
                    scope.$apply(function () {
                        logoutUser();
                    });
                });
                $window.addEventListener('keydown', handleKeyPress);
                scope.$on('$destroy', function () {
                    $window.removeEventListener('keydown', handleKeyPress);
                });
            }
        };
    }])
    .directive('btnUserInfo', [function () {
        return {
            restrict: 'CA',
            link: function (scope, elem) {
                elem.bind('click', function (event) {
                    $(this).next().toggleClass('active');
                    event.stopPropagation();
                });
                $(document).find('body').bind('click', function () {
                    $(elem).next().removeClass('active');
                });
            }
        };
    }
    ]);

angular.module('bahmni.common.appFramework', ['authentication']);

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.AppFramework = Bahmni.Common.AppFramework || {};

'use strict';

Bahmni.Common.AppFramework.AppDescriptor = function (context, inheritContext, retrieveUserCallback, mergeService) {
    this.id = null;
    this.instanceOf = null;
    this.description = null;
    this.contextModel = null;

    this.baseExtensionPoints = [];
    this.customExtensionPoints = [];

    this.baseExtensions = {};
    this.customExtensions = {};

    this.customConfigs = {};
    this.baseConfigs = {};

    this.extensionPath = context;
    this.contextPath = inheritContext ? context.split("/")[0] : context;

    var self = this;

    var setExtensionPointsFromExtensions = function (currentExtensions, currentExtensionPoints) {
        _.values(currentExtensions).forEach(function (extn) {
            if (extn) {
                var existing = self[currentExtensionPoints].filter(function (ep) {
                    return ep.id === extn.extensionPointId;
                });
                if (existing.length === 0) {
                    self[currentExtensionPoints].push({
                        id: extn.extensionPointId,
                        description: extn.description
                    });
                }
            }
        });
    };

    this.setExtensions = function (baseExtensions, customExtensions) {
        if (customExtensions) {
            setExtensionPointsFromExtensions(customExtensions, "customExtensionPoints");
            self.customExtensions = customExtensions;
        }
        self.baseExtensions = baseExtensions;
        setExtensionPointsFromExtensions(baseExtensions, "baseExtensionPoints");
    };

    this.setTemplate = function (template) {
        self.instanceOf = template.id;
        self.description = self.description || template.description;
        self.contextModel = self.contextModel || template.contextModel;
        if (template.configOptions) {
            _.values(template.configOptions).forEach(function (opt) {
                var existing = self.configs.filter(function (cfg) {
                    return cfg.name === opt.name;
                });
                if (existing.length > 0) {
                    existing[0].description = opt.description;
                } else {
                    self.configs.push({
                        name: opt.name,
                        description: opt.description,
                        value: opt.defaultValue
                    });
                }
            });
        }
    };

    var setConfig = function (instance, currentConfig) {
        for (var configName in instance.config) {
            var existingConfig = getConfig(self[currentConfig], configName);
            if (existingConfig) {
                existingConfig.value = instance.config[configName];
            } else {
                self[currentConfig][configName] = { name: configName, value: instance.config[configName] };
            }
        }
    };

    var setDefinitionExtensionPoints = function (extensionPoints, currentExtensionPoints) {
        if (extensionPoints) {
            extensionPoints.forEach(function (iep) {
                if (iep) {
                    var existing = self[currentExtensionPoints].filter(function (ep) {
                        return ep.id === iep.id;
                    });
                    if (existing.length === 0) {
                        self[currentExtensionPoints].push(iep);
                    }
                }
            });
        }
    };

    this.setDefinition = function (baseInstance, customInstance) {
        self.instanceOf = (customInstance && customInstance.instanceOf) ? customInstance.instanceOf : baseInstance.instanceOf;
        self.id = (customInstance && customInstance.id) ? customInstance.id : baseInstance.id;
        self.description = (customInstance && customInstance.description) ? customInstance.description : baseInstance.description;
        self.contextModel = (customInstance && customInstance.contextModel) ? customInstance.contextModel : baseInstance.contextModel;

        setDefinitionExtensionPoints(baseInstance.extensionPoints, "baseExtensionPoints");
        setConfig(baseInstance, "baseConfigs");
        if (customInstance) {
            setDefinitionExtensionPoints(customInstance.extensionPoints, "customExtensionPoints");
            setConfig(customInstance, "customConfigs");
        }
    };

    var getExtensions = function (extPointId, type, extensions) {
        var currentUser = retrieveUserCallback();
        var currentExtensions = _.values(extensions);
        if (currentUser && currentExtensions) {
            var extnType = type || 'all';
            var userPrivileges = currentUser.privileges.map(function (priv) {
                return priv.retired ? "" : priv.name;
            });
            var appsExtns = currentExtensions.filter(function (extn) {
                return ((extnType === 'all') || (extn.type === extnType)) &&
                    (extn.extensionPointId === extPointId) && (!extn.requiredPrivilege ||
                    (userPrivileges.indexOf(extn.requiredPrivilege) >= 0));
            });
            appsExtns.sort(function (extn1, extn2) {
                return extn1.order - extn2.order;
            });
            return appsExtns;
        }
    };

    this.getExtensions = function (extPointId, type, shouldMerge) {
        if (shouldMerge || shouldMerge === undefined) {
            var mergedExtensions = mergeService.merge(self.baseExtensions, self.customExtensions);
            return getExtensions(extPointId, type, mergedExtensions);
        }
        return [getExtensions(extPointId, type, self.baseExtensions), getExtensions(extPointId, type, self.customExtensions)];
    };

    this.getExtensionById = function (id, shouldMerge) {
        if (shouldMerge || shouldMerge === undefined) {
            var mergedExtensions = _.values(mergeService.merge(self.baseExtensions, self.customExtensions));
            return mergedExtensions.filter(function (extn) {
                return extn.id === id;
            })[0];
        } else {
            return [self.baseExtensions.filter(function (extn) {
                return extn.id === id;
            })[0], self.customExtensions.filter(function (extn) {
                return extn.id === id;
            })[0]];
        }
    };

    var getConfig = function (config, configName) {
        var cfgList = _.values(config).filter(function (cfg) {
            return cfg.name === configName;
        });
        return (cfgList.length > 0) ? cfgList[0] : null;
    };

    this.getConfig = function (configName, shouldMerge) {
        if (shouldMerge || shouldMerge === undefined) {
            return getConfig(mergeService.merge(self.baseConfigs, self.customConfigs), configName);
        } else {
            return [getConfig(self.baseConfigs, configName), getConfig(self.customConfigs, configName)];
        }
    };

    this.getConfigValue = function (configName, shouldMerge) {
        var config = this.getConfig(configName, shouldMerge);

        if (shouldMerge || shouldMerge === undefined) {
            return config ? config.value : null;
        }
        return config;
    };

    this.formatUrl = function (url, options, useQueryParams) {
        var pattern = /{{([^}]*)}}/g,
            matches = url.match(pattern),
            replacedString = url,
            checkQueryParams = useQueryParams || false,
            queryParameters = this.parseQueryParams();
        if (matches) {
            matches.forEach(function (el) {
                var key = el.replace("{{", '').replace("}}", '');
                var value = options[key];
                if (!value && (checkQueryParams === true)) {
                    value = queryParameters[key] || null;
                }
                replacedString = replacedString.replace(el, value);
            });
        }
        return replacedString.trim();
    };

    this.parseQueryParams = function (locationSearchString) {
        var urlParams;
        var match,
            pl = /\+/g,  // Regex for replacing addition symbol with a space
            search = /([^&=]+)=?([^&]*)/g,
            decode = function (s) { return decodeURIComponent(s.replace(pl, " ")); },
            queryString = locationSearchString || window.location.search.substring(1);

        urlParams = {};
        while (match = search.exec(queryString)) {  // eslint-disable-line no-cond-assign
            urlParams[decode(match[1])] = decode(match[2]);
        }
        return urlParams;
    };

    this.addConfigForPage = function (pageName, baseConfig, customConfig) {
        self.basePageConfigs = self.basePageConfigs || {};
        self.basePageConfigs[pageName] = baseConfig;

        self.customPageConfigs = self.customPageConfigs || {};
        self.customPageConfigs[pageName] = customConfig;
    };

    this.getConfigForPage = function (pageName, shouldMerge) {
        if (shouldMerge || shouldMerge === undefined) {
            return mergeService.merge(self.basePageConfigs[pageName], self.customPageConfigs[pageName]);
        }
        return [_.values(self.basePageConfigs[pageName]), _.values(self.customPageConfigs[pageName])];
    };
};

'use strict';

angular.module('bahmni.common.appFramework')
    .config(['$compileProvider', function ($compileProvider) {
        $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|ftp|mailto|chrome-extension|file):/);
    }])
    .service('appService', ['$http', '$q', 'sessionService', '$rootScope', 'mergeService', 'loadConfigService', 'messagingService', '$translate',
        function ($http, $q, sessionService, $rootScope, mergeService, loadConfigService, messagingService, $translate) {
            var currentUser = null;
            var baseUrl = Bahmni.Common.Constants.baseUrl;
            var customUrl = Bahmni.Common.Constants.customUrl;
            var appDescriptor = null;
            $rootScope.meetId = null;
            var loadConfig = function (url) {
                return loadConfigService.loadConfig(url, appDescriptor.contextPath);
            };

            var loadTemplate = function (appDescriptor) {
                var deferrable = $q.defer();
                loadConfig(baseUrl + appDescriptor.contextPath + "/appTemplate.json").then(
                function (result) {
                    if (_.keys(result.data).length > 0) {
                        appDescriptor.setTemplate(result.data);
                    }
                    deferrable.resolve(appDescriptor);
                },
                function (error) {
                    if (error.status !== 404) {
                        deferrable.reject(error);
                    } else {
                        deferrable.resolve(appDescriptor);
                    }
                }
            );
                return deferrable.promise;
            };

            var setDefinition = function (baseResultData, customResultData) {
                if (customResultData && (_.keys(baseResultData).length > 0 || _.keys(customResultData.length > 0))) {
                    appDescriptor.setDefinition(baseResultData, customResultData);
                } else if (_.keys(baseResultData).length > 0) {
                    appDescriptor.setDefinition(baseResultData);
                }
            };

            var loadDefinition = function (appDescriptor) {
                var deferrable = $q.defer();
                loadConfig(baseUrl + appDescriptor.contextPath + "/app.json").then(
                function (baseResult) {
                    if (baseResult.data.shouldOverRideConfig) {
                        loadConfig(customUrl + appDescriptor.contextPath + "/app.json").then(function (customResult) {
                            setDefinition(baseResult.data, customResult.data);
                            deferrable.resolve(appDescriptor);
                        },
                            function () {
                                setDefinition(baseResult.data);
                                deferrable.resolve(appDescriptor);
                            });
                    } else {
                        setDefinition(baseResult.data);
                        deferrable.resolve(appDescriptor);
                    }
                }, function (error) {
                    if (error.status !== 404) {
                        deferrable.reject(error);
                    } else {
                        deferrable.resolve(appDescriptor);
                    }
                });
                return deferrable.promise;
            };

            var setExtensions = function (baseResultData, customResultData) {
                if (customResultData) {
                    appDescriptor.setExtensions(baseResultData, customResultData);
                } else {
                    appDescriptor.setExtensions(baseResultData);
                }
            };
            var loadExtensions = function (appDescriptor, extensionFileName) {
                var deferrable = $q.defer();
                loadConfig(baseUrl + appDescriptor.extensionPath + extensionFileName).then(function (baseResult) {
                    if (baseResult.data.shouldOverRideConfig) {
                        loadConfig(customUrl + appDescriptor.extensionPath + extensionFileName).then(
                        function (customResult) {
                            setExtensions(baseResult.data, customResult.data);
                            deferrable.resolve(appDescriptor);
                        },
                        function () {
                            setExtensions(baseResult.data);
                            deferrable.resolve(appDescriptor);
                        });
                    } else {
                        setExtensions(baseResult.data);
                        deferrable.resolve(appDescriptor);
                    }
                }, function (error) {
                    if (error.status !== 404) {
                        deferrable.reject(error);
                    } else {
                        deferrable.resolve(appDescriptor);
                    }
                });
                return deferrable.promise;
            };

            var setDefaultPageConfig = function (pageName, baseResultData, customResultData) {
                if (customResultData && (_.keys(customResultData).length > 0 || _.keys(baseResultData).length > 0)) {
                    appDescriptor.addConfigForPage(pageName, baseResultData, customResultData);
                } else if (_.keys(baseResultData).length > 0) {
                    appDescriptor.addConfigForPage(pageName, baseResultData);
                }
            };

            var hasPrivilegeOf = function (privilegeName) {
                return _.some(currentUser.privileges, {name: privilegeName});
            };

            var loadPageConfig = function (pageName, appDescriptor) {
                var deferrable = $q.defer();
                loadConfig(baseUrl + appDescriptor.contextPath + "/" + pageName + ".json").then(
                function (baseResult) {
                    if (baseResult.data.shouldOverRideConfig) {
                        loadConfig(customUrl + appDescriptor.contextPath + "/" + pageName + ".json").then(
                            function (customResult) {
                                setDefaultPageConfig(pageName, baseResult.data, customResult.data);
                                deferrable.resolve(appDescriptor);
                            },
                            function () {
                                setDefaultPageConfig(pageName, baseResult.data);
                                deferrable.resolve(appDescriptor);
                            });
                    } else {
                        setDefaultPageConfig(pageName, baseResult.data);
                        deferrable.resolve(appDescriptor);
                    }
                }, function (error) {
                    if (error.status !== 404) {
                        messagingService.showMessage('error', $translate.instance("INCORRECT_CONFIGURATION_MESSAGE", {error: error.message}));
                        deferrable.reject(error);
                    } else {
                        deferrable.resolve(appDescriptor);
                    }
                });
                return deferrable.promise;
            };
            this.getAppDescriptor = function () {
                return appDescriptor;
            };

            this.configBaseUrl = function () {
                return baseUrl;
            };

            this.loadCsvFileFromConfig = function (name) {
                return loadConfig(baseUrl + appDescriptor.contextPath + "/" + name);
            };

            this.loadConfig = function (name, shouldMerge) {
                return loadConfig(baseUrl + appDescriptor.contextPath + "/" + name).then(
                function (baseResponse) {
                    if (baseResponse.data.shouldOverRideConfig) {
                        return loadConfig(customUrl + appDescriptor.contextPath + "/" + name).then(function (customResponse) {
                            if (shouldMerge || shouldMerge === undefined) {
                                return mergeService.merge(baseResponse.data, customResponse.data);
                            }
                            return [baseResponse.data, customResponse.data];
                        }, function () {
                            return baseResponse.data;
                        });
                    } else {
                        return baseResponse.data;
                    }
                }
            );
            };

            this.loadMandatoryConfig = function (path) {
                return $http.get(path);
            };

            this.getAppName = function () {
                return this.appName;
            };

            this.checkPrivilege = function (privilegeName) {
                if (hasPrivilegeOf(privilegeName)) {
                    return $q.when(true);
                }
                messagingService.showMessage("error", $translate.instant(Bahmni.Common.Constants.privilegeRequiredErrorMessage) + " [Privileges required: " + privilegeName + "]");
                return $q.reject();
            };

            this.initApp = function (appName, options, extensionFileSuffix, configPages) {
                this.appName = appName;
                var appLoader = $q.defer();
                var extensionFileName = (extensionFileSuffix && extensionFileSuffix.toLowerCase() !== 'default') ? "/extension-" + extensionFileSuffix + ".json" : "/extension.json";
                var promises = [];
                var opts = options || {'app': true, 'extension': true};

                var inheritAppContext = (!opts.inherit) ? true : opts.inherit;

                appDescriptor = new Bahmni.Common.AppFramework.AppDescriptor(appName, inheritAppContext, function () {
                    return currentUser;
                }, mergeService);

                var loadCredentialsPromise = sessionService.loadCredentials();
                var loadProviderPromise = loadCredentialsPromise.then(sessionService.loadProviders);

                promises.push(loadCredentialsPromise);
                promises.push(loadProviderPromise);
                if (opts.extension) {
                    promises.push(loadExtensions(appDescriptor, extensionFileName));
                }
                if (opts.template) {
                    promises.push(loadTemplate(appDescriptor));
                }
                if (opts.app) {
                    promises.push(loadDefinition(appDescriptor));
                }
                if (!_.isEmpty(configPages)) {
                    configPages.forEach(function (configPage) {
                        promises.push(loadPageConfig(configPage, appDescriptor));
                    });
                }
                $q.all(promises).then(function (results) {
                    currentUser = results[0];
                    appLoader.resolve(appDescriptor);
                    $rootScope.$broadcast('event:appExtensions-loaded');
                }, function (errors) {
                    appLoader.reject(errors);
                });
                return appLoader.promise;
            };
        }]);

'use strict';

angular.module('bahmni.common.appFramework')
    .service('mergeService', [function () {
        this.merge = function (base, custom) {
            var mergeResult = $.extend(true, {}, base, custom);
            return deleteNullValuedKeys(mergeResult);
        };
        var deleteNullValuedKeys = function (currentObject) {
            _.forOwn(currentObject, function (value, key) {
                if (_.isUndefined(value) || _.isNull(value) || _.isNaN(value) ||
                    (_.isObject(value) && _.isNull(deleteNullValuedKeys(value)))) {
                    delete currentObject[key];
                }
            });
            return currentObject;
        };
    }]);

angular.module('bahmni.common.patient', []);

'use strict';

angular.module('bahmni.common.patient')
.filter('age', ['$filter', '$translate', function ($filter, $translate) {
    return function (age) {
        var requiredAgeToShowCompletedYears = 5;
        if (age.years) {
            if (age.years < requiredAgeToShowCompletedYears) {
                return (age.years ? age.years + " " + $translate.instant("CLINICAL_YEARS_TRANSLATION_KEY") : "") +
                       (age.months ? " " + age.months + " " + $translate.instant("CLINICAL_MONTHS_TRANSLATION_KEY") : "");
            }
            return age.years + " " + $translate.instant("CLINICAL_YEARS_TRANSLATION_KEY");
        }
        if (age.months) {
            return age.months + " " + $translate.instant("CLINICAL_MONTHS_TRANSLATION_KEY");
        }
        return age.days + " " + $translate.instant("CLINICAL_DAYS_TRANSLATION_KEY");
    };
}]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.ConceptSet = Bahmni.ConceptSet || {};
Bahmni.ConceptSet.FormConditions = Bahmni.ConceptSet.FormConditions || {};

angular.module('bahmni.common.conceptSet', ['bahmni.common.uiHelper', 'ui.select2', 'pasvaz.bindonce', 'ngSanitize', 'ngTagsInput']);

'use strict';

angular.module('bahmni.common.conceptSet')
    .controller('ConceptSetGroupController', ['$scope', 'contextChangeHandler', 'spinner', 'messagingService',
        'conceptSetService', '$rootScope', 'sessionService', 'encounterService', 'treatmentConfig',
        'retrospectiveEntryService', 'userService', 'conceptSetUiConfigService', '$timeout', 'clinicalAppConfigService', '$stateParams', '$translate',
        function ($scope, contextChangeHandler, spinner, messagingService, conceptSetService, $rootScope, sessionService,
                  encounterService, treatmentConfig, retrospectiveEntryService, userService,
                  conceptSetUiConfigService, $timeout, clinicalAppConfigService, $stateParams, $translate) {
            var conceptSetUIConfig = conceptSetUiConfigService.getConfig();
            var init = function () {
                $scope.validationHandler = new Bahmni.ConceptSet.ConceptSetGroupPanelViewValidationHandler($scope.allTemplates);
                contextChangeHandler.add($scope.validationHandler.validate);
            };
            $scope.toggleSideBar = function () {
                $rootScope.showLeftpanelToggle = !$rootScope.showLeftpanelToggle;
            };
            $scope.showLeftpanelToggle = function () {
                return $rootScope.showLeftpanelToggle;
            };

            $scope.togglePref = function (conceptSet, conceptName) {
                $rootScope.currentUser.toggleFavoriteObsTemplate(conceptName);
                spinner.forPromise(userService.savePreferences());
            };

            $scope.getNormalized = function (conceptName) {
                return conceptName.replace(/['\.\s\(\)\/,\\]+/g, "_");
            };

            $scope.showPreviousButton = function (conceptSetName) {
                return conceptSetUIConfig[conceptSetName] && conceptSetUIConfig[conceptSetName].showPreviousButton;
            };

            $scope.showPrevious = function (conceptSetName, event) {
                event.stopPropagation();
                $timeout(function () {
                    $scope.$broadcast('event:showPrevious' + conceptSetName);
                });
            };
            $scope.isInEditEncounterMode = function () {
                return $stateParams.encounterUuid !== undefined && $stateParams.encounterUuid !== 'active';
            };

            $scope.computeField = function (conceptSet, event) {
                event.stopPropagation();
                $scope.consultation.preSaveHandler.fire();
                var defaultRetrospectiveVisitType = clinicalAppConfigService.getVisitTypeForRetrospectiveEntries();

                var encounterData = new Bahmni.Clinical.EncounterTransactionMapper().map(angular.copy($scope.consultation), $scope.patient, sessionService.getLoginLocationUuid(),
                    retrospectiveEntryService.getRetrospectiveEntry(), defaultRetrospectiveVisitType, $scope.isInEditEncounterMode());
                encounterData = encounterService.buildEncounter(encounterData);
                encounterData.drugOrders = [];

                var conceptSetData = {name: conceptSet.conceptName, uuid: conceptSet.uuid};
                var data = {
                    encounterModifierObservations: encounterData.observations,
                    drugOrders: encounterData.drugOrders,
                    conceptSetData: conceptSetData,
                    patientUuid: encounterData.patientUuid,
                    encounterDateTime: encounterData.encounterDateTime
                };

                spinner.forPromise(treatmentConfig().then(function (treatmentConfig) {
                    $scope.treatmentConfiguration = treatmentConfig;
                    return conceptSetService.getComputedValue(data);
                }).then(function (response) {
                    response = response.data;
                    copyValues($scope.consultation.observations, response.encounterModifierObservations);
                    $scope.consultation.newlyAddedTreatments = $scope.consultation.newlyAddedTreatments || [];
                    response.drugOrders.forEach(function (drugOrder) {
                        $scope.consultation.newlyAddedTreatments.push(Bahmni.Clinical.DrugOrderViewModel.createFromContract(drugOrder, $scope.treatmentConfiguration));
                    });
                }));
            };

            $scope.canRemove = function (index) {
                if ($scope.allTemplates[index].followupForm) {
                    return false;
                }
                var observations = $scope.allTemplates[index].observations;
                if (observations === undefined || _.isEmpty(observations)) {
                    return true;
                }
                return observations[0].uuid === undefined;
            };

            $scope.clone = function (index) {
                var clonedObj = $scope.allTemplates[index].clone();
                $scope.allTemplates.splice(index + 1, 0, clonedObj);
                $.scrollTo('#concept-set-' + (index + 1), 200, {offset: {top: -400}});
            };

            $scope.clonePanelConceptSet = function (conceptSet) {
                var index = _.findIndex($scope.allTemplates, conceptSet);
                messagingService.showMessage("info", $translate.instant("CLINICAL_TEMPLATE_ADDED_SUCCESS_KEY", {label: $scope.allTemplates[index].label}));
                $scope.clone(index);
                $scope.showLeftPanelConceptSet($scope.allTemplates[index + 1]);
            };

            $scope.isClonedSection = function (conceptSetTemplate, allTemplates) {
                if (allTemplates) {
                    var index = allTemplates.indexOf(conceptSetTemplate);
                    return (index > 0) ? allTemplates[index].label == allTemplates[index - 1].label : false;
                }
                return false;
            };

            $scope.isLastClonedSection = function (conceptSetTemplate) {
                var index = _.findIndex($scope.allTemplates, conceptSetTemplate);
                if ($scope.allTemplates) {
                    if (index == $scope.allTemplates.length - 1 || $scope.allTemplates[index].label != $scope.allTemplates[index + 1].label) {
                        return true;
                    }
                }
                return false;
            };

            $scope.remove = function (index) {
                var label = $scope.allTemplates[index].label;
                var currentTemplate = $scope.allTemplates[index];
                var anotherTemplate = _.find($scope.allTemplates, function (template) {
                    return template.label == currentTemplate.label && template !== currentTemplate;
                });
                if (anotherTemplate) {
                    $scope.allTemplates.splice(index, 1);
                }
                else {
                    $scope.allTemplates[index].isAdded = false;
                    var clonedObj = $scope.allTemplates[index].clone();
                    $scope.allTemplates[index] = clonedObj;
                    $scope.allTemplates[index].isAdded = false;
                    $scope.allTemplates[index].isOpen = false;
                    $scope.allTemplates[index].klass = "";
                    $scope.allTemplates[index].isLoaded = false;
                }
                $scope.leftPanelConceptSet = "";
                messagingService.showMessage("info", $translate.instant("CLINICAL_TEMPLATE_REMOVED_SUCCESS_KEY", {label: label}));
            };

            $scope.openActiveForm = function (conceptSet) {
                if (conceptSet && conceptSet.klass == 'active' && conceptSet != $scope.leftPanelConceptSet) {
                    $scope.showLeftPanelConceptSet(conceptSet);
                }
                return conceptSet.klass;
            };

            var copyValues = function (existingObservations, modifiedObservations) {
                existingObservations.forEach(function (observation, index) {
                    if (observation.groupMembers && observation.groupMembers.length > 0) {
                        copyValues(observation.groupMembers, modifiedObservations[index].groupMembers);
                    } else {
                        observation.value = modifiedObservations[index].value;
                    }
                });
            };

            var collapseExistingActiveSection = function (section) {
                if (section) {
                    section.klass = "";
                    section.isOpen = false;
                    section.isLoaded = false;
                }
            };

            $scope.showLeftPanelConceptSet = function (selectedConceptSet) {
                collapseExistingActiveSection($scope.leftPanelConceptSet);
                $scope.leftPanelConceptSet = selectedConceptSet;
                $scope.leftPanelConceptSet.isOpen = true;
                $scope.leftPanelConceptSet.isLoaded = true;
                $scope.leftPanelConceptSet.klass = "active";
                $scope.leftPanelConceptSet.atLeastOneValueIsSet = selectedConceptSet.hasSomeValue();
                $scope.leftPanelConceptSet.isAdded = true;
                $scope.consultation.lastvisited = selectedConceptSet.id || selectedConceptSet.formUuid;
                if ($rootScope.showLeftpanelToggle) {
                    $rootScope.showLeftpanelToggle = false;
                }
                $(window).scrollTop(0);
            };

            $scope.focusOnErrors = function () {
                var errorMessage = $scope.leftPanelConceptSet.errorMessage ? $scope.leftPanelConceptSet.errorMessage : "{{'CLINICAL_FORM_ERRORS_MESSAGE_KEY' | translate }}";
                messagingService.showMessage('error', errorMessage);
                $scope.$parent.$parent.$broadcast("event:errorsOnForm");
            };

            $scope.isFormTemplate = function (data) {
                return data.formUuid;
            };

            init();
        }])
    .directive('conceptSetGroup', function () {
        return {
            restrict: 'EA',
            scope: {
                conceptSetGroupExtensionId: "=?",
                observations: "=",
                allTemplates: "=",
                context: "=",
                autoScrollEnabled: "=",
                patient: "=",
                consultation: "="

            },
            controller: 'ConceptSetGroupController',
            templateUrl: '../common/concept-set/views/conceptSetGroup.html'
        };
    });

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('conceptSet', ['contextChangeHandler', 'appService', 'observationsService', 'messagingService', 'conceptSetService', 'conceptSetUiConfigService', 'spinner',
        function (contextChangeHandler, appService, observationsService, messagingService, conceptSetService, conceptSetUiConfigService, spinner) {
            var controller = function ($scope) {
                var conceptSetName = $scope.conceptSetName;
                var ObservationUtil = Bahmni.Common.Obs.ObservationUtil;
                var conceptSetUIConfig = conceptSetUiConfigService.getConfig();
                var observationMapper = new Bahmni.ConceptSet.ObservationMapper();
                var validationHandler = $scope.validationHandler() || contextChangeHandler;
                var id = "#" + $scope.sectionId;

                $scope.atLeastOneValueIsSet = $scope.atLeastOneValueIsSet || false;
                $scope.conceptSetRequired = false;
                $scope.showTitleValue = $scope.showTitle();
                $scope.numberOfVisits = conceptSetUIConfig[conceptSetName] && conceptSetUIConfig[conceptSetName].numberOfVisits ? conceptSetUIConfig[conceptSetName].numberOfVisits : null;
                $scope.hideAbnormalButton = conceptSetUIConfig[conceptSetName] && conceptSetUIConfig[conceptSetName].hideAbnormalButton;

                var focusFirstObs = function () {
                    if ($scope.conceptSetFocused && $scope.rootObservation.groupMembers && $scope.rootObservation.groupMembers.length > 0) {
                        var firstObs = _.find($scope.rootObservation.groupMembers, function (obs) {
                            return obs.isFormElement && obs.isFormElement();
                        });
                        if (firstObs) {
                            firstObs.isFocused = true;
                        }
                    }
                };

                var updateObservationsOnRootScope = function () {
                    if ($scope.rootObservation) {
                        for (var i = 0; i < $scope.observations.length; i++) {
                            if ($scope.observations[i].concept.uuid === $scope.rootObservation.concept.uuid) {
                                $scope.observations[i] = $scope.rootObservation;
                                return;
                            }
                        }
                        $scope.observations.push($scope.rootObservation);
                    }
                };

                var getObservationsOfCurrentTemplate = function () {
                    return _.filter($scope.observations, function (observation) {
                        return _.toLower(observation.conceptSetName) === _.toLower($scope.rootObservation.concept.name);
                    });
                };

                var getDefaults = function () {
                    var conceptSetUI = appService.getAppDescriptor().getConfigValue("conceptSetUI");
                    if (!conceptSetUI || !conceptSetUI.defaults) {
                        return;
                    }
                    return conceptSetUI.defaults || {};
                };

                var getCodedAnswerWithDefaultAnswerString = function (defaults, groupMember) {
                    var possibleAnswers = groupMember.possibleAnswers;
                    var defaultAnswer = defaults[groupMember.concept.name];
                    var defaultCodedAnswer;
                    if (defaultAnswer instanceof Array) {
                        defaultCodedAnswer = [];
                        _.each(defaultAnswer, function (answer) {
                            defaultCodedAnswer.push(_.find(possibleAnswers, {displayString: answer}));
                        });
                    } else {
                        defaultCodedAnswer = _.find(possibleAnswers, {displayString: defaultAnswer});
                    }
                    return defaultCodedAnswer;
                };

                var setDefaultsForGroupMembers = function (groupMembers, defaults) {
                    if (defaults) {
                        _.each(groupMembers, function (groupMember) {
                            var conceptFullName = groupMember.concept.name;
                            var present = _.includes(_.keys(defaults), conceptFullName);
                            if (present && groupMember.value == undefined) {
                                if (groupMember.concept.dataType == "Coded") {
                                    setDefaultsForCodedObservations(groupMember, defaults);
                                } else {
                                    groupMember.value = defaults[conceptFullName];
                                }
                            }
                            if (groupMember.groupMembers && groupMember.groupMembers.length > 0) {
                                setDefaultsForGroupMembers(groupMember.groupMembers, defaults);
                                if (groupMember instanceof Bahmni.ConceptSet.ObservationNode && defaults[groupMember.label] && groupMember.abnormalObs && groupMember.abnormalObs.value == undefined) {
                                    groupMember.onValueChanged(groupMember.value);
                                }
                            }
                        });
                    }
                };

                var setDefaultsForCodedObservations = function (observation, defaults) {
                    var defaultCodedAnswer = getCodedAnswerWithDefaultAnswerString(defaults, observation);
                    if (observation.isMultiSelect) {
                        if (!observation.hasValue()) {
                            _.each(defaultCodedAnswer, function (answer) {
                                observation.selectAnswer(answer);
                            });
                        }
                    } else if (!(defaultCodedAnswer instanceof Array)) {
                        observation.value = defaultCodedAnswer;
                    }
                };

                var getFlattenedObsValues = function (flattenedObs) {
                    return _.reduce(flattenedObs, function (flattenedObsValues, obs) {
                        if (flattenedObsValues[obs.concept.name + '|' + obs.uniqueId] == undefined) {
                            if (obs.isMultiSelect) {
                                var selectedObsConceptNames = [];
                                _.each(obs.selectedObs, function (observation) {
                                    if (!observation.voided) {
                                        selectedObsConceptNames.push(observation.value.name);
                                    }
                                    if (!observation.voided) {
                                        selectedObsConceptNames.push(observation.value.name);
                                    }
                                });
                                flattenedObsValues[obs.concept.name + '|' + obs.uniqueId] = selectedObsConceptNames;
                            } else if (obs.conceptUIConfig.multiSelect) {
                                var alreadyProcessedMultiSelect = [];
                                _.each(_.keys(flattenedObsValues), function (eachObsKey) {
                                    eachObsKey.split('|')[0] == obs.concept.name && alreadyProcessedMultiSelect.push(eachObsKey);
                                });
                                if (alreadyProcessedMultiSelect.length < 2) {
                                    flattenedObsValues[obs.concept.name + '|' + obs.uniqueId] = flattenedObsValues[obs.concept.name + '|' + undefined];
                                    // Set the individual Observation of Multi Select to be the MultiSelect Obs
                                }
                            } else if (obs.value instanceof Object) {
                                flattenedObsValues[obs.concept.name + '|' + obs.uniqueId] = (obs.value.name instanceof Object) ? obs.value.name.name : obs.value.name;
                            } else {
                                flattenedObsValues[obs.concept.name + '|' + obs.uniqueId] = obs.value;
                            }
                        }
                        return flattenedObsValues;
                    }, {});
                };

                var clearFieldValuesOnDisabling = function (obs) {
                    obs.comment = undefined;
                    if (obs.value || obs.isBoolean) {
                        obs.value = undefined;
                    } else if (obs.isMultiSelect) {
                        for (var key in obs.selectedObs) {
                            if (!obs.selectedObs[key].voided) {
                                obs.toggleSelection(obs.selectedObs[key].value);
                            }
                        }
                    }
                };

                var setObservationState = function (obsArray, disable, error, hide) {
                    if (!_.isEmpty(obsArray)) {
                        _.each(obsArray, function (obs) {
                            obs.disabled = disable || hide;
                            obs.error = error;
                            obs.hide = hide;
                            if (hide || obs.disabled) {
                                clearFieldValuesOnDisabling(obs);
                            }
                            if (obs.groupMembers) {
                                _.each(obs.groupMembers, function (groupMember) {
                                    // TODO : Hack to fix issue with formconditions on multiselect - Swathi
                                    groupMember && setObservationState([groupMember], disable, error, hide);
                                });
                            }
                        });
                    }
                };

                var processConditions = function (flattenedObs, fields, disable, error, hide) {
                    _.each(fields, function (field) {
                        var matchingObsArray = [];
                        var clonedObsInSameGroup;
                        flattenedObs.forEach(function (obs) {
                            if (clonedObsInSameGroup != false && obs.concept.name == field) {
                                matchingObsArray.push(obs);
                                clonedObsInSameGroup = true;
                            } else if (clonedObsInSameGroup && obs.concept.name != field) {
                                clonedObsInSameGroup = false;
                            }
                        });

                        if (!_.isEmpty(matchingObsArray)) {
                            setObservationState(matchingObsArray, disable, error, hide);
                        } else {
                            messagingService.showMessage("error", "No element found with name : " + field);
                        }
                    });
                };

                var runFormConditionForObs = function (enableCase, formName, formCondition, conceptName, flattenedObs) {
                    var conceptSetObsValues = getFlattenedObsValues(flattenedObs);
                    _.each(_.keys(conceptSetObsValues), function (eachObsKey) {
                        if (eachObsKey.split('|')[0] == conceptName && eachObsKey.split('|')[1] != 'undefined') {
                            var valueMap = _.reduce(conceptSetObsValues, function (conceptSetValueMap, obsValue, conceptName) {
                                conceptSetValueMap[conceptName.split('|')[0]] = obsValue;
                                return conceptSetValueMap;
                            }, {});
                            var conditions = formCondition(formName, valueMap, $scope.patient);
                            if (!_.isUndefined(conditions)) {
                                if (conditions.error && !_.isEmpty(conditions.error)) {
                                    messagingService.showMessage('error', conditions.error);
                                    processConditions(flattenedObs, [conceptName], false, true, false);
                                } else {
                                    enableCase && processConditions(flattenedObs, [conceptName], false, false, false);
                                }
                                processConditions(flattenedObs, conditions.disable, true);
                                processConditions(flattenedObs, conditions.enable, false);
                                processConditions(flattenedObs, conditions.show, false, undefined, false);
                                processConditions(flattenedObs, conditions.hide, false, undefined, true);
                                _.each(conditions.enable, function (subConditionConceptName) {
                                    var conditionFn = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[subConditionConceptName];
                                    if (conditionFn != null) {
                                        runFormConditionForObs(true, formName, conditionFn, subConditionConceptName, flattenedObs);
                                    }
                                });
                                _.each(conditions.disable, function (subConditionConceptName) {
                                    var conditionFn = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[subConditionConceptName];
                                    if (conditionFn != null) {
                                        _.each(flattenedObs, function (obs) {
                                            if (obs.concept.name == subConditionConceptName) {
                                                runFormConditionForObs(false, formName, conditionFn, subConditionConceptName, flattenedObs);
                                            }
                                        });
                                    }
                                });
                                _.each(conditions.show, function (subConditionConceptName) {
                                    var conditionFn = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[subConditionConceptName];
                                    if (conditionFn) {
                                        runFormConditionForObs(true, formName, conditionFn, subConditionConceptName, flattenedObs);
                                    }
                                });
                                _.each(conditions.hide, function (subConditionConceptName) {
                                    var conditionFn = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[subConditionConceptName];
                                    if (conditionFn) {
                                        _.each(flattenedObs, function (obs) {
                                            if (obs.concept.name == subConditionConceptName) {
                                                runFormConditionForObs(false, formName, conditionFn, subConditionConceptName, flattenedObs);
                                            }
                                        });
                                    }
                                });
                            }
                        }
                    });
                };

                var updateFormConditions = function (observationsOfCurrentTemplate, rootObservation) {
                    if (Bahmni.ConceptSet.FormConditions.rules) {
                        runFormConditionForAllObsRecursively(rootObservation.concept.name, rootObservation);
                    }
                };

                var runFormConditionForAllObsRecursively = function (formName, rootObservation) {
                    _.each(rootObservation.groupMembers, function (observation) {
                        var conditionFn = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[observation.concept.name];
                        if (conditionFn != null) {
                            var flattenedObs = ObservationUtil.flattenObsToArray([rootObservation]);
                            runFormConditionForObs(false, formName, conditionFn, observation.concept.name, flattenedObs);
                        }
                        if (observation.groupMembers && observation.groupMembers.length > 0) {
                            runFormConditionForAllObsRecursively(formName, observation);
                        }
                    });
                };
                var addDummyImage = function () {
                    _.each($scope.rootObservation.groupMembers, function (observation) {
                        addDummyImageObservationForSavedObs(observation, $scope.rootObservation);
                    });
                };
                var addDummyImageObservationForSavedObs = function (observation, rootObservation) {
                    _.each(observation.groupMembers, function (childObservation) {
                        addDummyImageObservationForSavedObs(childObservation, observation);
                    });
                    if (observation.getControlType() === 'image' && observation.value && rootObservation.groupMembers.indexOf(observation) === rootObservation.groupMembers.length - 1) {
                        rootObservation.groupMembers.push(observation.cloneNew());
                        return;
                    }
                };
                var init = function () {
                    return conceptSetService.getConcept({
                        name: conceptSetName,
                        v: "bahmni"
                    }).then(function (response) {
                        $scope.conceptSet = response.data.results[0];
                        $scope.rootObservation = $scope.conceptSet ? observationMapper.map($scope.observations, $scope.conceptSet, conceptSetUIConfig) : null;
                        if ($scope.rootObservation) {
                            $scope.rootObservation.conceptSetName = $scope.conceptSetName;
                            focusFirstObs();
                            updateObservationsOnRootScope();
                            var groupMembers = getObservationsOfCurrentTemplate()[0].groupMembers;
                            var defaults = getDefaults();
                            addDummyImage();
                            setDefaultsForGroupMembers(groupMembers, defaults);
                            var observationsOfCurrentTemplate = getObservationsOfCurrentTemplate();
                            updateFormConditions(observationsOfCurrentTemplate, $scope.rootObservation);
                        } else {
                            $scope.showEmptyConceptSetMessage = true;
                        }
                    }).catch(function (error) {
                        messagingService.showMessage('error', error.message);
                    });
                };
                spinner.forPromise(init(), id);

                var validateObservationTree = function () {
                    if (typeof $scope.rootObservation === "undefined" || $scope.rootObservation === null) {
                        return {allow: true, errorMessage: null };
                    }
                    $scope.atLeastOneValueIsSet = $scope.rootObservation && $scope.rootObservation.atLeastOneValueSet();
                    $scope.conceptSetRequired = $scope.required ? $scope.required : true;
                    var nodes = $scope.rootObservation && findInvalidNodes($scope.rootObservation.groupMembers, $scope.rootObservation);
                    return {allow: !nodes.status, errorMessage: nodes.message};
                }; // TODO: Write unit test for this function

                var findInvalidNodes = function (members, parentNode) {
                    var errorMessage = null;
                    var status = members.some(function (childNode) {
                        if (childNode.voided) {
                            return false;
                        }
                        var groupMembers = childNode.groupMembers || [];
                        for (var index in groupMembers) {
                            var information = groupMembers[index].groupMembers && groupMembers[index].groupMembers.length ? findInvalidNodes(groupMembers[index].groupMembers, groupMembers[index]) : validateChildNode(groupMembers[index], childNode);
                            if (information.status) {
                                errorMessage = information.message;
                                return true;
                            }
                        }
                        information = validateChildNode(childNode, parentNode);
                        if (information.status) {
                            errorMessage = information.message;
                            return true;
                        }
                        return !childNode.isValid($scope.atLeastOneValueIsSet, $scope.conceptSetRequired);
                    });
                    return {message: errorMessage, status: status};
                };
                var validateChildNode = function (childNode, parentNode) {
                    var errorMessage;
                    if (childNode.possibleAnswers && !childNode.possibleAnswers.length) {
                        if (typeof childNode.isValueInAbsoluteRange == 'function' && !childNode.isValueInAbsoluteRange()) {
                            errorMessage = "The value you entered (red field) is outside the range of allowable values for that record. Please check the value.";
                            return {message: errorMessage, status: true};
                        }

                        if (childNode.isNumeric()) {
                            if (!childNode.isValidNumeric()) {
                                errorMessage = "Please enter Integer value, decimal value is not allowed";
                                return {message: errorMessage, status: true};
                            }
                            if (parentNode) {
                                if (!childNode.isValidNumericValue() || !parentNode.isValidNumericValue()) {
                                    errorMessage = "Please enter Numeric values";
                                    return {message: errorMessage, status: true};
                                }
                            } else {
                                if (!childNode.isValidNumericValue()) {
                                    errorMessage = "Please enter Numeric values";
                                    return {message: errorMessage, status: true};
                                }
                            }
                        }
                    }
                    return {status: false};
                };

                validationHandler.add(validateObservationTree);

                var cleanUpListenerShowPrevious = $scope.$on('event:showPrevious' + conceptSetName, function () {
                    return spinner.forPromise(observationsService.fetch($scope.patient.uuid, $scope.conceptSetName, null, $scope.numberOfVisits, null, true), id).then(function (response) {
                        var recentObservations = ObservationUtil.flattenObsToArray(response.data);
                        var conceptSetObservation = $scope.observations.filter(function (observation) {
                            return observation.conceptSetName === $scope.conceptSetName;
                        });
                        ObservationUtil.flattenObsToArray(conceptSetObservation).forEach(function (obs) {
                            var correspondingRecentObs = _.filter(recentObservations, function (recentObs) {
                                return obs.concept.uuid === recentObs.concept.uuid;
                            });
                            if (correspondingRecentObs != null && correspondingRecentObs.length > 0) {
                                correspondingRecentObs.sort(function (obs1, obs2) {
                                    return new Date(obs2.encounterDateTime) - new Date(obs1.encounterDateTime);
                                });
                                obs.previous = correspondingRecentObs.map(function (previousObs) {
                                    return {
                                        value: Bahmni.Common.Domain.ObservationValueMapper.map(previousObs),
                                        date: previousObs.observationDateTime
                                    };
                                });
                            }
                        });
                    });
                });

                var deregisterAddMore = $scope.$root.$on("event:addMore", function (event, observation) {
                    updateFormConditions([observation], observation);
                });

                var deregisterObservationUpdated = $scope.$root.$on("event:observationUpdated-" + conceptSetName, function (event, conceptName, rootObservation) {
                    var formName = rootObservation.concept.name;
                    var formCondition = Bahmni.ConceptSet.FormConditions.rules && Bahmni.ConceptSet.FormConditions.rules[conceptName];
                    if (formCondition) {
                        var flattenedObs = ObservationUtil.flattenObsToArray([rootObservation]);
                        runFormConditionForObs(true, formName, formCondition, conceptName, flattenedObs);
                    }
                });

                $scope.$on('$destroy', function () {
                    deregisterObservationUpdated();
                    deregisterAddMore();
                    cleanUpListenerShowPrevious();
                });
            };

            return {
                restrict: 'E',
                scope: {
                    conceptSetName: "=",
                    observations: "=?",
                    required: "=?",
                    showTitle: "&",
                    validationHandler: "&",
                    patient: "=",
                    conceptSetFocused: "=?",
                    collapseInnerSections: "=?",
                    atLeastOneValueIsSet: "=?",
                    sectionId: "="
                },
                templateUrl: '../common/concept-set/views/conceptSet.html',
                controller: controller
            };
        }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('formControls', ['formService', 'spinner', '$timeout', '$translate',
        function (formService, spinner, $timeout, $translate) {
            var loadedFormDetails = {};
            var loadedFormTranslations = {};
            var unMountReactContainer = function (formUuid) {
                var reactContainerElement = angular.element(document.getElementById(formUuid));
                reactContainerElement.on('$destroy', function () {
                    unMountForm(document.getElementById(formUuid));
                });
            };

            var controller = function ($scope) {
                var formUuid = $scope.form.formUuid;
                var formVersion = $scope.form.formVersion;
                var formName = $scope.form.formName;
                var formObservations = $scope.form.observations;
                var collapse = $scope.form.collapseInnerSections && $scope.form.collapseInnerSections.value;
                var validateForm = $scope.validateForm || false;
                var locale = $translate.use();

                if (!loadedFormDetails[formUuid]) {
                    spinner.forPromise(formService.getFormDetail(formUuid, { v: "custom:(resources:(value))" })
                        .then(function (response) {
                            var formDetailsAsString = _.get(response, 'data.resources[0].value');
                            if (formDetailsAsString) {
                                var formDetails = JSON.parse(formDetailsAsString);
                                formDetails.version = formVersion;
                                loadedFormDetails[formUuid] = formDetails;
                                var formParams = { formName: formName, formVersion: formVersion, locale: locale, formUuid: formUuid };
                                $scope.form.events = formDetails.events;
                                spinner.forPromise(formService.getFormTranslations(formDetails.translationsUrl, formParams)
                                    .then(function (response) {
                                        var formTranslations = !_.isEmpty(response.data) ? response.data[0] : {};
                                        loadedFormTranslations[formUuid] = formTranslations;
                                        $scope.form.component = renderWithControls(formDetails, formObservations,
                                            formUuid, collapse, $scope.patient, validateForm, locale, formTranslations, $scope.formScope);
                                    }, function () {
                                        var formTranslations = {};
                                        loadedFormTranslations[formUuid] = formTranslations;
                                        $scope.form.component = renderWithControls(formDetails, formObservations,
                                            formUuid, collapse, $scope.patient, validateForm, locale, formTranslations, $scope.formScope);
                                    })
                                );
                            }
                            unMountReactContainer($scope.form.formUuid);
                        })
                    );
                } else {
                    $timeout(function () {
                        $scope.form.events = loadedFormDetails[formUuid].events;
                        $scope.form.component = renderWithControls(loadedFormDetails[formUuid], formObservations,
                            formUuid, collapse, $scope.patient, validateForm, locale, loadedFormTranslations[formUuid], $scope.formScope);
                        unMountReactContainer($scope.form.formUuid);
                    }, 0, false);
                }

                $scope.$watch('form.collapseInnerSections', function () {
                    var collapse = $scope.form.collapseInnerSections && $scope.form.collapseInnerSections.value;
                    if (loadedFormDetails[formUuid]) {
                        $scope.form.component = renderWithControls(loadedFormDetails[formUuid], formObservations,
                            formUuid, collapse, $scope.patient, validateForm, locale, loadedFormTranslations[formUuid], $scope.formScope);
                    }
                });

                $scope.$on('$destroy', function () {
                    if ($scope.$parent.consultation && $scope.$parent.consultation.observationForms) {
                        if ($scope.form.component) {
                            var formObservations = $scope.form.component.getValue();
                            $scope.form.observations = formObservations.observations;

                            var hasError = formObservations.errors;
                            if (!_.isEmpty(hasError)) {
                                $scope.form.isValid = false;
                            }
                        }
                    }
                });
            };

            return {
                restrict: 'E',
                scope: {
                    form: "=",
                    patient: "=",
                    validateForm: "=",
                    formScope: "="
                },
                controller: controller
            };
        }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('concept', ['RecursionHelper', 'spinner', '$filter', 'messagingService', '$rootScope', '$translate',
        function (RecursionHelper, spinner, $filter, messagingService, $rootScope, $translate) {
            var link = function (scope) {
                var hideAbnormalbuttonConfig = scope.observation && scope.observation.conceptUIConfig && scope.observation.conceptUIConfig['hideAbnormalButton'];
                scope.now = moment().format("YYYY-MM-DD hh:mm:ss");
                scope.showTitle = scope.showTitle === undefined ? true : scope.showTitle;
                scope.hideAbnormalButton = hideAbnormalbuttonConfig == undefined ? scope.hideAbnormalButton : hideAbnormalbuttonConfig;
                scope.cloneNew = function (observation, parentObservation) {
                    observation.showAddMoreButton = function () {
                        return false;
                    };
                    var newObs = observation.cloneNew();
                    newObs.scrollToElement = true;
                    var index = parentObservation.groupMembers.indexOf(observation);
                    parentObservation.groupMembers.splice(index + 1, 0, newObs);
                    messagingService.showMessage("info", $translate.instant("NEW_KEY") + " " + observation.label + " " + $translate.instant("SECTION_ADDED_KEY"));
                    scope.$root.$broadcast("event:addMore", newObs);
                };
                scope.removeClonedObs = function (observation, parentObservation) {
                    observation.voided = true;
                    var lastObservationByLabel = _.findLast(parentObservation.groupMembers, function (groupMember) {
                        return groupMember.label === observation.label && !groupMember.voided;
                    });

                    lastObservationByLabel.showAddMoreButton = function () { return true; };
                    observation.hidden = true;
                };
                scope.isClone = function (observation, parentObservation) {
                    if (parentObservation && parentObservation.groupMembers) {
                        var index = parentObservation.groupMembers.indexOf(observation);
                        return (index > 0) ? parentObservation.groupMembers[index].label == parentObservation.groupMembers[index - 1].label : false;
                    }
                    return false;
                };
                scope.isRemoveValid = function (observation) {
                    if (observation.getControlType() == 'image') {
                        return !observation.value;
                    }
                    return true;
                };

                scope.getStringValue = function (observations) {
                    return observations.map(function (observation) {
                        return observation.value + ' (' + $filter('bahmniDate')(observation.date) + ")";
                    }).join(", ");
                };

                scope.toggleSection = function () {
                    scope.collapse = !scope.collapse;
                };

                scope.isCollapsibleSet = function () {
                    return scope.showTitle == true;
                };

                scope.hasPDFAsValue = function () {
                    return scope.observation.value && (scope.observation.value.indexOf(".pdf") > 0);
                };

                scope.$watch('collapseInnerSections', function () {
                    scope.collapse = scope.collapseInnerSections && scope.collapseInnerSections.value;
                });

                scope.handleUpdate = function () {
                    scope.$root.$broadcast("event:observationUpdated-" + scope.conceptSetName, scope.observation.concept.name, scope.rootObservation);
                };

                scope.update = function (value) {
                    if (scope.getBooleanResult(scope.observation.isObservationNode)) {
                        scope.observation.primaryObs.value = value;
                    } else if (scope.getBooleanResult(scope.observation.isFormElement())) {
                        scope.observation.value = value;
                    }
                    scope.handleUpdate();
                };

                scope.getBooleanResult = function (value) {
                    return !!value;
                };
                scope.translatedLabel = function (observation) {
                    if (observation && observation.concept) {
                        var currentLocale = $rootScope.currentUser.userProperties.defaultLocale;
                        var conceptNames = observation.concept.names ? observation.concept.names : [];
                        var shortName = conceptNames.find(function (cn) {
                            return cn.locale === currentLocale && cn.conceptNameType === "SHORT";
                        });

                        if (shortName) {
                            return shortName.name;
                        }

                        var fsName = conceptNames.find(function (cn) {
                            return cn.locale === currentLocale && cn.conceptNameType === "FULLY_SPECIFIED";
                        });

                        if (fsName) {
                            return fsName.name;
                        }

                        return observation.concept.shortName || observation.concept.name;
                    }
                    if (observation) {
                        return observation.label;
                    }
                    return "UNKNOWN_OBSERVATION_CONCEPT";
                };
            };

            var compile = function (element) {
                return RecursionHelper.compile(element, link);
            };

            return {
                restrict: 'E',
                compile: compile,
                scope: {
                    conceptSetName: "=",
                    observation: "=",
                    atLeastOneValueIsSet: "=",
                    showTitle: "=",
                    conceptSetRequired: "=",
                    rootObservation: "=",
                    patient: "=",
                    collapseInnerSections: "=",
                    rootConcept: "&",
                    hideAbnormalButton: "="
                },
                templateUrl: '../common/concept-set/views/observation.html'
            };
        }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('buttonSelect', function () {
        return {
            restrict: 'E',
            scope: {
                observation: '=',
                abnormalObs: '=?'
            },

            link: function (scope, element, attrs) {
                if (attrs.dirtyCheckFlag) {
                    scope.hasDirtyFlag = true;
                }
            },
            controller: function ($scope) {
                $scope.isSet = function (answer) {
                    return $scope.observation.hasValueOf(answer);
                };

                $scope.select = function (answer) {
                    $scope.observation.toggleSelection(answer);
                    if ($scope.$parent.observation && typeof $scope.$parent.observation.onValueChanged == 'function') {
                        $scope.$parent.observation.onValueChanged();
                    }
                    $scope.$parent.handleUpdate();
                };

                $scope.getAnswerDisplayName = function (answer) {
                    var shortName = answer.names ? _.first(answer.names.filter(function (name) {
                        return name.conceptNameType === 'SHORT';
                    })) : null;
                    return shortName ? shortName.name : answer.displayString;
                };
            },
            templateUrl: '../common/concept-set/views/buttonSelect.html'
        };
    });

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('stepper', function () {
        return {
            restrict: 'E',
            require: 'ngModel',
            replace: true,
            scope: { ngModel: '=',
                obs: '=',
                ngClass: '=',
                focusMe: '='
            },
            template: '<div class="stepper clearfix">' +
                        '<button ng-click="decrement()" class="stepper__btn stepper__minus" ng-disabled="obs.disabled">-</button>' +
                        '<input id="{{::obs.uniqueId}}" obs-constraints ng-model="ngModel" obs="::obs" ng-class="ngClass" focus-me="focusMe" type="text" class="stepper__field" ng-disabled="obs.disabled" />' +
                        '<button ng-click="increment()" class="stepper__btn stepper__plus"  ng-disabled="obs.disabled">+</button>' +
                  '</div> ',

            link: function (scope, element, attrs, ngModelController) {
 // Specify how UI should be updated
                ngModelController.$render = function () {
//          element.html(ngModelController.$viewValue || '');
                };

            // when model change, cast to integer
                ngModelController.$formatters.push(function (value) {
                    return parseInt(value, 10);
                });

            // when view change, cast to integer
                ngModelController.$parsers.push(function (value) {
                    return parseInt(value, 10);
                });

                scope.increment = function () {
                    if (scope.obs.concept.hiNormal != null) {
                        var currValue = (isNaN(ngModelController.$viewValue) ? 0 : ngModelController.$viewValue);
                        if (currValue < scope.obs.concept.hiNormal) {
                            updateModel(+1);
                        }
                    } else {
                        updateModel(+1);
                    }
                };
                scope.decrement = function () {
                    if (scope.obs.concept.lowNormal != null) {
                        var currValue = (isNaN(ngModelController.$viewValue) ? 0 : ngModelController.$viewValue);
                        if (currValue > scope.obs.concept.lowNormal) {
                            updateModel(-1);
                        }
                    } else {
                        updateModel(-1);
                    }
                };
                function updateModel (offset) {
                    var currValue = 0;
                    if (isNaN(ngModelController.$viewValue)) {
                        if (scope.obs.concept.lowNormal != null) {
                            currValue = scope.obs.concept.lowNormal - offset; // To mention the start point for Plus And Minus
                            // if - or + is pressed on empty field, set them with low value or 0
                        }
                    } else {
                        currValue = parseInt(ngModelController.$viewValue);
                    }
                    ngModelController.$setViewValue(currValue + offset);
                }
            }
        };
    });

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('obsConstraints', function () {
        var attributesMap = {'Numeric': 'number', 'Date': 'date', 'Datetime': 'datetime'};
        var link = function ($scope, element) {
            var attributes = {};
            var obsConcept = $scope.obs.concept;
            if (obsConcept.conceptClass == Bahmni.Common.Constants.conceptDetailsClassName) {
                obsConcept = $scope.obs.primaryObs.concept;
            }
            attributes['type'] = attributesMap[obsConcept.dataType] || "text";
            if (attributes['type'] === 'number') {
                attributes['step'] = 'any';
            }
            if (obsConcept.hiNormal) {
                attributes['max'] = obsConcept.hiNormal;
            }
            if (obsConcept.lowNormal) {
                attributes['min'] = obsConcept.lowNormal;
            }
            if (attributes['type'] == 'date') {
                if ($scope.obs.conceptUIConfig == null || !$scope.obs.conceptUIConfig['allowFutureDates']) {
                    attributes['max'] = Bahmni.Common.Util.DateTimeFormatter.getDateWithoutTime();
                }
            }
            element.attr(attributes);
        };

        return {
            link: link,
            scope: {
                obs: '='
            },
            require: 'ngModel'
        };
    });

'use strict';
angular.module('bahmni.common.conceptSet')
    .directive('duration', ['contextChangeHandler', function (contextChangeHandler) {
        var link = function ($scope, element, attrs, ngModelController) {
            var setValue = function () {
                if ($scope.unitValue && $scope.measureValue) {
                    var value = $scope.unitValue * $scope.measureValue;
                    ngModelController.$setViewValue(value);
                } else {
                    ngModelController.$setViewValue(undefined);
                }
            };

            $scope.$watch('measureValue', setValue);
            $scope.$watch('unitValue', setValue);

            $scope.$watch('disabled', function (value) {
                if (value) {
                    $scope.unitValue = undefined;
                    $scope.measureValue = undefined;
                    $scope.hours = undefined;
                }
            });

            var illegalValueChecker = $scope.$watch('illegalValue', function (value) {
                $scope.illegalDurationValue = value;
                var contextChange = function () {
                    return {allow: !$scope.illegalDurationValue};
                };
                contextChangeHandler.add(contextChange);
            });

            $scope.$on('$destroy', function () {
                $scope.illegalDurationValue = false;
                illegalValueChecker();
            });
        };

        var controller = function ($scope) {
            var valueAndUnit = Bahmni.Common.Util.DateUtil.convertToUnits($scope.hours);
            $scope.units = valueAndUnit["allUnits"];
            $scope.measureValue = valueAndUnit["value"];
            $scope.unitValue = valueAndUnit["unitValueInMinutes"];
            var durations = Object.keys($scope.units).reverse();
            $scope.displayUnits = durations.map(function (duration) {
                return {"name": duration, "value": $scope.units[duration]};
            });
        };

        return {
            restrict: 'E',
            require: 'ngModel',
            controller: controller,
            scope: {
                hours: "=ngModel",
                illegalValue: "=",
                disabled: "="
            },
            link: link,
            template: '<span><input tabindex="1" style="float: left;" type="number" min="0" class="duration-value" ng-class="{\'illegalValue\': illegalValue}" ng-model=\'measureValue\' ng-disabled="disabled"/></span>' +
            '<span><select tabindex="1" ng-model=\'unitValue\' class="duration-unit" ng-class="{\'illegalValue\': illegalValue}" ng-options="displayUnit.value as displayUnit.name for displayUnit in displayUnits" ng-disabled="disabled"><option value=""></option>>' +
            '</select></span>'
        };
    }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .directive('latestObs', function () {
        var controller = function ($scope, observationsService, $q, spinner) {
            var init = function () {
                spinner.forPromise(observationsService.fetch($scope.patientUuid, $scope.conceptNames, "latest").then(function (response) {
                    var observations = new Bahmni.Common.Obs.ObservationMapper().map(response.data, []);
                    $scope.observations = _.sortBy(observations, 'sortWeight');
                }));
            };
            init();
        };

        return {
            restrict: 'E',
            controller: controller,
            templateUrl: '../common/concept-set/views/latestObs.html',
            scope: {
                patientUuid: "=",
                conceptNames: "="
            }
        };
    });

'use strict';

Bahmni.ConceptSet.ConceptSetGroupValidationHandler = function (conceptSetSections) {
    var validations = [];

    this.add = function (validation) {
        validations.push(validation);
    };

    this.validate = function () {
        var errorMessage = "";
        var allConceptSetSectionsValid = true;

        validations.forEach(function (validation) {
            var validationReturn = validation();
            if (_.isEmpty(errorMessage)) {
                errorMessage = validationReturn["errorMessage"];
            }
            allConceptSetSectionsValid = allConceptSetSectionsValid && validationReturn["allow"];
        });

        if (!allConceptSetSectionsValid) {
            conceptSetSections.filter(_.property('isLoaded')).forEach(function (conceptSetSection) { conceptSetSection.show(); });
        }
        return {allow: allConceptSetSectionsValid, errorMessage: errorMessage};
    };
};

'use strict';

Bahmni.ConceptSet.Observation = function (observation, savedObs, conceptUIConfig) {
    var self = this;
    angular.extend(this, observation);
    this.isObservation = true;
    this.conceptUIConfig = conceptUIConfig[this.concept.name] || [];
    this.uniqueId = _.uniqueId('observation_');
    this.erroneousValue = null;

    if (savedObs) {
        this.uuid = savedObs.uuid;
        this.value = savedObs.value;
        this.observationDateTime = savedObs.observationDateTime;
        this.provider = savedObs.provider;
    } else {
        this.value = this.conceptUIConfig.defaultValue;
    }

    Object.defineProperty(this, 'autocompleteValue', {
        enumerable: true,
        get: function () {
            return (this.value != null && (typeof this.value === "object")) ? this.value.name : this.value;
        },
        set: function (newValue) {
            this.__prevValue = this.value;
            this.value = newValue;
        }
    });

    Object.defineProperty(this, 'value', {
        enumerable: true,
        get: function () {
            if (self._value != null) {
                return self._value;
            }
            if (savedObs) {
                if (typeof (savedObs.value) === "object" && savedObs.value) {
                    savedObs.value['displayString'] = (savedObs.value.shortName ? savedObs.value.shortName : savedObs.value.name);
                }
            }
            return savedObs ? savedObs.value : undefined;
        },
        set: function (newValue) {
            self.__prevValue = this.value;
            self._value = newValue;
            if (!newValue) {
                savedObs = null;
            }
            self.onValueChanged();
        }
    });

    var cloneNonTabularObs = function (oldObs) {
        var newGroupMembers = [];
        oldObs.groupMembers.forEach(function (member) {
            if (member.isTabularObs === undefined) {
                var clone = member.cloneNew();
                clone.hidden = member.hidden;
                newGroupMembers.push(clone);
            }
        });
        return newGroupMembers;
    };

    var getTabularObs = function (oldObs) {
        var tabularObsList = [];
        oldObs.groupMembers.forEach(function (member) {
            if (member.isTabularObs !== undefined) {
                tabularObsList.push(member);
            }
        });
        return tabularObsList;
    };

    var cloneTabularObs = function (oldObs, tabularObsList) {
        tabularObsList = _.map(tabularObsList, function (tabularObs) {
            var matchingObsList = _.filter(oldObs.groupMembers, function (member) {
                return member.concept.name == tabularObs.concept.name;
            });
            return new Bahmni.ConceptSet.TabularObservations(matchingObsList, oldObs, conceptUIConfig);
        });
        tabularObsList.forEach(function (tabularObs) {
            oldObs.groupMembers.push(tabularObs);
        });
        return oldObs;
    };

    this.cloneNew = function () {
        var oldObs = angular.copy(observation);
        if (oldObs.groupMembers && oldObs.groupMembers.length > 0) {
            oldObs.groupMembers = _.filter(oldObs.groupMembers, function (member) {
                return !member.isMultiSelect;
            });
            var newGroupMembers = cloneNonTabularObs(oldObs);
            var tabularObsList = getTabularObs(oldObs);
            oldObs.groupMembers = newGroupMembers;
            if (!_.isEmpty(tabularObsList)) {
                oldObs = cloneTabularObs(oldObs, tabularObsList);
            }
        }
        new Bahmni.ConceptSet.MultiSelectObservations(conceptUIConfig).map(oldObs.groupMembers);
        var clone = new Bahmni.ConceptSet.Observation(oldObs, null, conceptUIConfig);
        clone.comment = undefined;
        clone.disabled = this.disabled;
        return clone;
    };
};

Bahmni.ConceptSet.Observation.prototype = {
    displayValue: function () {
        if (this.possibleAnswers.length > 0) {
            for (var i = 0; i < this.possibleAnswers.length; i++) {
                if (this.possibleAnswers[i].uuid === this.value) {
                    return this.possibleAnswers[i].display;
                }
            }
        } else {
            return this.value;
        }
    },

    isGroup: function () {
        if (this.groupMembers) {
            return this.groupMembers.length > 0;
        }
        return false;
    },

    isComputed: function () {
        return this.concept.conceptClass === "Computed";
    },

    isComputedAndEditable: function () {
        return this.concept.conceptClass === "Computed/Editable";
    },

    isNumeric: function () {
        return this.getDataTypeName() === "Numeric";
    },

    isValidNumeric: function () {
        if (!this.isDecimalAllowed()) {
            if (this.value && this.value.toString().indexOf('.') >= 0) {
                return false;
            }
        }
        return true;
    },
    isValidNumericValue: function () {
        var element = document.getElementById(this.uniqueId);
        if (this.value === "" && element) {
            return element.checkValidity();
        }
        return true;
    },

    isText: function () {
        return this.getDataTypeName() === "Text";
    },

    isCoded: function () {
        return this.getDataTypeName() === "Coded";
    },

    isDatetime: function () {
        return this.getDataTypeName() === "Datetime";
    },

    isImage: function () {
        return this.concept.conceptClass == Bahmni.Common.Constants.imageClassName;
    },

    isVideo: function () {
        return this.concept.conceptClass == Bahmni.Common.Constants.videoClassName;
    },

    getDataTypeName: function () {
        return this.concept.dataType;
    },

    isDecimalAllowed: function () {
        return this.concept.allowDecimal;
    },

    isDateDataType: function () {
        return 'Date'.indexOf(this.getDataTypeName()) != -1;
    },

    isVoided: function () {
        return this.voided === undefined ? false : this.voided;
    },

    getPossibleAnswers: function () {
        return this.possibleAnswers;
    },

    getHighAbsolute: function () {
        return this.concept.hiAbsolute;
    },

    getLowAbsolute: function () {
        return this.concept.lowAbsolute;
    },

    isHtml5InputDataType: function () {
        return ['Date', 'Numeric'].indexOf(this.getDataTypeName()) !== -1;
    },

    isGrid: function () {
        return this.conceptUIConfig.grid;
    },

    isButtonRadio: function () {
        return this.conceptUIConfig.buttonRadio;
    },

    isComplex: function () {
        return this.concept.dataType === "Complex";
    },

    isLocationRef: function () {
        return this.isComplex() && this.concept.handler === "LocationObsHandler";
    },

    isProviderRef: function () {
        return this.isComplex() && this.concept.handler === "ProviderObsHandler";
    },

    getControlType: function () {
        if (this.hidden) {
            return "hidden";
        }
        if (this.conceptUIConfig.freeTextAutocomplete) {
            return "freeTextAutocomplete";
        }
        if (this.isHtml5InputDataType()) {
            return "html5InputDataType";
        }
        if (this.isImage()) {
            return "image";
        }
        if (this.isVideo()) {
            return "video";
        }
        if (this.isText()) {
            return "text";
        }
        if (this.isCoded()) {
            return this._getCodedControlType();
        }
        if (this.isGrid()) {
            return "grid";
        }
        if (this.isDatetime()) {
            return "datetime";
        }
        if (this.isLocationRef()) {
            return "text";
        }
        if (this.isProviderRef()) {
            return "text";
        }
        return "unknown";
    },

    canHaveComment: function () {
        return this.conceptUIConfig.disableAddNotes ? !this.conceptUIConfig.disableAddNotes : (!this.isText() && !this.isImage() && !this.isVideo());
    },

    canAddMore: function () {
        return this.conceptUIConfig.allowAddMore == true;
    },

    isStepperControl: function () {
        if (this.isNumeric()) {
            return this.conceptUIConfig.stepper == true;
        }
    },

    isConciseText: function () {
        return this.conceptUIConfig.conciseText == true;
    },

    _getCodedControlType: function () {
        var conceptUIConfig = this.conceptUIConfig;
        if (conceptUIConfig.autocomplete) {
            return "autocomplete";
        }
        if (conceptUIConfig.dropdown) {
            return "dropdown";
        }
        return "buttonselect";
    },

    onValueChanged: function () {
        if (this.isNumeric()) {
            this.setErroneousValue();
        }
    },

    setErroneousValue: function () {
        if (this.hasValue()) {
            var erroneousValue = this.value > (this.concept.hiAbsolute || Infinity) || this.value < (this.concept.lowAbsolute || 0);
            this.erroneousValue = erroneousValue;
        } else {
            this.erroneousValue = undefined;
        }
    },

    getInputType: function () {
        return this.getDataTypeName();
    },

    atLeastOneValueSet: function () {
        if (this.isGroup()) {
            return this.groupMembers.some(function (childNode) {
                return childNode.atLeastOneValueSet();
            });
        } else {
            return this.hasValue() && !this.isVoided();
        }
    },

    hasValue: function () {
        var value = this.value;
        if (value === false) {
            return true;
        }
        if (value === 0) {
            return true;
        } //! value ignores 0
        if (value === '' || !value) {
            return false;
        }
        if (value instanceof Array) {
            return value.length > 0;
        }
        return true;
    },

    hasValueOf: function (value) {
        if (!this.value || !value) {
            return false;
        }
        return this.value == value || this.value.uuid == value.uuid;
    },

    toggleSelection: function (answer) {
        if (this.value && this.value.uuid === answer.uuid) {
            this.value = null;
        } else {
            this.value = answer;
        }
    },

    isValidDate: function () {
        if (this.isComputed()) {
            return true;
        }
        if (!this.hasValue()) {
            return true;
        }
        var date = Bahmni.Common.Util.DateUtil.parse(this.value);
        if (!this.conceptUIConfig.allowFutureDates) {
            var today = Bahmni.Common.Util.DateUtil.parse(moment().format("YYYY-MM-DD"));
            if (today < date) {
                return false;
            }
        }
        return date.getUTCFullYear() && date.getUTCFullYear().toString().length <= 4;
    },

    hasInvalidDateTime: function () {
        if (this.isComputed()) {
            return false;
        }
        var date = Bahmni.Common.Util.DateUtil.parse(this.value);
        if (!this.conceptUIConfig.allowFutureDates) {
            if (moment() < date) {
                return true;
            }
        }
        return this.value === "Invalid Datetime";
    },

    isValid: function (checkRequiredFields, conceptSetRequired) {
        if (this.isNumeric() && !this.isValidNumeric()) {
            return false;
        }
        if (this.error) {
            return false;
        }
        if (this.hidden) {
            return true;
        }
        if (checkRequiredFields) {
            if (this.isGroup()) {
                return this._hasValidChildren(checkRequiredFields, conceptSetRequired);
            }
            if (conceptSetRequired && this.isRequired() && !this.hasValue()) {
                return false;
            }
            if (this.isRequired() && !this.hasValue()) {
                return false;
            }
        }
        if (this._isDateDataType()) {
            return this.isValidDate();
        }
        if (this._isDateTimeDataType()) {
            return !this.hasInvalidDateTime();
        }
        if (this.erroneousValue) {
            return false;
        }
        if (this.getControlType() === 'autocomplete') {
            return _.isEmpty(this.value) || _.isObject(this.value);
        }
        return true;
    },

    isValueInAbsoluteRange: function () {
        if (this.erroneousValue) {
            return false;
        }
        if (this.isGroup()) {
            return this._areChildNodesInAbsoluteRange();
        }
        return true;
    },

    _isDateDataType: function () {
        return this.getDataTypeName() === 'Date';
    },

    _isDateTimeDataType: function () {
        return this.getDataTypeName() === "Datetime";
    },

    isRequired: function () {
        this.disabled = this.disabled ? this.disabled : false;
        return this.conceptUIConfig.required === true && this.disabled === false;
    },

    isFormElement: function () {
        return (!this.concept.set || this.isGrid()) && !this.isComputed();
    },

    _hasValidChildren: function (checkRequiredFields, conceptSetRequired) {
        return this.groupMembers.every(function (member) {
            return member.isValid(checkRequiredFields, conceptSetRequired);
        });
    },

    _areChildNodesInAbsoluteRange: function () {
        return this.groupMembers.every(function (member) {
            // Other than Bahmni.ConceptSet.Observation  and Bahmni.ConceptSet.ObservationNode, other concepts does not have isValueInAbsoluteRange fn
            return (typeof member.isValueInAbsoluteRange == 'function') ? member.isValueInAbsoluteRange() : true;
        });
    },

    markAsNonCoded: function () {
        this.markedAsNonCoded = !this.markedAsNonCoded;
    },

    toggleVoidingOfImage: function () {
        this.voided = !this.voided;
    },

    assignAddMoreButtonID: function () {
        return this.concept.name.split(' ').join('_').toLowerCase() + '_addmore_' + this.uniqueId;
    }
};

'use strict';

Bahmni.ConceptSet.BooleanObservation = function (observation, conceptUIConfig) {
    angular.extend(this, observation);

    this.isBoolean = true;
    this.conceptUIConfig = conceptUIConfig[this.concept.name] || {};

    this.cloneNew = function () {
        var clone = new Bahmni.ConceptSet.BooleanObservation(angular.copy(observation), conceptUIConfig);
        clone.value = undefined;
        clone.comment = undefined;
        clone.uuid = null;
        clone.disabled = this.disabled;
        return clone;
    };

    var possibleAnswers = [
        {displayString: "OBS_BOOLEAN_YES_KEY", value: true},
        {displayString: "OBS_BOOLEAN_NO_KEY", value: false}
    ];

    this.getPossibleAnswers = function () {
        return possibleAnswers;
    };

    this.hasValueOf = function (answer) {
        return this.value === answer.value;
    };

    this.toggleSelection = function (answer) {
        if (this.value === answer.value) {
            this.value = null;
        } else {
            this.value = answer.value;
        }
    };

    this.isFormElement = function () {
        return true;
    };

    this.getControlType = function () {
        return "buttonselect";
    };

    this.isRequired = function () {
        this.disabled = this.disabled ? this.disabled : false;
        return this.getConceptUIConfig().required === true && this.disabled === false;
    };

    this.isComputedAndEditable = function () {
        return this.concept.conceptClass === "Computed/Editable";
    };

    this.atLeastOneValueSet = function () {
        return (this.value != undefined);
    };
    this.isValid = function (checkRequiredFields, conceptSetRequired) {
        if (this.error) {
            return false;
        }
        var notYetSet = function (value) {
            return (typeof value == 'undefined' || value == null);
        };
        if (checkRequiredFields) {
            if (conceptSetRequired && this.isRequired() && notYetSet(this.value)) {
                return false;
            }
            if (this.isRequired() && notYetSet(this.value)) {
                return false;
            }
        }
        return true;
    };

    this.canHaveComment = function () {
        return this.getConceptUIConfig().disableAddNotes ? !this.getConceptUIConfig().disableAddNotes : true;
    };

    this.getConceptUIConfig = function () {
        return this.conceptUIConfig;
    };

    this.canAddMore = function () {
        return this.getConceptUIConfig().allowAddMore == true;
    };

    this.isComputed = function () {
        return this.concept.conceptClass === "Computed";
    };

    this.getDataTypeName = function () {
        return this.concept.dataType;
    };

    this.hasValue = function () {
        var value = this.value;
        if (value === false) {
            return true;
        }
        if (value === 0) {
            return true;
        } //! value ignores 0
        if (value === '' || !value) {
            return false;
        }
        if (value instanceof Array) {
            return value.length > 0;
        }
        return true;
    };

    this.isNumeric = function () {
        return this.getDataTypeName() === "Numeric";
    };

    this.isText = function () {
        return this.getDataTypeName() === "Text";
    };

    this.isCoded = function () {
        return this.getDataTypeName() === "Coded";
    };

    this._isDateTimeDataType = function () {
        return this.getDataTypeName() === "Datetime";
    };
};

(function () {
    var findObservationByClassName = function (groupMembers, conceptClassName) {
        return _.find(groupMembers, function (member) {
            return (member.concept.conceptClass.name === conceptClassName) || (member.concept.conceptClass === conceptClassName);
        });
    };
    var findObservationByConceptName = function (groupMembers, conceptName) {
        return _.find(groupMembers, {concept: {name: conceptName}});
    };
    var setNewObservation = function (observation, newValue) {
        if (observation) {
            observation.__prevValue = observation.value;
            observation.value = newValue;
            observation.voided = false;
        }
    };
    var voidObservation = function (observation) {
        if (observation) {
            if (observation.uuid) {
                observation.voided = true;
            } else {
                observation.value = undefined;
            }
        }
    };

    var isFreeTextAutocompleteType = function (conceptUIConfig) {
        return conceptUIConfig.autocomplete && conceptUIConfig.nonCodedConceptName && conceptUIConfig.codedConceptName;
    };

    Bahmni.ConceptSet.ObservationNode = function (observation, savedObs, conceptUIConfig, concept) {
        angular.extend(this, observation);

        this.conceptUIConfig = conceptUIConfig[concept.name.name] || (!_.isEmpty(concept.setMembers) && conceptUIConfig[concept.setMembers[0].name.name]) || {};

        this.cloneNew = function () {
            var oldObs = angular.copy(observation);
            oldObs.groupMembers = _.map(oldObs.groupMembers, function (member) {
                return member.cloneNew();
            });

            var clone = new Bahmni.ConceptSet.ObservationNode(oldObs, null, conceptUIConfig, concept);
            clone.comment = undefined;
            return clone;
        };

        var getPrimaryObservationValue = function () {
            return this.primaryObs && _.get(this, 'primaryObs.value.name') || _.get(this, 'primaryObs.value');
        };
        var setFreeTextPrimaryObservationValue = function (newValue) {
            var codedObservation = findObservationByConceptName(this.groupMembers, this.conceptUIConfig.codedConceptName);
            var nonCodedObservation = findObservationByConceptName(this.groupMembers, this.conceptUIConfig.nonCodedConceptName);
            if (typeof newValue === "object") {
                setNewObservation(codedObservation, newValue);
                voidObservation(nonCodedObservation);
                this.markedAsNonCoded = false;
            } else {
                setNewObservation(nonCodedObservation, newValue);
                voidObservation(codedObservation);
            }
            this.onValueChanged(newValue);
        };
        var setFirstObservationValue = function (newValue) {
            setNewObservation(this.primaryObs, newValue);
            this.onValueChanged(newValue);
        };
        Object.defineProperty(this, 'value', {
            enumerable: true,
            get: getPrimaryObservationValue,
            set: isFreeTextAutocompleteType(this.conceptUIConfig) ? setFreeTextPrimaryObservationValue : setFirstObservationValue
        });

        var getFreeTextPrimaryObservation = function () {
            var isAlreadySavedObservation = function (observation) {
                return _.isString(_.get(observation, 'value')) && !_.get(observation, 'voided');
            };
            var codedConceptObservation = findObservationByConceptName(this.groupMembers, this.conceptUIConfig.codedConceptName);
            var nonCodedConceptObservation = findObservationByConceptName(this.groupMembers, this.conceptUIConfig.nonCodedConceptName);

            if (isAlreadySavedObservation(nonCodedConceptObservation)) {
                return nonCodedConceptObservation;
            }
            if (!codedConceptObservation) {
                throw new Error("Configuration Error: Concept '" + this.conceptUIConfig.codedConceptName + "' is not a set member of '" + concept.name.name + "'.");
            }
            return codedConceptObservation;
        };
        var getGroupMembersWithoutClass = function (groupMembers, classNames) {
            return _.filter(groupMembers, function (member) {
                return !(_.includes(classNames, member.concept.conceptClass.name) || _.includes(classNames, member.concept.conceptClass));
            });
        };
        var getFirstObservation = function () {
            var observations = getGroupMembersWithoutClass(this.groupMembers, [Bahmni.Common.Constants.abnormalConceptClassName,
                Bahmni.Common.Constants.unknownConceptClassName,
                Bahmni.Common.Constants.durationConceptClassName]);
            if (_.isEmpty(observations)) {
                return this.groupMembers[0];
            }

            var primaryObs = observations[1] && observations[1].uuid && !observations[1].voided ? observations[1] : observations[0];
            if (observations[0].isMultiSelect) {
                return observations[0];
            }

            if (primaryObs.uuid && !primaryObs.voided) {
                return primaryObs;
            }

            return observations[1] && (observations[1].value || observations[1].value === "") && !observations[1].voided ? observations[1] : observations[0];
        };
        Object.defineProperty(this, 'primaryObs', {
            enumerable: true,
            get: isFreeTextAutocompleteType(this.conceptUIConfig) ? getFreeTextPrimaryObservation : getFirstObservation
        });
        this.isObservationNode = true;
        this.uniqueId = _.uniqueId('observation_');
        this.durationObs = findObservationByClassName(this.groupMembers, Bahmni.Common.Constants.durationConceptClassName);
        this.abnormalObs = findObservationByClassName(this.groupMembers, Bahmni.Common.Constants.abnormalConceptClassName);
        this.unknownObs = findObservationByClassName(this.groupMembers, Bahmni.Common.Constants.unknownConceptClassName);
        this.markedAsNonCoded = this.primaryObs.concept.dataType !== "Coded" && this.primaryObs.uuid;

        if (savedObs) {
            this.uuid = savedObs.uuid;
            this.observationDateTime = savedObs.observationDateTime;
        } else {
            this.value = this.conceptUIConfig.defaultValue;
        }
    };

    Bahmni.ConceptSet.ObservationNode.prototype = {
        canAddMore: function () {
            return this.conceptUIConfig.allowAddMore == true;
        },

        isStepperControl: function () {
            if (this.isNumeric()) {
                return this.conceptUIConfig.stepper == true;
            }
            return false;
        },

        getPossibleAnswers: function () {
            return this.primaryObs.concept.answers;
        },

        getCodedConcept: function () {
            return findObservationByConceptName(this.groupMembers, this.conceptUIConfig.codedConceptName).concept;
        },

        onValueChanged: function () {
            if (!this.primaryObs.hasValue() && this.abnormalObs) {
                this.abnormalObs.value = undefined;
                this.abnormalObs.erroneousValue = undefined;
            }
            if (this.primaryObs.isNumeric() && this.primaryObs.hasValue() && this.abnormalObs) {
                this.setAbnormal();
            }
//        TODO: Mihir, D3 : Hacky fix to update the datetime to current datetime on the server side. Ideal would be void the previous observation and create a new one.
            this.primaryObs.observationDateTime = null;
            if (this.unknownObs) {
                this.setUnknown();
            }
        },

        setAbnormal: function () {
            if (this.primaryObs.hasValue()) {
                var erroneousValue = this.value > (this.primaryObs.concept.hiAbsolute || Infinity) || this.value < (this.primaryObs.concept.lowAbsolute || 0);
                var valueInRange = this.value <= (this.primaryObs.concept.hiNormal || Infinity) && this.value >= (this.primaryObs.concept.lowNormal || 0);
                this.abnormalObs.value = !valueInRange;
                this.abnormalObs.erroneousValue = erroneousValue;
            } else {
                this.abnormalObs.value = undefined;
                this.abnormalObs.erroneousValue = undefined;
            }
        },

        setUnknown: function () {
            if (this.primaryObs.atLeastOneValueSet() && this.primaryObs.hasValue()) {
                this.unknownObs.value = false;
            } else {
                if (this.unknownObs.value == false) {
                    this.unknownObs.value = undefined;
                }
            }
        },

        displayValue: function () {
            if (this.possibleAnswers.length > 0) {
                for (var i = 0; i < this.possibleAnswers.length; i++) {
                    if (this.possibleAnswers[i].uuid === this.value) {
                        return this.possibleAnswers[i].display;
                    }
                }
            } else {
                return this.value;
            }
        },

        isGroup: function () {
            return false;
        },

        getControlType: function () {
            if (isFreeTextAutocompleteType(this.conceptUIConfig)) {
                return "freeTextAutocomplete";
            }
            if (this.conceptUIConfig.autocomplete) {
                return "autocomplete";
            }
            if (this.isHtml5InputDataType()) {
                return "html5InputDataType";
            }
            if (this.primaryObs.isText()) {
                return "text";
            }
            if (this.conceptUIConfig.dropdown) {
                return "dropdown";
            }
            return "buttonselect";
        },

        isHtml5InputDataType: function () {
            return ['Date', 'Numeric', 'Datetime'].indexOf(this.primaryObs.getDataTypeName()) != -1;
        },

        _isDateTimeDataType: function () {
            return this.primaryObs.getDataTypeName() === "Datetime";
        },

        isComputed: function () {
            return this.primaryObs.isComputed();
        },

        isConciseText: function () {
            return this.conceptUIConfig.conciseText === true;
        },

        isComputedAndEditable: function () {
            return this.concept.conceptClass === "Computed/Editable";
        },

        atLeastOneValueSet: function () {
            return this.primaryObs.hasValue();
        },

        doesNotHaveDuration: function () {
            if (!this.durationObs || !this.conceptUIConfig.durationRequired) {
                return false;
            } else {
                if (!this.durationObs.value) {
                    return true;
                }
                return this.durationObs.value < 0;
            }
        },

        isValid: function (checkRequiredFields, conceptSetRequired) {
            if (this.isNumeric() && (!this.isValidNumeric() || !this.isValidNumericValue())) {
                return false;
            }
            if (this.isGroup()) {
                return this._hasValidChildren(checkRequiredFields, conceptSetRequired);
            }
            if (checkRequiredFields) {
                if (conceptSetRequired && this.isRequired() && !this.primaryObs.hasValue()) {
                    return false;
                }
                if (this.isRequired() && !this.primaryObs.hasValue()) {
                    return false;
                }
                if (this.getControlType() === "freeTextAutocomplete") {
                    return this.isValidFreeTextAutocomplete();
                }
            }
            if (this.primaryObs.getDataTypeName() === "Date") {
                return this.primaryObs.isValidDate();
            }
            if (this.primaryObs.hasValue() && this.doesNotHaveDuration()) {
                return false;
            }
            if (this.abnormalObs && this.abnormalObs.erroneousValue) {
                return false;
            }
            if (this.primaryObs.hasValue() && this.primaryObs._isDateTimeDataType()) {
                return !this.hasInvalidDateTime();
            }
            if (this.getControlType() === 'autocomplete') {
                return _.isEmpty(this.primaryObs.value) || _.isObject(this.primaryObs.value);
            }
            if (this.primaryObs.hasValue() && this.primaryObs.erroneousValue) {
                return false;
            }
            return true;
        },

        isValueInAbsoluteRange: function () {
            return !(this.abnormalObs && this.abnormalObs.erroneousValue);
        },

        isValidFreeTextAutocomplete: function () {
            return !(this.primaryObs.concept.dataType !== "Coded" && !this.markedAsNonCoded && this.primaryObs.value);
        },

        isRequired: function () {
            this.disabled = this.disabled ? this.disabled : false;
            return this.conceptUIConfig.required === true && this.disabled === false;
        },

        isDurationRequired: function () {
            return !!this.conceptUIConfig.durationRequired && !!this.primaryObs.value;
        },

        isNumeric: function () {
            return this.primaryObs.getDataTypeName() === "Numeric";
        },

        isDecimalAllowed: function () {
            return this.primaryObs.concept.allowDecimal;
        },

        isValidNumeric: function () {
            if (!this.isDecimalAllowed()) {
                if (this.value && this.value.toString().indexOf('.') >= 0) {
                    return false;
                }
            }
            return true;
        },
        isValidNumericValue: function () {
            var element = document.getElementById(this.uniqueId);
            if (this.value === "" && element) {
                return element.checkValidity();
            }
            return true;
        },

        _hasValidChildren: function (checkRequiredFields, conceptSetRequired) {
            return this.groupMembers.every(function (member) {
                return member.isValid(checkRequiredFields, conceptSetRequired);
            });
        },

        markAsNonCoded: function () {
            this.markedAsNonCoded = !this.markedAsNonCoded;
        },

        toggleAbnormal: function () {
            this.abnormalObs.value = !this.abnormalObs.value;
        },

        toggleUnknown: function () {
            if (!this.unknownObs.value) {
                this.unknownObs.value = true;
            } else {
                this.unknownObs.value = undefined;
            }
        },

        assignAddMoreButtonID: function () {
            return this.concept.name.split(' ').join('_').toLowerCase() + '_addmore_' + this.uniqueId;
        },

        canHaveComment: function () {
            return this.conceptUIConfig.disableAddNotes ? !this.conceptUIConfig.disableAddNotes : true;
        },

        hasInvalidDateTime: function () {
            if (this.isComputed()) {
                return false;
            }
            var date = Bahmni.Common.Util.DateUtil.parse(this.value);
            if (!this.conceptUIConfig.allowFutureDates) {
                if (moment() < date) {
                    return true;
                }
            }
            return this.value === "Invalid Datetime";
        }

    };
})();

'use strict';

Bahmni.ConceptSet.TabularObservations = function (obsGroups, parentObs, conceptUIConfig) {
    this.parentObs = parentObs;
    this.concept = obsGroups[0] && obsGroups[0].concept;
    this.label = obsGroups[0] && obsGroups[0].label;
    this.conceptUIConfig = conceptUIConfig[this.concept.name] || {};
    this.isTabularObs = true;
    this.rows = _.map(obsGroups, function (group) {
        return new Bahmni.ConceptSet.ObservationRow(group, conceptUIConfig);
    });

    this.columns = _.map(obsGroups[0].groupMembers, function (group) {
        return group.concept;
    });

    this.cloneNew = function () {
        var old = this;
        var clone = new Bahmni.ConceptSet.TabularObservations(angular.copy(obsGroups), parentObs, conceptUIConfig);
        clone.rows = _.map(old.rows, function (row) {
            return row.cloneNew();
        });
        clone.disabled = this.disabled;
        return clone;
    };

    this.addNew = function (row) {
        var newRow = row.cloneNew();
        this.rows.push(newRow);
        this.parentObs.groupMembers.push(newRow.obsGroup);
    };

    this.remove = function (row) {
        row.void();
        this.rows.splice(this.rows.indexOf(row), 1);
        if (this.rows.length == 0) {
            this.addNew(row);
        }
    };

    this.isFormElement = function () {
        return false;
    };

    this.getControlType = function () {
        return "tabular";
    };

    this.isValid = function (checkRequiredFields, conceptSetRequired) {
        return _.every(this.rows, function (observationRow) {
            return _.every(observationRow.cells, function (conceptSetObservation) {
                return conceptSetObservation.isValid(checkRequiredFields, conceptSetRequired);
            });
        });
    };

    this.getConceptUIConfig = function () {
        return this.conceptUIConfig || {};
    };

    this.canAddMore = function () {
        return this.getConceptUIConfig().allowAddMore == true;
    };

    this.atLeastOneValueSet = function () {
        return this.rows.some(function (childNode) {
            return childNode.obsGroup.atLeastOneValueSet();
        });
    };

    this.isNumeric = function () {
        return this.concept.dataType === "Numeric";
    };
    this.isValidNumericValue = function () {
        var element = document.getElementById(this.uniqueId);
        if (this.value === "" && element) {
            return element.checkValidity();
        }
        return true;
    };
};

Bahmni.ConceptSet.ObservationRow = function (obsGroup, conceptUIConfig) {
    this.obsGroup = obsGroup;
    this.concept = obsGroup.concept;
    this.cells = obsGroup.groupMembers;
    this.void = function () {
        this.obsGroup.voided = true;
    };

    this.cloneNew = function () {
        var newObsGroup = this.obsGroup.cloneNew();
        newObsGroup.hidden = true;
        var clone = new Bahmni.ConceptSet.ObservationRow(newObsGroup, conceptUIConfig);
        clone.disabled = this.disabled;
        return clone;
    };
};

'use strict';

Bahmni.ConceptSet.MultiSelectObservations = function (conceptSetConfig) {
    var self = this;
    this.multiSelectObservationsMap = {};

    this.map = function (memberOfCollection) {
        memberOfCollection.forEach(function (member) {
            if (isMultiSelectable(member.concept, conceptSetConfig)) {
                add(member.concept, member, memberOfCollection);
            }
        });
        insertMultiSelectObsInExistingOrder(memberOfCollection);
    };

    var isMultiSelectable = function (concept, conceptSetConfig) {
        return conceptSetConfig[concept.name] && conceptSetConfig[concept.name].multiSelect;
    };

    var insertMultiSelectObsInExistingOrder = function (memberOfCollection) {
        getAll().forEach(function (multiObs) {
            var index = _.findIndex(memberOfCollection, function (member) {
                return member.concept.name === multiObs.concept.name;
            });
            memberOfCollection.splice(index, 0, multiObs);
        });
    };

    var add = function (concept, obs, memberOfCollection) {
        var conceptName = concept.name.name || concept.name;
        self.multiSelectObservationsMap[conceptName] = self.multiSelectObservationsMap[conceptName] || new Bahmni.ConceptSet.MultiSelectObservation(concept, memberOfCollection, conceptSetConfig);
        self.multiSelectObservationsMap[conceptName].add(obs);
    };

    var getAll = function () {
        return _.values(self.multiSelectObservationsMap);
    };
};

Bahmni.ConceptSet.MultiSelectObservation = function (concept, memberOfCollection, conceptSetConfig) {
    var self = this;
    this.label = concept.shortName || concept.name;
    this.isMultiSelect = true;
    this.selectedObs = {};
    this.concept = concept;
    this.concept.answers = this.concept.answers || [];
    this.groupMembers = [];
    this.provider = null;
    this.observationDateTime = "";
    this.conceptUIConfig = conceptSetConfig[this.concept.name] || {};

    this.possibleAnswers = self.concept.answers.map(function (answer) {
        var cloned = _.cloneDeep(answer);
        if (answer.name.name) {
            cloned.name = answer.name.name;
        }
        return cloned;
    });

    this.getPossibleAnswers = function () {
        return this.possibleAnswers;
    };

    this.cloneNew = function () {
        var clone = new Bahmni.ConceptSet.MultiSelectObservation(concept, memberOfCollection, conceptSetConfig);
        clone.disabled = this.disabled;
        return clone;
    };

    this.add = function (obs) {
        if (obs.value) {
            self.selectedObs[obs.value.name] = obs;

            if (!self.provider) {
                self.provider = self.selectedObs[obs.value.name].provider;
            }
            var currentObservationDateTime = self.selectedObs[obs.value.name].observationDateTime;
            if (self.observationDateTime < currentObservationDateTime) {
                self.observationDateTime = currentObservationDateTime;
            }
        }
        obs.hidden = true;
    };

    this.isComputedAndEditable = function () {
        return this.concept.conceptClass === "Computed/Editable";
    };

    this.hasValueOf = function (answer) {
        return self.selectedObs[answer.name] && !self.selectedObs[answer.name].voided;
    };

    this.toggleSelection = function (answer) {
        if (self.hasValueOf(answer)) {
            unselectAnswer(answer);
        } else {
            self.selectAnswer(answer);
        }
    };

    this.isFormElement = function () {
        return true;
    };

    this.getControlType = function () {
        var conceptConfig = this.getConceptUIConfig();
        if (this.isCoded() && conceptConfig.autocomplete == true && conceptConfig.multiSelect == true) { return "autocompleteMultiSelect"; } else if (conceptConfig.autocomplete == true) {
            return "autocomplete";
        }
        return "buttonselect";
    };

    this.atLeastOneValueSet = function () {
        var obsValue = _.filter(this.selectedObs, function (obs) {
            return obs.value;
        });
        return !_.isEmpty(obsValue);
    };

    this.hasValue = function () {
        return !_.isEmpty(this.selectedObs);
    };

    this.hasNonVoidedValue = function () {
        var hasNonVoidedValue = false;
        if (this.hasValue()) {
            angular.forEach(this.selectedObs, function (obs) {
                if (!obs.voided) {
                    hasNonVoidedValue = true;
                }
            });
        }
        return hasNonVoidedValue;
    };

    this.isValid = function (checkRequiredFields, conceptSetRequired) {
        if (this.error) {
            return false;
        }
        if (checkRequiredFields) {
            if (conceptSetRequired && this.isRequired() && !this.hasNonVoidedValue()) {
                return false;
            }
            if (this.isRequired() && !this.hasNonVoidedValue()) {
                return false;
            }
        }
        return true;
    };

    this.canHaveComment = function () {
        return false;
    };

    this.getConceptUIConfig = function () {
        return this.conceptUIConfig || {};
    };

    this.canAddMore = function () {
        return this.getConceptUIConfig().allowAddMore == true;
    };

    this.isRequired = function () {
        this.disabled = this.disabled ? this.disabled : false;
        return this.getConceptUIConfig().required === true && this.disabled === false;
    };

    var createObsFrom = function (answer) {
        var obs = newObservation(concept, answer, conceptSetConfig);
        memberOfCollection.push(obs);
        return obs;
    };

    var removeObsFrom = function (answer) {
        var obs = newObservation(concept, answer, conceptSetConfig);
        _.remove(memberOfCollection, function (member) {
            if (member.value) {
                return obs.value.displayString == member.value.displayString;
            }
            return false;
        });
    };

    this.selectAnswer = function (answer) {
        var obs = self.selectedObs[answer.name];
        if (obs) {
            obs.value = answer;
            obs.voided = false;
        } else {
            obs = createObsFrom((answer));
            self.add(obs);
        }
    };

    var unselectAnswer = function (answer) {
        var obs = self.selectedObs[answer.name];
        if (obs && obs.uuid) {
            obs.value = null;
            obs.voided = true;
        } else {
            removeObsFrom(answer);
            delete self.selectedObs[answer.name];
        }
    };

    var newObservation = function (concept, value, conceptSetConfig) {
        var observation = buildObservation(concept);
        return new Bahmni.ConceptSet.Observation(observation, {value: value}, conceptSetConfig, []);
    };

    var buildObservation = function (concept) {
        return { concept: concept, units: concept.units, label: concept.shortName || concept.name, possibleAnswers: self.concept.answers, groupMembers: [], comment: null};
    };

    this.getValues = function () {
        var values = [];
        _.values(self.selectedObs).forEach(function (obs) {
            if (obs.value) {
                values.push(obs.value.shortName || obs.value.name);
            }
        });
        return values;
    };

    this.isComputed = function () {
        return this.concept.conceptClass === "Computed";
    };

    this.getDataTypeName = function () {
        return this.concept.dataType;
    };

    this._isDateTimeDataType = function () {
        return this.getDataTypeName() === "Datetime";
    };

    this.isNumeric = function () {
        return this.getDataTypeName() === "Numeric";
    };

    this.isText = function () {
        return this.getDataTypeName() === "Text";
    };

    this.isCoded = function () {
        return this.getDataTypeName() === "Coded";
    };
};

'use strict';

Bahmni.ConceptSet.CustomRepresentationBuilder = {
    build: function (fields, childPropertyName, numberOfLevels) {
        var childPropertyRep = childPropertyName + ':{{entity_fileds}}';
        var singleEntityString = "(" + fields.concat(childPropertyRep).join(',') + ")";
        var customRepresentation = singleEntityString;
        for (var i = 0; i < numberOfLevels; i++) {
            customRepresentation = customRepresentation.replace("{{entity_fileds}}", singleEntityString);
        }
        customRepresentation = customRepresentation.replace("," + childPropertyRep, '');
        return customRepresentation;
    }
};

'use strict';

Bahmni.ConceptSet.ConceptSetSection = function (extensions, user, config, observations, conceptSet) {
    var self = this;

    self.clone = function () {
        var clonedConceptSetSection = new Bahmni.ConceptSet.ConceptSetSection(extensions, user, config, [], conceptSet);
        clonedConceptSetSection.isAdded = true;
        return clonedConceptSetSection;
    };

    var init = function () {
        self.observations = observations;
        self.options = extensions.extensionParams || {};
        self.conceptName = conceptSet.name ? conceptSet.name.name : self.options.conceptName;
        var conceptName = _.find(conceptSet.names, {conceptNameType: "SHORT"}) || _.find(conceptSet.names, {conceptNameType: "FULLY_SPECIFIED"});
        conceptName = conceptName ? conceptName.name : conceptName;
        self.label = conceptName || self.conceptName || self.options.conceptName;
        self.isLoaded = self.isOpen;
        self.collapseInnerSections = {value: false};
        self.uuid = conceptSet.uuid;
        self.alwaysShow = user.isFavouriteObsTemplate(self.conceptName);
        self.allowAddMore = config.allowAddMore;
        self.id = "concept-set-" + conceptSet.uuid;
    };

    var getShowIfFunction = function () {
        if (!self.showIfFunction) {
            var showIfFunctionStrings = self.options.showIf || ["return true;"];
            self.showIfFunction = new Function("context", showIfFunctionStrings.join('\n')); // eslint-disable-line no-new-func
        }
        return self.showIfFunction;
    };

    var atLeastOneValueSet = function (observation) {
        if (observation.groupMembers && observation.groupMembers.length > 0) {
            return observation.groupMembers.some(function (groupMember) {
                return atLeastOneValueSet(groupMember);
            });
        } else {
            return !(_.isUndefined(observation.value) || observation.value === "");
        }
    };

    self.isAvailable = function (context) {
        return getShowIfFunction()(context || {});
    };

    self.show = function () {
        self.isOpen = true;
        self.isLoaded = true;
    };

    self.hide = function () {
        self.isOpen = false;
    };

    self.getObservationsForConceptSection = function () {
        return self.observations.filter(function (observation) {
            return observation.concept.name === self.conceptName;
        });
    };
    self.hasSomeValue = function () {
        var observations = self.getObservationsForConceptSection();
        return _.some(observations, function (observation) {
            return atLeastOneValueSet(observation);
        });
    };

    self.showComputeButton = function () {
        return config.computeDrugs === true;
    };

    self.toggle = function () {
        self.added = !self.added;
        if (self.added) {
            self.show();
        }
    };
    self.maximizeInnerSections = function (event) {
        event.stopPropagation();
        self.collapseInnerSections = {value: false};
    };
    self.minimizeInnerSections = function (event) {
        event.stopPropagation();
        self.collapseInnerSections = {value: true};
    };

    self.toggleDisplay = function () {
        if (self.isOpen) {
            self.hide();
        } else {
            self.show();
        }
    };

    self.canToggle = function () {
        return !self.hasSomeValue();
    };

    self.canAddMore = function () {
        return self.allowAddMore == true;
    };

    Object.defineProperty(self, "isOpen", {
        get: function () {
            if (self.open === undefined) {
                self.open = self.hasSomeValue();
            }
            return self.open;
        },
        set: function (value) {
            self.open = value;
        }
    });

    self.isDefault = function () {
        return self.options.default;
    };

    Object.defineProperty(self, "isAdded", {
        get: function () {
            if (self.added === undefined) {
                if (self.options.default) {
                    self.added = true;
                } else {
                    self.added = self.hasSomeValue();
                }
            }
            return self.added;
        },
        set: function (value) {
            self.added = value;
        }
    });

    init();
};

'use strict';

Bahmni.ObservationForm = function (formUuid, user, formName, formVersion, observations, label, extension) {
    var self = this;

    var init = function () {
        self.formUuid = formUuid;
        self.formVersion = formVersion;
        self.formName = formName;
        self.label = label;
        self.conceptName = formName;
        self.collapseInnerSections = {value: false};
        self.alwaysShow = user.isFavouriteObsTemplate(self.conceptName);
        self.observations = [];
        _.each(observations, function (observation) {
            var observationFormField = observation.formFieldPath ?
                Bahmni.Common.Util.FormFieldPathUtil.getFormNameAndVersion(observation.formFieldPath) : null;
            if (observationFormField && observationFormField.formName === formName
                && observationFormField.formVersion == formVersion) {
                self.observations.push(observation);
            }
        });
        self.isOpen = self.observations.length > 0;
        self.id = "concept-set-" + formUuid;
        self.options = extension ? (extension.extensionParams || {}) : {};
        self.order = extension ? (extension.order || undefined) : undefined;
        self.privileges = [];
    };

    self.toggleDisplay = function () {
        if (self.isOpen) {
            hide();
        } else {
            show();
        }
    };

    function hide () {
        self.isOpen = false;
    }

    function show () {
        self.isOpen = true;
    }

    // parameters added to show in observation page :: START
    self.clone = function () {
        var clonedObservationFormSection = new Bahmni.ObservationForm(self.formUuid, user, self.formName, self.formVersion, []);
        clonedObservationFormSection.isOpen = true;
        return clonedObservationFormSection;
    };

    self.isAvailable = function (context) {
        return true;
    };

    self.show = function () {
        self.isOpen = true;
        self.isLoaded = true;
    };

    self.toggle = function () {
        self.added = !self.added;
        if (self.added) {
            self.show();
        }
    };

    self.hasSomeValue = function () {
        var observations = self.getObservationsForConceptSection();
        return _.some(observations, function (observation) {
            return atLeastOneValueSet(observation);
        });
    };

    self.getObservationsForConceptSection = function () {
        return self.observations.filter(function (observation) {
            return observation.formFieldPath.split('.')[0] === self.formName;
        });
    };

    var atLeastOneValueSet = function (observation) {
        if (observation.groupMembers && observation.groupMembers.length > 0) {
            return observation.groupMembers.some(function (groupMember) {
                return atLeastOneValueSet(groupMember);
            });
        } else {
            return !(_.isUndefined(observation.value) || observation.value === "");
        }
    };

    self.isDefault = function () {
        return self.options.default;
    };

    Object.defineProperty(self, "isAdded", {
        get: function () {
            if (self.added === undefined) {
                if (self.options.default) {
                    self.added = true;
                } else {
                    self.added = self.hasSomeValue();
                }
            }
            return self.added;
        },
        set: function (value) {
            self.added = value;
        }
    });

    self.maximizeInnerSections = function (event) {
        event.stopPropagation();
        self.collapseInnerSections = {value: false};
    };

    self.minimizeInnerSections = function (event) {
        event.stopPropagation();
        self.collapseInnerSections = {value: true};
    };

    // parameters added to show in observation page :: END

    init();
};

"use strict";

Bahmni.ConceptSet.ObservationMapper = function () {
    var conceptMapper = new Bahmni.Common.Domain.ConceptMapper();
    var self = this;
    // TODO : Shouldn't this be in clinical module. Don't see a reason for this to be in concept-set code - Shruthi
    this.getObservationsForView = function (observations, conceptSetConfig, conceptGroupFormatService) {
        return internalMapForDisplay(observations, conceptSetConfig, conceptGroupFormatService);
    };

    var internalMapForDisplay = function (observations, conceptSetConfig, conceptGroupFormatService) {
        var observationsForDisplay = [];
        _.forEach(observations, function (savedObs) {
            if (conceptGroupFormatService.isObsGroupFormatted(savedObs)) {
                var observationNode = new Bahmni.ConceptSet.ObservationNode(savedObs, savedObs, [], savedObs.concept);
                var obsToDisplay = createObservationForDisplay(observationNode, observationNode.primaryObs.concept, conceptGroupFormatService);
                if (obsToDisplay) {
                    observationsForDisplay.push(obsToDisplay);
                    return;
                }
            }
            else {
                if (savedObs.concept.set) {
                    if (conceptSetConfig[savedObs.concept.name] && conceptSetConfig[savedObs.concept.name].grid) {
                        savedObs.value = self.getGridObservationDisplayValue(savedObs, conceptGroupFormatService);
                        observationsForDisplay = observationsForDisplay.concat(createObservationForDisplay(savedObs, savedObs.concept, conceptGroupFormatService));
                    } else {
                        var groupMemberObservationsForDisplay = internalMapForDisplay(savedObs.groupMembers, conceptSetConfig, conceptGroupFormatService);
                        observationsForDisplay = observationsForDisplay.concat(groupMemberObservationsForDisplay);
                    }
                } else {
                    var obsToDisplay = null;
                    if (savedObs.isMultiSelect) {
                        obsToDisplay = savedObs;
                    } else if (!savedObs.hidden) {
                        var observation = newObservation(savedObs.concept, savedObs, []);
                        obsToDisplay = createObservationForDisplay(observation, observation.concept, conceptGroupFormatService);
                    }
                    if (obsToDisplay) {
                        observationsForDisplay.push(obsToDisplay);
                    }
                }
            }
        });
        return observationsForDisplay;
    };

    this.map = function (observations, rootConcept, conceptSetConfig) {
        var savedObs = findInSavedObservation(rootConcept, observations)[0];
        return mapObservation(rootConcept, savedObs, conceptSetConfig || {});
    };

    var findInSavedObservation = function (concept, observations) {
        return _.filter(observations, function (obs) {
            return obs && obs.concept && concept.uuid === obs.concept.uuid;
        });
    };

    var mapObservation = function (concept, savedObs, conceptSetConfig) {
        var obs = null;
        if (savedObs && (savedObs.isObservation || savedObs.isObservationNode)) {
            return savedObs;
        }
        var mappedGroupMembers = concept && concept.set ? mapObservationGroupMembers(savedObs ? savedObs.groupMembers : [], concept, conceptSetConfig) : [];

        if (concept.conceptClass.name === Bahmni.Common.Constants.conceptDetailsClassName) {
            obs = newObservationNode(concept, savedObs, conceptSetConfig, mappedGroupMembers);
        } else {
            obs = newObservation(concept, savedObs, conceptSetConfig, mappedGroupMembers);
            new Bahmni.ConceptSet.MultiSelectObservations(conceptSetConfig).map(mappedGroupMembers);
        }

        mapTabularObs(mappedGroupMembers, concept, obs, conceptSetConfig);
        return obs;
    };

    function mapTabularObs (mappedGroupMembers, concept, obs, conceptSetConfig) {
        var tabularObsGroups = _.filter(mappedGroupMembers, function (member) {
            return conceptSetConfig[member.concept.name] && conceptSetConfig[member.concept.name]['isTabular'];
        });

        if (tabularObsGroups.length > 0) {
            var array = _.map(concept.setMembers, function (member) {
                return member.name.name;
            });
            tabularObsGroups.forEach(function (group) {
                group.hidden = true;
            });

            var groupedObsGroups = _.groupBy(tabularObsGroups, function (group) {
                return group.concept.name;
            });

            _.values(groupedObsGroups).forEach(function (groups) {
                var tabularObservations = new Bahmni.ConceptSet.TabularObservations(groups, obs, conceptSetConfig);
                obs.groupMembers.push(tabularObservations);
            });
            var sortedGroupMembers = _.sortBy(obs.groupMembers, function (observation) {
                return array.indexOf(observation.concept.name);
            });
            obs.groupMembers.length = 0;
            obs.groupMembers.push.apply(obs.groupMembers, sortedGroupMembers);
        }
    }

    var mapObservationGroupMembers = function (observations, parentConcept, conceptSetConfig) {
        var observationGroupMembers = [];
        var conceptSetMembers = parentConcept.setMembers;
        conceptSetMembers.forEach(function (memberConcept) {
            var savedObservations = findInSavedObservation(memberConcept, observations);
            var configForConcept = conceptSetConfig[memberConcept.name.name] || {};
            var numberOfNodes = configForConcept.multiple || 1;
            for (var i = savedObservations.length - 1; i >= 0; i--) {
                observationGroupMembers.push(mapObservation(memberConcept, savedObservations[i], conceptSetConfig));
            }
            for (var i = 0; i < numberOfNodes - savedObservations.length; i++) {
                observationGroupMembers.push(mapObservation(memberConcept, null, conceptSetConfig));
            }
        });
        return observationGroupMembers;
    };

    var getDatatype = function (concept) {
        if (concept.dataType) {
            return concept.dataType;
        }
        return concept.datatype && concept.datatype.name;
    };

    // tODO : remove conceptUIConfig
    var newObservation = function (concept, savedObs, conceptSetConfig, mappedGroupMembers) {
        var observation = buildObservation(concept, savedObs, mappedGroupMembers);
        var obs = new Bahmni.ConceptSet.Observation(observation, savedObs, conceptSetConfig, mappedGroupMembers);
        if (getDatatype(concept) == "Boolean") {
            obs = new Bahmni.ConceptSet.BooleanObservation(obs, conceptSetConfig);
        }
        return obs;
    };

    // TODO : remove conceptUIConfig
    var newObservationNode = function (concept, savedObsNode, conceptSetConfig, mappedGroupMembers) {
        var observation = buildObservation(concept, savedObsNode, mappedGroupMembers);
        return new Bahmni.ConceptSet.ObservationNode(observation, savedObsNode, conceptSetConfig, concept);
    };

    var showAddMoreButton = function (rootObservation) {
        var observation = this;
        var lastObservationByLabel = _.findLast(rootObservation.groupMembers, {label: observation.label});
        return lastObservationByLabel.uuid === observation.uuid;
    };

    function buildObservation (concept, savedObs, mappedGroupMembers) {
        var comment = savedObs ? savedObs.comment : null;
        return {
            concept: conceptMapper.map(concept),
            units: concept.units,
            label: getLabel(concept),
            possibleAnswers: concept.answers,
            groupMembers: mappedGroupMembers,
            comment: comment,
            showAddMoreButton: showAddMoreButton
        };
    }

    var createObservationForDisplay = function (observation, concept, conceptGroupFormatService) {
        if (observation.value == null) {
            return;
        }
        var observationValue = getObservationDisplayValue(observation, conceptGroupFormatService);
        observationValue = observation.durationObs ? observationValue + " " + getDurationDisplayValue(observation.durationObs) : observationValue;
        return {
            value: observationValue,
            abnormalObs: observation.abnormalObs,
            duration: observation.durationObs,
            provider: observation.provider,
            label: getLabel(observation.concept),
            observationDateTime: observation.observationDateTime,
            concept: concept,
            comment: observation.comment,
            uuid: observation.uuid
        };
    };

    var getObservationDisplayValue = function (observation, conceptGroupFormatService) {
        if (observation.isBoolean || observation.type === "Boolean") {
            return observation.value === true ? "Yes" : "No";
        }
        if (!observation.value) {
            return "";
        }
        if (typeof observation.value.name === "object") {
            var valueConcept = conceptMapper.map(observation.value);
            return valueConcept.shortName || valueConcept.name;
        }

        if (observation.groupMembers === undefined || observation.groupMembers.length <= 0) {
            return observation.value.shortName || observation.value.name || observation.value;
        }

        if (observation.durationObs !== undefined) {
            return observation.primaryObs && (observation.primaryObs.value.shortName || observation.primaryObs.value.name || observation.primaryObs.value);
        }

        return conceptGroupFormatService.groupObs(observation);
    };

    var getDurationDisplayValue = function (duration) {
        var durationForDisplay = Bahmni.Common.Util.DateUtil.convertToUnits(duration.value);
        if (durationForDisplay["value"] && durationForDisplay["unitName"]) {
            return "since " + durationForDisplay["value"] + " " + durationForDisplay["unitName"];
        }
        return "";
    };

    this.getGridObservationDisplayValue = function (observation, conceptGroupFormatService) {
        var memberValues = _.compact(_.map(observation.groupMembers, function (member) {
            return getObservationDisplayValue(member, conceptGroupFormatService);
        }));
        return memberValues.join(', ');
    };
    var getLabel = function (concept) {
        var mappedConcept = conceptMapper.map(concept);
        return mappedConcept.shortName || mappedConcept.name;
    };
};

'use strict';

angular.module('bahmni.common.conceptSet')
    .factory('conceptService', ['$q', '$http', function ($q, $http) {
        var conceptMapper = new Bahmni.Common.Domain.ConceptMapper();
        var mapConceptOrGetDrug = function (conceptAnswer) {
            return conceptAnswer.concept && conceptMapper.map(conceptAnswer.concept) || conceptAnswer.drug;
        };

        var getAnswersForConceptName = function (request) {
            var params = {
                q: request.term,
                question: request.answersConceptName,
                v: "custom:(concept:(uuid,name:(display,uuid,name,conceptNameType),names:(display,uuid,name,conceptNameType)),drug:(uuid,name,display))",
                s: "byQuestion"
            };
            return $http.get(Bahmni.Common.Constants.bahmniConceptAnswerUrl, {params: params})
                .then(_.partial(_.get, _, 'data.results'))
                .then(function (conceptAnswers) {
                    return _(conceptAnswers)
                        .map(mapConceptOrGetDrug)
                        .uniqBy('uuid')
                        .value();
                });
        };

        var getAnswers = function (defaultConcept) {
            var deferred = $q.defer();
            var response = _(defaultConcept.answers)
                .uniqBy('uuid')
                .map(conceptMapper.map)
                .value();
            deferred.resolve(response);
            return deferred.promise;
        };

        return {
            getAnswersForConceptName: getAnswersForConceptName,
            getAnswers: getAnswers
        };
    }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .factory('conceptSetUiConfigService', ['$http', '$q', 'appService', function ($http, $q, appService) {
        var setConceptUuidInsteadOfName = function (config, conceptNameField, uuidField) {
            var conceptName = config[conceptNameField];
            if (conceptName != null) {
                return $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                    params: {name: conceptName, v: "custom:(uuid,name)"}
                }).then(function (response) {
                    var concept = response.data.results.filter(function (c) {
                        return c.name.name === conceptName;
                    });
                    if (concept.length > 0) {
                        config[uuidField] = concept[0].uuid;
                    }
                });
            }
        };

        var setExtraData = function (config) {
            Object.getOwnPropertyNames(config).forEach(function (conceptConfigKey) {
                var conceptConfig = config[conceptConfigKey];
                if (conceptConfig['freeTextAutocomplete'] instanceof Object) {
                    setConceptUuidInsteadOfName(conceptConfig['freeTextAutocomplete'], 'codedConceptName', 'codedConceptUuid');
                    setConceptUuidInsteadOfName(conceptConfig['freeTextAutocomplete'], 'conceptSetName', 'conceptSetUuid');
                }
            });
        };

        var getConfig = function () {
            var config = appService.getAppDescriptor().getConfigValue("conceptSetUI") || {};
            setExtraData(config);
            return config;
        };

        return {
            getConfig: getConfig
        };
    }]);

'use strict';

angular.module('bahmni.common.conceptSet')
    .factory('conceptGroupFormatService', ['$translate', 'appService', function ($translate, appService) {
        var conceptGroupFormatConfig = appService.getAppDescriptor().getConfigValue("obsGroupDisplayFormat") || {};
        var isConceptDefinedInConfig = function (observation) {
            if (observation.groupMembers.length > 0) {
                if ((observation.formNamespace === null && observation.obsGroupUuid !== null) || observation.formNamespace !== null) {
                    return conceptGroupFormatConfig.hasOwnProperty(observation.concept.name);
                }
            }
            return false;
        };

        var isConceptClassConceptDetails = function (observation) {
            return observation.concept.conceptClass === "Concept Details";
        };

        var isObsGroupFormatted = function (observation) {
            return isConceptClassConceptDetails(observation) || isConceptDefinedInConfig(observation);
        };

        var groupObs = function (observation) {
            if (conceptGroupFormatConfig != {}) {
                if (isConceptDefinedInConfig(observation)) {
                    var group = conceptGroupFormatConfig[observation.concept.name];
                    var interpolateParams = {};
                    observation.groupMembers.forEach(function (item) {
                        if (group.displayObsFormat.concepts.includes(item.concept.name)) {
                            interpolateParams[item.concept.name.replace(/[ ()/,]+/g, '')] = item.value.name || item.value;
                        }
                    });
                    return $translate.instant(group.displayObsFormat.translationKey, interpolateParams);
                }
            }

            if (isConceptClassConceptDetails(observation) && observation.groupMembers.length > 0) {
                var sortedGroupMembers = observation.groupMembers.sort(function (a, b) {
                    return a.conceptSortWeight - b.conceptSortWeight;
                });
                var obsValueList = [];
                sortedGroupMembers.forEach(function (obs) {
                    if (obs.concept.conceptClass !== "Abnormal") {
                        if (obs.value && obs.value.name) {
                            obsValueList.push(obs.value.name);
                        }
                        else {
                            obsValueList.push(obs.value);
                        }
                    }
                });
                return obsValueList.join(", ");
            }
        };

        var getConfig = function () {
            return conceptGroupFormatConfig;
        };

        return {
            getConfig: getConfig,
            groupObs: groupObs,
            isObsGroupFormatted: isObsGroupFormatted
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
.filter('thumbnail', function () {
    return function (url, extension) {
        if (url) {
            if (extension) {
                return Bahmni.Common.Constants.documentsPath + '/' + url.replace(/(.*)\.(.*)$/, "$1_thumbnail." + extension) || null;
            }
            return Bahmni.Common.Constants.documentsPath + '/' + url.replace(/(.*)\.(.*)$/, "$1_thumbnail.$2") || null;
        }
    };
});

'use strict';

angular.module('bahmni.common.uiHelper')
    .filter('days', function () {
        return function (startDate, endDate) {
            return Bahmni.Common.Util.DateUtil.diffInDays(startDate, endDate);
        };
    }).filter('bahmniDateTime', function () {
        return function (date) {
            return Bahmni.Common.Util.DateUtil.formatDateWithTime(date);
        };
    }).filter('bahmniDate', function () {
        return function (date) {
            return Bahmni.Common.Util.DateUtil.formatDateWithoutTime(date);
        };
    }).filter('bahmniTime', function () {
        return function (date) {
            return Bahmni.Common.Util.DateUtil.formatTime(date);
        };
    }).filter('bahmniDateInStrictMode', function () {
        return function (date) {
            return Bahmni.Common.Util.DateUtil.formatDateInStrictMode(date);
        };
    }).filter('bahmniDateTimeWithFormat', function () {
        return function (date, format) {
            return Bahmni.Common.Util.DateUtil.getDateTimeInSpecifiedFormat(date, format);
        };
    }).filter('addDays', function () {
        return function (date, numberOfDays) {
            return Bahmni.Common.Util.DateUtil.addDays(date, numberOfDays);
        };
    });

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Logging = Bahmni.Common.Logging || {};

angular.module('bahmni.common.logging', []);

'use strict';

angular.module('bahmni.common.logging')
.config(['$provide', function ($provide) {
    $provide.decorator("$exceptionHandler", function ($delegate, $injector, $window, $log) {
        var logError = function (exception, cause) {
            try {
                var messagingService = $injector.get('messagingService');
                var loggingService = $injector.get('loggingService');
                var errorMessage = exception.toString();
                var stackTrace = printStackTrace({ e: exception });
                var errorDetails = {
                    timestamp: new Date(),
                    browser: $window.navigator.userAgent,
                    errorUrl: $window.location.href,
                    errorMessage: errorMessage,
                    stackTrace: stackTrace,
                    cause: (cause || "")
                };
                loggingService.log(errorDetails);
                messagingService.showMessage('error', errorMessage);
                exposeException(errorDetails);
            } catch (loggingError) {
                $log.warn("Error logging failed");
                $log.log(loggingError);
            }
        };

        var exposeException = function (exceptionDetails) {
            window.angular_exception = window.angular_exception || [];
            window.angular_exception.push(exceptionDetails);
        };

        return function (exception, cause) {
            $delegate(exception, cause);
            logError(exception, cause);
        };
    });
}]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};

angular.module('bahmni.common.displaycontrol', []);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.Observation = Bahmni.Common.DisplayControl.Observation || {};

angular.module('bahmni.common.displaycontrol.observation', ['bahmni.common.conceptSet', 'pascalprecht.translate']);

'use strict';

angular.module('bahmni.common.conceptSet')
    .factory('formService', ['$http', function ($http) {
        var getFormList = function (encounterUuid) {
            return $http.get(Bahmni.Common.Constants.latestPublishedForms, {params: {encounterUuid: encounterUuid}});
        };

        var getAllForms = function () {
            return $http.get(Bahmni.Common.Constants.allFormsUrl, {params: {v: "custom:(version,name,uuid)"}});
        };

        var getFormDetail = function (formUuid, params) {
            return $http.get(Bahmni.Common.Constants.formUrl + '/' + formUuid, {params: params});
        };

        const getUrlWithUuid = function (url, patientUuid) {
            return url.replace('{patientUuid}', patientUuid);
        };

        var getAllPatientForms = function (patientUuid, numberOfVisits, patientProgramUuid) {
            const patientFormsUrl = getUrlWithUuid(Bahmni.Common.Constants.patientFormsUrl, patientUuid);
            const params = {
                numberOfVisits: numberOfVisits,
                formType: 'v2',
                patientProgramUuid: patientProgramUuid
            };
            return $http.get(patientFormsUrl, {params: params});
        };

        var getFormTranslations = function (url, form) {
            if (url && url !== Bahmni.Common.Constants.formTranslationsUrl) {
                return $http.get(url);
            }
            return $http.get(Bahmni.Common.Constants.formTranslationsUrl, { params: form});
        };

        var getFormTranslate = function (formName, formVersion, locale, formUuid) {
            return $http.get(Bahmni.Common.Constants.formBuilderTranslationApi, { params: {formName: formName,
                formVersion: formVersion, locale: locale, formUuid: formUuid}});
        };

        return {
            getFormList: getFormList,
            getAllForms: getAllForms,
            getFormDetail: getFormDetail,
            getFormTranslations: getFormTranslations,
            getFormTranslate: getFormTranslate,
            getAllPatientForms: getAllPatientForms
        };
    }]);

'use strict';

Bahmni.Common.DisplayControl.Observation.GroupingFunctions = function () {
    var self = this;
    var observationGroupingFunction = function (obs) {
        return Bahmni.Common.Util.DateUtil.getDateTimeWithoutSeconds(obs.encounterDateTime);
    };

    self.groupByEncounterDate = function (bahmniObservations) {
        var obsArray = [];
        bahmniObservations = _.groupBy(bahmniObservations, observationGroupingFunction);

        var sortWithInAConceptDateCombination = function (anObs, challengerObs) {
            if (anObs.encounterDateTime < challengerObs.encounterDateTime) {
                return 1;
            }
            if (anObs.encounterDateTime > challengerObs.encounterDateTime) {
                return -1;
            }
            if (anObs.conceptSortWeight < challengerObs.conceptSortWeight) {
                return -1;
            }
            if (anObs.conceptSortWeight > challengerObs.conceptSortWeight) {
                return 1;
            }

            return 0;
        };

        for (var obsKey in bahmniObservations) {
            var dateTime = obsKey;

            var anObs = {
                "key": dateTime,
                "value": bahmniObservations[dateTime].sort(sortWithInAConceptDateCombination),
                "date": dateTime
            };

            obsArray.push(anObs);
        }
        return _.sortBy(obsArray, 'date').reverse();
    };

    self.persistOrderOfConceptNames = function (bahmniObservations) {
        var obsArray = [];
        for (var obsKey in bahmniObservations) {
            var anObs = {
                "key": obsKey,
                "value": [bahmniObservations[obsKey]],
                "date": bahmniObservations[obsKey].encounterDateTime
            };
            obsArray.push(anObs);
        }
        return obsArray;
    };

    var observationDateTimeGroupingFunction = function (obs) {
        return Bahmni.Common.Util.DateUtil.getDateTimeWithoutSeconds(obs.observationDateTime);
    };

    self.groupByObservationDateTime = function (bahmniObservations) {
        var obsArray = [];
        var index = 0;
        var oKey = null;
        for (var obsKey in bahmniObservations) {
            if (index === 0) {
                index += 1;
                oKey = observationDateTimeGroupingFunction(bahmniObservations[obsKey]);
            }
            var anObs = {
                "key": oKey,
                "value": bahmniObservations[obsKey],
                "date": observationDateTimeGroupingFunction(bahmniObservations[obsKey])
            };
            obsArray.push(anObs);
        }
        var sortedArr = _.sortBy(obsArray, 'date').reverse();
        var obsValues = [];
        for (var obsKey in sortedArr) {
            obsValues.push(sortedArr[obsKey].value);
        }
        var ele = {};
        ele.key = oKey;
        ele.value = obsValues;
        ele.date = oKey;
        return obsValues.length > 0 ? [ele] : [];
    };

    return self;
};

'use strict';

angular.module('bahmni.common.displaycontrol.observation')
    .service('formHierarchyService', ['formService', function (formService) {
        var self = this;

        self.build = function (observations) {
            var obs = self.preProcessMultipleSelectObsToObs(observations);
            obs = self.createDummyObsGroupForObservationsForForm(obs);
            self.createDummyObsGroupForSectionsForForm(obs);
        };

        self.preProcessMultipleSelectObsToObs = function (observations) {
            _.forEach(observations, function (obs) {
                _.forEach(obs.value, function (value, index) {
                    if (value.type == "multiSelect") {
                        obs.value.push(value.groupMembers[0]);
                        obs.value.splice(index, 1);
                    }
                });
            });
            return observations;
        };

        self.createDummyObsGroupForObservationsForForm = function (observations) {
            _.forEach(observations, function (obs) {
                var newValues = [];
                _.forEach(obs.value, function (value) {
                    if (!value.formFieldPath) {
                        newValues.push(value);
                        return;
                    }

                    var dummyObsGroup = {
                        "groupMembers": [],
                        "concept": {
                            "shortName": "",
                            "conceptClass": null
                        },
                        "encounterUuid": ""
                    };

                    dummyObsGroup.concept.shortName = value.formFieldPath.split('.')[0];
                    dummyObsGroup.encounterUuid = value.encounterUuid;
                    var previousDummyObsGroupFound;
                    _.forEach(newValues, function (newValue) {
                        if (dummyObsGroup.concept.shortName == newValue.concept.shortName) {
                            newValue.groupMembers.push(value);
                            previousDummyObsGroupFound = true;
                        }
                    });

                    if (previousDummyObsGroupFound) {
                        return;
                    }

                    dummyObsGroup.groupMembers.push(value);
                    newValues.push(dummyObsGroup);
                });

                obs.value = newValues;
            });

            return observations;
        };

        self.getFormVersion = function (members) {
            var formVersion;
            _.forEach(members, function (member) {
                if (member.formFieldPath) {
                    formVersion = member.formFieldPath.split('.')[1].split('/')[0];
                    return false;
                }
            });
            return formVersion;
        };

        self.getMemberFromFormByFormFieldPath = function (members, id) {
            return _.filter(members, function (member) {
                return member.formFieldPath.split('.')[1].split('/')[1].split('-')[0] == id;
            });
        };

        self.getFormByFormName = function (formList, formName, formVersion) {
            return _.find(formList, function (form) {
                return form.name == formName && form.version == formVersion;
            });
        };

        self.parseSection = function (members, controls, value) {
            var sectionIsEmpty = true;
            _.forEach(controls, function (control) {
                var dummyObsGroup = {
                    "groupMembers": [],
                    "concept": {
                        "shortName": "",
                        "conceptClass": null
                    }
                };
                if (control.type == "section") {
                    dummyObsGroup.concept.shortName = control.label.value;
                    value.groupMembers.push(dummyObsGroup);
                    if (!self.parseSection(members, control.controls, dummyObsGroup)) {
                        value.groupMembers.pop();
                    } else {
                        sectionIsEmpty = false;
                    }
                } else {
                    var member = self.getMemberFromFormByFormFieldPath(members, control.id);
                    if (member.length != 0) {
                        if (member[0].formFieldPath.split('-')[1] != 0) {
                            _.reverse(member);
                        }
                        _.map(member, function (m) {
                            value.groupMembers.push(m);
                        });
                        sectionIsEmpty = false;
                    }
                }
            });
            if (sectionIsEmpty) {
                return null;
            }
            return value;
        };

        self.createSectionForSingleForm = function (obsFromSameForm, formDetails) {
            var members = obsFromSameForm.groupMembers.slice();
            obsFromSameForm.groupMembers.splice(0, obsFromSameForm.groupMembers.length);

            return self.parseSection(members, formDetails.controls, obsFromSameForm);
        };

        self.createDummyObsGroupForSectionsForForm = function (bahmniObservations) {
            if (_.isEmpty(bahmniObservations)) {
                return;
            }

            formService.getAllForms().then(function (response) {
                var allForms = response.data;
                _.forEach(bahmniObservations, function (observation) {
                    var forms = [];
                    _.forEach(observation.value, function (form) {
                        if (form.concept.conceptClass) {
                            forms.push(form);
                            return;
                        }
                        var observationForm = self.getFormByFormName(allForms, form.concept.shortName, self.getFormVersion(form.groupMembers));
                        if (!observationForm) {
                            return;
                        }
                        formService.getFormDetail(observationForm.uuid, { v: "custom:(resources:(value))"}).then(function (response) {
                            var formDetailsAsString = _.get(response, 'data.resources[0].value');
                            if (formDetailsAsString) {
                                var formDetails = JSON.parse(formDetailsAsString);
                                forms.push(self.createSectionForSingleForm(form, formDetails));
                            }
                            observation.value = forms;
                        });
                    });
                });
            });
        };
    }
    ]);

'use strict';

angular.module('bahmni.common.displaycontrol.observation')
    .service('formRecordTreeBuildService', ['formService', '$window', function (formService, $window) {
        var self = this;
        self.formBuildForms = [];
        self.build = function (bahmniObservations, hasNoHierarchy) {
            _.forEach(bahmniObservations, function (obs) {
                obs.value = self.preProcessMultiSelectObs(obs.value);
            });

            formService.getAllForms().then(function (response) {
                var formBuildForms = response.data;
                var obs = self.createObsGroupForForm(bahmniObservations, formBuildForms);
                if (!hasNoHierarchy) {
                    updateObservationsWithFormDefinition(obs, formBuildForms);
                }
            });
        };

        self.createMultiSelectObservation = function (observations) {
            var multiSelectObject = new Bahmni.Common.Obs.MultiSelectObservation(observations, {multiSelect: true});
            multiSelectObject.formFieldPath = observations[0].formFieldPath;
            multiSelectObject.encounterUuid = observations[0].encounterUuid;
            return multiSelectObject;
        };

        self.preProcessMultiSelectObs = function (value) {
            var clonedGroupMembers = _.cloneDeep(value);
            _.forEach(clonedGroupMembers, function (member) {
                if (member && member.groupMembers.length === 0) {
                    var obsWithSameFormFieldPath = self.getRecordObservations(member.formFieldPath, value);
                    if (obsWithSameFormFieldPath.length > 1) {
                        var multiSelectObject = self.createMultiSelectObservation(obsWithSameFormFieldPath);
                        value.push(multiSelectObject);
                    } else if (obsWithSameFormFieldPath.length === 1) {
                        value.push(obsWithSameFormFieldPath[0]);
                    }
                } else if (member.groupMembers.length > 0) {
                    var obsGroups = self.getRecordObservations(member.formFieldPath, value);
                    _.forEach(obsGroups, function (obsGroup) {
                        obsGroup.groupMembers = self.preProcessMultiSelectObs(obsGroup.groupMembers);
                        value.push(obsGroup);
                    });
                }
            });
            return value;
        };

        self.createObsGroupForForm = function (observations, formBuilderForms) {
            _.forEach(observations, function (obs) {
                var newValues = [];
                _.forEach(obs.value, function (value) {
                    if (!value.formFieldPath) {
                        newValues.push(value);
                        return;
                    }
                    var obsGroup = {
                        "groupMembers": [],
                        "concept": {
                            "shortName": "",
                            "conceptClass": null
                        },
                        "encounterUuid": ""

                    };
                    var formName = value.formFieldPath.split('.')[0];
                    var formBuilderForm = formBuilderForms.find(function (form) { return form.name ===
                        formName; });
                    obsGroup.concept.shortName = formName;
                    var locale = localStorage.getItem("NG_TRANSLATE_LANG_KEY") || "en";
                    var formNameTranslations = formBuilderForm && formBuilderForm.nameTranslation
                        ? JSON.parse(formBuilderForm.nameTranslation) : [];
                    if (formNameTranslations.length > 0) {
                        var currentLabel = formNameTranslations
                            .find(function (formNameTranslation) {
                                return formNameTranslation.locale === locale;
                            });
                        if (currentLabel) {
                            obsGroup.concept.shortName = currentLabel.display;
                        }
                    }
                    obsGroup.encounterUuid = value.encounterUuid;
                    var previousObsGroupFound;
                    _.forEach(newValues, function (newValue) {
                        if (obsGroup.concept.shortName === newValue.concept.shortName) {
                            newValue.groupMembers.push(value);
                            previousObsGroupFound = true;
                        }
                    });
                    if (previousObsGroupFound) {
                        return;
                    }
                    obsGroup.groupMembers.push(value);
                    newValues.push(obsGroup);
                });
                obs.value = newValues;
            });
            return observations;
        };

        var updateObservationsWithFormDefinition = function (observations, formBuildForms) {
            var allForms = formBuildForms;
            _.forEach(observations, function (observation) {
                var forms = [];
                _.forEach(observation.value, function (form) {
                    if (form.concept.conceptClass) {
                        forms.push(form);
                        return;
                    }
                    var observationForm = self.getFormByFormName(allForms, self.getFormName(form.groupMembers), self.getFormVersion(form.groupMembers));
                    if (!observationForm) {
                        return;
                    }
                    formService.getFormDetail(observationForm.uuid, {v: "custom:(resources:(value))"}).then(function (response) {
                        var formDetailsAsString = _.get(response, 'data.resources[0].value');
                        if (formDetailsAsString) {
                            var formDef = JSON.parse(formDetailsAsString);
                            formDef.version = observationForm.version;
                            var locale = $window.localStorage["NG_TRANSLATE_LANG_KEY"] || "en";
                            return formService.getFormTranslate(formDef.name, formDef.version, locale, formDef.uuid)
                                .then(function (response) {
                                    var translationData = response.data;
                                    forms.push(self.updateObservationsWithRecordTree(formDef, form, translationData));
                                    observation.value = forms;
                                });
                        }
                        observation.value = forms;
                    });
                });
            });
        };

        self.getFormByFormName = function (formList, formName, formVersion) {
            return _.find(formList, function (form) {
                return form.name === formName && form.version === formVersion;
            });
        };

        self.getFormName = function (members) {
            var member = _.find(members, function (member) {
                return member.formFieldPath !== null;
            });
            return member ? member.formFieldPath.split('.')[0] : undefined;
        };

        self.getFormVersion = function (members) {
            var member = _.find(members, function (member) {
                return member.formFieldPath !== null;
            });
            return member ? member.formFieldPath.split('.')[1].split('/')[0] : undefined;
        };

        self.updateObservationsWithRecordTree = function (formDef, form, translationData) {
            var recordTree = getRecordTree(formDef, form.groupMembers);
            recordTree = JSON.parse(JSON.stringify(recordTree));
            self.createGroupMembers(recordTree, form, form.groupMembers, translationData);
            return form;
        };

        self.createColumnGroupsForTable = function (record, columns, tableGroup, obsList, translationData) {
            _.forEach(columns, function (column, index) {
                var obsGroup = {
                    "groupMembers": [],
                    "concept": {
                        "shortName": "",
                        "conceptClass": null
                    }
                };
                var translationKey = column.translationKey;
                var defaultShortName = column.value;
                obsGroup.concept.shortName = self.getTranslatedShortName(translationData, translationKey, obsGroup, defaultShortName);
                var columnRecord = self.getColumnObs(index, record);
                column.children = columnRecord;
                self.createGroupMembers(column, obsGroup, obsList, translationData);
                if (obsGroup.groupMembers.length > 0) {
                    tableGroup.groupMembers.push(obsGroup);
                }
            });
        };

        self.getTranslatedShortName = function (translationData, translationKey, obsGroup, defaultShortName) {
            if (self.isTranslationKeyPresent(translationData, translationKey)) {
                return translationData.labels[translationKey][0];
            }
            return defaultShortName;
        };

        self.isTranslationKeyPresent = function (translationData, translationKey) {
            return translationData && translationData.labels &&
                translationData.labels[translationKey][0] !== translationKey;
        };

        self.getColumnObs = function (columnIndex, record) {
            var columnChildren = [];
            _.map(record.children, function (child) {
                if (child.control.properties && child.control.properties.location.column === columnIndex) {
                    columnChildren.push(child);
                }
            });
            return columnChildren;
        };

        self.createGroupMembers = function (recordTree, obsGroup, obsList, translationData) {
            _.forEach(recordTree.children, function (record) {
                if (record.control.type === 'obsControl' || record.control.type === 'obsGroupControl') {
                    var recordObservations = self.getRecordObservations(record.formFieldPath, obsList);
                    _.forEach(recordObservations, function (recordObservation) {
                        obsGroup.groupMembers.push(recordObservation);
                    });
                }
                else if (record.control.type === 'section') {
                    var sectionGroup = self.createObsGroup(record, translationData);
                    self.createGroupMembers(record, sectionGroup, obsList, translationData);
                    if (sectionGroup.groupMembers.length > 0) {
                        obsGroup.groupMembers.push(sectionGroup);
                    }
                }
                else if (record.control.type === "table") {
                    var tableGroup = self.createObsGroup(record, translationData);
                    var columns = record.control.columnHeaders;
                    self.createColumnGroupsForTable(record, columns, tableGroup, obsList, translationData);
                    if (tableGroup.groupMembers.length > 0) {
                        obsGroup.groupMembers.push(tableGroup);
                    }
                }
            });
        };

        self.getTableColumns = function (record) {
            return _.filter(record.control.columnHeaders, function (child) {
                return child.type === "label";
            });
        };

        self.getRecordObservations = function (obsFormFieldPath, obsList) {
            return _.remove(obsList, function (obs) {
                return obs.formFieldPath && obs.formFieldPath === obsFormFieldPath;
            });
        };

        self.createObsGroup = function (record, translationData) {
            var obsGroup = {
                "groupMembers": [],
                "concept": {
                    "shortName": "",
                    "conceptClass": null
                }
            };
            var translationKey = record.control.label.translationKey;
            var defaultShortName = record.control.label.value;
            obsGroup.concept.shortName =
                self.getTranslatedShortName(translationData, translationKey, obsGroup, defaultShortName);
            return obsGroup;
        };
    }]);

'use strict';

angular.module('bahmni.common.displaycontrol.observation')
    .directive('bahmniObservation', ['encounterService', 'observationsService', 'appService', '$q', 'spinner', '$rootScope',
        'formRecordTreeBuildService', '$translate', 'providerInfoService', 'conceptGroupFormatService', 'formPrintService',
        function (encounterService, observationsService, appService, $q, spinner, $rootScope,
                  formRecordTreeBuildService, $translate, providerInfoService, conceptGroupFormatService, formPrintService) {
            var controller = function ($scope) {
                $scope.print = $rootScope.isBeingPrinted || false;

                $scope.showGroupDateTime = $scope.config.showGroupDateTime !== false;

                var mapObservation = function (observations) {
                    var conceptsConfig = $scope.config.formType === Bahmni.Common.Constants.forms2Type ? {} :
                        appService.getAppDescriptor().getConfigValue("conceptSetUI") || {};

                    observations = new Bahmni.Common.Obs.ObservationMapper().map(observations, conceptsConfig, null, $translate, conceptGroupFormatService);

                    if ($scope.config.conceptNames) {
                        observations = _.filter(observations, function (observation) {
                            return _.some($scope.config.conceptNames, function (conceptName) {
                                var comparableAttr = observation.conceptFSN != null ? 'conceptFSN' : 'concept.name';
                                return _.toLower(conceptName) === _.toLower(_.get(observation, comparableAttr));
                            });
                        });
                        if ($scope.config.customSortNeeded && $scope.config.conceptNames) {
                            observations.sort(function (a, b) {
                                const indexOfA = $scope.config.conceptNames.indexOf(a.concept.name);
                                const indexOfB = $scope.config.conceptNames.indexOf(b.concept.name);
                                return indexOfA - indexOfB;
                            });
                        }
                    }

                    if ($scope.config.persistOrderOfConcepts) {
                        $scope.bahmniObservations = new Bahmni.Common.DisplayControl.Observation.GroupingFunctions().persistOrderOfConceptNames(observations);
                    } else if ($scope.config.persistOrderOfObsDateTime) {
                        $scope.bahmniObservations = new Bahmni.Common.DisplayControl.Observation.GroupingFunctions().groupByObservationDateTime(observations);
                    } else {
                        $scope.bahmniObservations = new Bahmni.Common.DisplayControl.Observation.GroupingFunctions().groupByEncounterDate(observations);
                    }

                    if (_.isEmpty($scope.bahmniObservations)) {
                        $scope.noObsMessage = $translate.instant(Bahmni.Common.Constants.messageForNoObservation);
                        $scope.$emit("no-data-present-event");
                    } else {
                        if (!$scope.showGroupDateTime) {
                            _.forEach($scope.bahmniObservations, function (bahmniObs) {
                                bahmniObs.isOpen = true;
                            });
                        } else {
                            $scope.bahmniObservations[0].isOpen = true;
                        }
                        providerInfoService.setProvider($scope.bahmniObservations[0].value);
                    }

                    var formObservations = _.filter(observations, function (obs) {
                        return obs.formFieldPath;
                    });

                    if (formObservations.length > 0) {
                        formRecordTreeBuildService.build($scope.bahmniObservations, $scope.hasNoHierarchy);
                    }
                };

                var fetchObservations = function () {
                    if ($scope.config.formType === Bahmni.Common.Constants.formBuilderDisplayControlType) {
                        var getFormNameAndVersion = Bahmni.Common.Util.FormFieldPathUtil.getFormNameAndVersion;
                        encounterService.findByEncounterUuid($scope.config.encounterUuid, {includeAll: false}).then(function (reponse) {
                            var encounterTransaction = reponse.data;
                            var observationsForSelectedForm = _.filter(encounterTransaction.observations, function (obs) {
                                if (obs.formFieldPath) {
                                    var obsFormNameAndVersion = getFormNameAndVersion(obs.formFieldPath);
                                    return obsFormNameAndVersion.formName === $scope.config.formName;
                                }
                            });
                            mapObservation(observationsForSelectedForm);
                        });
                        $scope.title = $scope.config.formDisplayName;
                    } else {
                        if ($scope.observations) {
                            mapObservation($scope.observations, $scope.config);
                            $scope.isFulfilmentDisplayControl = true;
                        } else {
                            if ($scope.config.observationUuid) {
                                $scope.initialization = observationsService.getByUuid($scope.config.observationUuid).then(function (response) {
                                    mapObservation([response.data], $scope.config);
                                });
                            } else if ($scope.config.encounterUuid) {
                                var fetchForEncounter = observationsService.fetchForEncounter($scope.config.encounterUuid, $scope.config.conceptNames);
                                $scope.initialization = fetchForEncounter.then(function (response) {
                                    mapObservation(response.data, $scope.config);
                                });
                            } else if ($scope.enrollment) {
                                $scope.initialization = observationsService.fetchForPatientProgram($scope.enrollment, $scope.config.conceptNames, $scope.config.scope, $scope.config.obsIgnoreList).then(function (response) {
                                    mapObservation(response.data, $scope.config);
                                });
                            } else {
                                $scope.initialization = observationsService.fetch($scope.patient.uuid, $scope.config.conceptNames,
                                    $scope.config.scope, $scope.config.numberOfVisits, $scope.visitUuid,
                                    $scope.config.obsIgnoreList, null).then(function (response) {
                                        mapObservation(response.data, $scope.config);
                                    });
                            }
                        }
                    }
                };
                $scope.translateAttributeName = function (attribute) {
                    var keyName = attribute.toUpperCase().replace(/\s\s+/g, ' ').replace(/[^a-zA-Z0-9 _]/g, "").trim().replace(/ /g, "_");
                    var translationKey = keyName;
                    var translation = $translate.instant(translationKey);
                    if (translation == translationKey) {
                        return translation;
                    }
                    return translation;
                };
                $scope.toggle = function (element) {
                    element.isOpen = !element.isOpen;
                };

                $scope.isClickable = function () {
                    return $scope.isOnDashboard && $scope.section.expandedViewConfig &&
                        ($scope.section.expandedViewConfig.pivotTable || $scope.section.expandedViewConfig.observationGraph);
                };

                fetchObservations();

                $scope.dialogData = {
                    "patient": $scope.patient,
                    "section": $scope.section
                };

                $scope.$on("event:printForm", function (event, dashboardConfig) {
                    var printData = {};
                    printData.bahmniObservations = $scope.bahmniObservations;
                    $scope.bahmniObservations.forEach(function (obs) {
                        printData.title = obs.value[0].concept.name;
                    });
                    printData.patient = $scope.patient;
                    printData.printConfig = dashboardConfig ? dashboardConfig.printing : {};
                    printData.printConfig.header = printData.title;
                    if ($scope.bahmniObservations && $scope.config.encounterUuid && $scope.patient) {
                        formPrintService.printForm(printData, $scope.config.encounterUuid, $rootScope.facilityLocation);
                    }
                });
            };

            var link = function ($scope, element) {
                $scope.initialization && spinner.forPromise($scope.initialization, element);
            };

            return {
                restrict: 'E',
                controller: controller,
                link: link,
                templateUrl: function (element, attrs) {
                    if (attrs.templateUrl) {
                        return attrs.templateUrl;
                    } else {
                        return "../common/displaycontrols/observation/views/observationDisplayControl.html";
                    }
                },
                scope: {
                    patient: "=",
                    visitUuid: "@",
                    section: "=?",
                    config: "=",
                    title: "=sectionTitle",
                    isOnDashboard: "=?",
                    observations: "=?",
                    message: "=?",
                    enrollment: "=?",
                    hasNoHierarchy: "@"
                }
            };
        }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.PivotTable = Bahmni.Common.DisplayControl.PivotTable || {};

angular.module('bahmni.common.displaycontrol', []);
angular.module('bahmni.common.displaycontrol.pivottable', []);

'use strict';
angular.module('bahmni.common.displaycontrol.pivottable').directive('pivotTable', ['$rootScope', '$filter', '$stateParams', 'spinner', 'pivotTableService', 'appService', 'conceptSetUiConfigService', '$interval',
    function ($rootScope, $filter, $stateParams, spinner, pivotTableService, appService, conceptSetUiConfigService, $interval) {
        return {
            scope: {
                patientUuid: "=",
                diseaseName: "=",
                displayName: "=",
                config: "=",
                visitUuid: "=",
                status: "=?"
            },
            link: function (scope, element) {
                var tablescroll;
                if (!scope.config) {
                    return;
                }

                scope.groupBy = scope.config.groupBy || "visits";
                scope.heading = scope.config.rowHeading || scope.groupBy;
                scope.groupByEncounters = scope.groupBy === "encounters";
                scope.groupByVisits = scope.groupBy === "visits";

                scope.getOnlyDate = function (startdate) {
                    return Bahmni.Common.Util.DateUtil.formatDateWithoutTime(startdate);
                };

                scope.getOnlyTime = function (startDate) {
                    return Bahmni.Common.Util.DateUtil.formatTime(startDate);
                };

                scope.isLonger = function (value) {
                    return value ? value.length > 13 : false;
                };

                scope.getColumnValue = function (value, conceptName) {
                    if (conceptName && conceptSetUiConfigService.getConfig()[conceptName] && conceptSetUiConfigService.getConfig()[conceptName].displayMonthAndYear == true) {
                        return Bahmni.Common.Util.DateUtil.getDateInMonthsAndYears(value);
                    }
                    const number = Number.parseFloat(value);
                    return number ? number : scope.isLonger(value) ? value.substring(0, 10) + "..." : value;
                };

                scope.scrollLeft = function () {
                    $('table.pivot-table tbody').animate({
                        scrollLeft: 0});
                    return false;
                };
                scope.scrollRight = function () {
                    $('table.pivot-table tbody').animate({
                        scrollLeft: tablescroll});
                    return false;
                };

                var programConfig = appService.getAppDescriptor().getConfigValue("program") || {};

                var startDate = null, endDate = null;
                if (programConfig.showDetailsWithinDateRange) {
                    startDate = $stateParams.dateEnrolled;
                    endDate = $stateParams.dateCompleted;
                }

                var checkIfPivotTableLoaded = $interval(function () {
                    if ($('table.pivot-table tbody tr').length > 11) {
                        $('table.pivot-table tbody').animate({
                            scrollLeft: '20000px' }, 500);
                        tablescroll = $('table.pivot-table tbody').scrollLeft();
                        clearInterval(checkIfPivotTableLoaded);
                    }
                    else if ($('table.pivot-table tbody tr').length < 12) {
                        $('.btn-scroll-right, .btn-scroll-left').attr("disabled", true);
                        clearInterval(checkIfPivotTableLoaded);
                    }
                }, 1000, 2);

                var pivotDataPromise = pivotTableService.getPivotTableFor(scope.patientUuid, scope.config, scope.visitUuid, startDate, endDate);
                spinner.forPromise(pivotDataPromise, element);
                pivotDataPromise.then(function (response) {
                    var concepts = _.map(response.data.conceptDetails, function (conceptDetail) {
                        return {
                            name: conceptDetail.fullName,
                            shortName: conceptDetail.name,
                            lowNormal: conceptDetail.lowNormal,
                            hiNormal: conceptDetail.hiNormal,
                            units: conceptDetail.units
                        };
                    });
                    if (scope.config.obsConcepts) {
                        concepts.sort(function (a, b) {
                            const indexOfA = scope.config.obsConcepts.indexOf(a.name);
                            const indexOfB = scope.config.obsConcepts.indexOf(b.name);
                            return indexOfA - indexOfB;
                        });
                    }
                    var tabluarDataInAscOrderByDate = _(response.data.tabularData).toPairs().sortBy(0).fromPairs().value();
                    scope.result = {concepts: concepts, tabularData: tabluarDataInAscOrderByDate};
                    scope.hasData = !_.isEmpty(scope.result.tabularData);
                    scope.status = scope.status || {};
                    scope.status.data = scope.hasData;
                });
                scope.showOnPrint = !$rootScope.isBeingPrinted;
            },

            templateUrl: '../common/displaycontrols/pivottable/views/pivotTable.html'
        };
    }]);

'use strict';

angular.module('bahmni.common.displaycontrol.pivottable')
    .service('pivotTableService', ['$http', function ($http) {
        this.getPivotTableFor = function (patientUuid, diseaseSummaryConfig, visitUuid, startDate, endDate) {
            return $http.get(Bahmni.Common.Constants.diseaseSummaryPivotUrl, {
                params: {
                    patientUuid: patientUuid,
                    visit: visitUuid,
                    numberOfVisits: diseaseSummaryConfig["numberOfVisits"],
                    initialCount: diseaseSummaryConfig["initialCount"],
                    latestCount: diseaseSummaryConfig["latestCount"],
                    obsConcepts: diseaseSummaryConfig["obsConcepts"],
                    drugConcepts: diseaseSummaryConfig["drugConcepts"],
                    labConcepts: diseaseSummaryConfig["labConcepts"],
                    groupBy: diseaseSummaryConfig["groupBy"],
                    startDate: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(startDate),
                    endDate: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(endDate)
                }
            });
        };
    }]);

'use strict';

angular.module('bahmni.common.util')
    .factory('formPrintService', ['$http', '$q', 'printer', 'diagnosisService', 'observationsService', 'encounterService', 'visitService', 'allergyService',
        function ($http, $q, printer, diagnosisService, observationsService, encounterService, visitService, allergyService) {
            var printForm = function (printData, encounterUuid, location) {
                var templateUrl = printData.printConfig.templateUrl;
                if (templateUrl) {
                    var promises = [];
                    printData.diagnosesWithCodes = "";
                    printData.observationsEntries = [];
                    var visitSummary = null;
                    if (printData.printConfig.observationsConcepts !== undefined) {
                        var promise = $q.all([diagnosisService.getPatientDiagnosis(printData.patient.uuid),
                            observationsService.fetch(printData.patient.uuid, printData.printConfig.observationsConcepts, "latest", null, null, null, null, null)]).then(function (response) {
                                const diagnoses = response[0].data;
                                printData.observationsEntries = response[1].data;
                                angular.forEach(diagnoses, function (diagnosis) {
                                    if (diagnosis.order === printData.printConfig.printDiagnosis.order &&
                                        diagnosis.certainty === printData.printConfig.printDiagnosis.certainity) {
                                        if (printData.diagnosesWithCodes.length > 0) {
                                            printData.diagnosesWithCodes += ", ";
                                        }
                                        if (diagnosis.codedAnswer !== null && diagnosis.codedAnswer.mappings.length !== 0) {
                                            printData.diagnosesWithCodes += diagnosis.codedAnswer.mappings[0].code + " - " + diagnosis.codedAnswer.name;
                                        }
                                        else if (diagnosis.codedAnswer !== null && diagnosis.codedAnswer.mappings.length == 0) {
                                            printData.diagnosesWithCodes += diagnosis.codedAnswer.name;
                                        }
                                        else if (diagnosis.codedAnswer == null && diagnosis.freeTextAnswer !== null) {
                                            printData.diagnosesWithCodes += diagnosis.freeTextAnswer;
                                        }
                                    }
                                });
                            });
                        promises.push(promise);
                    }
                    if (encounterUuid) {
                        var encounterPromise = encounterService.findByEncounterUuid(encounterUuid).then(function (response) {
                            return response.data.visitUuid;
                        });
                        promises.push(encounterPromise);
                    }
                    printData.allergies = "";
                    var allergyPromise = allergyService.getAllergyForPatient(printData.patient.uuid).then(function (response) {
                        var allergies = response.data;
                        var allergiesList = [];
                        if (response.status === 200 && allergies.entry) {
                            allergies.entry.forEach(function (allergy) {
                                if (allergy.resource.code.coding) {
                                    allergiesList.push(allergy.resource.code.coding[0].display);
                                }
                            });
                        }
                        printData.allergies = allergiesList.join(", ");
                    });
                    promises.push(allergyPromise);

                    Promise.all(promises)
                    .then(function (response) {
                        if (response[1]) {
                            return visitService.getVisitSummary(response[1]);
                        }
                    })
                    .then(function (response) {
                        visitSummary = response ? response.data : undefined;
                    })
                    .then(function () {
                        printData.additionalInfo = {};
                        printData.additionalInfo.visitType = visitSummary ? visitSummary.visitType : null;
                        printData.additionalInfo.currentDate = new Date();
                        printData.additionalInfo.facilityLocation = location;
                        var tabName = printData.printConfig.header ? printData.printConfig.header.toLowerCase().replace(/[^a-zA-Z0-9]+(.)/g, function (match, chr) {
                            return chr.toUpperCase();
                        }).replace(/^[a-z]/, function (match) {
                            return match.toUpperCase();
                        }) : "";
                        var pageTitle = printData.patient.givenName + printData.patient.familyName + "_" + printData.patient.identifier + "_" + tabName;
                        printer.print(templateUrl, printData, pageTitle);
                    }).catch(function (error) {
                        console.error("Error fetching details for print: ", error);
                    });
                } else {
                    printer.print("../clinical/common/views/formPrint.html", printData);
                }
            };

            return {
                printForm: printForm
            };
        }]);

'use strict';

angular.module('bahmni.common.util')
    .factory('allergyService', ['$http', 'appService', function ($http, appService) {
        var getAllergyForPatient = function (patientUuid) {
            var patientAllergyURL = appService.getAppDescriptor().formatUrl(Bahmni.Common.Constants.patientAllergiesURL, {'patientUuid': patientUuid});
            return $http.get(patientAllergyURL, {
                method: "GET",
                withCredentials: true,
                cache: false
            });
        };

        var fetchAndProcessAllergies = function (patientUuid) {
            return getAllergyForPatient(patientUuid).then(function (response) {
                var allergies = response.data;
                var allergiesList = [];
                if (response.status === 200 && allergies.entry && allergies.entry.length > 0) {
                    allergies.entry.forEach(function (allergy) {
                        if (allergy.resource.code.coding) {
                            allergiesList.push(allergy.resource.code.coding[0].display);
                        }
                    });
                }
                return allergiesList.join(", ");
            });
        };

        return {
            getAllergyForPatient: getAllergyForPatient,
            fetchAndProcessAllergies: fetchAndProcessAllergies
        };
    }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.Custom = Bahmni.Common.DisplayControl.Custom || {};

angular.module('bahmni.common.displaycontrol.custom', []);

'use strict';

angular.module('bahmni.common.displaycontrol.custom')
    .directive('customDisplayControl', [function () {
        return {
            restrict: 'E',
            template: '<div compile-html="config.template"></div>',
            scope: {
                patient: "=",
                visitUuid: "=",
                section: "=",
                config: "=",
                enrollment: "=",
                params: "=",
                visitSummary: '='
            }
        };
    }]);

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Obs = Bahmni.Common.Obs || {};

angular.module('bahmni.common.obs', []);

'use strict';

Bahmni.Common.Obs.Observation = (function () {
    var Observation = function (obs, conceptConfig, $translate, conceptGroupFormatService) {
        angular.extend(this, obs);
        this.concept = obs.concept;
        this.conceptConfig = conceptConfig;
        // translate should be passed for chief complaint data check
        this.translate = $translate;
        this.conceptGroupFormatService = conceptGroupFormatService;
    };

    Observation.prototype = {

        isFormElement: function () {
            return this.groupMembers && this.groupMembers.length <= 0;
        },

        isImageConcept: function () {
            return this.concept.conceptClass === "Image";
        },
        isVideoConcept: function () {
            return this.concept.conceptClass === "Video";
        },

        hasPDFAsValue: function () {
            return (this.value.indexOf(".pdf") > 0);
        },

        isComplexConcept: function () {
            return this.concept.dataType === "Complex";
        },

        getComplexDataType: function () {
            return this.complexData ? this.complexData.dataType : null;
        },

        isLocationRef: function () {
            return this.isComplexConcept() && this.getComplexDataType() === "Location";
        },

        isProviderRef: function () {
            return this.isComplexConcept() && this.getComplexDataType() === "Provider";
        },

        isConceptClassConceptDetails: function () {
            return this.concept.conceptClass === "Concept Details";
        },
        getNewFormatFileNameSeparator: function () {
            // we are using this to separate random characters (patientID, uuid) and actual file name when saving the files in the new format
            return '__';
        },
        isFileNameOfNewFormat: function () {
            return this.getDisplayValue().lastIndexOf(this.getNewFormatFileNameSeparator()) > -1;
        },
        getDisplayFileName: function () {
            var displayValue = this.getDisplayValue();
            return this.isFileNameOfNewFormat() ? displayValue.substring(displayValue.lastIndexOf(this.getNewFormatFileNameSeparator()) + this.getNewFormatFileNameSeparator().length) : displayValue;
        },
        getChiefComplaintCodedComment: function () {
            if (this.isConceptNameChiefComplaintData()) {
                return this.groupMembers[0].comment;
            }
            return '';
        },
        isConceptNameChiefComplaintData: function () {
            // checks if the concept name  is Chief complaint data conceptset and it is part of form
            return this.groupMembers.length > 1 && this.formNamespace != null && this.translate && this.concept.name === this.translate.instant("CHIEF_COMPLAINT_DATA_CONCEPT_NAME_KEY");
        },
        isObsGroupFormatted: function () {
            return this.conceptGroupFormatService !== undefined && this.conceptGroupFormatService.isObsGroupFormatted(this);
        },
        getDisplayValue: function () {
            var value;
            if (this.type === "Boolean" || this.concept && this.concept.dataType === "Boolean") {
                return this.value === true ? "OBS_BOOLEAN_YES_KEY" : "OBS_BOOLEAN_NO_KEY";
            }
            if (this.type === "Datetime" || this.concept && this.concept.dataType === "Datetime") {
                var date = Bahmni.Common.Util.DateUtil.parseDatetime(this.value);
                return date != null ? Bahmni.Common.Util.DateUtil.formatDateWithTime(date) : "";
            }
            if (this.conceptConfig && this.conceptConfig.displayMonthAndYear) {
                value = Bahmni.Common.Util.DateUtil.getDateInMonthsAndYears(this.value);
                if (value != null) {
                    return value;
                }
            }
            if (this.type === "Date" || this.concept && this.concept.dataType === "Date") {
                return this.value ? Bahmni.Common.Util.DateUtil.formatDateWithoutTime(this.value) : "";
            }

            if (this.isLocationRef()) {
                return this.complexData.display;
            }

            if (this.isProviderRef()) {
                return this.complexData.display;
            }

            if (this.groupMembers.length <= 0) {
                value = this.value;
                var displayValue = value && (value.shortName || (value.name && (value.name.name || value.name)) || value);
                if (this.duration) {
                    displayValue = displayValue + " " + this.getDurationDisplayValue();
                }
                return displayValue;
            }

            return this.conceptGroupFormatService !== undefined && this.conceptGroupFormatService.groupObs(this);
        },

        getDurationDisplayValue: function () {
            var durationForDisplay = Bahmni.Common.Util.DateUtil.convertToUnits(this.duration);
            return "since " + durationForDisplay["value"] + " " + durationForDisplay["unitName"];
        }
    };

    return Observation;
})();


'use strict';

Bahmni.Common.Obs.MultiSelectObservation = (function () {
    var MultiSelectObservation = function (groupMembers, conceptConfig) {
        this.type = "multiSelect";
        this.concept = groupMembers[0].concept;
        this.encounterDateTime = groupMembers[0].encounterDateTime;
        this.groupMembers = groupMembers;
        this.conceptConfig = conceptConfig;
        this.observationDateTime = getLatestObservationDateTime(this.groupMembers);
        this.providers = groupMembers[0].providers;
        this.creatorName = groupMembers[0].creatorName;
    };
    var getLatestObservationDateTime = function (groupMembers) {
        var latestObservationDateTime = groupMembers[0].observationDateTime;
        groupMembers.forEach(function (member) {
            latestObservationDateTime = latestObservationDateTime < member.observationDateTime ? member.observationDateTime : latestObservationDateTime;
        });
        return latestObservationDateTime;
    };

    MultiSelectObservation.prototype = {

        isFormElement: function () {
            return true;
        },

        getDisplayValue: function () {
            var getName = Bahmni.Common.Domain.ObservationValueMapper.getNameFor["Object"];
            return _.map(this.groupMembers, getName).join(", ");
        }
    };

    return MultiSelectObservation;
})();

'use strict';

Bahmni.Common.Obs.GridObservation = (function () {
    var conceptMapper = new Bahmni.Common.Domain.ConceptMapper();

    var GridObservation = function (obs, conceptConfig) {
        angular.extend(this, obs);
        this.type = "grid";
        this.conceptConfig = conceptConfig;
    };

    var getObservationDisplayValue = function (observation) {
        if (observation.isBoolean || observation.type === "Boolean") {
            return observation.value === true ? "OBS_BOOLEAN_YES_KEY" : "OBS_BOOLEAN_NO_KEY";
        }
        if (!observation.value) {
            return "";
        }
        if (typeof observation.value.name === 'object') {
            var valueConcept = conceptMapper.map(observation.value);
            return valueConcept.shortName || valueConcept.name;
        }
        return observation.value.shortName || observation.value.name || observation.value;
    };

    GridObservation.prototype = {

        isFormElement: function () {
            return true;
        },

        getDisplayValue: function () {
            var gridObservationDisplayValue = _.compact(_.map(this.groupMembers, function (member) {
                return getObservationDisplayValue(member);
            })).join(', ');
            return gridObservationDisplayValue || this.value;
        }
    };

    return GridObservation;
})();

'use strict';

Bahmni.Common.Obs.ImageObservation = function (observation, concept, provider) {
    this.concept = concept;
    this.imageObservation = observation;
    this.dateTime = observation.observationDateTime;
    this.provider = provider;
};

'use strict';

Bahmni.Common.Obs.ObservationMapper = function () {
    var conceptMapper = new Bahmni.Common.Domain.ConceptMapper();

    this.map = function (bahmniObservations, allConceptsConfig, dontSortByObsDateTime, $translate, conceptGroupFormatService) {
        var mappedObservations = mapObservations(bahmniObservations, allConceptsConfig, dontSortByObsDateTime, $translate, conceptGroupFormatService);
        return mapUIObservations(mappedObservations, allConceptsConfig);
    };

    var mapObservations = function (bahmniObservations, allConceptsConfig, dontSortByObsDateTime, $translate, conceptGroupFormatService) {
        var mappedObservations = [];
        if (dontSortByObsDateTime) {
            bahmniObservations = _.flatten(bahmniObservations);
        } else {
            bahmniObservations = Bahmni.Common.Obs.ObservationUtil.sortSameConceptsWithObsDateTime(bahmniObservations);
        }
        $.each(bahmniObservations, function (i, bahmniObservation) {
            var conceptConfig = bahmniObservation.formFieldPath ? [] : allConceptsConfig[bahmniObservation.concept.name] || [];
            var observation = new Bahmni.Common.Obs.Observation(bahmniObservation, conceptConfig, $translate, conceptGroupFormatService);
            if (observation.groupMembers && observation.groupMembers.length >= 0) {
                observation.groupMembers = mapObservations(observation.groupMembers, allConceptsConfig, dontSortByObsDateTime, $translate, conceptGroupFormatService);
            }
            mappedObservations.push(observation);
        });
        return mappedObservations;
    };

    var mapUIObservations = function (observations, allConceptsConfig) {
        var groupedObservations = _.groupBy(observations, function (observation) {
            return observation.formFieldPath + "#" + observation.concept.name;
        });
        var mappedObservations = [];
        $.each(groupedObservations, function (i, obsGroup) {
            var conceptConfig = obsGroup[0].formFieldPath ? [] : allConceptsConfig[obsGroup[0].concept.name] || [];
            if (conceptConfig.multiSelect) {
                var multiSelectObservations = {};
                $.each(obsGroup, function (i, observation) {
                    if (multiSelectObservations[observation.encounterDateTime]) {
                        multiSelectObservations[observation.encounterDateTime].push(observation);
                    } else {
                        var observations = [];
                        observations.push(observation);
                        multiSelectObservations[observation.encounterDateTime] = observations;
                    }
                });
                $.each(multiSelectObservations, function (i, observations) {
                    mappedObservations.push(new Bahmni.Common.Obs.MultiSelectObservation(observations, conceptConfig));
                });
            } else if (conceptConfig.grid) {
                mappedObservations.push(new Bahmni.Common.Obs.GridObservation(obsGroup[0], conceptConfig));
            } else {
                $.each(obsGroup, function (i, obs) {
                    obs.groupMembers = mapUIObservations(obs.groupMembers, allConceptsConfig);
                    mappedObservations.push(obs);
                });
            }
        });
        return mappedObservations;
    };

    this.getGridObservationDisplayValue = function (observationTemplate) {
        var memberValues = _.compact(_.map(observationTemplate.bahmniObservations, function (observation) {
            return getObservationDisplayValue(observation);
        }));
        return memberValues.join(', ');
    };

    var getObservationDisplayValue = function (observation) {
        if (observation.isBoolean || observation.type === "Boolean") {
            return observation.value === true ? "Yes" : "No";
        }
        if (!observation.value) {
            return "";
        }
        if (typeof observation.value.name === 'object') {
            var valueConcept = conceptMapper.map(observation.value);
            return valueConcept.shortName || valueConcept.name;
        }
        return observation.value.shortName || observation.value.name || observation.value;
    };
};

'use strict';

angular.module('bahmni.common.obs')
    .directive('showObservation', ['ngDialog', function (ngDialog) {
        var controller = function ($scope, $rootScope, $filter) {
            $scope.toggle = function (observation) {
                observation.showDetails = !observation.showDetails;
            };

            $scope.print = $rootScope.isBeingPrinted || false;

            $scope.dateString = function (observation) {
                var filterName;
                if ($scope.showDate && $scope.showTime) {
                    filterName = 'bahmniDateTime';
                } else if (!$scope.showDate && ($scope.showTime || $scope.showTime === undefined)) {
                    filterName = 'bahmniTime';
                } else {
                    return null;
                }
                return $filter(filterName)(observation.observationDateTime);
            };
            $scope.openVideoInPopup = function (observation) {
                ngDialog.open({
                    template: "../common/obs/views/showVideo.html",
                    closeByDocument: false,
                    className: 'ngdialog-theme-default',
                    showClose: true,
                    data: {
                        observation: observation
                    }
                });
            };
            $scope.displayLabel = function (observation) {
                if ($scope.displayNameType === 'FSN') {
                    return observation.concept.name;
                } else {
                    return (observation.concept.shortName.charAt(0).toUpperCase() + observation.concept.shortName.slice(1)) || observation.concept.name;
                }
            };
        };
        return {
            restrict: 'E',
            scope: {
                observation: "=?",
                patient: "=",
                showDate: "=?",
                showTime: "=?",
                showDetailsButton: "=?",
                configIsObservationForImages: "=?",
                displayNameType: "=?"
            },
            controller: controller,
            template: function (element, attrs) {
                if (attrs.templateURL) {
                    return '<ng-include src="' + attrs.templateURL + '" />';
                } else {
                    return '<ng-include src="\'../common/obs/views/showObservation.html\'" />';
                }
            }
        };
    }]);

'use strict';

Bahmni.Common.Obs.ObservationUtil = (function () {
    var sortSameConceptsWithObsDateTime = function (observation) {
        var sortedObservations = [];
        for (var i = 0; i < observation.length; i++) {
            if (i !== observation.length - 1) {
                if (observation[i].conceptUuid !== observation[i + 1].conceptUuid) {
                    sortedObservations.push(observation[i]);
                } else {
                    var sameConceptsSubArray = [];
                    var j = i + 1;
                    sameConceptsSubArray.push(observation[i]);
                    while (j < observation.length && observation[i].conceptUuid === observation[j].conceptUuid) {
                        sameConceptsSubArray.push(observation[j++]);
                    }
                    sameConceptsSubArray = _.sortBy(sameConceptsSubArray, 'observationDateTime');
                    sortedObservations.push(sameConceptsSubArray);
                    i = j - 1;
                }
            } else {
                sortedObservations.push(observation[i]);
            }
        }
        return _.flatten(sortedObservations);
    };

    var getValue = function (observation) {
        if (observation.selectedObs) {
            return observation.getValues();
        }
        var obsValue;
        if (observation.value && observation.value.name && observation.value.name.name) {
            obsValue = observation.value.name.name;
        } else if (observation.value && observation.value.name && !observation.value.name.name) {
            obsValue = observation.value.name;
        } else {
            obsValue = observation.value;
        }

        return (obsValue === undefined || obsValue === null) ? obsValue : (obsValue.displayString || obsValue);
    };

    var collect = function (flattenedObservations, key, value) {
        if (value != undefined) {
            flattenedObservations[key] = flattenedObservations[key] ? _.uniq(_.flatten(_.union([flattenedObservations[key]], [value]))) : value;
        }
    };

    var findLeafObservations = function (flattenedObservations, observation) {
        if (!_.isEmpty(observation.groupMembers)) {
            _.each(observation.groupMembers, function (member) {
                findLeafObservations(flattenedObservations, member);
            });
        } else {
            collect(flattenedObservations, observation.concept.name, getValue(observation));
        }
    };

    var flatten = function (observation) {
        var flattenedObservation = {};
        if (!_.isEmpty(observation)) {
            findLeafObservations(flattenedObservation, observation);
        }
        return flattenedObservation;
    };

    var flattenObsToArray = function (observations) {
        var flattened = [];
        flattened.push.apply(flattened, observations);
        observations.forEach(function (obs) {
            if (obs.groupMembers && obs.groupMembers.length > 0) {
                flattened.push.apply(flattened, flattenObsToArray(obs.groupMembers));
            }
        });
        return flattened;
    };

    return {
        sortSameConceptsWithObsDateTime: sortSameConceptsWithObsDateTime,
        flatten: flatten,
        flattenObsToArray: flattenObsToArray
    };
})();

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.hint = Bahmni.Common.DisplayControl.hint || {};

angular.module('bahmni.common.displaycontrol.hint', []);

'use strict';

angular.module('bahmni.common.displaycontrol.hint')
    .directive('hint', [
        function () {
            var link = function ($scope) {
                $scope.hintForNumericConcept = Bahmni.Common.Domain.Helper.getHintForNumericConcept($scope.conceptDetails);
            };

            return {
                restrict: 'E',
                link: link,
                template: '<small class="hint" ng-if="::hintForNumericConcept">{{::hintForNumericConcept}}</small>',
                scope: {
                    conceptDetails: "="
                }
            };
        }]);

'use strict';

Bahmni.Common.Domain.Diagnosis = function (codedAnswer, order, certainty, existingObsUuid, freeTextAnswer, diagnosisDateTime, voided) {
    var self = this;
    self.codedAnswer = codedAnswer;
    self.order = order;
    self.certainty = certainty;
    self.existingObs = existingObsUuid;
    self.freeTextAnswer = freeTextAnswer;
    self.diagnosisDateTime = diagnosisDateTime;
    self.diagnosisStatus = undefined;
    self.isNonCodedAnswer = false;
    if (self.codedAnswer) {
        self.conceptName = self.codedAnswer.name;
    }
    self.voided = voided;
    self.firstDiagnosis = null;
    self.comments = "";

    self.getDisplayName = function () {
        if (self.freeTextAnswer) {
            return self.freeTextAnswer;
        } else {
            return self.codedAnswer.shortName || self.codedAnswer.name;
        }
    };

    self.isPrimary = function () {
        return self.order == "PRIMARY";
    };

    self.isSecondary = function () {
        return self.order == "SECONDARY";
    };

    self.isRuledOut = function () {
        return self.diagnosisStatus == $rootScope.diagnosisStatus;
    };

    self.answerNotFilled = function () {
        return !self.codedAnswer.name;
    };

    self.isValidAnswer = function () {
        return (self.codedAnswer.name && self.codedAnswer.uuid) ||
            (self.codedAnswer.name && !self.codedAnswer.uuid && self.isNonCodedAnswer) ||
            self.answerNotFilled();
    };
    self.isValidOrder = function () {
        return self.isEmpty() || self.order !== undefined;
    };

    self.isValidCertainty = function () {
        return self.isEmpty() || self.certainty !== undefined;
    };

    self.isEmpty = function () {
        return self.getDisplayName() === undefined || self.getDisplayName().length === 0;
    };

    self.diagnosisStatusValue = null;
    self.diagnosisStatusConcept = null;
    Object.defineProperty(this, 'diagnosisStatus', {
        get: function () {
            return this.diagnosisStatusValue;
        },
        set: function (newStatus) {
            if (newStatus) {
                this.diagnosisStatusValue = newStatus;
                this.diagnosisStatusConcept = { name: Bahmni.Common.Constants.ruledOutdiagnosisStatus};
            } else {
                this.diagnosisStatusValue = null;
                this.diagnosisStatusConcept = null;
            }
        }
    });

    self.clearCodedAnswerUuid = function () {
        self.codedAnswer.uuid = undefined;
    };

    self.setAsNonCodedAnswer = function () {
        self.isNonCodedAnswer = !self.isNonCodedAnswer;
    };
};

'use strict';

Bahmni.DiagnosisMapper = function (diagnosisStatus) {
    var self = this;

    var mapDiagnosis = function (diagnosis) {
        if (!diagnosis.codedAnswer) {
            diagnosis.codedAnswer = {
                name: undefined,
                uuid: undefined
            };
        }
        var mappedDiagnosis = angular.extend(new Bahmni.Common.Domain.Diagnosis(), diagnosis);
        if (mappedDiagnosis.firstDiagnosis) {
            mappedDiagnosis.firstDiagnosis = mapDiagnosis(mappedDiagnosis.firstDiagnosis);
        }
        if (mappedDiagnosis.latestDiagnosis) {
            mappedDiagnosis.latestDiagnosis = mapDiagnosis(mappedDiagnosis.latestDiagnosis);
        }

        if (diagnosis.diagnosisStatusConcept) {
            if (Bahmni.Common.Constants.ruledOutdiagnosisStatus === diagnosis.diagnosisStatusConcept.name) {
                mappedDiagnosis.diagnosisStatus = diagnosisStatus;
            }
        }
        return mappedDiagnosis;
    };

    self.mapDiagnosis = mapDiagnosis;

    self.mapDiagnoses = function (diagnoses) {
        var mappedDiagnoses = [];
        _.each(diagnoses, function (diagnosis) {
            mappedDiagnoses.push(mapDiagnosis(diagnosis));
        });
        return mappedDiagnoses;
    };

    self.mapPastDiagnosis = function (diagnoses, currentEncounterUuid) {
        var pastDiagnosesResponse = [];
        diagnoses.forEach(function (diagnosis) {
            if (diagnosis.encounterUuid !== currentEncounterUuid) {
                diagnosis.previousObs = diagnosis.existingObs;
                diagnosis.existingObs = null;
                diagnosis.inCurrentEncounter = undefined;
                pastDiagnosesResponse.push(diagnosis);
            }
        });
        return pastDiagnosesResponse;
    };

    self.mapSavedDiagnosesFromCurrentEncounter = function (diagnoses, currentEncounterUuid) {
        var savedDiagnosesFromCurrentEncounter = [];
        diagnoses.forEach(function (diagnosis) {
            if (diagnosis.encounterUuid === currentEncounterUuid) {
                diagnosis.inCurrentEncounter = true;
                savedDiagnosesFromCurrentEncounter.push(diagnosis);
            }
        });
        return savedDiagnosesFromCurrentEncounter;
    };
};

'use strict';

angular.module('bahmni.common.domain')
    .service('diagnosisService', ['$http', '$rootScope', '$bahmniCookieStore', 'appService', function ($http, $rootScope, $bahmniCookieStore, appService) {
        var self = this;
        this.getAllFor = function (searchTerm, locale) {
            var url = Bahmni.Common.Constants.bahmniapiConceptUrl;
            var parameters = { term: searchTerm, limit: Bahmni.Common.Constants.emrapiDiagnosisLimit };
            if (locale) {
                parameters.locale = locale;
            }
            return $http.get(url, {
                params: parameters
            });
        };

        this.getDiagnoses = function (patientUuid, visitUuid) {
            var url = Bahmni.Common.Constants.bahmniDiagnosisUrl;
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    url = Bahmni.Common.Constants.bahmniDistroDiagnosisUrl;
                }
            }
            return $http.get(url, {
                params: { patientUuid: patientUuid, visitUuid: visitUuid }
            });
        };

        this.getPatientDiagnosis = function (patientUuid) {
            var url = Bahmni.Common.Constants.bahmniDiagnosisUrl;
            return $http.get(url, {
                params: { patientUuid: patientUuid }
            });
        };

        this.deleteDiagnosis = function (obsUuid) {
            var url = Bahmni.Common.Constants.bahmniDeleteDiagnosisUrl;
            return $http.get(url, {
                params: { obsUuid: obsUuid }
            });
        };

        this.getDiagnosisConceptSet = function () {
            return $http.get(Bahmni.Common.Constants.conceptUrl, {
                method: "GET",
                params: {
                    v: 'custom:(uuid,name,setMembers)',
                    code: Bahmni.Common.Constants.diagnosisConceptSet,
                    source: Bahmni.Common.Constants.emrapiConceptMappingSource
                },
                withCredentials: true
            });
        };

        this.getPastAndCurrentDiagnoses = function (patientUuid, encounterUuid) {
            return self.getDiagnoses(patientUuid).then(function (response) {
                var diagnosisMapper = new Bahmni.DiagnosisMapper($rootScope.diagnosisStatus);
                var allDiagnoses = diagnosisMapper.mapDiagnoses(response.data);
                var pastDiagnoses = diagnosisMapper.mapPastDiagnosis(allDiagnoses, encounterUuid);
                var savedDiagnosesFromCurrentEncounter = diagnosisMapper.mapSavedDiagnosesFromCurrentEncounter(allDiagnoses, encounterUuid);
                return {
                    "pastDiagnoses": pastDiagnoses,
                    "savedDiagnosesFromCurrentEncounter": savedDiagnosesFromCurrentEncounter
                };
            });
        };

        this.populateDiagnosisInformation = function (patientUuid, consultation) {
            return this.getPastAndCurrentDiagnoses(patientUuid, consultation.encounterUuid).then(function (diagnosis) {
                consultation.pastDiagnoses = diagnosis.pastDiagnoses;
                consultation.savedDiagnosesFromCurrentEncounter = diagnosis.savedDiagnosesFromCurrentEncounter;
                return consultation;
            });
        };

        this.getPatientDiagnosis = function (patientUuid) {
            var url = Bahmni.Common.Constants.bahmniDiagnosisUrl;
            return $http.get(url, {
                params: { patientUuid: patientUuid }
            });
        };
    }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.Diagnosis = Bahmni.Common.DisplayControl.Diagnosis || {};

angular.module('bahmni.common.displaycontrol.diagnosis', []);

'use strict';

angular.module('bahmni.common.displaycontrol.diagnosis')
.filter('primaryDiagnosisFirst', function () {
    return function (diagnoses) {
        var primaryDiagnoses = _.filter(diagnoses, function (diagnosis) { return diagnosis.isPrimary(); });
        var otherDiagnoses = _.filter(diagnoses, function (diagnosis) { return !diagnosis.isPrimary(); });
        return primaryDiagnoses.concat(otherDiagnoses);
    };
});

'use strict';

angular.module('bahmni.common.displaycontrol.diagnosis')
    .directive('bahmniDiagnosis', ['diagnosisService', '$q', 'spinner', '$rootScope', '$filter', '$translate', 'providerInfoService',
        function (diagnosisService, $q, spinner, $rootScope, $filter, $translate, providerInfoService) {
            var controller = function ($scope) {
                var getAllDiagnosis = function () {
                    return diagnosisService.getDiagnoses($scope.patientUuid, $scope.visitUuid).then(function (response) {
                        var diagnosisMapper = new Bahmni.DiagnosisMapper($rootScope.diagnosisStatus);
                        $scope.allDiagnoses = diagnosisMapper.mapDiagnoses(response.data);
                        if ($scope.showRuledOutDiagnoses == false) {
                            $scope.allDiagnoses = _.filter($scope.allDiagnoses, function (diagnoses) {
                                return diagnoses.diagnosisStatus !== $rootScope.diagnosisStatus;
                            });
                        }
                        providerInfoService.setProvider($scope.allDiagnoses);
                        $scope.isDataPresent = function () {
                            if ($scope.allDiagnoses && $scope.allDiagnoses.length == 0) {
                                $scope.$emit("no-data-present-event");
                                return false;
                            }
                            return true;
                        };
                    });
                };
                $scope.title = $scope.config.title;
                $scope.toggle = function (diagnosis, toggleLatest) {
                    if (toggleLatest) {
                        diagnosis.showDetails = false;
                        diagnosis.showLatestDetails = !diagnosis.showLatestDetails;
                    } else {
                        diagnosis.showLatestDetails = false;
                        diagnosis.showDetails = !diagnosis.showDetails;
                    }
                };

                var getPromises = function () {
                    return [getAllDiagnosis()];
                };

                $scope.isLatestDiagnosis = function (diagnosis) {
                    return diagnosis.latestDiagnosis ? diagnosis.existingObs == diagnosis.latestDiagnosis.existingObs : false;
                };

                $scope.translateDiagnosisLabels = function (key, type) {
                    if (key) {
                        var translationKey = "CLINICAL_DIAGNOSIS_" + type + "_" + key.toUpperCase();
                        var translation = $translate.instant(translationKey);
                        if (translation != translationKey) {
                            return translation;
                        }
                    }
                    return key;
                };

                $scope.initialization = $q.all(getPromises());
            };

            var link = function ($scope, element) {
                spinner.forPromise($scope.initialization, element);
            };

            return {
                restrict: 'E',
                controller: controller,
                link: link,
                templateUrl: function (element, attrs) {
                    if (attrs.templateUrl) {
                        return attrs.templateUrl;
                    } else {
                        return "../common/displaycontrols/diagnosis/views/diagnosisDisplayControl.html";
                    }
                },
                scope: {
                    patientUuid: "=",
                    config: "=",
                    visitUuid: "=?",
                    showRuledOutDiagnoses: "=?",
                    hideTitle: "=?",
                    showLatestDiagnosis: "@showLatestDiagnosis"
                }
            };
        }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.I18n = Bahmni.Common.I18n || {};

angular.module('bahmni.common.i18n', []);

'use strict';

angular.module('bahmni.common.i18n', ['pascalprecht.translate'])
    .provider('$bahmniTranslate', ['$translateProvider', function ($translateProvider) {
        this.init = function (options) {
            var preferredLanguage = window.localStorage["NG_TRANSLATE_LANG_KEY"] || "en";
            $translateProvider.useLoader('mergeLocaleFilesService', options);
            $translateProvider.useSanitizeValueStrategy('escaped');
            $translateProvider.preferredLanguage(preferredLanguage);
            $translateProvider.useLocalStorage();
        };
        this.$get = [function () {
            return $translateProvider;
        }];
    }
    ])
    .filter('titleTranslate', ['$translate', function ($translate) {
        return function (input) {
            if (!input) {
                return input;
            }
            if (input.translationKey) {
                return $translate.instant(input.translationKey);
            }
            if (input.dashboardName) {
                return input.dashboardName;
            }
            if (input.title) {
                return input.title;
            }
            if (input.label) {
                return input.label;
            }
            if (input.display) {
                return input.display;
            }
            return $translate.instant(input);
        };
    }]);

'use strict';

angular.module('bahmni.common.i18n')
    .service('mergeLocaleFilesService', ['$http', '$q', 'mergeService', function ($http, $q, mergeService) {
        return function (options) {
            var baseLocaleUrl = '../i18n/';
            var customLocaleUrl = Bahmni.Common.Constants.rootDir + '/bahmni_config/openmrs/i18n/';

            var loadFile = function (url) {
                return $http.get(url, {withCredentials: true});
            };

            var mergeLocaleFile = function (options) {
                var fileURL = options.app + "/locale_" + options.key + ".json";

                var loadBahmniTranslations = function () {
                    return loadFile(baseLocaleUrl + fileURL).then(function (result) {
                        return result;
                    }, function () {
                        return;
                    });
                };
                var loadCustomTranslations = function () {
                    return loadFile(customLocaleUrl + fileURL).then(function (result) {
                        return result;
                    }, function () {
                        return;
                    });
                };

                var mergeTranslations = function (result) {
                    var baseFileData = result[0] ? result[0].data : undefined;
                    var customFileData = result[1] ? result[1].data : undefined;
                    if (options.shouldMerge || options.shouldMerge === undefined) {
                        return mergeService.merge(baseFileData, customFileData);
                    }
                    return [baseFileData, customFileData];
                };

                return $q.all([loadBahmniTranslations(), loadCustomTranslations()])
                    .then(mergeTranslations);
            };
            return mergeLocaleFile(options);
        };
    }]);

var Bahmni = Bahmni || {};
Bahmni.Registration = Bahmni.Registration || {};
Bahmni.Registration.AttributesConditions = Bahmni.Registration.AttributesConditions || {};

angular.module('bahmni.registration', ['ui.router', 'bahmni.common.config', 'bahmni.common.domain', 'bahmni.common.util',
    'bahmni.common.uiHelper', 'bahmni.common.conceptSet', 'infinite-scroll', 'bahmni.common.patient',
    'bahmni.common.logging', 'pascalprecht.translate']);

'use strict';

angular
    .module('registration', ['ui.router', 'bahmni.registration', 'authentication', 'bahmni.common.config',
        'bahmni.common.appFramework', 'httpErrorInterceptor', 'bahmni.common.photoCapture', 'bahmni.common.obs',
        'bahmni.common.displaycontrol.observation', 'bahmni.common.i18n', 'bahmni.common.displaycontrol.custom',
        'bahmni.common.routeErrorHandler', 'bahmni.common.displaycontrol.pivottable', 'RecursionHelper', 'ngSanitize',
        'bahmni.common.uiHelper', 'bahmni.common.domain', 'ngDialog', 'pascalprecht.translate', 'ngCookies',
        'monospaced.elastic', 'bahmni.common.displaycontrol.hint', 'bahmni.common.attributeTypes',
        'bahmni.common.models', 'bahmni.common.uicontrols',
        'bahmni.common.displaycontrol.diagnosis'])
    .config(['$urlRouterProvider', '$stateProvider', '$httpProvider', '$bahmniTranslateProvider', '$compileProvider', function ($urlRouterProvider, $stateProvider, $httpProvider, $bahmniTranslateProvider, $compileProvider) {
        $httpProvider.defaults.headers.common['Disable-WWW-Authenticate'] = true;
        $urlRouterProvider.otherwise('/search');

        $compileProvider.debugInfoEnabled(false);


        $stateProvider
            .state('search', {
                url: '/search',
                reloadOnSearch: false,
                views: {
                    'layout': {templateUrl: 'views/layout.html', controller: 'SearchPatientController'},
                    'content@search': {templateUrl: 'views/search.html'}
                },
                resolve: {
                    initialize: function (initialization) {
                        return initialization();
                    }
                }
            })
            .state('newpatient', {
                url: '/patient/new',
                views: {
                    'layout': {templateUrl: 'views/layout.html', controller: 'CreatePatientController'},
                    'content@newpatient': {templateUrl: 'views/newpatient.html'}
                },
                resolve: {
                    initialize: function (initialization) {
                        return initialization();
                    }
                }
            })
            .state('patient', {
                url: '/patient/:patientUuid',
                abstract: true,
                views: {
                    'layout': {template: '<div ui-view="layout"></div>'}
                },
                resolve: {
                    initialize: function (initialization) {
                        return initialization();
                    }
                }
            })
            .state('patient.edit', {
                url: '?serverError',
                views: {
                    'layout': {templateUrl: 'views/layout.html', controller: 'EditPatientController'},
                    'content@patient.edit': {templateUrl: 'views/editpatient.html'},
                    'headerExtension@patient.edit': {template: '<div print-options></div>'}
                }
            })
            .state('patient.visit', {
                url: '/visit',
                views: {
                    'layout': {templateUrl: 'views/layout.html', controller: 'VisitController'},
                    'content@patient.visit': {templateUrl: 'views/visit.html'},
                    'headerExtension@patient.visit': {template: '<div print-options></div>'}
                }
            })
            .state('patient.printSticker', {
                url: '/printSticker',
                views: {
                    'layout': {templateUrl: 'views/layout.html'},
                    'content@patient.printSticker': {templateUrl: 'views/notimplemented.html'}
                }
            });
        $bahmniTranslateProvider.init({app: 'registration', shouldMerge: true});
    }]).run(['$rootScope', '$templateCache', '$bahmniCookieStore', 'locationService', 'messagingService', 'auditLogService',
        '$window', function ($rootScope, $templateCache, $bahmniCookieStore, locationService,
              messagingService, auditLogService, $window) {
            var getStates = function (toState, fromState) {
                var states = [];
                if (fromState === "newpatient" && (toState === "patient.edit" || toState === "patient.visit")) {
                    states.push("newpatient.save");
                }
                if (toState === 'patient.edit') {
                    states.push("patient.view");
                } else {
                    states.push(toState);
                }
                return states;
            };
            moment.locale($window.localStorage["NG_TRANSLATE_LANG_KEY"] || "en");
            var loginLocationUuid = $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName).uuid;
            locationService.getVisitLocation(loginLocationUuid).then(function (response) {
                if (response.data) {
                    $rootScope.visitLocation = response.data.uuid;
                }
            });

            $rootScope.$on('$stateChangeStart', function () {
                messagingService.hideMessages("error");
            });

            $rootScope.createAuditLog = function (event, toState, toParams, fromState) {
                var states = getStates(toState.name, fromState.name);
                states.forEach(function (state) {
                    auditLogService.log(toParams.patientUuid, Bahmni.Registration.StateNameEvenTypeMap[state], undefined, "MODULE_LABEL_REGISTRATION_KEY");
                });
            };

            $rootScope.$on('$stateChangeSuccess', $rootScope.createAuditLog);
        }
    ]);

'use strict';

angular.module('bahmni.registration').factory('initialization',
    ['$rootScope', '$q', 'configurations', 'authenticator', 'appService', 'spinner', 'preferences', 'locationService', 'mergeService', '$translate',
        function ($rootScope, $q, configurations, authenticator, appService, spinner, preferences, locationService, mergeService, $translate) {
            var getConfigs = function () {
                var configNames = ['encounterConfig', 'patientAttributesConfig', 'identifierTypesConfig', 'addressLevels', 'genderMap', 'relationshipTypeConfig', 'relationshipTypeMap', 'loginLocationToVisitTypeMapping', 'helpDeskNumber', 'quickLogoutComboKey', 'contextCookieExpirationTimeInMinutes'];
                return configurations.load(configNames).then(function () {
                    var mandatoryPersonAttributes = appService.getAppDescriptor().getConfigValue("mandatoryPersonAttributes");
                    var patientAttributeTypes = new Bahmni.Common.Domain.AttributeTypeMapper().mapFromOpenmrsAttributeTypes(configurations.patientAttributesConfig(), mandatoryPersonAttributes, {}, $rootScope.currentUser.userProperties.defaultLocale);
                    $rootScope.regEncounterConfiguration = angular.extend(new Bahmni.Registration.RegistrationEncounterConfig(), configurations.encounterConfig());
                    $rootScope.encounterConfig = angular.extend(new EncounterConfig(), configurations.encounterConfig());
                    $rootScope.patientConfiguration = new Bahmni.Registration.PatientConfig(patientAttributeTypes.attributeTypes,
                    configurations.identifierTypesConfig(), appService.getAppDescriptor().getConfigValue("patientInformation"),
                    appService.getAppDescriptor().getConfigValue("addressAttributes"));
                    $rootScope.regEncounterConfiguration.loginLocationToVisitTypeMap = configurations.loginLocationToVisitTypeMapping();

                    $rootScope.addressLevels = configurations.addressLevels();
                    $rootScope.fieldValidation = appService.getAppDescriptor().getConfigValue("fieldValidation");
                    $rootScope.genderMap = configurations.genderMap();
                    $rootScope.helpDeskNumber = configurations.helpDeskNumber();
                    Bahmni.Common.Util.GenderUtil.translateGender($rootScope.genderMap, $translate);
                    $rootScope.relationshipTypeMap = configurations.relationshipTypeMap();
                    $rootScope.relationshipTypes = configurations.relationshipTypes();
                    $rootScope.quickLogoutComboKey = configurations.quickLogoutComboKey() || 'Escape';
                    $rootScope.cookieExpiryTime = configurations.contextCookieExpirationTimeInMinutes() || 0;
                });
            };

            var loadValidators = function (baseUrl, contextPath) {
                var script = baseUrl + contextPath + '/fieldValidation.js';
                Bahmni.Common.Util.DynamicResourceLoader.includeJs(script, false);
            };

            var initApp = function () {
                return appService.initApp('registration', {'app': true, 'extension': true });
            };

            var getIdentifierPrefix = function () {
                preferences.identifierPrefix = appService.getAppDescriptor().getConfigValue("defaultIdentifierPrefix");
            };

            var initAppConfigs = function () {
                $rootScope.registration = $rootScope.registration || {};
                getIdentifierPrefix();
            };

            var mapRelationsTypeWithSearch = function () {
                var relationshipTypeMap = $rootScope.relationshipTypeMap || {};
                if (!relationshipTypeMap.provider) {
                    return "patient";
                }
                $rootScope.relationshipTypes.forEach(function (relationshipType) {
                    relationshipType.searchType = (relationshipTypeMap.provider.indexOf(relationshipType.aIsToB) > -1) ? "provider" : "patient";
                });
            };

            var loggedInLocation = function () {
                return locationService.getLoggedInLocation().then(function (location) {
                    $rootScope.loggedInLocation = location;
                });
            };

            var facilityVisitLocation = function () {
                return locationService.getFacilityVisitLocation().then(function (response) {
                    if (response.uuid) {
                        locationService.getByUuid(response.uuid).then(function (location) {
                            $rootScope.facilityVisitLocation = location;
                        });
                    }
                });
            };

            var mergeFormConditions = function () {
                var formConditions = Bahmni.ConceptSet.FormConditions;
                if (formConditions) {
                    formConditions.rules = mergeService.merge(formConditions.rules, formConditions.rulesOverride);
                }
            };

            var checkPrivilege = function () {
                return appService.checkPrivilege("app:registration");
            };

            return function () {
                return spinner.forPromise(authenticator.authenticateUser()
                .then(initApp)
                .then(checkPrivilege)
                .then(getConfigs)
                .then(initAppConfigs)
                .then(mapRelationsTypeWithSearch)
                .then(loggedInLocation)
                .then(facilityVisitLocation)
                .then(loadValidators(appService.configBaseUrl(), "registration"))
                .then(mergeFormConditions)
            );
            };
        }]
);

'use strict';

/* exported defaults */
var defaults = {
    maxAutocompleteResults: 20
};

var Bahmni = Bahmni || {};
Bahmni.Registration = Bahmni.Registration || {};
var hostUrl = Bahmni.Common.Constants.hostURL;
var RESTWS_V1 = hostUrl + "/openmrs/ws/rest/v1";

Bahmni.Registration.Constants = {
    openmrsUrl: hostUrl + "/openmrs",
    registrationEncounterType: "REG",
    baseOpenMRSRESTURL: RESTWS_V1,
    patientImageUrlByPatientUuid: RESTWS_V1 + "/patientImage?patientUuid=",
    bahmniRESTBaseURL: hostUrl + "/openmrs/ws/rest/v1/bahmnicore",
    emrApiRESTBaseURL: hostUrl + "/openmrs/ws/rest/emrapi",
    emrApiEncounterUrl: hostUrl + "/openmrs/ws/rest/emrapi/encounter",
    webServiceRestBaseURL: hostUrl + "/openmrs/ws/rest/v1",
    basePatientUrl: RESTWS_V1 + "/patient/",
    patientSearchURL: "/search",
    existingPatient: "/bahmni/registration/index.html#/patient/",
    newPatient: "/bahmni/registration/index.html#/patient/new",
    allAddressFileds: ["uuid", "preferred", "address1", "address2", "address3", "address4", "address5", "address6", "cityVillage", "countyDistrict", "stateProvince", "postalCode", "country", "latitude", "longitude"],
    nextStepConfigId: "org.bahmni.registration.patient.next",
    patientNameDisplayOrder: ["firstName", "middleName", "lastName"],
    registrationMessage: "REGISTRATION_MESSAGE",
    enableWhatsAppButton: false,
    enableDashboardRedirect: false,
    dashboardUrl: "/bahmni/clinical/index.html#/default/patient/{{patientUuid}}/dashboard",
    certificateHeader: "Print Header"
};

Bahmni.Registration.Constants.Errors = {
    manageIdentifierSequencePrivilege: "You don't have the privilege to create a patient with the given ID."
};

'use strict';

function getWatchers (element) {
    var elementToWatch = element ? angular.element(element) : angular.element(document.getElementsByTagName('body'));

    var watchers = [];

    var f = function (element) {
        angular.forEach(['$scope', '$isolateScope'], function (scopeProperty) {
            if (element.data() && element.data().hasOwnProperty(scopeProperty)) {
                angular.forEach(element.data()[scopeProperty].$$watchers, function (watcher) {
                    watchers.push(watcher);
                });
            }
        });

        angular.forEach(element.children(), function (childElement) {
            f(angular.element(childElement));
        });
    };

    f(elementToWatch);

    // Remove duplicate watchers
    var watchersWithoutDuplicates = [];
    angular.forEach(watchers, function (item) {
        if (watchersWithoutDuplicates.indexOf(item) < 0) {
            watchersWithoutDuplicates.push(item);
        }
    });

    console.log(watchersWithoutDuplicates);
    return watchersWithoutDuplicates;
}

'use strict';

angular.module('bahmni.common.patient')
    .directive('fallbackSrc', function () {
        return {
            restrict: 'A',
            link: function (scope, element, attrs) {
                if (_.isEmpty(attrs.ngSrc)) {
                    element.attr('src', attrs.fallbackSrc);
                }
                element.bind('error', function () {
                    element.attr('src', attrs.fallbackSrc);
                });
            }
        };
    });

'use strict';

angular.module('bahmni.registration')
    .directive('extraPatientIdentifiers', function () {
        return {
            templateUrl: 'views/patientIdentifier.html',
            scope: {
                fieldValidation: '='
            },
            restrict: 'E',
            link: function (scope) {
                scope.controllerScope = scope.$parent;
            }
        };
    });

'use strict';

angular.module('bahmni.registration')
    .directive('addressFields', function () {
        return {
            restrict: 'AE',
            templateUrl: ' views/addressFields.html',
            controller: 'AddressFieldsDirectiveController',
            scope: {
                address: '=',
                addressLevels: '=',
                fieldValidation: '=',
                strictAutocompleteFromLevel: '=',
                handleUpdate: '=',
                addressAttributes: '=',
                getDataResults: '=',
                patient: '='
            }
        };
    })
    .controller('AddressFieldsDirectiveController', ['$scope', 'addressHierarchyService', '$translate', function ($scope, addressHierarchyService, $translate) {
        var addressLevelsCloneInDescendingOrder = $scope.addressLevels.slice(0).reverse();
        $scope.addressLevelsChunks = Bahmni.Common.Util.ArrayUtil.chunk(addressLevelsCloneInDescendingOrder, 2);
        var addressLevelsNamesInDescendingOrder = addressLevelsCloneInDescendingOrder.map(function (addressLevel) {
            return addressLevel.addressField;
        });
        var catchmentAttribute = $scope.patient["Catchment Area"];
        $scope.selectedCatchmentOption = "In";
        var modulePrefixMap = {
            'registration': 'REGISTRATION',
            'program': 'PROGRAM',
            'OT': 'OT'
        };

        $scope.addressHandleUpdate = function () {
            var catchmentAttribute = $scope.patient["Catchment Area"];
            if (catchmentAttribute && catchmentAttribute.value && catchmentAttribute.value.toLowerCase().includes("out")) {
                $scope.selectedCatchmentOption = "Out";
            } else {
                $scope.selectedCatchmentOption = "In";
            }
            $scope.handleUpdate();
        };

        $scope.addressFieldSelected = function (fieldName) {
            return function (addressFieldItem) {
                var parentFields = addressLevelsNamesInDescendingOrder.slice(addressLevelsNamesInDescendingOrder.indexOf(fieldName) + 1);
                $scope.selectedValue[fieldName] = addressFieldItem.addressField.name;
                var parent = addressFieldItem.addressField.parent;
                parentFields.forEach(function (parentField) {
                    if (!parent) {
                        return;
                    }
                    $scope.address[parentField] = parent.name;
                    $scope.selectedValue[parentField] = parent.name;
                    parent = parent.parent;
                });
            };
        };
        $scope.getTranslatedAddressFields = function (address) {
            var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(address, Bahmni.Common.Constants.registration, $translate);
            return translatedName;
        };
        $scope.removeAutoCompleteEntry = function (fieldName) {
            return function () {
                $scope.selectedValue[fieldName] = null;
            };
        };

        $scope.getAddressEntryList = function (field) {
            return function (searchAttrs) {
                return addressHierarchyService.search(field, searchAttrs.term);
            };
        };

        $scope.getAddressDataResults = addressHierarchyService.getAddressDataResults;

        $scope.clearFields = function (fieldName) {
            var childFields = addressLevelsNamesInDescendingOrder.slice(0, addressLevelsNamesInDescendingOrder.indexOf(fieldName));
            childFields.forEach(function (childField) {
                if (!_.isEmpty($scope.selectedValue[childField])) {
                    $scope.address[childField] = null;
                    $scope.selectedValue[childField] = null;
                }
            });
        };
        var init = function () {
            $scope.addressLevels.reverse();
            var isStrictEntry = false;
            _.each($scope.addressLevels, function (addressLevel) {
                addressLevel.isStrictEntry = $scope.strictAutocompleteFromLevel == addressLevel.addressField || isStrictEntry;
                isStrictEntry = addressLevel.isStrictEntry;
            });
            $scope.addressLevels.reverse();

            // wait for address to be resolved in edit patient scenario
            var addressWatch = $scope.$watch('address', function (newValue) {
                if (newValue !== undefined) {
                    $scope.selectedValue = _.mapValues($scope.address, function (value, key) {
                        var addressLevel = _.find($scope.addressLevels, {addressField: key});
                        return addressLevel && addressLevel.isStrictEntry ? value : null;
                    });
                    addressWatch();
                }
            });
        };
        init();
    }]);

'use strict';

angular.module('bahmni.registration')
    .directive('topDownAddressFields', function () {
        return {
            restrict: 'AE',
            templateUrl: 'views/topDownAddressFields.html',
            controller: 'TopDownAddressFieldsDirectiveController',
            scope: {
                address: '=',
                addressLevels: '=',
                fieldValidation: '=',
                strictAutocompleteFromLevel: '='
            }
        };
    })
    .controller('TopDownAddressFieldsDirectiveController', ['$scope', 'addressHierarchyService', '$translate', function ($scope, addressHierarchyService, $translate) {
        $scope.addressFieldInvalid = false;
        var selectedAddressUuids = {};
        var selectedUserGeneratedIds = {};
        var modulePrefixMap = {
            'registration': 'REGISTRATION',
            'program': 'PROGRAM',
            'OT': 'OT'
        };
        var addressLevelsCloneInDescendingOrder = $scope.addressLevels.slice(0).reverse();
        var addressLevelUIOrderBasedOnConfig = $scope.addressLevels;
        $scope.addressLevelsChunks = Bahmni.Common.Util.ArrayUtil.chunk(addressLevelUIOrderBasedOnConfig, 2);
        var addressLevelsNamesInDescendingOrder = addressLevelsCloneInDescendingOrder.map(function (addressLevel) {
            return addressLevel.addressField;
        });

        var populateSelectedAddressUuids = function (levelIndex, parentUuid) {
            if ($scope.addressLevels.length === 0 || !$scope.addressLevels[levelIndex]) {
                return;
            }

            var fieldName = $scope.addressLevels[levelIndex].addressField;
            var addressValue = $scope.address[fieldName];
            if (addressValue) {
                addressHierarchyService.search(fieldName, addressValue, parentUuid).then(function (response) {
                    var address = response && response.data && response.data[0];
                    if (address) {
                        selectedAddressUuids[fieldName] = address.uuid;
                        selectedUserGeneratedIds[fieldName] = address.userGeneratedId;
                        populateSelectedAddressUuids(levelIndex + 1, address.uuid);
                    }
                });
            }
        };
        $scope.getTranslatedTopAddress = function (address) {
            var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(address, Bahmni.Common.Constants.registration, $translate);
            return translatedName;
        };
        $scope.addressFieldSelected = function (fieldName) {
            return function (addressFieldItem) {
                selectedAddressUuids[fieldName] = addressFieldItem.addressField.uuid;
                selectedUserGeneratedIds[fieldName] = addressFieldItem.addressField.userGeneratedId;
                $scope.selectedValue[fieldName] = addressFieldItem.addressField.name;
                var parentFields = addressLevelsNamesInDescendingOrder.slice(addressLevelsNamesInDescendingOrder.indexOf(fieldName) + 1);
                var parent = addressFieldItem.addressField.parent;
                parentFields.forEach(function (parentField) {
                    if (!parent) {
                        return;
                    }
                    $scope.address[parentField] = parent.name;
                    $scope.selectedValue[parentField] = parent.name;
                    parent = parent.parent;
                });
            };
        };

        $scope.findParentField = function (fieldName) {
            var found = _.find($scope.addressLevels, {addressField: fieldName});
            var index = _.findIndex($scope.addressLevels, found);
            var parentFieldName;
            var topLevel = 0;
            if (index !== topLevel) {
                var parent = $scope.addressLevels[index - 1];
                parentFieldName = parent.addressField;
            }
            return parentFieldName;
        };

        $scope.isReadOnly = function (addressLevel) {
            if (!$scope.address) {
                return false;
            }
            if (!addressLevel.isStrictEntry) {
                return false;
            }
            var fieldName = addressLevel.addressField;
            var parentFieldName = $scope.findParentField(fieldName);
            var parentValue = $scope.address[parentFieldName];
            var parentValueInvalid = isParentValueInvalid(parentFieldName);
            if (!parentFieldName) {
                return false;
            }
            if (parentFieldName && !parentValue) {
                return true;
            }
            return parentFieldName && parentValue && parentValueInvalid;
        };

        var isParentValueInvalid = function (parentId) {
            return angular.element($("#" + parentId)).hasClass('illegalValue');
        };

        var parentUuid = function (field) {
            return selectedAddressUuids[$scope.findParentField(field)];
        };

        $scope.getAddressEntryList = function (field) {
            return function (searchAttrs) {
                return addressHierarchyService.search(field, searchAttrs.term, parentUuid(field));
            };
        };

        $scope.getAddressDataResults = addressHierarchyService.getAddressDataResults;

        $scope.clearFields = function (fieldName) {
            var childFields = addressLevelsNamesInDescendingOrder.slice(0, addressLevelsNamesInDescendingOrder.indexOf(fieldName));
            childFields.forEach(function (childField) {
                if ($scope.selectedValue[childField] !== null) {
                    $scope.address[childField] = null;
                    $scope.selectedValue[childField] = null;
                    selectedAddressUuids[childField] = null;
                    selectedUserGeneratedIds[childField] = null;
                }
            });

            if (_.isEmpty($scope.address[fieldName])) {
                $scope.address[fieldName] = null;
                selectedUserGeneratedIds[fieldName] = null;
            }
        };

        $scope.removeAutoCompleteEntry = function (fieldName) {
            return function () {
                $scope.selectedValue[fieldName] = null;
            };
        };

        var init = function () {
            $scope.addressLevels.reverse();
            var isStrictEntry = false;
            _.each($scope.addressLevels, function (addressLevel) {
                addressLevel.isStrictEntry = $scope.strictAutocompleteFromLevel == addressLevel.addressField || isStrictEntry;
                isStrictEntry = addressLevel.isStrictEntry;
            });
            $scope.addressLevels.reverse();

            // wait for address to be resolved in edit patient scenario
            var deregisterAddressWatch = $scope.$watch('address', function (newValue) {
                if (newValue !== undefined) {
                    populateSelectedAddressUuids(0);
                    $scope.selectedValue = _.mapValues($scope.address, function (value, key) {
                        var addressLevel = _.find($scope.addressLevels, {addressField: key});
                        return addressLevel && addressLevel.isStrictEntry ? value : null;
                    });
                    deregisterAddressWatch();
                }
            });
        };
        init();
    }]);

'use strict';

angular.module('bahmni.registration')
    .directive('printOptions', ['$rootScope', 'registrationCardPrinter', 'spinner', 'appService', '$filter',
        function ($rootScope, registrationCardPrinter, spinner, appService, $filter) {
            var controller = function ($scope) {
                $scope.printOptions = appService.getAppDescriptor().getConfigValue("printOptions");
                $scope.defaultPrint = $scope.printOptions && $scope.printOptions[0];

                var mapRegistrationObservations = function () {
                    var obs = {};
                    $scope.observations = $scope.observations || [];
                    var getValue = function (observation) {
                        obs[observation.concept.name] = obs[observation.concept.name] || [];
                        observation.value && obs[observation.concept.name].push(observation.value);
                        observation.groupMembers.forEach(getValue);
                    };

                    $scope.observations.forEach(getValue);
                    return obs;
                };

                $scope.print = function (option) {
                    var location = $rootScope.facilityVisitLocation ? $rootScope.facilityVisitLocation : $rootScope.loggedInLocation;
                    var locationAddress = "";
                    var attributeDisplay = location.attributes[0] ? location.attributes[0].display.split(": ") : null;
                    if (attributeDisplay && attributeDisplay[0] === Bahmni.Registration.Constants.certificateHeader) {
                        locationAddress = attributeDisplay[1];
                    }
                    return registrationCardPrinter.print(option.templateUrl, $scope.patient, mapRegistrationObservations(), $scope.encounterDateTime, { "name": location.name, "address": locationAddress });
                };

                $scope.buttonText = function (option, type) {
                    var printHtml = "";
                    var optionValue = option && $filter('titleTranslate')(option);
                    if (type) {
                        printHtml = '<i class="fa fa-print"></i>';
                    }
                    return '<span>' + optionValue + '</span>' + printHtml;
                };
            };

            return {
                restrict: 'A',
                templateUrl: 'views/printOptions.html',
                controller: controller
            };
        }]);

'use strict';

angular.module('bahmni.registration')
    .directive('patientRelationship', function () {
        return {
            restrict: 'AE',
            templateUrl: 'views/patientRelationships.html',
            controller: 'PatientRelationshipController',
            scope: {
                patient: "="
            }
        };
    })
    .controller('PatientRelationshipController', ['$window', '$scope', '$rootScope', 'spinner', 'patientService', 'providerService', 'appService', '$q',
        function ($window, $scope, $rootScope, spinner, patientService, providerService, appService, $q) {
            $scope.addPlaceholderRelationship = function () {
                $scope.patient.newlyAddedRelationships.push({});
            };

            $scope.removeRelationship = function (relationship, index) {
                if (relationship.uuid) {
                    relationship.voided = true;
                    $scope.patient.deletedRelationships.push(relationship);
                } else {
                    $scope.patient.newlyAddedRelationships.splice(index, 1);
                }
            };

            $scope.isPatientRelationship = function (relationship) {
                var relationshipType = getRelationshipType(relationship);
                return relationshipType && (_.isUndefined(relationshipType.searchType) || relationshipType.searchType === "patient");
            };

            var getRelationshipType = function (relationship) {
                if (angular.isUndefined(relationship['relationshipType'])) {
                    return false;
                }
                return $scope.getRelationshipType(relationship.relationshipType.uuid);
            };

            $scope.getChosenRelationshipType = function (relation) {
                if ($scope.isPatientRelationship(relation)) {
                    return "patient";
                } else if ($scope.isProviderRelationship(relation)) {
                    return "provider";
                }
            };

            $scope.isProviderRelationship = function (relationship) {
                var relationshipType = getRelationshipType(relationship);
                return relationshipType && relationshipType.searchType === "provider";
            };

            $scope.getRelationshipType = function (uuid) {
                return _.find($scope.relationshipTypes, {uuid: uuid});
            };

            $scope.getRelationshipTypeForDisplay = function (relationship) {
                var personUuid = $scope.patient.uuid;
                var relationshipType = $scope.getRelationshipType(relationship.relationshipType.uuid);
                if (!relationship.personA) {
                    return "";
                }
                if (relationship.personA.uuid === personUuid) {
                    return relationshipType.aIsToB;
                } else {
                    return relationshipType.bIsToA;
                }
            };

            $scope.getRelatedToPersonForDisplay = function (relationship) {
                var personRelatedTo = getPersonRelatedTo(relationship);
                return personRelatedTo ? personRelatedTo.display : "";
            };

            var getName = function (patient) {
                return patient.givenName + (patient.middleName ? " " + patient.middleName : "") +
                    (patient.familyName ? " " + patient.familyName : "");
            };

            var getPersonB = function (personName, personUuid) {
                return {'display': personName, 'uuid': personUuid};
            };
            $scope.searchByPatientIdentifier = function (relationship) {
                if (!relationship.patientIdentifier) {
                    relationship.personB = null;
                    relationship.content = null;
                    return;
                }
                if (relationship.hasOwnProperty('personB')) {
                    relationship.personB = null;
                }
                return patientService.searchByIdentifier(relationship.patientIdentifier).then(function (response) {
                    if (angular.isUndefined(response)) {
                        return;
                    }

                    var patients = response.data.pageOfResults;
                    if (patients.length === 0) {
                        return;
                    }
                    relationship.content = getPatientGenderAndAge(patients[0]);
                    var personUuid = patients[0]['uuid'];
                    var personName = getName(patients[0]);

                    relationship.personB = getPersonB(personName, personUuid);
                });
            };

            $scope.showPersonNotFound = function (relationship) {
                return (relationship.patientIdentifier && !relationship.personB) &&
                    $scope.getChosenRelationshipType(relationship) !== 'patient';
            };

            $scope.isInvalidRelation = function (relation) {
                return _.isEmpty(_.get(relation, "personB.uuid")) || $scope.duplicateRelationship(relation);
            };

            $scope.duplicateRelationship = function (relationship) {
                if (_.isEmpty(relationship.relationshipType) || _.isEmpty(relationship.personB)) {
                    return false;
                }
                var existingRelatives = getAlreadyAddedRelationshipPersonUuid($scope.patient, relationship.relationshipType.uuid);
                return _.get(_.countBy(existingRelatives, _.identity), relationship.personB.uuid, 0) > 1;
            };

            var getPersonRelatedTo = function (relationship) {
                return relationship.personA && relationship.personA.uuid === $scope.patient.uuid ? relationship.personB : relationship.personA;
            };

            $scope.openPatientDashboardInNewTab = function (relationship) {
                var personRelatedTo = getPersonRelatedTo(relationship);
                $window.open(getPatientRegistrationUrl(personRelatedTo.uuid), '_blank');
            };

            var getPatientRegistrationUrl = function (patientUuid) {
                return '#/patient/' + patientUuid;
            };

            $scope.getProviderList = function () {
                return function (searchAttrs) {
                    return providerService.search(searchAttrs.term);
                };
            };

            $scope.providerSelected = function (relationship) {
                return function (providerData) {
                    relationship.providerName = providerData.identifier;
                    relationship.personB = getPersonB(providerData.identifier, providerData.uuid);
                };
            };

            var clearPersonB = function (relationship, fieldName) {
                if (!relationship[fieldName]) {
                    delete relationship.personB;
                }
            };

            var getDeletedRelationshipUuids = function (patient, relationTypeUuid) {
                return getPersonUuidsForRelationship(patient.deletedRelationships, relationTypeUuid);
            };

            var getNewlyAddedRelationshipPersonUuid = function (patient, relationTypeUuid) {
                return getPersonUuidsForRelationship(patient.newlyAddedRelationships, relationTypeUuid);
            };

            var getPersonUuidsForRelationship = function (relationships, relationshipTypeUuid) {
                var uuids = [];
                _.each(relationships, function (relationship) {
                    if (relationship.personB && relationship.relationshipType.uuid === relationshipTypeUuid) {
                        uuids.push(relationship.personB.uuid);
                    }
                });

                return uuids;
            };

            var getAlreadyAddedRelationshipPersonUuid = function (patient, relationTypeUuid) {
                var personUuids = _.concat(getPersonUuidsForRelationship(patient.relationships, relationTypeUuid),
                    getNewlyAddedRelationshipPersonUuid(patient, relationTypeUuid));

                return _.difference(personUuids, getDeletedRelationshipUuids(patient, relationTypeUuid));
            };

            $scope.clearProvider = function (relationship) {
                clearPersonB(relationship, 'providerName');
            };

            var getLimit = function (configName, defaultValue) {
                return appService.getAppDescriptor().getConfigValue(configName) || defaultValue;
            };

            $scope.searchByPatientIdentifierOrName = function (searchAttrs) {
                var term = searchAttrs.term;
                if (term && term.length >= getLimit("minCharRequireToSearch", 1)) {
                    return patientService.searchByNameOrIdentifier(term, getLimit("possibleRelativeSearchLimit", Bahmni.Common.Constants.defaultPossibleRelativeSearchLimit));
                }
                return $q.when();
            };

            $scope.clearPatient = function (relationship) {
                clearPersonB(relationship, 'patientIdentifier');
            };

            $scope.patientSelected = function (relationship) {
                return function (patientData) {
                    relationship.patientIdentifier = patientData.identifier;
                    relationship.personB = getPersonB(patientData.value, patientData.uuid);
                };
            };

            $scope.getPatientList = function (response) {
                if (angular.isUndefined(response)) {
                    return;
                }
                return response.data.pageOfResults.map(function (patient) {
                    return {
                        value: getName(patient) + " - " + patient.identifier,
                        uuid: patient.uuid,
                        identifier: patient.identifier
                    };
                });
            };

            $scope.getProviderDataResults = function (data) {
                return data.data.results.filter(function (provider) {
                    return provider.person;
                })
                    .map(function (providerDetails) {
                        return {
                            'value': providerDetails.display || providerDetails.person.display,
                            'uuid': providerDetails.person.uuid,
                            'identifier': providerDetails.identifier || providerDetails.person.display
                        };
                    });
            };

            $scope.onEdit = function (relationship) {
                return function () {
                    delete relationship.personB;
                };
            };

            $scope.clearRelationshipRow = function (relationship, index) {
                delete relationship.personB;
                delete relationship.patientIdentifier;
                delete relationship.providerName;
                delete relationship.endDate;
                delete relationship.content;
                managePlaceholderRelationshipRows(index);
            };

            var managePlaceholderRelationshipRows = function (index) {
                var iter;
                for (iter = 0; iter < $scope.patient.newlyAddedRelationships.length; iter++) {
                    if ($scope.isEmpty($scope.patient.newlyAddedRelationships[iter]) && iter !== index) {
                        $scope.patient.newlyAddedRelationships.splice(iter, 1);
                    }
                }

                var emptyRows = _.filter($scope.patient.newlyAddedRelationships, $scope.isEmpty);
                if (emptyRows.length === 0) {
                    $scope.addPlaceholderRelationship();
                }
            };

            $scope.isEmpty = function (relationship) {
                return !relationship.relationshipType || !relationship.relationshipType.uuid;
            };

            var getPatientGenderAndAge = function (patient) {
                var patientGenderAndAge = [patient.givenName, patient.age, $rootScope.genderMap[angular.uppercase(patient.gender)]];
                return patientGenderAndAge.join(", ");
            };

            var init = function () {
                $scope.relationshipTypes = $rootScope.relationshipTypes;
                $scope.patient.relationships = $scope.patient.relationships || [];
            };

            init();
        }
    ]);

'use strict';

angular.module('bahmni.registration')
    .controller('NavigationController', ['$scope', '$rootScope', '$location', 'sessionService', '$window', 'appService', '$sce',
        function ($scope, $rootScope, $location, sessionService, $window, appService, $sce) {
            $scope.extensions = appService.getAppDescriptor().getExtensions("org.bahmni.registration.navigation", "link");
            var path = $location.path();
            $scope.hasPrint = !(path === "/search" || path === "/patient/new");
            $scope.goTo = function (url) {
                $location.url(url);
            };

            $scope.htmlLabel = function (label) {
                return $sce.trustAsHtml(label);
            };

            $scope.logout = function () {
                $rootScope.errorMessage = null;
                sessionService.destroy().then(
                    function () {
                        $window.location = "../home/";
                    }
                );
            };

            $scope.sync = function () {
            };
        }]);

'use strict';

angular.module('bahmni.registration')
    .controller('SearchPatientController', ['$rootScope', '$scope', '$location', '$window', 'spinner', 'patientService', 'appService',
        'messagingService', '$translate', '$filter',
        function ($rootScope, $scope, $location, $window, spinner, patientService, appService, messagingService, $translate, $filter) {
            $scope.results = [];
            var searching = false;
            var maxAttributesFromConfig = 5;
            const allSearchConfigs = appService.getAppDescriptor().getConfigValue("patientSearch") || {};
            const patientSearchResultOptions = allSearchConfigs.patientSearchResultOptions != null ? allSearchConfigs.patientSearchResultOptions : {};
            const ignoredIdentifiers = new Set(patientSearchResultOptions.ignorePatientIdentifiers || []);
            $scope.showAge = patientSearchResultOptions.showAge != null ? patientSearchResultOptions.showAge : true;
            $scope.showDOB = patientSearchResultOptions.showDOB != null ? patientSearchResultOptions.showDOB : false;
            $scope.extraIdentifierTypes = _.filter($rootScope.patientConfiguration.identifierTypes, function (identifierType) {
                return !identifierType.primary && !ignoredIdentifiers.has(identifierType.name);
            });
            var patientSearchResultConfigs = appService.getAppDescriptor().getConfigValue("patientSearchResults") || {};

            maxAttributesFromConfig = !_.isEmpty(allSearchConfigs.programAttributes) ? maxAttributesFromConfig - 1 : maxAttributesFromConfig;

            $scope.getAddressColumnName = function (column) {
                var columnName = "";
                var columnCamelCase = column.replace(/([-_][a-z])/g, function ($1) {
                    return $1.toUpperCase().replace(/[-_]/, '');
                });
                _.each($scope.addressLevels, function (addressLevel) {
                    if (addressLevel.addressField === columnCamelCase) { columnName = addressLevel.name; }
                });
                return columnName;
            };

            var hasSearchParameters = function () {
                return (
                    ($scope.searchParameters.name || '').trim().length > 0 ||
                    ($scope.searchParameters.addressFieldValue || '').trim().length > 0 ||
                    ($scope.searchParameters.customAttribute || '').trim().length > 0 ||
                    ($scope.searchParameters.programAttributeFieldValue || '').trim().length > 0 ||
                    ($scope.searchParameters.gender || '').trim().length > 0
                );
            };

            var searchBasedOnQueryParameters = function (offset) {
                if (!isUserPrivilegedForSearch()) {
                    showInsufficientPrivMessage();
                    return;
                }
                var searchParameters = $location.search();
                $scope.searchParameters.addressFieldValue = searchParameters.addressFieldValue || '';
                $scope.searchParameters.name = searchParameters.name || '';
                $scope.searchParameters.customAttribute = searchParameters.customAttribute || '';
                $scope.searchParameters.programAttributeFieldValue = searchParameters.programAttributeFieldValue || '';
                $scope.searchParameters.addressSearchResultsConfig = searchParameters.addressSearchResultsConfig || '';
                $scope.searchParameters.personSearchResultsConfig = searchParameters.personSearchResultsConfig || '';
                $scope.searchParameters.gender = searchParameters.gender || '';
                $scope.searchParameters.registrationNumber =
                    searchParameters.registrationNumber || "";
                if (hasSearchParameters()) {
                    searching = true;

                    var filterByLastVisitLocation = !$scope.searchParameters.allLocations;

                    return patientService.search(
                        $scope.searchParameters.name,
                        undefined,
                        $scope.addressSearchConfig.field,
                        $scope.searchParameters.addressFieldValue,
                        $scope.searchParameters.customAttribute,
                        offset,
                        $scope.customAttributesSearchConfig.fields,
                        $scope.programAttributesSearchConfig.field,
                        $scope.searchParameters.programAttributeFieldValue,
                        $scope.addressSearchResultsConfig.fields,
                        $scope.personSearchResultsConfig.fields,
                        $scope.searchParameters.gender,
                        filterByLastVisitLocation
                    ).finally(function () {
                        searching = false;
                    });
                }
            };
            $scope.convertToTableHeader = function (camelCasedText) {
                return $translate.instant(camelCasedText).replace(/[A-Z]|^[a-z]/g, function (str) {
                    return " " + str.toUpperCase() + "";
                }).trim();
            };

            $scope.getProgramAttributeValues = function (result) {
                var attributeValues = result && result.patientProgramAttributeValue && result.patientProgramAttributeValue[$scope.programAttributesSearchConfig.field];
                var commaSeparatedAttributeValues = "";
                _.each(attributeValues, function (attr) {
                    commaSeparatedAttributeValues = commaSeparatedAttributeValues + attr + ", ";
                });
                return commaSeparatedAttributeValues.substring(0, commaSeparatedAttributeValues.length - 2);
            };

            var mapExtraIdentifiers = function (data) {
                if (data !== "Searching") {
                    _.each(data.pageOfResults, function (result) {
                        result.extraIdentifiers = result.extraIdentifiers && JSON.parse(result.extraIdentifiers);
                    });
                }
            };

            var mapCustomAttributesSearchResults = function (data) {
                if (($scope.personSearchResultsConfig.fields) && data !== "Searching") {
                    _.map(data.pageOfResults, function (result) {
                        result.customAttribute = result.customAttribute && JSON.parse(result.customAttribute);
                    });
                }
            };

            var mapAddressAttributesSearchResults = function (data) {
                if (($scope.addressSearchResultsConfig.fields) && data !== "Searching") {
                    _.map(data.pageOfResults, function (result) {
                        try {
                            result.addressFieldValue = JSON.parse(result.addressFieldValue);
                        } catch (e) {
                        }
                    });
                }
            };

            var mapProgramAttributesSearchResults = function (data) {
                if (($scope.programAttributesSearchConfig.field) && data !== "Searching") {
                    _.map(data.pageOfResults, function (result) {
                        var programAttributesObj = {};
                        var arrayOfStringOfKeysValue = result.patientProgramAttributeValue && result.patientProgramAttributeValue.substring(2, result.patientProgramAttributeValue.length - 2).split('","');
                        _.each(arrayOfStringOfKeysValue, function (keyValueString) {
                            var keyValueArray = keyValueString.split('":"');
                            var key = keyValueArray[0];
                            var value = keyValueArray[1];
                            if (!_.includes(_.keys(programAttributesObj), key)) {
                                programAttributesObj[key] = [];
                                programAttributesObj[key].push(value);
                            } else {
                                programAttributesObj[key].push(value);
                            }
                        });
                        result.patientProgramAttributeValue = programAttributesObj;
                    });
                }
            };

            var showSearchResults = function (searchPromise) {
                $scope.noMoreResultsPresent = false;
                if (searchPromise) {
                    searchPromise.then(function (data) {
                        mapExtraIdentifiers(data);
                        mapCustomAttributesSearchResults(data);
                        mapAddressAttributesSearchResults(data);
                        mapProgramAttributesSearchResults(data);

                        $scope.results = data.pageOfResults;
                        $scope.noResultsMessage =
                            $scope.results.length === 0 ? 'REGISTRATION_NO_RESULTS_FOUND' : null;
                    });
                }
            };

            var setPatientIdentifierSearchConfig = function () {
                $scope.patientIdentifierSearchConfig = {};
                $scope.patientIdentifierSearchConfig.show = allSearchConfigs.searchByPatientIdentifier === undefined ? true : allSearchConfigs.searchByPatientIdentifier;
            };

            var setAddressSearchConfig = function () {
                $scope.addressSearchConfig = allSearchConfigs.address || {};
                $scope.addressSearchConfig.show = !_.isEmpty($scope.addressSearchConfig) && !_.isEmpty($scope.addressSearchConfig.field);
                if ($scope.addressSearchConfig.label && !$scope.addressSearchConfig.label) {
                    throw new Error("Search Config label is not present!");
                }
                if ($scope.addressSearchConfig.field && !$scope.addressSearchConfig.field) {
                    throw new Error("Search Config field is not present!");
                }
            };

            var setCustomAttributesSearchConfig = function () {
                var customAttributesSearchConfig = allSearchConfigs.customAttributes;
                $scope.customAttributesSearchConfig = customAttributesSearchConfig || {};
                $scope.customAttributesSearchConfig.show = !_.isEmpty(customAttributesSearchConfig) && !_.isEmpty(customAttributesSearchConfig.fields);
            };

            var setProgramAttributesSearchConfig = function () {
                $scope.programAttributesSearchConfig = allSearchConfigs.programAttributes || {};
                $scope.programAttributesSearchConfig.show = !_.isEmpty($scope.programAttributesSearchConfig.field);
            };

            var sliceExtraColumns = function () {
                var orderedColumns = Object.keys(patientSearchResultConfigs);
                _.each(orderedColumns, function (column) {
                    if (patientSearchResultConfigs[column].fields && !_.isEmpty(patientSearchResultConfigs[column].fields)) {
                        patientSearchResultConfigs[column].fields = patientSearchResultConfigs[column].fields.slice(patientSearchResultConfigs[column].fields, maxAttributesFromConfig);
                        maxAttributesFromConfig -= patientSearchResultConfigs[column].fields.length;
                    }
                });
            };

            var setSearchResultsConfig = function () {
                var resultsConfigNotFound = false;
                if (_.isEmpty(patientSearchResultConfigs)) {
                    resultsConfigNotFound = true;
                    patientSearchResultConfigs.address = { "fields": allSearchConfigs.address ? [allSearchConfigs.address.field] : [] };
                    patientSearchResultConfigs.personAttributes
                        = { fields: allSearchConfigs.customAttributes ? allSearchConfigs.customAttributes.fields : {} };
                } else {
                    if (!patientSearchResultConfigs.address) patientSearchResultConfigs.address = {};
                    if (!patientSearchResultConfigs.personAttributes) patientSearchResultConfigs.personAttributes = {};
                }

                if (patientSearchResultConfigs.address.fields && !_.isEmpty(patientSearchResultConfigs.address.fields)) {
                    patientSearchResultConfigs.address.fields =
                        patientSearchResultConfigs.address.fields.filter(function (item) {
                            return !_.isEmpty($scope.getAddressColumnName(item));
                        });
                }
                if (!resultsConfigNotFound) sliceExtraColumns();
                $scope.personSearchResultsConfig = patientSearchResultConfigs.personAttributes;
                $scope.addressSearchResultsConfig = patientSearchResultConfigs.address;
            };

            var initialize = function () {
                $scope.searchParameters = {};
                $scope.searchActions = appService.getAppDescriptor().getExtensions("org.bahmni.registration.patient.search.result.action");
                setPatientIdentifierSearchConfig();
                setAddressSearchConfig();
                setCustomAttributesSearchConfig();
                setProgramAttributesSearchConfig();
                setSearchResultsConfig();
            };

            var identifyParams = function (querystring) {
                querystring = querystring.substring(querystring.indexOf('?') + 1).split('&');
                var params = {}, pair, d = decodeURIComponent;
                for (var i = querystring.length - 1; i >= 0; i--) {
                    pair = querystring[i].split('=');
                    params[d(pair[0])] = d(pair[1]);
                }
                return params;
            };

            initialize();

            $scope.qrData = '';
            $scope.patientId = '';
            $scope.isScanning = false;
            var stream = null;
            $scope.toggleScanning = function () {
                if ($scope.isScanning) {
                    stopScanning();
                } else {
                    startScanning();
                }
            };

            function startScanning () {
                $scope.video = document.getElementById('video');
                $scope.video.style.height = "100%";
                $scope.video.style.width = "100%";

                navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
                    .then(function (mediaStream) {
                        stream = mediaStream;
                        $scope.video.srcObject = stream;
                        $scope.video.setAttribute('playsinline', true); // Required for iOS Safari
                        $scope.video.play();
                        $scope.isScanning = true;
                        scan();
                    }).catch(function (err) {
                        console.error('Error accessing the camera: ', err);
                        // Handle error: display message to the user, prompt for retry, etc.
                    });
            }

            function stopScanning () {
                if (stream) {
                    var tracks = stream.getTracks();
                    for (var i = 0; i < tracks.length; i++) {
                        tracks[i].stop();
                    }
                    stream = null;
                }
                $scope.video.style.height = "0%";
                $scope.video.style.width = "0%";

                $scope.video.srcObject = null;
                $scope.isScanning = false;
            }

            function scan () {
                if ($scope.video.readyState === $scope.video.HAVE_ENOUGH_DATA) {
                    var canvasElement = document.createElement('canvas');
                    var canvas = canvasElement.getContext('2d');

                    canvasElement.width = $scope.video.videoWidth;
                    canvasElement.height = $scope.video.videoHeight;
                    canvas.drawImage($scope.video, 0, 0, canvasElement.width, canvasElement.height);

                    var imageData = canvas.getImageData(0, 0, canvasElement.width, canvasElement.height);
                    var code = jsQR(imageData.data, imageData.width, imageData.height, {
                        inversionAttempts: 'dontInvert'
                    });

                    if (code) {
                        $scope.$apply(function () {
                            $scope.qrData = code.data;
                            try {
                                var parsedData;
                                try {
                                    parsedData = JSON.parse(code.data);
                                }
                                catch (exception) {
                                    console.error("Error while psrsing: ", exception);
                                    parsedData = JSON.parse('"' + code.data + '"');
                                }
                                var patientId;
                                if (parsedData.hidn !== undefined) {
                                    patientId = parsedData.hidn;
                                } else {
                                    patientId = code.data;
                                }
                                var searchPromise = patientService.search(undefined, patientId, $scope.addressSearchConfig.field,
                                    undefined, undefined, undefined, $scope.customAttributesSearchConfig.fields,
                                    $scope.programAttributesSearchConfig.field, $scope.searchParameters.programAttributeFieldValue,
                                    $scope.addressSearchResultsConfig.fields, $scope.personSearchResultsConfig.fields,
                                    $scope.isExtraIdentifierConfigured())
                                    .then(function (data) {
                                        if (data.pageOfResults.length > 0) {
                                            var patient = data.pageOfResults[0];
                                            var forwardUrl = appService.getAppDescriptor().getConfigValue("searchByIdForwardUrl") || "/patient/{{patientUuid}}";
                                            $location.url(appService.getAppDescriptor().formatUrl(forwardUrl, { 'patientUuid': patient.uuid }));
                                        } else {
                                            var errorMessage = $translate.instant("PATIENT_NOT_EXISTS", { patientId: patientId });
                                            messagingService.showMessage('error', errorMessage);
                                        }
                                    });
                            } catch (e) {
                                console.error('Error parsing QR code data: ', e);
                            }
                            stopScanning();
                        });
                        return;
                    }
                }
                if ($scope.isScanning) {
                    requestAnimationFrame(scan);
                }
            }

            $scope.disableSearchButton = function () {
                return !$scope.searchParameters.name && !$scope.searchParameters.addressFieldValue && !$scope.searchParameters.phoneNumber && !$scope.searchParameters.fileNumber && !$scope.searchParameters.programAttributeFieldValue && !$scope.searchParameters.gender;
            };

            $scope.$watch(function () {
                return $location.search();
            }, function () {
                showSearchResults(searchBasedOnQueryParameters(0));
            });

            $scope.searchById = function () {
                if (!isUserPrivilegedForSearch()) {
                    showInsufficientPrivMessage();
                    return;
                }
                if (!$scope.searchParameters.registrationNumber) {
                    return;
                }
                $scope.results = [];

                var patientIdentifier = $scope.searchParameters.registrationNumber;

                $location.search({
                    registrationNumber: $scope.searchParameters.registrationNumber,
                    programAttributeFieldName: $scope.programAttributesSearchConfig.field,
                    patientAttributes: $scope.customAttributesSearchConfig.fields,
                    programAttributeFieldValue: $scope.searchParameters.programAttributeFieldValue,
                    addressSearchResultsConfig: $scope.addressSearchResultsConfig.fields,
                    personSearchResultsConfig: $scope.personSearchResultsConfig.fields
                });

                var searchPromise = patientService.search(undefined, patientIdentifier, $scope.addressSearchConfig.field,
                    undefined, undefined, undefined, $scope.customAttributesSearchConfig.fields,
                    $scope.programAttributesSearchConfig.field, $scope.searchParameters.programAttributeFieldValue,
                    $scope.addressSearchResultsConfig.fields, $scope.personSearchResultsConfig.fields,
                    $scope.isExtraIdentifierConfigured())
                    .then(function (data) {
                        mapExtraIdentifiers(data);
                        mapCustomAttributesSearchResults(data);
                        mapAddressAttributesSearchResults(data);
                        mapProgramAttributesSearchResults(data);
                        if (data.pageOfResults.length === 1) {
                            var patient = data.pageOfResults[0];
                            var forwardUrl = appService.getAppDescriptor().getConfigValue("searchByIdForwardUrl") || "/patient/{{patientUuid}}";
                            $location.url(appService.getAppDescriptor().formatUrl(forwardUrl, { 'patientUuid': patient.uuid }));
                        } else if (data.pageOfResults.length > 1) {
                            $scope.results = data.pageOfResults;
                            $scope.noResultsMessage = null;
                        } else {
                            $scope.patientIdentifier = { 'patientIdentifier': patientIdentifier };
                            $scope.noResultsMessage = 'REGISTRATION_LABEL_COULD_NOT_FIND_PATIENT';
                        }
                    });
                spinner.forPromise(searchPromise);
            };
            var isUserPrivilegedForSearch = function () {
                var applicablePrivs = [Bahmni.Common.Constants.viewPatientsPrivilege, Bahmni.Common.Constants.editPatientsPrivilege,
                    Bahmni.Common.Constants.addVisitsPrivilege, Bahmni.Common.Constants.deleteVisitsPrivilege];
                var userPrivs = _.map($rootScope.currentUser.privileges, function (privilege) {
                    return privilege.name;
                });
                var result = _.some(userPrivs, function (privName) {
                    return _.includes(applicablePrivs, privName);
                });
                return result;
            };

            var showInsufficientPrivMessage = function () {
                var message = $translate.instant("REGISTRATION_INSUFFICIENT_PRIVILEGE");
                messagingService.showMessage('error', message);
            };

            $scope.loadingMoreResults = function () {
                return searching && !$scope.noMoreResultsPresent;
            };

            $scope.searchPatients = function () {
                if (!isUserPrivilegedForSearch()) {
                    showInsufficientPrivMessage();
                    return;
                }
                var queryParams = {};
                $scope.results = [];
                if ($scope.searchParameters.name) {
                    queryParams.name = $scope.searchParameters.name;
                }
                if ($scope.searchParameters.addressFieldValue) {
                    queryParams.addressFieldValue = $scope.searchParameters.addressFieldValue;
                }
                // if ($scope.searchParameters.customAttribute && $scope.customAttributesSearchConfig.show) {
                //     queryParams.customAttribute = $scope.searchParameters.customAttribute;
                // }
                if ($scope.searchParameters.phoneNumber) {
                    queryParams.customAttribute = $scope.searchParameters.phoneNumber;
                    queryParams.patientAttributes = ['phoneNumber'];
                }
                else if ($scope.searchParameters.fileNumber) {
                    queryParams.customAttribute = $scope.searchParameters.fileNumber;
                    queryParams.patientAttributes = ['FileNumber'];
                }
                if ($scope.searchParameters.programAttributeFieldValue && $scope.programAttributesSearchConfig.show) {
                    queryParams.programAttributeFieldName = $scope.programAttributesSearchConfig.field;
                    queryParams.programAttributeFieldValue = $scope.searchParameters.programAttributeFieldValue;
                }
                if ($scope.searchParameters.gender) {
                    queryParams.gender = $scope.searchParameters.gender;
                }

                queryParams.allLocations = $scope.searchParameters.allLocations;

                $location.search(queryParams);
            };

            $scope.resultsPresent = function () {
                return angular.isDefined($scope.results) && $scope.results.length > 0;
            };

            $scope.editPatientUrl = function (url, options) {
                var temp = url;
                for (var key in options) {
                    temp = temp.replace("{{" + key + "}}", options[key]);
                }
                return temp;
            };

            $scope.nextPage = function () {
                if ($scope.nextPageLoading) {
                    return;
                }
                $scope.nextPageLoading = true;
                var promise = searchBasedOnQueryParameters($scope.results.length);
                if (promise) {
                    promise.then(function (data) {
                        angular.forEach(data.pageOfResults, function (result) {
                            $scope.results.push(result);
                        });
                        $scope.noMoreResultsPresent = (data.pageOfResults.length === 0);
                        $scope.nextPageLoading = false;
                    }, function () {
                        $scope.nextPageLoading = false;
                    });
                }
            };

            $scope.forPatient = function (patient) {
                $scope.selectedPatient = patient;
                return $scope;
            };

            $scope.doExtensionAction = function (extension) {
                var forwardTo = appService.getAppDescriptor().formatUrl(extension.url, { 'patientUuid': $scope.selectedPatient.uuid });
                if (extension.label === 'Print') {
                    var params = identifyParams(forwardTo);
                    if (params.launch === 'dialog') {
                        var firstChar = forwardTo.charAt(0);
                        var prefix = firstChar === "/" ? "#" : "#/";
                        var hiddenFrame = $("#printPatientFrame")[0];
                        hiddenFrame.src = prefix + forwardTo;
                        hiddenFrame.contentWindow.print();
                    } else {
                        $location.url(forwardTo);
                    }
                } else {
                    $location.url(forwardTo);
                }
            };

            $scope.extensionActionText = function (extension) {
                return $filter('titleTranslate')(extension);
            };

            $scope.isExtraIdentifierConfigured = function () {
                return !_.isEmpty($scope.extraIdentifierTypes);
            };
        }]);

'use strict';

angular.module('bahmni.registration')
    .controller('PatientCommonController', ['$scope', '$rootScope', '$http', 'patientAttributeService', 'appService', 'patientService', 'spinner', '$location', 'ngDialog', '$window', '$state', '$document', '$translate',
        function ($scope, $rootScope, $http, patientAttributeService, appService, patientService, spinner, $location, ngDialog, $window, $state, $document, $translate) {
            var autoCompleteFields = appService.getAppDescriptor().getConfigValue("autoCompleteFields", []);
            var showCasteSameAsLastNameCheckbox = appService.getAppDescriptor().getConfigValue("showCasteSameAsLastNameCheckbox");
            var personAttributes = [];
            var caste;
            var contactAttribute;
            $scope.showMiddleName = appService.getAppDescriptor().getConfigValue("showMiddleName");
            $scope.showLastName = appService.getAppDescriptor().getConfigValue("showLastName");
            $scope.isLastNameMandatory = $scope.showLastName && appService.getAppDescriptor().getConfigValue("isLastNameMandatory");
            $scope.showBirthTime = appService.getAppDescriptor().getConfigValue("showBirthTime") != null
                ? appService.getAppDescriptor().getConfigValue("showBirthTime") : true;  // show birth time by default
            $scope.genderCodes = Object.keys($rootScope.genderMap);
            $scope.dobMandatory = appService.getAppDescriptor().getConfigValue("dobMandatory") || false;
            $scope.readOnlyExtraIdentifiers = appService.getAppDescriptor().getConfigValue("readOnlyExtraIdentifiers");
            $scope.showSaveConfirmDialogConfig = appService.getAppDescriptor().getConfigValue("showSaveConfirmDialog");
            $scope.showSaveAndContinueButton = false;
            $scope.regExtPoints = appService.getAppDescriptor().getExtensions("org.bahmni.registration.identifier", "link");

            $scope.showExtIframe = false;
            var identifierExtnMap = new Map();
            $scope.attributesToBeDisabled = [];

            $scope.getExtButtons = function (identifierType) {
                var extensionPoint = getExtensionPoint(identifierType);
                if (extensionPoint != null && extensionPoint.extensionParams !== null && extensionPoint.extensionParams.buttons !== null) {
                    return extensionPoint.extensionParams.buttons;
                }
                return null;
            };

            $scope.openIdentifierPopup = function (identifierType, action) {
                var iframe = $document[0].getElementById("extension-popup");
                iframe.src = getExtensionPoint(identifierType).src + "?action=" + action;
                $scope.showExtIframe = true;
                $window.addEventListener("message", function (popupWindowData) {
                    if (popupWindowData.data.patient !== undefined) {
                        $rootScope.extenstionPatient = popupWindowData.data.patient;
                        if ($rootScope.extenstionPatient.id !== undefined) {
                            $rootScope.isExistingPatient = true;
                            if ($rootScope.extenstionPatient.id !== $scope.patient.uuid) {
                                $window.open(Bahmni.Registration.Constants.existingPatient + $rootScope.extenstionPatient.id, "_self");
                            }
                        } else $window.open(Bahmni.Registration.Constants.newPatient, "_self");
                        $scope.updateInfoFromExtSource($rootScope.extenstionPatient);
                        $scope.$digest();
                    }
                    if (popupWindowData.data.patientUuid !== undefined) {
                        $window.open(Bahmni.Registration.Constants.existingPatient + popupWindowData.data.patientUuid, "_self");
                    }
                }, false);
            };

            $scope.isDisabledAttribute = function (attribute) {
                return $scope.attributesToBeDisabled !== undefined && $scope.attributesToBeDisabled.includes(attribute);
            };

            function isIdentifierVoided (identifierType) {
                if ($scope.patient.uuid !== undefined && $rootScope.patientIdentifiers !== undefined) {
                    for (var i = 0; i < $rootScope.patientIdentifiers.length; i++) {
                        var identifier = $rootScope.patientIdentifiers[i];
                        if (identifier.identifierType.display === identifierType) {
                            return true;
                        }
                    }
                }
                return false;
            }

            $scope.showOnlyCreateButton = function (identifierTypes) {
                for (var i = 0; i < identifierTypes.length; i++) {
                    if (identifierTypes[i].registrationNumber) {
                        return true;
                    }
                }
                return false;
            };

            $scope.showIdentifierVerificationButton = function (identifierType, identifierValue) {
                var extenstionPoint = getExtensionPoint(identifierType);
                if (extenstionPoint != null && identifierValue === undefined && _.some($rootScope.currentUser.privileges, {name: extenstionPoint.extensionParams.requiredPrivilege})) {
                    if (identifierExtnMap.get(extenstionPoint.id) === identifierType || identifierExtnMap.get(extenstionPoint.id) === undefined) {
                        if (identifierExtnMap.get(extenstionPoint.id) === undefined) {
                            identifierExtnMap.set(extenstionPoint.id, identifierType);
                        }
                        return !isIdentifierVoided(identifierType);
                    }
                }
                return false;
            };

            function getExtensionPoint (identifierType) {
                if ($scope.regExtPoints !== null) {
                    for (var i = 0; i < $scope.regExtPoints.length; i++) {
                        var identifierTypes = $scope.regExtPoints[i].extensionParams.identifierType;
                        for (var j = 0; j < identifierTypes.length; j++) {
                            if (identifierType === identifierTypes[j]) {
                                return $scope.regExtPoints[i];
                            }
                        }
                    }
                }
                return null;
            }

            $scope.updateInfoFromExtSource = function (patient) {
                $scope.showExtIframe = false;
                var identifierMatch = false;
                for (var i = 0; i < $scope.patient.extraIdentifiers.length; i++) {
                    var identifier = $scope.patient.extraIdentifiers[i];
                    for (var j = 0; j < patient.identifiers.length; j++) {
                        if (patient.identifiers[j]) {
                            var identifierType = patient.identifiers[j].type.text;
                            if (identifier.identifierType.name === identifierType) {
                                identifier.registrationNumber = patient.identifiers[j].value;
                                var extensionParam = getExtensionPoint(identifierType).extensionParams;
                                $scope.attributesToBeDisabled = extensionParam.nonEditable !== null ? extensionParam.nonEditable : null;
                                identifier.generate();
                                if (!identifierMatch) {
                                    extensionParam.addressMap !== null ? updatePatientAddress(patient.address[0], extensionParam.addressMap) : {};
                                    contactAttribute = extensionParam.contact ? extensionParam.contact : "primaryContact";
                                    changePatientDetails(patient, extensionParam.isMiddleNameFieldPresent);
                                    identifierMatch = true;
                                }
                            }
                        }
                    }
                }
            };

            function updatePatientAddress (address, addressMap) {
                $scope.patient.address = {};
                for (var key in addressMap) {
                    if (address[key] && address[key] !== null) {
                        if (key === "line") {
                            for (var index in addressMap[key]) {
                                $scope.patient.address[addressMap[key][index]] = address[key][index];
                            }
                        } else { $scope.patient.address[addressMap[key]] = address[key]; }
                    }
                }
            }

            function updatePatientName (name, isMiddleNameFieldPresent) {
                if (isMiddleNameFieldPresent) {
                    $scope.patient.givenName = name.givenName[0];
                    $scope.patient.middleName = name.givenName.length > 1 ? name.givenName[1] : "";
                }
                else {
                    $scope.patient.givenName = name.givenName.join(" ");
                }

                $scope.patient.familyName = name.familyName;
            }

            function changePatientDetails (changedDetails, isMiddleNameFieldPresent) {
                for (var key in changedDetails) {
                    switch (key) {
                    case 'names':
                        if (changedDetails.names != null) {
                            for (var i = 0; i < changedDetails.names.length; i++) {
                                if (changedDetails.names[i].use === "preferred") {
                                    updatePatientName(changedDetails.names[i], isMiddleNameFieldPresent);
                                    break;
                                }
                            }
                            updatePatientName(changedDetails.names[0], isMiddleNameFieldPresent);
                        }
                        break;
                    case 'gender':
                        if (changedDetails.gender) {
                            $scope.patient.gender = changedDetails.gender;
                        }
                        break;
                    case 'contactPoint':
                        if (changedDetails.contactPoint != null) {
                            for (var i = 0; i < changedDetails.contactPoint.length; i++) {
                                var contact = changedDetails.contactPoint[i];
                                if (contact.system === "phone") { $scope.patient[contactAttribute] = contact.value; }
                            }
                        }
                        break;
                    default:
                        $scope.patient.birthdateEstimated = changedDetails.isBirthDateEstimated;
                        $scope.patient.birthdate = changedDetails.birthDate !== undefined ? new Date(changedDetails.birthDate) : new Date();
                        $scope.patient.calculateAge();
                        break;
                    }
                }
            }

            $scope.closeIdentifierPopup = function () {
                $scope.showExtIframe = false;
            };

            function initPatientNameDisplayOrder () {
                var validNameFields = Bahmni.Registration.Constants.patientNameDisplayOrder;
                var nameFields = appService.getAppDescriptor().getConfigValue("patientNameDisplayOrder") || [];
                var valid = _.every(nameFields, function (val) { return validNameFields.indexOf(val) >= 0; });
                if (nameFields.length !== 3 || !valid) {
                    $scope.patientNameDisplayOrder = validNameFields;
                } else {
                    $scope.patientNameDisplayOrder = nameFields;
                }
            }

            initPatientNameDisplayOrder();
            var dontSaveButtonClicked = false;

            var isHref = false;

            $rootScope.onHomeNavigate = function (event) {
                if ($scope.showSaveConfirmDialogConfig && $state.current.name != "patient.visit") {
                    event.preventDefault();
                    $scope.targetUrl = event.currentTarget.getAttribute('href');
                    isHref = true;
                    $scope.confirmationPrompt(event);
                }
            };
            $scope.getTranslatedPatientControls = function (controls) {
                var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(controls, Bahmni.Common.Constants.registration, $translate);
                return translatedName;
            };
            var stateChangeListener = $rootScope.$on("$stateChangeStart", function (event, toState, toParams) {
                if ($scope.showSaveConfirmDialogConfig && (toState.url == "/search" || toState.url == "/patient/new")) {
                    $scope.targetUrl = toState.name;
                    isHref = false;
                    $scope.confirmationPrompt(event, toState, toParams);
                }
            });

            $scope.localLanguageNameIsRequired = function (nameType) {
                personAttributes = _.keyBy($rootScope.patientConfiguration.attributeTypes, function (attribute) {
                    return attribute.name;
                });
                if (_.isEmpty(nameType)) {
                    return personAttributes.givenNameLocal.required || personAttributes.middleNameLocal.required || personAttributes.familyNameLocal.required;
                }
                return nameType && personAttributes[nameType] && personAttributes[nameType].required;
            };

            $scope.confirmationPrompt = function (event, toState) {
                if (dontSaveButtonClicked === false) {
                    if (event) {
                        event.preventDefault();
                    }
                    ngDialog.openConfirm({template: "../common/ui-helper/views/saveConfirmation.html", scope: $scope});
                }
            };

            $scope.continueWithoutSaving = function () {
                ngDialog.close();
                dontSaveButtonClicked = true;
                if (isHref === true) {
                    $window.open($scope.targetUrl, '_self');
                } else {
                    $state.go($scope.targetUrl);
                }
            };

            $scope.cancelTransition = function () {
                ngDialog.close();
                delete $scope.targetUrl;
            };

            $scope.$on("$destroy", function () {
                stateChangeListener();
            });

            $scope.getDeathConcepts = function () {
                return $http({
                    url: Bahmni.Common.Constants.globalPropertyUrl,
                    method: 'GET',
                    params: {
                        property: 'concept.reasonForDeath'
                    },
                    withCredentials: true,
                    transformResponse: [function (deathConcept) {
                        if (_.isEmpty(deathConcept)) {
                            $scope.deathConceptExists = false;
                        } else {
                            $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                                params: {
                                    name: deathConcept,
                                    v: "custom:(uuid,name,set,names,setMembers:(uuid,display,name:(uuid,name),names,retired))"
                                },
                                withCredentials: true
                            }).then(function (results) {
                                $scope.deathConceptExists = !!results.data.results.length;
                                $scope.deathConcepts = results.data.results[0] ? results.data.results[0].setMembers : [];

                                var activeDeathConcepts = filterRetireDeathConcepts($scope.deathConcepts);
                                _.forEach(activeDeathConcepts, function (deathConcept, index) {
                                    activeDeathConcepts[index] = $scope.updateDisplayFieldToLocaleSpecific(
                                    $scope.filterNamesForLocale(deathConcept, $rootScope.currentUser.userProperties.defaultLocale, "FULLY_SPECIFIED"));
                                });
                            });
                        }
                    }]
                });
            };
            spinner.forPromise($scope.getDeathConcepts());
            var filterRetireDeathConcepts = function (deathConcepts) {
                return _.filter(deathConcepts, function (concept) {
                    return !concept.retired;
                });
            };

            $scope.filterNamesForLocale = function (jsonNames, locale, nametype) {
                var localeNames = _.filter(jsonNames.names, function (name) {
                    return name.locale == locale && name.conceptNameType == nametype;
                });
                if (localeNames.length > 0) {
                    jsonNames.names = localeNames;
                }
                return jsonNames;
            };

            $scope.updateDisplayFieldToLocaleSpecific = function (concept) {
                concept.display = concept.names[0].display;
            };

            $scope.isAutoComplete = function (fieldName) {
                return !_.isEmpty(autoCompleteFields) ? autoCompleteFields.indexOf(fieldName) > -1 : false;
            };

            $scope.showCasteSameAsLastName = function () {
                personAttributes = _.map($rootScope.patientConfiguration.attributeTypes, function (attribute) {
                    return attribute.name.toLowerCase();
                });
                var personAttributeHasCaste = personAttributes.indexOf("caste") !== -1;
                caste = personAttributeHasCaste ? $rootScope.patientConfiguration.attributeTypes[personAttributes.indexOf("caste")].name : undefined;
                return showCasteSameAsLastNameCheckbox && personAttributeHasCaste;
            };

            $scope.setCasteAsLastName = function () {
                if ($scope.patient.sameAsLastName) {
                    $scope.patient[caste] = $scope.patient.familyName;
                }
            };

            var showSections = function (sectionsToShow, allSections) {
                _.each(sectionsToShow, function (sectionName) {
                    allSections[sectionName].canShow = true;
                    allSections[sectionName].expand = true;
                });
            };

            var hideSections = function (sectionsToHide, allSections) {
                _.each(sectionsToHide, function (sectionName) {
                    allSections[sectionName].canShow = false;
                });
            };

            var executeRule = function (ruleFunction) {
                var attributesShowOrHideMap = ruleFunction($scope.patient);
                var patientAttributesSections = $rootScope.patientConfiguration.getPatientAttributesSections();
                showSections(attributesShowOrHideMap.show, patientAttributesSections);
                hideSections(attributesShowOrHideMap.hide, patientAttributesSections);
            };

            $scope.handleUpdate = function (attribute) {
                var ruleFunction = Bahmni.Registration.AttributesConditions.rules && Bahmni.Registration.AttributesConditions.rules[attribute];
                if (ruleFunction) {
                    executeRule(ruleFunction);
                }
            };

            var executeShowOrHideRules = function () {
                _.each(Bahmni.Registration.AttributesConditions.rules, function (rule) {
                    executeRule(rule);
                });
            };

            var setAttributesToBeDisabled = function () {
                $scope.patient.extraIdentifiers.forEach(function (identifier) {
                    var extensionPoint = getExtensionPoint(identifier.identifierType.name);
                    if (extensionPoint !== null) {
                        extensionPoint.extensionParams.identifierType.forEach(function (identifiers) {
                            if (identifier.identifierType.name === identifiers) {
                                if (identifier.registrationNumber !== undefined) {
                                    $scope.attributesToBeDisabled = extensionPoint.extensionParams.nonEditable;
                                }
                            }
                        });
                    }
                });
            };

            $scope.$watch('patientLoaded', function () {
                if ($scope.patientLoaded) {
                    executeShowOrHideRules();
                    if (!$scope.createPatient) {
                        if ($scope.patient.extraIdentifiers !== undefined) {
                            setAttributesToBeDisabled();
                        }
                        if ($scope.isExistingPatient && $rootScope.extenstionPatient !== undefined) {
                            $rootScope.isExistingPatient = false;
                            $scope.updateInfoFromExtSource($rootScope.extenstionPatient);
                        }
                    }
                }
            });

            $scope.getAutoCompleteList = function (attributeName, query, type) {
                return patientAttributeService.search(attributeName, query, type);
            };

            $scope.getDataResults = function (data) {
                return data.results;
            };

            $scope.$watch('patient.familyName', function () {
                if ($scope.patient.sameAsLastName) {
                    $scope.patient[caste] = $scope.patient.familyName;
                }
            });

            $scope.$watch('patient.caste', function () {
                if ($scope.patient.sameAsLastName && ($scope.patient.familyName !== $scope.patient[caste])) {
                    $scope.patient.sameAsLastName = false;
                }
            });

            $scope.selectIsDead = function () {
                if ($scope.patient.causeOfDeath || $scope.patient.deathDate) {
                    $scope.patient.dead = true;
                }
            };

            $scope.disableIsDead = function () {
                return ($scope.patient.causeOfDeath || $scope.patient.deathDate) && $scope.patient.dead;
            };
        }]);


'use strict';

angular.module('bahmni.registration')
    .controller('CreatePatientController', ['$scope', '$rootScope', '$state', 'patientService', 'patient', 'spinner', 'appService', 'messagingService', 'ngDialog', '$q', '$translate', 'sessionService', '$http',
        function ($scope, $rootScope, $state, patientService, patient, spinner, appService, messagingService, ngDialog, $q, $translate, sessionService, $http) {
            var dateUtil = Bahmni.Common.Util.DateUtil;
            $scope.actions = {};
            var errorMessage;
            var configValueForEnterId = appService.getAppDescriptor().getConfigValue('showEnterID');
            $scope.addressHierarchyConfigs = appService.getAppDescriptor().getConfigValue("addressHierarchy");
            $scope.disablePhotoCapture = appService.getAppDescriptor().getConfigValue("disablePhotoCapture");
            $scope.showEnterID = configValueForEnterId === null ? true : configValueForEnterId;
            $scope.relatedIdentifierAttribute = appService.getAppDescriptor().getConfigValue('relatedIdentifierAttribute');
            $scope.today = Bahmni.Common.Util.DateTimeFormatter.getDateWithoutTime(dateUtil.now());
            $scope.moduleName = appService.getAppDescriptor().getConfigValue('registrationModuleName');
            var patientId;

            var uniquePersonAttribute = appService.getAppDescriptor().getConfigValue("uniquePersonAttribute") || undefined;
            var loginLocationUuid = sessionService.getLoginLocationUuid();
            const patientSearchByPersonAttributeUrl = Bahmni.Common.Constants.bahmniCommonsSearchUrl + "/patient?patientAttributes=" + uniquePersonAttribute + "&s=byIdOrNameOrVillage&startIndex=0&patientSearchResultsConfig=" + uniquePersonAttribute + "&customAttribute=";
            const uniquePersonAttributeErrorText = appService.getAppDescriptor().getConfigValue("uniquePersonAttributeErrorText") || "";

            var getPersonAttributeTypes = function () {
                return $rootScope.patientConfiguration.attributeTypes;
            };
            $scope.getTranslatedPatientIdentifier = function (patientIdentifier) {
                var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(patientIdentifier, Bahmni.Common.Constants.registration, $translate);
                return translatedName;
            };
            var prepopulateDefaultsInFields = function () {
                var personAttributeTypes = getPersonAttributeTypes();
                var patientInformation = appService.getAppDescriptor().getConfigValue("patientInformation");
                if (!patientInformation || !patientInformation.defaults) {
                    return;
                }
                var defaults = patientInformation.defaults;
                var defaultVariableNames = _.keys(defaults);

                var hasDefaultAnswer = function (personAttributeType) {
                    return _.includes(defaultVariableNames, personAttributeType.name);
                };

                var isConcept = function (personAttributeType) {
                    return personAttributeType.format === "org.openmrs.Concept";
                };

                var setDefaultAnswer = function (personAttributeType) {
                    $scope.patient[personAttributeType.name] = defaults[personAttributeType.name];
                };

                var setDefaultConcept = function (personAttributeType) {
                    var defaultAnswer = defaults[personAttributeType.name];
                    var isDefaultAnswer = function (answer) {
                        return answer.fullySpecifiedName === defaultAnswer;
                    };

                    _.chain(personAttributeType.answers).filter(isDefaultAnswer).each(function (answer) {
                        $scope.patient[personAttributeType.name] = {
                            conceptUuid: answer.conceptId,
                            value: answer.fullySpecifiedName
                        };
                    }).value();
                };

                var isDateType = function (personAttributeType) {
                    return personAttributeType.format === "org.openmrs.util.AttributableDate";
                };

                var isDefaultValueToday = function (personAttributeType) {
                    if (defaults[personAttributeType.name].toLowerCase() === "today") {
                        return true;
                    }
                    return false;
                };

                var setDefaultValue = function (personAttributeType) {
                    if (isDefaultValueToday(personAttributeType)) {
                        $scope.patient[personAttributeType.name] = new Date();
                    }
                    else {
                        $scope.patient[personAttributeType.name] = '';
                    }
                };

                var defaultsWithAnswers = _.chain(personAttributeTypes)
                    .filter(hasDefaultAnswer)
                    .each(setDefaultAnswer).value();

                _.chain(defaultsWithAnswers).filter(isConcept).each(setDefaultConcept).value();
                _.chain(defaultsWithAnswers).filter(isDateType).each(setDefaultValue).value();
                if ($scope.relatedIdentifierAttribute && $scope.relatedIdentifierAttribute.name) {
                    $scope.patient[$scope.relatedIdentifierAttribute.name] = false;
                }
            };

            var expandSectionsWithDefaultValue = function () {
                angular.forEach($rootScope.patientConfiguration && $rootScope.patientConfiguration.getPatientAttributesSections(), function (section) {
                    var notNullAttribute = _.find(section && section.attributes, function (attribute) {
                        return $scope.patient[attribute.name] !== undefined;
                    });
                    section.expand = section.expanded || (notNullAttribute ? true : false);
                });
            };

            var init = function () {
                $scope.patient = patient.create();
                prepopulateDefaultsInFields();
                expandSectionsWithDefaultValue();
                $scope.patientLoaded = true;
                $scope.createPatient = true;

                // IPLit: initially selecting patient id source === logged in location IdentifierSourceName, location id prefix
                if ($rootScope.loggedInLocation && $rootScope.loggedInLocation.attributes) {
                    var foundSourceAttr = $rootScope.loggedInLocation.attributes.find(attr => attr.display.includes('IdentifierSourceName'));
                    if (foundSourceAttr) {
                        var sourceIds = foundSourceAttr.display.split(':');
                        var locationSourceIdentifier = sourceIds && sourceIds.length > 1 ? sourceIds[1].trim() : '';
                        if (locationSourceIdentifier && locationSourceIdentifier.length > 0) {
                            var selectedIdentifierSource = $scope.patient.primaryIdentifier.identifierType.identifierSources.find(src => src.prefix === locationSourceIdentifier);
                            if (selectedIdentifierSource) {
                                $scope.patient.primaryIdentifier.selectedIdentifierSource = selectedIdentifierSource;
                            }
                        }
                    }
                }
            };

            $scope.fileNumberAttribute = $rootScope.patientConfiguration.attributeTypes.find(item => item.name === "FileNumber");
            $scope.locationOfVisit = $rootScope.patientConfiguration.attributeTypes.find(item => item.name === "Location of Visit");

            init();

            var prepopulateFields = function () {
                var fieldsToPopulate = appService.getAppDescriptor().getConfigValue("prepopulateFields");
                if (fieldsToPopulate) {
                    _.each(fieldsToPopulate, function (field) {
                        var addressLevel = _.find($scope.addressLevels, function (level) {
                            return level.name === field;
                        });
                        if (addressLevel) {
                            $scope.patient.address[addressLevel.addressField] = $rootScope.loggedInLocation[addressLevel.addressField];
                        }
                    });
                }
            };
            prepopulateFields();

            var addNewRelationships = function () {
                var newRelationships = _.filter($scope.patient.newlyAddedRelationships, function (relationship) {
                    return relationship.relationshipType && relationship.relationshipType.uuid;
                });
                newRelationships = _.each(newRelationships, function (relationship) {
                    delete relationship.patientIdentifier;
                    delete relationship.content;
                    delete relationship.providerName;
                });
                $scope.patient.relationships = newRelationships;
            };

            var getConfirmationViaNgDialog = function (config) {
                var ngDialogLocalScope = config.scope.$new();
                ngDialogLocalScope.yes = function () {
                    ngDialog.close();
                    config.yesCallback();
                };
                ngDialogLocalScope.no = function () {
                    ngDialog.close();
                };
                ngDialog.open({
                    template: config.template,
                    data: config.data,
                    scope: ngDialogLocalScope
                });
            };

            var copyPatientProfileDataToScope = function (response) {
                var patientProfileData = response.data;
                $scope.patient.uuid = patientProfileData.patient.uuid;
                $scope.patient.name = patientProfileData.patient.person.names[0].display;
                $scope.patient.isNew = true;
                $scope.patient.registrationDate = dateUtil.now();
                $scope.patient.newlyAddedRelationships = [{}];
                $scope.actions.followUpAction(patientProfileData);
                patientId = patientProfileData.patient.identifiers[0].identifier;
            };

            var createPatient = function (jumpAccepted) {
                return patientService.create($scope.patient, jumpAccepted).then(function (response) {
                    copyPatientProfileDataToScope(response);
                }, function (response) {
                    if (response.status === 412) {
                        var data = _.map(response.data, function (data) {
                            return {
                                sizeOfTheJump: data.sizeOfJump,
                                identifierName: _.find($rootScope.patientConfiguration.identifierTypes, {uuid: data.identifierType}).name
                            };
                        });
                        getConfirmationViaNgDialog({
                            template: 'views/customIdentifierConfirmation.html',
                            data: data,
                            scope: $scope,
                            yesCallback: function () {
                                return createPatient(true);
                            }
                        });
                    }
                    if (response.isIdentifierDuplicate) {
                        errorMessage = response.message;
                    }
                });
            };

            var createPromise = function () {
                var deferred = $q.defer();
                createPatient().finally(function () {
                    return deferred.resolve({});
                });
                return deferred.promise;
            };

            var searchDuplicatePersonAttributePatients = function (pa) {
                var loginLocation = '&loginLocationUuid=' + loginLocationUuid;
                var finalPatientSearchUrl = patientSearchByPersonAttributeUrl + pa + loginLocation;
                return $http.get(finalPatientSearchUrl, {
                    method: "GET",
                    withCredentials: true
                });
            };

            var validateUniquePersonAttribute = function () {
                var errorText = '';
                var deferred = $q.defer();
                if (uniquePersonAttribute) {
                    var uniquePersonAttributeVal = $scope.patient[uniquePersonAttribute];
                    if (uniquePersonAttributeVal) {
                        return searchDuplicatePersonAttributePatients(uniquePersonAttributeVal).then(function (result) {
                            deferred.resolve(result);
                            if (result.data && result.data.pageOfResults && result.data.pageOfResults.length === 0) {
                                errorText = '';
                            } else {
                                var pt = _.find(result.data.pageOfResults, function (p) {
                                    if (p && p.uuid && p.uuid !== $scope.patient.uuid) {
                                        return p;
                                    }
                                });
                                if (pt) {
                                    errorText = uniquePersonAttributeErrorText;
                                }
                            }
                            return errorText;
                        }).then(function (errorText) {
                            return errorText;
                        });
                    } else {
                        deferred.resolve(errorText);
                    }
                } else {
                    deferred.resolve(errorText);
                }
                return deferred.promise;
            };

            $scope.create = function () {
                addNewRelationships();
                var errorMessages = Bahmni.Common.Util.ValidationUtil.validate($scope.patient, $scope.patientConfiguration.attributeTypes);
                return spinner.forPromise(validateUniquePersonAttribute().then(function (errorText) {
                    if (errorText && errorText.length > 0) {
                        errorMessages.push(errorText);
                    }
                })).then(function () {
                    if (errorMessages.length > 0) {
                        errorMessages.forEach(function (errorMessage) {
                            messagingService.showMessage('error', errorMessage);
                        });
                        return $q.when({});
                    }
                    return spinner.forPromise(createPromise()).then(function (response) {
                        if (errorMessage) {
                            messagingService.showMessage("error", errorMessage);
                            errorMessage = undefined;
                        }
                    });
                });
            };

            $scope.afterSave = function () {
                messagingService.showMessage("info", "REGISTRATION_LABEL_SAVED");
                $state.go("patient.edit", {
                    patientUuid: $scope.patient.uuid
                });
            };

            $scope.handleUpdate = function (attribute) {
            };

            $scope.getDataResults = function (data) {
                return data.results;
            };
        }
    ]);

'use strict';

angular.module('bahmni.registration')
    .controller('EditPatientController', ['$scope', 'patientService', 'encounterService', '$stateParams', 'openmrsPatientMapper',
        '$window', '$q', 'spinner', 'appService', 'messagingService', '$rootScope', 'auditLogService', 'sessionService', '$http',
        function ($scope, patientService, encounterService, $stateParams, openmrsPatientMapper, $window, $q, spinner,
                  appService, messagingService, $rootScope, auditLogService, sessionService, $http) {
            var dateUtil = Bahmni.Common.Util.DateUtil;
            var uuid = $stateParams.patientUuid;
            $scope.patient = {};
            $scope.actions = {};
            var uniquePersonAttribute = appService.getAppDescriptor().getConfigValue("uniquePersonAttribute");
            var loginLocationUuid = sessionService.getLoginLocationUuid();
            const patientSearchByPersonAttributeUrl = Bahmni.Common.Constants.bahmniCommonsSearchUrl + "/patient?patientAttributes=" + uniquePersonAttribute + "&s=byIdOrNameOrVillage&startIndex=0&patientSearchResultsConfig=" + uniquePersonAttribute + "&customAttribute=";
            $scope.addressHierarchyConfigs = appService.getAppDescriptor().getConfigValue("addressHierarchy");
            $scope.disablePhotoCapture = appService.getAppDescriptor().getConfigValue("disablePhotoCapture");
            $scope.today = dateUtil.getDateWithoutTime(dateUtil.now());
            var setReadOnlyFields = function () {
                $scope.readOnlyFields = {};
                var readOnlyFields = appService.getAppDescriptor().getConfigValue("readOnlyFields");
                angular.forEach(readOnlyFields, function (readOnlyField) {
                    if ($scope.patient[readOnlyField]) {
                        $scope.readOnlyFields[readOnlyField] = true;
                    }
                });
                $scope.readOnlyFields["Subscription card Numbers"] = true;
                if ($scope.patient["Subscription Card"] && $scope.patient["Subscription card"].value.toLowerCase().includes("yes")) {
                    $scope.readOnlyFields["Subscription card Numbers"] = false;
                }
            };

            var searchDuplicatePersonAttributePatients = function (pa) {
                var loginLocation = '&loginLocationUuid=' + loginLocationUuid;
                var finalPatientSearchUrl = patientSearchByPersonAttributeUrl + pa + loginLocation;
                return $http.get(finalPatientSearchUrl, {
                    method: "GET",
                    withCredentials: true
                });
            };
            var successCallBack = function (openmrsPatient) {
                $scope.openMRSPatient = openmrsPatient["patient"];
                $scope.patient = openmrsPatientMapper.map(openmrsPatient);
                setReadOnlyFields();
                expandDataFilledSections();
                $scope.patientLoaded = true;
                $scope.enableWhatsAppButton = (appService.getAppDescriptor().getConfigValue("enableWhatsAppButton") || Bahmni.Registration.Constants.enableWhatsAppButton) && ($scope.patient.phoneNumber != undefined);
                $scope.relatedIdentifierAttribute = appService.getAppDescriptor().getConfigValue('relatedIdentifierAttribute');
                if ($scope.relatedIdentifierAttribute && $scope.relatedIdentifierAttribute.name) {
                    const hideOrDisableAttr = $scope.relatedIdentifierAttribute.hideOrDisable;
                    const hideAttrOnValue = $scope.relatedIdentifierAttribute.hideOnValue;
                    $scope.showRelatedIdentifierOption = !(hideOrDisableAttr === "hide" && $scope.patient[$scope.relatedIdentifierAttribute.name] &&
                                            $scope.patient[$scope.relatedIdentifierAttribute.name].toString() === hideAttrOnValue);
                    $scope.showDisabledAttrOption = hideOrDisableAttr === "disable" ? true : false;
                }
            };

            var expandDataFilledSections = function () {
                angular.forEach($rootScope.patientConfiguration && $rootScope.patientConfiguration.getPatientAttributesSections(), function (section) {
                    var notNullAttribute = _.find(section && section.attributes, function (attribute) {
                        return $scope.patient[attribute.name] !== undefined;
                    });
                    section.expand = section.expanded || (notNullAttribute ? true : false);
                });
            };

            (function () {
                var getPatientPromise = patientService.get(uuid).then(successCallBack);

                var isDigitized = encounterService.getDigitized(uuid);

                var identifiers = patientService.getAllPatientIdentifiers(uuid);

                identifiers.then(function (response) {
                    $rootScope.patientIdentifiers = response.data.results;
                });

                isDigitized.then(function (data) {
                    var encountersWithObservations = data.data.results.filter(function (encounter) {
                        return encounter.obs.length > 0;
                    });
                    $scope.isDigitized = encountersWithObservations.length > 0;
                });

                spinner.forPromise($q.all([getPatientPromise, isDigitized, identifiers]));
            })();

            $scope.update = function () {
                addNewRelationships();
                var errorMessages = Bahmni.Common.Util.ValidationUtil.validate($scope.patient, $scope.patientConfiguration.attributeTypes);
                return spinner.forPromise(validateUniquePersonAttribute().then(function (errorText) {
                    if (errorText && errorText.length > 0) {
                        errorMessages.push(errorText);
                    }
                })).then(function () {
                    if (errorMessages.length > 0) {
                        errorMessages.forEach(function (errorMessage) {
                            messagingService.showMessage('error', errorMessage);
                        });
                        return $q.when({});
                    }

                    return spinner.forPromise(patientService.update($scope.patient, $scope.openMRSPatient).then(function (result) {
                        var patientProfileData = result.data;
                        if (!patientProfileData.error) {
                            successCallBack(patientProfileData);
                            $scope.actions.followUpAction(patientProfileData);
                        }
                    }));
                });
            };

            var addNewRelationships = function () {
                var newRelationships = _.filter($scope.patient.newlyAddedRelationships, function (relationship) {
                    return relationship.relationshipType && relationship.relationshipType.uuid;
                });
                newRelationships = _.each(newRelationships, function (relationship) {
                    delete relationship.patientIdentifier;
                    delete relationship.content;
                    delete relationship.providerName;
                });
                $scope.patient.relationships = _.concat(newRelationships, $scope.patient.deletedRelationships);
            };

            $scope.isReadOnly = function (field) {
                return $scope.readOnlyFields ? ($scope.readOnlyFields[field] ? true : false) : undefined;
            };

            $scope.notifyOnWhatsAapp = function () {
                var name = $scope.patient.givenName + " " + $scope.patient.familyName;
                var whatsAppMessage = patientService.getRegistrationMessage($scope.patient.primaryIdentifier.identifier, name, $scope.patient.age.years, $scope.patient.gender);
                var phoneNumber = $scope.patient.phoneNumber.replace("+", "");
                var url = "https://api.whatsapp.com/send?phone=" + phoneNumber + "&text=" + encodeURIComponent(whatsAppMessage);
                window.open(url);
            };

            $scope.afterSave = function () {
                auditLogService.log($scope.patient.uuid, Bahmni.Registration.StateNameEvenTypeMap['patient.edit'], undefined, "MODULE_LABEL_REGISTRATION_KEY");
                messagingService.showMessage("info", "REGISTRATION_LABEL_SAVED");
            };

            var validateUniquePersonAttribute = function () {
                var errorText = null;
                var deferred = $q.defer();
                if (uniquePersonAttribute) {
                    var uniquePersonAttributeVal = $scope.patient[uniquePersonAttribute];
                    if (uniquePersonAttributeVal) {
                        return searchDuplicatePersonAttributePatients(uniquePersonAttributeVal).then(function (result) {
                            deferred.resolve(result);
                            if (result.data && result.data.results && result.data.results.length === 0) {
                                errorText = '';
                            } else {
                                var pt = _.find(result.data.results, function (p) {
                                    if (p && p.uuid && p.uuid !== $scope.patient.uuid) {
                                        return p;
                                    }
                                });
                                if (pt) {
                                    errorText = uniquePersonAttributeErrorText;
                                }
                            }
                            return errorText;
                        }).then(function (errorText) {
                            return errorText;
                        });
                    } else {
                        deferred.resolve(errorText);
                    }
                } else {
                    deferred.resolve(errorText);
                }
                return deferred.promise;
            };

            $scope.handleUpdate = function (attribute) {
            };

            $scope.fileNumberAttribute = $rootScope.patientConfiguration.attributeTypes.find(item => item.name === "FileNumber");
            $scope.locationOfVisit = $rootScope.patientConfiguration.attributeTypes.find(item => item.name === "Location of Visit");

            $scope.getDataResults = function (data) {
                return data.results;
            };
        }]);

'use strict';

angular.module('bahmni.registration')
    .directive('patientAction', ['$window', '$location', '$state', 'spinner', '$rootScope', '$stateParams',
        '$bahmniCookieStore', 'appService', 'visitService', 'sessionService', 'encounterService',
        'messagingService', '$translate', 'auditLogService',
        function ($window, $location, $state, spinner, $rootScope, $stateParams,
            $bahmniCookieStore, appService, visitService, sessionService, encounterService,
            messagingService, $translate, auditLogService) {
            var controller = function ($scope) {
                var self = this;
                var uuid = $stateParams.patientUuid;
                var editActionsConfig = appService.getAppDescriptor().getExtensions(Bahmni.Registration.Constants.nextStepConfigId, "config") || [];
                var conceptSetExtensions = appService.getAppDescriptor().getExtensions("org.bahmni.registration.conceptSetGroup.observations", "config");
                var loginLocationUuid = $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName).uuid;
                var defaultVisitType = $rootScope.regEncounterConfiguration.getDefaultVisitType(loginLocationUuid);
                defaultVisitType = defaultVisitType || appService.getAppDescriptor().getConfigValue('defaultVisitType');
                var showStartVisitButton = appService.getAppDescriptor().getConfigValue("showStartVisitButton");
                var forwardUrlsForVisitTypes = appService.getAppDescriptor().getConfigValue("forwardUrlsForVisitTypes");
                var showSuccessMessage = appService.getAppDescriptor().getConfigValue("showSuccessMessage");
                showStartVisitButton = (_.isUndefined(showStartVisitButton) || _.isNull(showStartVisitButton)) ? true : showStartVisitButton;
                var visitLocationUuid = $rootScope.visitLocation;
                var forwardUrls = forwardUrlsForVisitTypes || false;

                var getForwardUrlEntryForVisitFromTheConfig = function () {
                    var matchedEntry = _.find(forwardUrls, function (entry) {
                        if (self.hasActiveVisit) {
                            return entry.visitType === self.activeVisit.visitType.name;
                        }
                        return entry.visitType === $scope.visitControl.selectedVisitType.name;
                    });
                    return matchedEntry;
                };

                var keyForActiveVisitEntry = function () {
                    var matchedEntry = getForwardUrlEntryForVisitFromTheConfig();
                    if (matchedEntry) {
                        $scope.activeVisitConfig = matchedEntry;
                        if (_.isEmpty(_.get($scope.activeVisitConfig, 'translationKey'))) {
                            $scope.activeVisitConfig.translationKey = "REGISTRATION_LABEL_ENTER_VISIT";
                            $scope.activeVisitConfig.shortcutKey = "REGISTRATION_ENTER_VISIT_DETAILS_ACCESS_KEY";
                        }
                        return 'forwardAction';
                    }
                };

                function setForwardActionKey () {
                    if (editActionsConfig.length === 0) {
                        $scope.forwardActionKey = self.hasActiveVisit ? (getForwardUrlEntryForVisitFromTheConfig() ? keyForActiveVisitEntry() : 'enterVisitDetails') : 'startVisit';
                    } else {
                        $scope.actionConfig = editActionsConfig[0];
                        $scope.forwardActionKey = 'configAction';
                    }
                }

                var init = function () {
                    if (_.isEmpty(uuid)) {
                        self.hasActiveVisit = false;
                        setForwardActionKey();
                        return;
                    }
                    var searchParams = {
                        patient: uuid,
                        includeInactive: false,
                        v: "custom:(uuid,visitType,location:(uuid))"
                    };
                    spinner.forPromise(visitService.search(searchParams).then(function (response) {
                        var results = response.data.results;
                        var activeVisitForCurrentLoginLocation;
                        if (results) {
                            activeVisitForCurrentLoginLocation = _.filter(results, function (result) {
                                return result.location.uuid === visitLocationUuid;
                            });
                        }
                        self.hasActiveVisit = activeVisitForCurrentLoginLocation && (activeVisitForCurrentLoginLocation.length > 0);
                        if (self.hasActiveVisit) {
                            self.activeVisit = activeVisitForCurrentLoginLocation[0];
                        }
                        setForwardActionKey();
                    }));
                };

                $scope.visitControl = new Bahmni.Common.VisitControl(
                    $rootScope.regEncounterConfiguration.getVisitTypesAsArray(),
                    defaultVisitType, encounterService, $translate, visitService
                );

                $scope.visitControl.onStartVisit = function () {
                    $rootScope.startedVisit = true;
                    $scope.setSubmitSource('startVisit');
                };

                $scope.setSubmitSource = function (source) {
                    $scope.actions.submitSource = source;
                };

                $scope.showStartVisitButton = function () {
                    return showStartVisitButton;
                };

                var goToForwardUrlPage = function (patientData) {
                    var forwardUrl = appService.getAppDescriptor().formatUrl($scope.activeVisitConfig.forwardUrl, {'patientUuid': patientData.patient.uuid});
                    $window.location.href = forwardUrl;
                };

                $scope.actions.followUpAction = function (patientProfileData) {
                    messagingService.clearAll();
                    switch ($scope.actions.submitSource) {
                    case 'startVisit':
                        var entry = getForwardUrlEntryForVisitFromTheConfig();
                        var forwardUrl = entry ? entry.forwardUrl : undefined;
                        return createVisit(patientProfileData, forwardUrl);
                    case 'forwardAction':
                        return goToForwardUrlPage(patientProfileData);
                    case 'enterVisitDetails':
                        return goToVisitPage(patientProfileData);
                    case 'configAction':
                        return handleConfigAction(patientProfileData);
                    case 'save':
                        $scope.afterSave();
                    }
                };

                var handleConfigAction = function (patientProfileData) {
                    var forwardUrl = appService.getAppDescriptor().formatUrl($scope.actionConfig.extensionParams.forwardUrl, {'patientUuid': patientProfileData.patient.uuid});
                    if (!self.hasActiveVisit) {
                        createVisit(patientProfileData, forwardUrl);
                    } else {
                        $window.location.href = forwardUrl;
                    }
                };

                var goToVisitPage = function (patientData) {
                    $scope.patient.uuid = patientData.patient.uuid;
                    $scope.patient.name = patientData.patient.person.names[0].display;
                    $location.path("/patient/" + patientData.patient.uuid + "/visit");
                };

                var isEmptyVisitLocation = function () {
                    return _.isEmpty($rootScope.visitLocation);
                };

                var checkIfActiveVisitExists = function (patientProfileData) {
                    return $scope.visitControl.checkIfActiveVisitExists(patientProfileData.patient.uuid, $rootScope.visitLocation).then(function (response) {
                        var checkExists = response.data.results.length;
                        if (checkExists === 0) {
                            return false;
                        } else {
                            return true;
                        }
                    });
                };
                var createVisit = function (patientProfileData, forwardUrl) {
                    if (isEmptyVisitLocation()) {
                        $state.go('patient.edit', {patientUuid: $scope.patient.uuid}).then(function () {
                            messagingService.showMessage("error", "NO_LOCATION_TAGGED_TO_VISIT_LOCATION");
                        });
                        return;
                    }
                    checkIfActiveVisitExists(patientProfileData).then(function (exists) {
                        if (exists) return messagingService.showMessage("error", "VISIT_OF_THIS_PATIENT_AT_SAME_LOCATION_EXISTS");

                        spinner.forPromise($scope.visitControl.createVisitOnly(patientProfileData.patient.uuid, $rootScope.visitLocation).then(function (response) {
                            auditLogService.log(patientProfileData.patient.uuid, "OPEN_VISIT", { visitUuid: response.data.uuid, visitType: response.data.visitType.display }, 'MODULE_LABEL_REGISTRATION_KEY');
                            if (forwardUrl) {
                                var updatedForwardUrl = appService.getAppDescriptor().formatUrl(forwardUrl, { 'patientUuid': patientProfileData.patient.uuid });
                                $window.location.href = updatedForwardUrl;
                                if (showSuccessMessage) {
                                    messagingService.showMessage("info", "REGISTRATION_LABEL_SAVE_REDIRECTION");
                                }
                            } else {
                                goToVisitPage(patientProfileData);
                            }
                        }, function () {
                            $state.go('patient.edit', { patientUuid: $scope.patient.uuid });
                        }));
                    });
                };

                init();
            };
            return {
                restrict: 'E',
                templateUrl: 'views/patientAction.html',
                controller: controller
            };
        }
    ]);

'use strict';

angular.module('bahmni.registration')
    .controller('VisitController', ['$window', '$scope', '$rootScope', '$state', '$bahmniCookieStore', 'patientService', 'encounterService', '$stateParams', 'spinner', '$timeout', '$q', 'appService', 'openmrsPatientMapper', 'contextChangeHandler', 'messagingService', 'sessionService', 'visitService', '$location', '$translate',
        'auditLogService', 'formService',
        function ($window, $scope, $rootScope, $state, $bahmniCookieStore, patientService, encounterService, $stateParams, spinner, $timeout, $q, appService, openmrsPatientMapper, contextChangeHandler, messagingService, sessionService, visitService, $location, $translate, auditLogService, formService) {
            var vm = this;
            var patientUuid = $stateParams.patientUuid;
            var extensions = appService.getAppDescriptor().getExtensions("org.bahmni.registration.conceptSetGroup.observations", "config");
            var formExtensions = appService.getAppDescriptor().getExtensions("org.bahmni.registration.conceptSetGroup.observations", "forms");
            var locationUuid = sessionService.getLoginLocationUuid();
            var selectedProvider = $rootScope.currentProvider;
            var regEncounterTypeUuid = $rootScope.regEncounterConfiguration.encounterTypes[Bahmni.Registration.Constants.registrationEncounterType];
            var visitLocationUuid = $rootScope.visitLocation;
            var redirectToDashboard = false;
            var filterBasedOnLocation = appService.getAppDescriptor().getConfigValue("filterBasedOnLocation") || false;
            var getPreviousVisitData = appService.getAppDescriptor().getConfigValue("getPreviousVisitData");
            getPreviousVisitData = getPreviousVisitData || false;
            var conceptsToGetFromPrevVisit = appService.getAppDescriptor().getConfigValue("previousVisitConceptNamesToPull");
            conceptsToGetFromPrevVisit = conceptsToGetFromPrevVisit || [];
            var getPreviousObs = conceptsToGetFromPrevVisit.join(',');
            $scope.enableDashboardRedirect = _.some($rootScope.currentUser.privileges, {name: "app:clinical"}) && (appService.getAppDescriptor().getConfigValue("enableDashboardRedirect") || Bahmni.Registration.Constants.enableDashboardRedirect);

            var getPatient = function () {
                var deferred = $q.defer();
                patientService.get(patientUuid).then(function (openMRSPatient) {
                    deferred.resolve(openMRSPatient);
                    $scope.patient = openmrsPatientMapper.map(openMRSPatient);
                    $scope.patient.name = openMRSPatient.patient.person.names[0].display;
                    $scope.patient.uuid = openMRSPatient.patient.uuid;
                });
                return deferred.promise;
            };

            var getActiveEncounter = function () {
                var deferred = $q.defer();
                encounterService.find({
                    "patientUuid": patientUuid,
                    "providerUuids": !_.isEmpty($scope.currentProvider.uuid) ? [$scope.currentProvider.uuid] : null,
                    "includeAll": false,
                    locationUuid: locationUuid,
                    encounterTypeUuids: [regEncounterTypeUuid]
                }, getPreviousVisitData, getPreviousObs, filterBasedOnLocation).then(function (response) {
                    deferred.resolve(response);
                    if (response.data && response.data.context && response.data.context.visitAttributesTypes) {
                        var attrTypes = [];
                        for (var i = 2; i < response.data.context.visitAttributesTypes.length; i++) {
                            var attrTypeObject = response.data.context.visitAttributesTypes[i];
                            if (attrTypeObject) {
                                var dataClassName = attrTypeObject.DatatypeClassname;
                                var preferredHandlerClassname = attrTypeObject.PreferredHandlerClassname;
                                var attrName = attrTypeObject.Name;
                                var attrValue = attrTypeObject.Value;
                                var attrDescription = attrTypeObject.Description;
                                var handlerConfig = [];
                                if (attrTypeObject.HandlerConfig && attrTypeObject.HandlerConfig.length > 0) {
                                    handlerConfig = attrTypeObject.HandlerConfig.split(',');
                                }
                                if (preferredHandlerClassname && preferredHandlerClassname.length > 0) {
                                    preferredHandlerClassname = preferredHandlerClassname.substr(preferredHandlerClassname.lastIndexOf(".") + 1);
                                } else {
                                    preferredHandlerClassname = "textHandler";
                                    if (attrName === 'Token#') {
                                        attrValue = Number(attrValue);
                                    }
                                }
                                var initialValue = handlerConfig && handlerConfig.length > 0 ? handlerConfig[0] : "";
                                if (attrName === 'Follow-up Date') {
                                    attrValue = attrValue ? moment(attrValue).toDate() : "";
                                }
                                var attrType = {
                                    "preferredHandlerClassname": preferredHandlerClassname,
                                    "attrName": attrName,
                                    "attrDescription": attrDescription,
                                    "handlerConfig": handlerConfig,
                                    "attrValue": attrValue || initialValue
                                };
                                attrTypes.push(attrType);
                            }
                        }
                        if (attrTypes.length > 0) {
                            $scope.attrTypes = attrTypes;
                        }
                    }
                    if (response.data.observations && conceptsToGetFromPrevVisit.length > 0 && $rootScope.startedVisit) {
                        var observations = [];
                        var conceptNames = conceptsToGetFromPrevVisit;
                        for (var i = 0; i < conceptNames.length; i++) {
                            var observation = getMatchingConceptObservation(conceptNames[i], response.data.observations);
                            if (observation) {
                                observations.push(observation);
                            }
                        }
                        $scope.observations = observations;
                    } else {
                        $scope.observations = response.data.observations;
                    }
                    $scope.encounterUuid = response.data.encounterUuid;
                    $scope.observations = response.data.observations;
                });
                return deferred.promise;
            };

            var getAllForms = function () {
                var deferred = $q.defer();
                formService.getFormList($scope.encounterUuid)
                    .then(function (response) {
                        $scope.conceptSets = extensions.map(function (extension) {
                            return new Bahmni.ConceptSet.ConceptSetSection(extension, $rootScope.currentUser, {}, [], {});
                        });

                        $scope.observationForms = getObservationForms(formExtensions, response.data);
                        $scope.conceptSets = $scope.conceptSets.concat($scope.observationForms);

                        $scope.availableConceptSets = $scope.conceptSets.filter(function (conceptSet) {
                            return conceptSet.isAvailable($scope.context);
                        });
                        deferred.resolve(response.data);
                    });
                return deferred.promise;
            };

            $scope.hideFields = appService.getAppDescriptor().getConfigValue("hideFields");

            $scope.back = function () {
                $state.go('patient.edit');
            };

            $scope.updatePatientImage = function (image) {
                var updateImagePromise = patientService.updateImage($scope.patient.uuid, image.replace("data:image/jpeg;base64,", ""));
                spinner.forPromise(updateImagePromise);
                return updateImagePromise;
            };

            var save = function () {
                var visitAttributesTypes = [];
                if ($scope.attrTypes && $scope.attrTypes.length > 0) {
                    for (var i = 0; i < $scope.attrTypes.length; i++) {
                        var valueAttr = $scope.attrTypes[i].attrValue;
                        if ($scope.attrTypes[i].attrName === 'Follow-up Date') {
                            valueAttr = valueAttr ? moment(valueAttr).toDate().toString() : null;
                        }
                        var objAttr = {
                            "Name": $scope.attrTypes[i].attrName,
                            "Value": valueAttr || ""
                        };
                        visitAttributesTypes.push(objAttr);
                    }
                }

                $scope.encounter = {
                    patientUuid: $scope.patient.uuid,
                    locationUuid: locationUuid,
                    encounterTypeUuid: regEncounterTypeUuid,
                    orders: [],
                    drugOrders: [],
                    extensions: {},
                    context: {"visitAttributesTypes": visitAttributesTypes}
                };

                $bahmniCookieStore.put(Bahmni.Common.Constants.grantProviderAccessDataCookieName, selectedProvider, {
                    path: '/',
                    expires: 1
                });

                $scope.encounter.observations = $scope.observations;
                $scope.encounter.observations = new Bahmni.Common.Domain.ObservationFilter().filter($scope.encounter.observations);

                addFormObservations($scope.encounter.observations);
                $rootScope.startedVisit = false;

                var createPromise = encounterService.create($scope.encounter);
                spinner.forPromise(createPromise);
                return createPromise.then(function (response) {
                    var messageParams = {encounterUuid: response.data.encounterUuid, encounterType: response.data.encounterType};
                    auditLogService.log(patientUuid, 'EDIT_ENCOUNTER', messageParams, 'MODULE_LABEL_REGISTRATION_KEY');
                    var visitType, visitTypeUuid;
                    visitTypeUuid = response.data.visitTypeUuid;
                    visitService.getVisitType().then(function (response) {
                        visitType = _.find(response.data.results, function (type) {
                            if (type.uuid === visitTypeUuid) {
                                return type;
                            }
                        });
                    });
                });
            };

            var getMatchingConceptObservation = function (conceptName, obs) {
                return _.find(obs, function (observation) {
                    return observation.concept && observation.concept.name === conceptName;
                });
            };

            var isUserPrivilegedToCloseVisit = function () {
                var applicablePrivs = [Bahmni.Common.Constants.closeVisitPrivilege, Bahmni.Common.Constants.deleteVisitsPrivilege];
                var userPrivs = _.map($rootScope.currentUser.privileges, function (privilege) {
                    return privilege.name;
                });
                return _.some(userPrivs, function (privName) {
                    return _.includes(applicablePrivs, privName);
                });
            };

            var searchActiveVisitsPromise = function () {
                return visitService.search({
                    patient: patientUuid, includeInactive: false, v: "custom:(uuid,location:(uuid))"
                }).then(function (response) {
                    var results = response.data.results;
                    var activeVisitForCurrentLoginLocation;
                    if (results) {
                        activeVisitForCurrentLoginLocation = _.filter(results, function (result) {
                            return result.location.uuid === visitLocationUuid;
                        });
                    }

                    var hasActiveVisit = activeVisitForCurrentLoginLocation.length > 0;
                    vm.visitUuid = hasActiveVisit ? activeVisitForCurrentLoginLocation[0].uuid : "";
                    $scope.canCloseVisit = isUserPrivilegedToCloseVisit() && hasActiveVisit;
                });
            };

            $scope.closeVisitIfDischarged = function () {
                visitService.getVisitSummary(vm.visitUuid).then(function (response) {
                    var visitSummary = response.data;
                    if (visitSummary.admissionDetails && !visitSummary.dischargeDetails) {
                        messagingService.showMessage("error", 'REGISTRATION_VISIT_CANNOT_BE_CLOSED');
                        var messageParams = {visitUuid: vm.visitUuid, visitType: visitSummary.visitType};
                        auditLogService.log(patientUuid, 'CLOSE_VISIT_FAILED', messageParams, 'MODULE_LABEL_REGISTRATION_KEY');
                    } else {
                        closeVisit(visitSummary.visitType);
                    }
                });
            };

            var closeVisit = function (visitType) {
                var confirmed = $window.confirm($translate.instant("REGISTRATION_CONFIRM_CLOSE_VISIT"));
                if (confirmed) {
                    visitService.endVisit(vm.visitUuid).then(function () {
                        $location.url(Bahmni.Registration.Constants.patientSearchURL);
                        var messageParams = {visitUuid: vm.visitUuid, visitType: visitType};
                        auditLogService.log(patientUuid, 'CLOSE_VISIT', messageParams, 'MODULE_LABEL_REGISTRATION_KEY');
                    });
                }
            };
            $scope.getTranslatedPrimaryIdentifierInVisit = function (primaryIdentifierName) {
                var translatedName = Bahmni.Common.Util.TranslationUtil.translateAttribute(primaryIdentifierName, Bahmni.Common.Constants.registration, $translate);
                return translatedName;
            };
            $scope.getMessage = function () {
                return $scope.message;
            };

            var isObservationFormValid = function () {
                var valid = true;
                _.each($scope.observationForms, function (observationForm) {
                    if (valid && observationForm.component) {
                        var value = observationForm.component.getValue();
                        if (value.errors) {
                            messagingService.showMessage('error', "{{'REGISTRATION_FORM_ERRORS_MESSAGE_KEY' | translate }}");
                            valid = false;
                        }
                    }
                });
                return valid;
            };

            var validate = function () {
                var isFormValidated = mandatoryValidate();
                var deferred = $q.defer();
                var contxChange = contextChangeHandler.execute();
                var allowContextChange = contxChange["allow"];
                var errorMessage;
                if (!isObservationFormValid()) {
                    deferred.reject("Some fields are not valid");
                    return deferred.promise;
                }
                if (!allowContextChange) {
                    errorMessage = contxChange["errorMessage"] ? contxChange["errorMessage"] : 'REGISTRATION_LABEL_CORRECT_ERRORS';
                    messagingService.showMessage('error', errorMessage);
                    deferred.reject("Some fields are not valid");
                    return deferred.promise;
                } else if (!isFormValidated) { // This ELSE IF condition is to be deleted later.
                    errorMessage = "REGISTRATION_LABEL_ENTER_MANDATORY_FIELDS";
                    messagingService.showMessage('error', errorMessage);
                    deferred.reject("Some fields are not valid");
                    return deferred.promise;
                } else {
                    deferred.resolve();
                    return deferred.promise;
                }
            };

            // Start :: Registration Page validation
            // To be deleted later - Hacky fix only for Registration Page
            var mandatoryConceptGroup = [];
            var mandatoryValidate = function () {
                conceptGroupValidation($scope.observations);
                return isValid(mandatoryConceptGroup);
            };

            var conceptGroupValidation = function (observations) {
                var concepts = _.filter(observations, function (observationNode) {
                    return isMandatoryConcept(observationNode);
                });
                if (!_.isEmpty(concepts)) {
                    mandatoryConceptGroup = _.union(mandatoryConceptGroup, concepts);
                }
            };
            var isMandatoryConcept = function (observation) {
                if (!_.isEmpty(observation.groupMembers)) {
                    conceptGroupValidation(observation.groupMembers);
                } else {
                    return observation.conceptUIConfig && observation.conceptUIConfig.required;
                }
            };
            var isValid = function (mandatoryConcepts) {
                var concept = mandatoryConcepts.filter(function (mandatoryConcept) {
                    if (mandatoryConcept.hasValue()) {
                        return false;
                    }
                    if (mandatoryConcept instanceof Bahmni.ConceptSet.Observation &&
                        mandatoryConcept.conceptUIConfig && mandatoryConcept.conceptUIConfig.multiSelect) {
                        return false;
                    }
                    if (mandatoryConcept.isMultiSelect) {
                        return _.isEmpty(mandatoryConcept.getValues());
                    }
                    return !mandatoryConcept.value;
                });
                return _.isEmpty(concept);
            };
            // End :: Registration Page validation

            var afterSave = function () {
                var forwardUrl = appService.getAppDescriptor().getConfigValue("afterVisitSaveForwardUrl");
                var dashboardUrl = appService.getAppDescriptor().getConfigValue("dashboardUrl") || Bahmni.Registration.Constants.dashboardUrl;
                if (forwardUrl != null) {
                    $window.location.href = appService.getAppDescriptor().formatUrl(forwardUrl, {'patientUuid': patientUuid});
                } else if (dashboardUrl != null && redirectToDashboard) {
                    $window.location.href = appService.getAppDescriptor().formatUrl(dashboardUrl, {'patientUuid': patientUuid});
                } else {
                    $state.transitionTo($state.current, $state.params, {
                        reload: true,
                        inherit: false,
                        notify: true
                    });
                }
                messagingService.showMessage('info', 'REGISTRATION_LABEL_SAVED');
            };

            $scope.submit = function () {
                return validate().then(save).then(afterSave);
            };

            $scope.today = function () {
                return new Date();
            };

            $scope.disableFormSubmitOnEnter = function () {
                $('.visit-patient').find('input').keypress(function (e) {
                    if (e.which === 13) { // Enter key = keycode 13
                        return false;
                    }
                });
            };

            var getConceptSet = function () {
                var visitType = $scope.encounterConfig.getVisitTypeByUuid($scope.visitTypeUuid);
                $scope.context = {visitType: visitType, patient: $scope.patient};
            };

            var getObservationForms = function (extensions, observationsForms) {
                var forms = [];
                var observations = $scope.observations || [];
                _.each(extensions, function (ext) {
                    var options = ext.extensionParams || {};
                    var observationForm = _.find(observationsForms, function (form) {
                        return (form.formName === options.formName || form.name === options.formName);
                    });
                    if (observationForm) {
                        var formUuid = observationForm.formUuid || observationForm.uuid;
                        var formName = observationForm.name || observationForm.formName;
                        var formVersion = observationForm.version || observationForm.formVersion;
                        forms.push(new Bahmni.ObservationForm(formUuid, $rootScope.currentUser, formName, formVersion, observations, formName, ext));
                    }
                });
                return forms;
            };

            $scope.isFormTemplate = function (data) {
                return data.formUuid;
            };

            var addFormObservations = function (observations) {
                if ($scope.observationForms) {
                    _.remove(observations, function (observation) {
                        return observation.formNamespace;
                    });
                    _.each($scope.observationForms, function (observationForm) {
                        if (observationForm.component) {
                            var formObservations = observationForm.component.getValue();
                            _.each(formObservations.observations, function (obs) {
                                observations.push(obs);
                            });
                        }
                    });
                }
            };

            $scope.setDashboardRedirect = function () {
                redirectToDashboard = true;
                return validate().then(save).then(afterSave);
            };

            $scope.onOrderSubmit = function () {
                var forwardUrl = appService.getAppDescriptor().getConfigValue("afterVisitOrdersForwardUrl");
                if (forwardUrl != null) {
                    $window.open(appService.getAppDescriptor().formatUrl(forwardUrl, {'patientUuid': $scope.patient.uuid}));
                } else {
                    $state.transitionTo($state.current, $state.params, {
                        reload: true,
                        inherit: false,
                        notify: true
                    });
                }
                messagingService.showMessage('info', 'REGISTRATION_LABEL_SAVED');
                location.reload(true);
            };

            spinner.forPromise($q.all([getPatient(), getActiveEncounter(), searchActiveVisitsPromise()])
                .then(function () {
                    getAllForms().then(function () {
                        getConceptSet();
                    });
                }));
        }]);

'use strict';

angular.module('bahmni.registration')
    .factory('patientService', ['$http', '$rootScope', '$bahmniCookieStore', '$q', 'patientServiceStrategy', 'sessionService', '$translate', 'appService', function ($http, $rootScope, $bahmniCookieStore, $q, patientServiceStrategy, sessionService, $translate, appService) {
        var openmrsUrl = Bahmni.Registration.Constants.openmrsUrl;
        var baseOpenMRSRESTURL = Bahmni.Registration.Constants.baseOpenMRSRESTURL;

        var search = function (query, identifier, addressFieldName, addressFieldValue, customAttributeValue,
                               offset, customAttributeFields, programAttributeFieldName, programAttributeFieldValue, addressSearchResultsConfig,
                               patientSearchResultsConfig, gender, filterPatientsByLocation) {
            var params = {
                q: query,
                s: "byIdOrNameOrVillage",
                identifier: identifier,
               // addressFieldName: addressFieldName,
                addressFieldValue: addressFieldValue,
                customAttribute: customAttributeValue,
                startIndex: offset || 0,
                patientAttributes: customAttributeFields,
                programAttributeFieldName: programAttributeFieldName,
                programAttributeFieldValue: programAttributeFieldValue,
                addressSearchResultsConfig: addressSearchResultsConfig,
                patientSearchResultsConfig: patientSearchResultsConfig,
                loginLocationUuid: sessionService.getLoginLocationUuid(),
                filterByLastVisitLocation: filterPatientsByLocation
            };

            if (gender !== undefined && gender !== null && gender !== '') {
                params.gender = gender;
            }
            var config = {
                params: params,
                withCredentials: true
            };
            return patientServiceStrategy.search(config);
        };

        var searchByIdentifier = function (identifier) {
            return $http.get(Bahmni.Common.Constants.bahmniCommonsSearchUrl + "/patient", {
                method: "GET",
                params: {
                    identifier: identifier,
                    loginLocationUuid: sessionService.getLoginLocationUuid()
                },
                withCredentials: true
            });
        };

        var searchByNameOrIdentifier = function (query, limit) {
            return $http.get(Bahmni.Common.Constants.bahmniCommonsSearchUrl + "/patient/lucene", {
                method: "GET",
                params: {
                    identifier: query,
                    filterOnAllIdentifiers: true,
                    q: query,
                    s: "byIdOrName",
                    limit: limit,
                    loginLocationUuid: sessionService.getLoginLocationUuid()
                },
                withCredentials: true
            });
        };

        var get = function (uuid) {
            return patientServiceStrategy.get(uuid);
        };

        var create = function (patient, jumpAccepted) {
            return patientServiceStrategy.create(patient, jumpAccepted);
        };

        var update = function (patient, openMRSPatient) {
            return patientServiceStrategy.update(patient, openMRSPatient, $rootScope.patientConfiguration.attributeTypes);
        };

        var getAllPatientIdentifiers = function (uuid) {
            var url = Bahmni.Registration.Constants.basePatientUrl + uuid + "/identifier";
            return $http.get(url, {
                method: "GET",
                params: {
                    includeAll: true
                },
                withCredentials: true
            });
        };

        var updateImage = function (uuid, image) {
            var url = baseOpenMRSRESTURL + "/personimage/";
            var data = {
                "person": {"uuid": uuid},
                "base64EncodedImage": image
            };
            var config = {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            };
            return $http.post(url, data, config);
        };

        var getRegistrationMessage = function (patientId, name, age, gender) {
            var locationName = $rootScope.facilityVisitLocation && $rootScope.facilityVisitLocation.name ? $rootScope.facilityVisitLocation.name : $rootScope.loggedInLocation.name;
            var message = $translate.instant(appService.getAppDescriptor().getConfigValue("registrationMessage") || Bahmni.Registration.Constants.registrationMessage);
            message = message.replace("#clinicName", locationName);
            message = message.replace("#patientId", patientId);
            message = message.replace("#name", name);
            message = message.replace("#age", age);
            message = message.replace("#gender", gender);
            message = message.replace("#helpDeskNumber", $rootScope.helpDeskNumber);
            return message;
        };

        return {
            search: search,
            searchByIdentifier: searchByIdentifier,
            create: create,
            update: update,
            get: get,
            updateImage: updateImage,
            searchByNameOrIdentifier: searchByNameOrIdentifier,
            getAllPatientIdentifiers: getAllPatientIdentifiers,
            getRegistrationMessage: getRegistrationMessage
        };
    }]);

'use strict';

angular.module('bahmni.registration')
    .factory('patientAttributeService', ['$http', '$q', function ($http, $q) {
        var urlMap;

        var init = function () {
            urlMap = {
                "personName": Bahmni.Common.Constants.bahmniSearchUrl + "/personname",
                "personAttribute": Bahmni.Common.Constants.bahmniSearchUrl + "/personattribute"
            };
        };
        init();

        var search = function (fieldName, query, type) {
            var url = urlMap[type];
            var queryWithoutTrailingSpaces = query.trimLeft();

            return $http.get(url, {
                method: "GET",
                params: {q: queryWithoutTrailingSpaces, key: fieldName },
                withCredentials: true
            });
        };

        return {
            search: search
        };
    }]);

'use strict';

angular.module('bahmni.registration')
    .factory('addressHierarchyService', ['$http',
        function ($http) {
            var parseSearchString = function (searchString) {
                searchString = searchString.replace(new RegExp("\\(", "g"), "\\(");
                searchString = searchString.replace(new RegExp("\\)", "g"), "\\)");
                return searchString;
            };

            var search = function (fieldName, query, parentUuid) {
                var params = {searchString: query, addressField: fieldName, parentUuid: parentUuid, limit: defaults.maxAutocompleteResults};
                var url = Bahmni.Registration.Constants.openmrsUrl + "/module/addresshierarchy/ajax/getPossibleAddressHierarchyEntriesWithParents.form";

                return $http.get(url, {
                    method: "GET",
                    params: params,
                    withCredentials: true
                });
            };

            var getNextAvailableParentName = function (addressField) {
                var parent = addressField.parent;
                while (parent) {
                    if (parent.name) {
                        return parent.name;
                    } else {
                        parent = parent.parent;
                    }
                }
                return "";
            };

            var getAddressDataResults = function (data) {
                return data.data ? data.data.map(function (addressField) {
                    var parentName = getNextAvailableParentName(addressField);
                    return {
                        'value': addressField.name,
                        'label': addressField.name + (parentName ? ", " + parentName : ""),
                        addressField: addressField
                    };
                }) : [];
            };

            return {
                search: search,
                getNextAvailableParentName: getNextAvailableParentName,
                getAddressDataResults: getAddressDataResults
            };
        }]);

'use strict';

angular.module('bahmni.registration')
    .factory('registrationCardPrinter', ['printer', function (printer) {
        var print = function (templatePath, patient, obs, encounterDateTime, location) {
            templatePath = templatePath || "views/nolayoutfound.html";
            printer.print(templatePath, {patient: patient, today: new Date(), obs: obs || {}, encounterDateTime: encounterDateTime, location: location });
        };

        return {
            print: print
        };
    }]);

'use strict';

Bahmni.Common.Domain.AttributeTypeMapper = (function () {
    function AttributeTypeMapper () {
    }

    AttributeTypeMapper.prototype.mapFromOpenmrsAttributeTypes = function (mrsAttributeTypes, mandatoryAttributes, attributesConfig, defaultLocale) {
        var attributeTypes = [];
        angular.forEach(mrsAttributeTypes, function (mrsAttributeType) {
            var isRequired = function () {
                var element = _.find(mandatoryAttributes, function (mandatoryAttribute) {
                    return mandatoryAttribute == mrsAttributeType.name;
                });
                return element ? true : false;
            };

            var getLocaleSpecificConceptName = function (concept, locale, conceptNameType) {
                conceptNameType = conceptNameType ? conceptNameType : "SHORT";
                var localeSpecificName = _.filter(concept.names, function (name) {
                    return name.locale == locale && name.conceptNameType == conceptNameType;
                });
                if (localeSpecificName && localeSpecificName[0]) {
                    return localeSpecificName[0].display;
                }
                return null;
            };

            var getConceptDisplayName = function (concept, locale) {
                var conceptNames = concept.names || [];
                var shortName = conceptNames.find(function (cn) {
                    return cn.locale === locale && cn.conceptNameType === "SHORT";
                });
                if (shortName) {
                    return shortName.name;
                }
                var fsName = conceptNames.find(function (cn) {
                    return cn.locale === locale && cn.conceptNameType === "FULLY_SPECIFIED";
                });
                if (fsName) {
                    return fsName.name;
                }
                return concept.name ? concept.name.display : concept.displayString;
            };

            var attributeType = {
                uuid: mrsAttributeType.uuid,
                sortWeight: mrsAttributeType.sortWeight,
                name: mrsAttributeType.name,
                fullySpecifiedName: mrsAttributeType.name,
                description: mrsAttributeType.description || mrsAttributeType.name,
                format: mrsAttributeType.format || mrsAttributeType.datatypeClassname,
                answers: [],
                required: isRequired(),
                concept: mrsAttributeType.concept || {},
                excludeFrom: (attributesConfig && attributesConfig[mrsAttributeType.name] && attributesConfig[mrsAttributeType.name].excludeFrom) || []
            };
            attributeType.concept.dataType = attributeType.concept.datatype && attributeType.concept.datatype.name;

            if (mrsAttributeType.concept && mrsAttributeType.concept.answers) {
                angular.forEach(mrsAttributeType.concept.answers, function (mrsAnswer) {
                    var displayName = getConceptDisplayName(mrsAnswer, defaultLocale);
                    var fullySpecifiedName = getLocaleSpecificConceptName(mrsAnswer, defaultLocale, "FULLY_SPECIFIED");
                    fullySpecifiedName = fullySpecifiedName || mrsAnswer.name.display;

                    attributeType.answers.push({
                        fullySpecifiedName: fullySpecifiedName,
                        description: displayName,
                        conceptId: mrsAnswer.uuid
                    });
                });
            }
            if (attributeType.format == "org.openmrs.customdatatype.datatype.RegexValidatedTextDatatype") {
                attributeType.pattern = mrsAttributeType.datatypeConfig;
            }

            attributeTypes.push(attributeType);
        });
        return {
            attributeTypes: attributeTypes
        };
    };

    return AttributeTypeMapper;
})();

'use strict';

Bahmni.Common.Domain.AttributeFormatter = (function () {
    function AttributeFormatter () {
    }

    AttributeFormatter.prototype.getMrsAttributes = function (model, attributeTypes) {
        return attributeTypes.map(function (result) {
            var attribute = {
                attributeType: {
                    uuid: result.uuid
                }
            };
            if (!_.isEmpty(model)) {
                setAttributeValue(result, attribute, model[result.name]);
            }
            return attribute;
        });
    };

    AttributeFormatter.prototype.getMrsAttributesForUpdate = function (model, attributeTypes, attributes) {
        return _.filter(AttributeFormatter.prototype.getMrsAttributes(model, attributeTypes), function (mrsAttribute) {
            var attribute = _.find(attributes, function (attribute) {
                return mrsAttribute.attributeType.uuid === attribute.attributeType.uuid;
            });
            if (attribute && !attribute.voided) {
                mrsAttribute.uuid = attribute.uuid;
            }
            return isAttributeChanged(mrsAttribute);
        });
    };

    AttributeFormatter.prototype.removeUnfilledAttributes = function (formattedAttributes) {
        return _.filter(formattedAttributes, isAttributeChanged);
    };

    var isAttributeChanged = function (attribute) {
        return attribute.value || attribute.uuid;
    };

    var setAttributeValue = function setAttributeValue (attributeType, attr, value) {
        if (value === "" || value === null || value === undefined || value.conceptUuid === null) {
            attr.voided = true;
        } else if (attributeType.format === "org.openmrs.Concept") {
            var attrDescription = _.find(attributeType.answers, function (answer) {
                if (answer.conceptId === value.conceptUuid) {
                    return true;
                }
            });
            attr.value = attrDescription != undefined ? attrDescription.description : null;
            attr.hydratedObject = value.conceptUuid;
        } else if (attributeType.format == "org.openmrs.util.AttributableDate" || attributeType.format == "org.openmrs.customdatatype.datatype.DateDatatype") {
            var mnt = moment(value);
            attr.value = mnt.format('YYYY-MM-DD');
        } else {
            attr.value = value.toString();
        }
    };

    return AttributeFormatter;
})();

'use strict';

angular.module('bahmni.registration').factory('openmrsPatientMapper', ['patient', '$rootScope', 'age', 'identifiers',
    function (patient, $rootScope, age, identifiers) {
        var patientModel = patient;
        var whereAttributeTypeExists = function (attribute) {
                return $rootScope.patientConfiguration.get(attribute.attributeType.uuid);
            },
            addAttributeToPatient = function (patient, attribute) {
                var attributeType = $rootScope.patientConfiguration.get(attribute.attributeType.uuid);
                if (attributeType) {
                    if (attributeType.format === "org.openmrs.Concept" && attribute.value) {
                        patient[attributeType.name] = {conceptUuid: attribute.value.uuid, value: attribute.value.display};
                    } else if (attributeType.format === "org.openmrs.util.AttributableDate") {
                        patient[attributeType.name] = parseDate(attribute.value);
                    } else {
                        patient[attributeType.name] = attribute.value;
                    }
                }
            },
            mapAttributes = function (patient, attributes) {
                attributes.filter(whereAttributeTypeExists).forEach(function (attribute) {
                    addAttributeToPatient(patient, attribute);
                });
            },
            parseDate = function (dateStr) {
                return Bahmni.Common.Util.DateUtil.parseServerDateToDate(dateStr);
            },
            mapAddress = function (preferredAddress) {
                return preferredAddress || {};
            },
            mapRelationships = function (patient, relationships) {
                patient.relationships = relationships || [];
                patient.newlyAddedRelationships = [{}];
                patient.hasRelationships = patient.relationships.length > 0;
            },

            map = function (openmrsPatient) {
                var relationships = openmrsPatient.relationships;
                openmrsPatient = openmrsPatient.patient;
                var openmrsPerson = openmrsPatient.person;
                var patient = patientModel.create();
                var birthDate = parseDate(openmrsPerson.birthdate);
                patient.uuid = openmrsPatient.uuid;
                patient.givenName = openmrsPerson.preferredName.givenName;
                patient.middleName = openmrsPerson.preferredName.middleName;
                patient.familyName = openmrsPerson.preferredName.familyName;
                patient.birthdate = !birthDate ? null : birthDate;
                patient.age = birthDate ? age.fromBirthDate(birthDate) : null;
                patient.gender = openmrsPerson.gender;
                patient.address = mapAddress(openmrsPerson.preferredAddress);
                patient.birthtime = parseDate(openmrsPerson.birthtime);
                patient.image = Bahmni.Registration.Constants.patientImageUrlByPatientUuid + openmrsPatient.uuid + "&q=" + new Date().toISOString();
                patient.registrationDate = Bahmni.Common.Util.DateUtil.parse(openmrsPerson.auditInfo.dateCreated);
                patient.dead = openmrsPerson.dead;
                patient.isDead = patient.dead;
                patient.deathDate = parseDate(openmrsPerson.deathDate);
                patient.causeOfDeath = openmrsPerson.causeOfDeath;
                patient.birthdateEstimated = openmrsPerson.birthdateEstimated;
                patient.bloodGroup = openmrsPerson.bloodGroup;
                mapAttributes(patient, openmrsPerson.attributes);
                mapRelationships(patient, relationships);
                _.assign(patient, identifiers.mapIdentifiers(openmrsPatient.identifiers));

                return patient;
            };

        return {
            map: map
        };
    }]);

'use strict';

Bahmni.Registration.CreatePatientRequestMapper = (function () {
    function CreatePatientRequestMapper (currentDate) {
        this.currentDate = currentDate;
    }

    CreatePatientRequestMapper.prototype.mapFromPatient = function (patientAttributeTypes, patient) {
        var constants = Bahmni.Registration.Constants;
        var allIdentifiers = _.concat(patient.extraIdentifiers, patient.primaryIdentifier);
        var identifiers = _.filter(allIdentifiers, function (identifier) {
            return !_.isEmpty(identifier.selectedIdentifierSource) || (identifier.identifier !== undefined);
        });
        identifiers = _.map(identifiers, function (identifier) {
            return {
                identifier: identifier.identifier,
                identifierSourceUuid: identifier.selectedIdentifierSource ? identifier.selectedIdentifierSource.uuid : undefined,
                identifierPrefix: identifier.selectedIdentifierSource ? identifier.selectedIdentifierSource.prefix : undefined,
                identifierType: identifier.identifierType.uuid,
                preferred: identifier.preferred,
                voided: identifier.voided
            };
        });
        var openMRSPatient = {
            patient: {
                person: {
                    names: [
                        {
                            givenName: patient.givenName,
                            middleName: patient.middleName,
                            familyName: patient.familyName,
                            display: patient.givenName + (patient.familyName ? " " + patient.familyName : ""),
                            "preferred": false
                        }
                    ],
                    addresses: [_.pick(patient.address, constants.allAddressFileds)],
                    birthdate: this.getBirthdate(patient.birthdate, patient.age),
                    birthdateEstimated: patient.birthdateEstimated,
                    gender: patient.gender,
                    birthtime: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(patient.birthtime),
                    personDateCreated: patient.registrationDate,
                    attributes: new Bahmni.Common.Domain.AttributeFormatter().getMrsAttributes(patient, patientAttributeTypes),
                    dead: patient.dead,
                    deathDate: Bahmni.Common.Util.DateUtil.getDateWithoutTime(patient.deathDate),
                    causeOfDeath: patient.causeOfDeath ? patient.causeOfDeath.uuid : '',
                    uuid: patient.uuid
                },
                identifiers: identifiers,
                uuid: patient.uuid
            }
        };

        this.setImage(patient, openMRSPatient);
        openMRSPatient.relationships = patient.relationships;
        return openMRSPatient;
    };

    CreatePatientRequestMapper.prototype.setImage = function (patient, openMRSPatient) {
        if (patient.getImageData()) {
            openMRSPatient.image = patient.getImageData();
        }
    };

    CreatePatientRequestMapper.prototype.getBirthdate = function (birthdate, age) {
        var mnt;
        if (birthdate) {
            mnt = moment(birthdate);
        } else if (age !== undefined) {
            mnt = moment(this.currentDate).subtract('days', age.days).subtract('months', age.months).subtract('years', age.years);
        }
        return mnt.format('YYYY-MM-DD');
    };

    return CreatePatientRequestMapper;
})();

'use strict';

Bahmni.Registration.UpdatePatientRequestMapper = (function () {
    var UpdatePatientRequestMapper = function (currentDate) {
        this.currentDate = currentDate;
    };

    UpdatePatientRequestMapper.prototype.currentDate = undefined;

    UpdatePatientRequestMapper.prototype.mapFromPatient = function (patientAttributeTypes, openMRSPatient, patient) {
        var openMRSPatientProfile = {
            patient: {
                person: {
                    names: [
                        {
                            uuid: openMRSPatient.person.names[0].uuid,
                            givenName: patient.givenName,
                            middleName: patient.middleName,
                            familyName: patient.familyName,
                            display: patient.givenName + (patient.familyName ? " " + patient.familyName : ""),
                            "preferred": true
                        }
                    ],
                    addresses: [_.pick(patient.address, Bahmni.Registration.Constants.allAddressFileds)],
                    birthdate: this.getBirthdate(patient.birthdate, patient.age),
                    birthdateEstimated: patient.birthdateEstimated,
                    birthtime: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(patient.birthtime),
                    gender: patient.gender,
                    attributes: this.getMrsAttributes(openMRSPatient, patient, patientAttributeTypes),
                    dead: patient.dead,
                    deathDate: Bahmni.Common.Util.DateUtil.getDateWithoutTime(patient.deathDate),
                    causeOfDeath: patient.causeOfDeath ? patient.causeOfDeath.uuid : ''
                }
            }
        };

        var allIdentifiers = _.concat(patient.extraIdentifiers, patient.primaryIdentifier);
        var nonEmptyIdentifiers = _.filter(allIdentifiers, function (identifier) {
            return identifier.uuid || identifier.identifier;
        });

        openMRSPatientProfile.patient.identifiers = _.map(nonEmptyIdentifiers, function (identifier) {
            return {
                uuid: identifier.uuid,
                identifier: identifier.identifier,
                identifierType: identifier.identifierType.uuid,
                preferred: identifier.preferred,
                voided: identifier.voided
            };
        });

        this.setImage(patient, openMRSPatientProfile);

        if (patient.relationships) {
            openMRSPatientProfile.relationships = patient.relationships;
        }

        return openMRSPatientProfile;
    };

    UpdatePatientRequestMapper.prototype.setImage = function (patient, openMRSPatient) {
        if (patient.getImageData()) {
            openMRSPatient.image = patient.getImageData();
        }
    };

    UpdatePatientRequestMapper.prototype.getMrsAttributes = function (openMRSPatient, patient, patientAttributeTypes) {
        var attributes = [];
        patientAttributeTypes.forEach(function (attributeType) {
            var attr = {
                attributeType: {
                    uuid: attributeType.uuid
                }
            };
            var savedAttribute = openMRSPatient.person.attributes.filter(function (attribute) {
                return attributeType.uuid === attribute.attributeType.uuid;
            })[0];

            if (savedAttribute) {
                attr.uuid = savedAttribute.uuid;
                setAttributeValue(attributeType, attr, patient[savedAttribute.attributeType.display]);
            } else {
                setAttributeValue(attributeType, attr, patient[attributeType.name]);
            }
            attributes.push(attr);
        });
        return attributes;
    };

    var setAttributeValue = function (attributeType, attr, value) {
        if (value === "" || value === null || value === undefined || value.conceptUuid === null) {
            attr.voided = true;
        } else if (attributeType.format === "org.openmrs.Concept") {
            attr.hydratedObject = value.conceptUuid;
        } else if (attributeType.format === "org.openmrs.util.AttributableDate") {
            var mnt = moment(value);
            attr.value = mnt.format('YYYY-MM-DDTHH:mm:ss.SSSZZ');
        } else {
            attr.value = value.toString();
        }
    };

    UpdatePatientRequestMapper.prototype.getBirthdate = function (birthdate, age) {
        var mnt;
        if (birthdate) {
            mnt = moment(birthdate);
        } else if (age !== undefined) {
            mnt = moment(this.currentDate).subtract('days', age.days).subtract('months', age.months).subtract('years', age.years);
        }
        return mnt.format('YYYY-MM-DDTHH:mm:ss.SSSZZ');
    };

    return UpdatePatientRequestMapper;
})();

'use strict';

angular.module('bahmni.registration')
    .factory('patient', ['age', 'identifiers', function (age, identifiers) {
        var create = function () {
            var calculateAge = function () {
                if (this.birthdate) {
                    this.age = age.fromBirthDate(this.birthdate);
                } else {
                    this.age = age.create(null, null, null);
                }
            };

            var calculateBirthDate = function () {
                this.birthdate = age.calculateBirthDate(this.age);
            };

            var fullNameLocal = function () {
                var givenNameLocal = this.givenNameLocal || this.givenName || "";
                var middleNameLocal = this.middleNameLocal || this.middleName || "";
                var familyNameLocal = this.familyNameLocal || this.familyName || "";
                return (givenNameLocal.trim() + " " + (middleNameLocal ? middleNameLocal + " " : "") + familyNameLocal.trim()).trim();
            };

            var getImageData = function () {
                return this.image && this.image.indexOf('data') === 0 ? this.image.replace("data:image/jpeg;base64,", "") : null;
            };

            var identifierDetails = identifiers.create();

            var patient = {
                address: {},
                age: age.create(),
                birthdate: null,
                calculateAge: calculateAge,
                image: '../images/blank-user.gif',
                fullNameLocal: fullNameLocal,
                getImageData: getImageData,
                relationships: [],
                newlyAddedRelationships: [{}],
                deletedRelationships: [],
                calculateBirthDate: calculateBirthDate
            };
            return _.assign(patient, identifierDetails);
        };

        return {
            create: create
        };
    }]);

'use strict';

Bahmni.Registration.Identifier = function (identifierType) {
    this.identifierType = identifierType;
    this.preferred = identifierType.primary;
    this.voided = false;
    return this;
};

var prototype = Bahmni.Registration.Identifier.prototype;
prototype.hasIdentifierSources = function () {
    return this.identifierType.identifierSources.length > 0;
};

prototype.isPrimary = function () {
    return this.identifierType.primary;
};
prototype.map = function (identifiers) {
    var savedIdentifier = _.find(identifiers, {identifierType: {uuid: this.identifierType.uuid}});
    if (savedIdentifier) {
        this.registrationNumber = savedIdentifier.identifier;
        this.identifier = savedIdentifier.identifier;
        this.preferred = savedIdentifier.preferred;
        this.voided = savedIdentifier.voided;
        this.uuid = savedIdentifier.uuid;
    }
    return this;
};

prototype.hasIdentifierSourceWithEmptyPrefix = function () {
    var identifierSources = this.identifierType.identifierSources;
    return identifierSources.length === 1 && _.isEmpty(identifierSources[0].prefix);
};

prototype.isIdentifierRequired = function () {
    if (this.hasOldIdentifier) {
        return true;
    } else if (this.identifierType.required) {
        return !this.hasIdentifierSources();
    }
    return false;
};

prototype.generate = function () {
    if (this.registrationNumber && this.registrationNumber.length > 0) {
        this.identifier = this.selectedIdentifierSource ? this.selectedIdentifierSource.prefix + this.registrationNumber : this.registrationNumber;
        this.voided = false;
    } else if (this.uuid) {
        this.voided = true;
    }
};

prototype.clearRegistrationNumber = function () {
    this.registrationNumber = null;
    this.identifier = null;
};


'use strict';

angular.module('bahmni.registration')
    .factory('identifiers', ['$rootScope', 'preferences', function ($rootScope, preferences) {
        var create = function () {
            var identifiers = [];
            _.each($rootScope.patientConfiguration.identifierTypes, function (identifierType) {
                var identifier = new Bahmni.Registration.Identifier(identifierType);
                if (identifier.isPrimary()) {
                    identifier.selectedIdentifierSource = _.find(identifier.identifierType.identifierSources, {prefix: preferences.identifierPrefix});
                    identifier.hasOldIdentifier = preferences.hasOldIdentifier;
                }
                identifier.selectedIdentifierSource = identifier.selectedIdentifierSource || identifier.identifierType.identifierSources[0];
                identifiers.push(identifier);
            });
            return {
                primaryIdentifier: getPrimaryIdentifier(identifiers),
                extraIdentifiers: getExtraIdentifiers(identifiers)
            };
        };

        var mapIdentifiers = function (identifiers) {
            var mappedIdentifiers = [];
            _.each($rootScope.patientConfiguration.identifierTypes, function (identifierType) {
                var mappedIdentifier = new Bahmni.Registration.Identifier(identifierType).map(identifiers);
                mappedIdentifiers.push(mappedIdentifier);
            });

            return {
                primaryIdentifier: getPrimaryIdentifier(mappedIdentifiers),
                extraIdentifiers: getExtraIdentifiers(mappedIdentifiers)
            };
        };

        var getPrimaryIdentifier = function (identifiers) {
            return _.find(identifiers, {identifierType: {primary: true}});
        };

        var getExtraIdentifiers = function (identifiers) {
            return _.filter(identifiers, {identifierType: {primary: false}});
        };

        return {
            create: create,
            mapIdentifiers: mapIdentifiers
        };
    }]);

'use strict';

angular.module('bahmni.registration')
    .factory('preferences', [function () {
        return {
            hasOldIdentifier: false
        };
    }]);

'use strict';

Bahmni.Registration.RegistrationEncounterConfig = (function () {
    function RegistrationEncounterConfig (conceptData, encounterTypes, visitTypes) {
        this.conceptData = conceptData;
        this.encounterTypes = encounterTypes;
        this.visitTypes = visitTypes;
    }

    RegistrationEncounterConfig.prototype = {
        getVisitTypesAsArray: function () {
            var visitTypesArray = [];
            for (var name in this.visitTypes) {
                visitTypesArray.push({name: name, uuid: this.visitTypes[name]});
            }
            return visitTypesArray;
        },
        getDefaultVisitType: function (locationUuid) {
            var visitType = null;
            _.each(this.loginLocationToVisitTypeMap.results, function (result) {
                if (result.entity.uuid === locationUuid) {
                    visitType = result.mappings[0].name;
                }
            });
            return visitType;
        }
    };
    return RegistrationEncounterConfig;
})();

'use strict';

Bahmni.Registration.PatientConfig = (function () {
    function PatientConfig (patientAttributeTypes, identifierTypes, patientInformation, addressAttributes) {
        this.attributeTypes = patientAttributeTypes;
        this.identifierTypes = identifierTypes;
        var addressAttributesSection = [];
        var patientAttributesSections = {};
        // Avoiding multiple calls from angular code. Side effect of the way angular does dirty check. [Shruti/ Sush]
        if (!this.attributeRows && this.attributeTypes) {
            if (!patientInformation) {
                this.attributeRows = this.splitAsRows(this.attributeTypes);
                return;
            }

            var hiddenAttributes = patientInformation["hidden"] && patientInformation["hidden"].attributes;
            delete patientInformation["hidden"];

            var otherInformationAttributes = this.attributeTypes.map(function (item) {
                item.keyPrefix = "PATIENT_ATTRIBUTE_";
                return item;
            }).filter(function (item) {
                return !isHiddenPatientAttribute(hiddenAttributes, item) &&
                    !isItemAMandatoryField(item) &&
                    !isAttributeInOtherSection(patientInformation, patientAttributesSections, item, addressAttributes, addressAttributesSection);
            });

            this.attributeRows = this.splitAsRows(otherInformationAttributes);
            this.patientAttributesSections = patientAttributesSections;
            this.addressAttributesSection = addressAttributesSection;
        }
    }

    function isHiddenPatientAttribute (hiddenAttributes, item) { // Ignore hidden fields from patientInformation configuration
        return hiddenAttributes && hiddenAttributes.indexOf(item.name) > -1;
    }

    function isAttributeInOtherSection (patientInformation, patientAttributesSections, item, addressAttributes, addressAttributesSection) {
        if (item.name.includes("FileNumber") || item.name.includes("Location of Visit")) {
            return true;
        }
        if (addressAttributes !== null && addressAttributes !== undefined && addressAttributes.length > 0 && addressAttributes.includes(item.name)) {
            addressAttributesSection.push(item);
            return true;
        } else {
            return _.find(patientInformation, function (section, key) {
                return _.find(section.attributes, function (attribute) {
                    if (attribute === item.name) {
                        var sectionObject = patientAttributesSections[key];
                        if (!sectionObject) {
                            sectionObject = {
                                attributes: [],
                                title: section.title,
                                expanded: section.expanded,
                                translationKey: section.translationKey,
                                shortcutKey: section.shortcutKey,
                                order: section.order,
                                canShow: true
                            };
                        }
                        sectionObject.attributes.push(item);
                        patientAttributesSections[key] = sectionObject;
                        return true;
                    }
                    return false;
                });
            });
        }
    }

    function isItemAMandatoryField (item) {
        var mandatoryPatientAttributes = ["healthCenter", "givenNameLocal", "middleNameLocal", "familyNameLocal"];
        return mandatoryPatientAttributes.indexOf(item.name) > -1;
    }

    PatientConfig.prototype = {
        get: function (attributeUuid) {
            return this.attributeTypes.filter(function (item) {
                return item.uuid === attributeUuid;
            })[0];
        },

        customAttributeRows: function () {
            return this.attributeRows;
        },

        getAddressAttributes: function () {
            return this.addressAttributesSection;
        },

        getPatientAttributesSections: function () {
            return this.patientAttributesSections;
        },

        getOrderedPatientAttributesSections: function () {
            return _.sortBy(this.patientAttributesSections, 'order');
        },

        splitAsRows: function (attributes) {
            var attributeRows = [];
            var row = [];
            for (var i in attributes) {
                row.push(attributes[i]);
                if (i !== 0 && (i % 2) !== 0) {
                    attributeRows.push(row);
                    row = [];
                }
            }
            if (row.length > 0) {
                attributeRows.push(row);
            }

            return attributeRows;
        },

        heathCentreAttribute: function () {
            return this.attributeTypes.filter(function (item) {
                return item.name === "healthCenter";
            })[0];
        },

        local: function () {
            var givenName = this.attributeTypes.filter(function (item) {
                return item.name === "givenNameLocal";
            })[0];
            var middleName = this.attributeTypes.filter(function (item) {
                return item.name === "middleNameLocal";
            })[0];
            var familyName = this.attributeTypes.filter(function (item) {
                return item.name === "familyNameLocal";
            })[0];

            if (givenName && middleName && familyName) {
                return { "showNameField": true, "labelForNameField": givenName.description, "placeholderForGivenName": givenName.description, "placeholderForMiddleName": middleName.description, "placeholderForFamilyName": familyName.description};
            }
            return {"showNameField": false};
        }

    };
    return PatientConfig;
})();

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.PatientSearch = Bahmni.Common.PatientSearch || {};

Bahmni.Common.PatientSearch.Constants = {
    searchExtensionTileViewType: "tile",
    searchExtensionTabularViewType: "tabular",
    searchExtensionCustomViewType: "custom",
    nameHeading: ["NAME", "Name", "name"],
    patientTileHeight: 100,
    patientTileWidth: 100,
    printIgnoreHeadingsList: ["DQ_COLUMN_TITLE_ACTION"],
    tileLoadRatio: 1 / 2
};

'use strict';

Bahmni.Common.PatientSearch.Search = function (searchTypes) {
    var self = this;
    self.searchTypes = searchTypes || [];
    self.searchType = this.searchTypes[0];
    self.searchParameter = '';
    self.noResultsMessage = null;
    self.searchResults = [];
    self.activePatients = [];
    self.navigated = false;
    self.links = self.searchType && self.searchType.links ? self.searchType.links : [];
    self.searchColumns = self.searchType && self.searchType.searchColumns ? self.searchType.searchColumns : ["identifier", "name"];
    angular.forEach(searchTypes, function (searchType) {
        searchType.patientCount = "...";
    });

    self.switchSearchType = function (searchType) {
        self.noResultsMessage = null;
        if (!self.isSelectedSearch(searchType)) {
            self.searchParameter = '';
            self.navigated = true;
            self.searchType = searchType;
            self.activePatients = [];
            self.searchResults = [];
            self.links = self.searchType && self.searchType.links ? self.searchType.links : [];
            self.searchColumns = self.searchType && self.searchType.searchColumns ? self.searchType.searchColumns : ["identifier", "name"];
        }
        self.markPatientEntry();
    };

    self.markPatientEntry = function () {
        self.startPatientSearch = true;
        window.setTimeout(function () { // eslint-disable-line angular/timeout-service
            self.startPatientSearch = false;
        });
    };

    self.patientsCount = function () {
        return self.activePatients.length;
    };

    self.updatePatientList = function (patientList) {
        self.activePatients = patientList.map(mapPatient);
        self.searchResults = self.activePatients;
    };

    self.updateSearchResults = function (patientList) {
        self.updatePatientList(patientList);
        if (self.activePatients.length === 0 && self.searchParameter != '') {
            self.noResultsMessage = "NO_RESULTS_FOUND";
        } else {
            self.noResultsMessage = null;
        }
    };

    self.hasSingleActivePatient = function () {
        return self.activePatients.length === 1;
    };

    self.filterPatients = function (matchingCriteria) {
        matchingCriteria = matchingCriteria ? matchingCriteria : matchesNameOrId;
        self.searchResults = self.searchParameter ? self.activePatients.filter(matchingCriteria) : self.activePatients;
    };

    self.filterPatientsByIdentifier = function () {
        self.filterPatients(matchesId);
    };

    self.isSelectedSearch = function (searchType) {
        return self.searchType && self.searchType.id == searchType.id;
    };

    self.isCurrentSearchLookUp = function () {
        return self.searchType && self.searchType.handler;
    };

    self.isTileView = function () {
        return self.searchType && self.searchType.view === Bahmni.Common.PatientSearch.Constants.searchExtensionTileViewType;
    };

    self.isTabularView = function () {
        return self.searchType && self.searchType.view === Bahmni.Common.PatientSearch.Constants.searchExtensionTabularViewType;
    };

    self.isCustomView = function () {
        return self.searchType && self.searchType.view === Bahmni.Common.PatientSearch.Constants.searchExtensionCustomViewType;
    };

    self.showPatientCountOnSearchParameter = function (searchType) {
        return showPatientCount(searchType) && self.searchParameter;
    };

    function mapPatient (patient) {
        if (patient.name || patient.givenName || patient.familyName) {
            patient.name = patient.name || (patient.givenName + (patient.familyName ? ' ' + patient.familyName : ""));
        }
        patient.display = _.map(self.searchColumns, function (column) {
            return patient[column];
        }).join(" - ");

        var extraIdentifier = null;
        if (patient.extraIdentifiers) {
            var objIdentifiers = JSON.parse(patient.extraIdentifiers);
            for (var key in objIdentifiers) {
                extraIdentifier = objIdentifiers[key];
                break;
            }
        } else if (patient.extraIdentifierVal) {
            extraIdentifier = patient.extraIdentifierVal;
        }
        patient.extraIdentifier = patient.extraIdentifier ? patient.extraIdentifier : (extraIdentifier ? extraIdentifier : patient.identifier);
        patient.image = Bahmni.Common.Constants.patientImageUrlByPatientUuid + patient.uuid;
        return patient;
    }

    var matchesNameOrId = function (patient) {
        return patient.display.toLowerCase().indexOf(self.searchParameter.toLowerCase()) !== -1;
    };

    var matchesId = function (patient) {
        return patient.identifier.toLowerCase().indexOf(self.searchParameter.toLowerCase()) !== -1;
    };

    var showPatientCount = function (searchType) {
        return self.isSelectedSearch(searchType) && self.isCurrentSearchLookUp();
    };
};

angular.module('bahmni.common.patientSearch', ['bahmni.common.patient', 'infinite-scroll']);


'use strict';

angular.module('bahmni.common.patientSearch')
.controller('PatientsListController', ['$scope', '$window', 'patientService', '$rootScope', 'appService', 'spinner',
    '$stateParams', '$bahmniCookieStore', 'printer', 'configurationService', "$timeout",
    function ($scope, $window, patientService, $rootScope, appService, spinner, $stateParams, $bahmniCookieStore, printer, configurationService, $timeout) {
        $scope.preferExtraIdInSearchResults = appService.getAppDescriptor().getConfigValue("preferExtraIdInSearchResults");
        $scope.activeHeaders = [];
        const DEFAULT_FETCH_DELAY = 2000;
        var patientSearchConfig = appService.getAppDescriptor().getConfigValue("patientSearch");
        var patientListSpinner;
        var initialize = function () {
            var searchTypes = appService.getAppDescriptor().getExtensions("org.bahmni.patient.search", "config").map(mapExtensionToSearchType);
            $scope.ignoredTabularViewHeadingsConfig = appService.getAppDescriptor().getConfigValue("ignoredTabularViewHeadings") || [];
            $scope.identifierHeadingsConfig = appService.getAppDescriptor().getConfigValue("identifierHeadings") || [];
            $scope.search = new Bahmni.Common.PatientSearch.Search(_.without(searchTypes, undefined));
            $scope.search.markPatientEntry();
            $scope.$watch('search.searchType', function (currentSearchType) {
                _.isEmpty(currentSearchType) || fetchPatients(currentSearchType);
            });
            $scope.$watch('search.activePatients', function (activePatientsList) {
                if (activePatientsList.length > 0 && patientListSpinner) {
                    hideSpinner(spinner, patientListSpinner, $(".tab-content"));
                }
            });
            $scope.$watch('search.visiblePatients', function (activePatientsList) {
                if (activePatientsList && activePatientsList.length > 0) {
                    $scope.getHeadings();
                }
                else {
                    if ($scope.activeHeaders.length != 0) {
                        $scope.activeHeaders = [];
                    }
                }
            });
            if (patientSearchConfig && patientSearchConfig.serializeSearch) {
                getPatientCountSeriallyBySearchIndex(0);
            }
            else {
                _.each($scope.search.searchTypes, function (searchType) {
                    _.isEmpty(searchType) || ($scope.search.searchType != searchType && getPatientCount(searchType, null));
                });
            }
            if ($rootScope.currentSearchType != null) {
                $scope.search.switchSearchType($rootScope.currentSearchType);
            }
            configurationService.getConfigurations(['identifierTypesConfig']).then(function (response) {
                $scope.primaryIdentifier = _.find(response.identifierTypesConfig, {primary: true}).name;
            });
        };

        $scope.searchPatients = function () {
            return spinner.forPromise(patientService.search($scope.search.searchParameter)).then(function (response) {
                $scope.search.updateSearchResults(response.data.pageOfResults);
                if ($scope.search.hasSingleActivePatient()) {
                    $scope.forwardPatient($scope.search.activePatients[0]);
                }
            });
        };

        $scope.filterPatientsAndSubmit = function () {
            if ($scope.search.searchResults.length == 1) {
                $scope.forwardPatient($scope.search.searchResults[0]);
            }
        };
        var getPatientCount = function (searchType, patientListSpinner) {
            if (searchType.handler) {
                var params = { q: searchType.handler, v: "full",
                    location_uuid: $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName).uuid,
                    provider_uuid: $rootScope.currentProvider.uuid };
                if (searchType.additionalParams) {
                    params["additionalParams"] = searchType.additionalParams;
                }
                patientService.findPatients(params).then(function (response) {
                    searchType.patientCount = response.data.length;
                    if ($scope.search.isSelectedSearch(searchType)) {
                        $scope.search.updatePatientList(response.data);
                    }
                    if (patientListSpinner) {
                        hideSpinner(spinner, patientListSpinner, $(".tab-content"));
                    }
                });
            }
        };

        var hideSpinner = function (spinnerObj, data, container) {
            spinnerObj.hide(data, container);
            $(container).children('patient-list-spinner').hide();
        };

        $scope.getHeadings = function () {
            if ($scope.search.activePatients && $scope.search.activePatients.length > 0) {
                var headings = _.chain($scope.search.activePatients[0])
                    .keys()
                    .filter(function (heading) {
                        return _.indexOf($scope.ignoredTabularViewHeadingsConfig, heading) === -1;
                    })
                    .value();
                setActiveHeadings(headings);
            }
        };

        var setActiveHeadings = function (headings) {
            headings.map(function (heading) {
                var newHeading = { name: heading, sortInfo: heading };
                if (!$scope.activeHeaders.find(function (activeHeader) {
                    return activeHeader.name == newHeading.name && activeHeader.sortInfo == newHeading.sortInfo;
                })) {
                    $scope.activeHeaders.push(newHeading);
                }
            });
        };

        $scope.sortVisiblePatientsBy = function (sortColumn) {
            var emptyObjects = _.filter($scope.search.searchResults, function (visiblePatient) {
                return !_.property(sortColumn)(visiblePatient);
            });

            var nonEmptyObjects = _.difference($scope.search.searchResults, emptyObjects);
            var sortedNonEmptyObjects = _.sortBy(nonEmptyObjects, function (visiblePatient) {
                var value = _.get(visiblePatient, sortColumn);
                if (!isNaN(Date.parse(value))) {
                    var parsedDate = moment(value, Bahmni.Common.Constants.clientDateDisplayFormat + " " + Bahmni.Common.Constants.timeDisplayFormat);
                    if (parsedDate.isValid()) {
                        return parsedDate.toDate().getTime();
                    }
                }
                else if (angular.isNumber(value)) {
                    return value;
                }
                else if (angular.isString(value)) {
                    return value.toLowerCase();
                }
                return value;
            });
            if ($scope.reverseSort) {
                sortedNonEmptyObjects.reverse();
            }
            $scope.search.visiblePatients = sortedNonEmptyObjects.concat(emptyObjects);
            $scope.sortColumn = sortColumn;
            $scope.reverseSort = !$scope.reverseSort;
        };

        $scope.isHeadingOfLinkColumn = function (heading) {
            var identifierHeading = _.includes($scope.identifierHeadingsConfig, heading);
            if (identifierHeading) {
                return identifierHeading;
            } else if ($scope.search.searchType && $scope.search.searchType.links) {
                return _.find($scope.search.searchType.links, {linkColumn: heading});
            }
            else if ($scope.search.searchType && $scope.search.searchType.linkColumn) {
                return _.includes([$scope.search.searchType.linkColumn], heading);
            }
        };
        $scope.isHeadingOfName = function (heading) {
            return _.includes(Bahmni.Common.PatientSearch.Constants.nameHeading, heading);
        };
        $scope.getPrintableHeadings = function () {
            $scope.getHeadings();
            var printableHeadings = $scope.activeHeaders.filter(function (heading) {
                return _.indexOf(Bahmni.Common.PatientSearch.Constants.printIgnoreHeadingsList, heading.name) === -1;
            });
            return printableHeadings;
        };
        $scope.printPage = function () {
            if ($scope.search.searchType.printHtmlLocation != null) {
                printer.printFromScope($scope.search.searchType.printHtmlLocation, $scope);
            }
        };

        $scope.iconAttributeConfig = appService.getAppDescriptor().getConfigValue('iconAttribute') || {};

        var mapExtensionToSearchType = function (appExtn) {
            return {
                name: appExtn.label,
                display: appExtn.extensionParams.display,
                handler: appExtn.extensionParams.searchHandler,
                forwardUrl: appExtn.extensionParams.forwardUrl,
                targetedTab: appExtn.extensionParams.targetedTab || null,
                id: appExtn.id,
                params: appExtn.extensionParams.searchParams,
                refreshTime: appExtn.extensionParams.refreshTime || 0,
                view: appExtn.extensionParams.view || Bahmni.Common.PatientSearch.Constants.searchExtensionTileViewType,
                showPrint: appExtn.extensionParams.showPrint || false,
                printHtmlLocation: appExtn.extensionParams.printHtmlLocation || null,
                additionalParams: appExtn.extensionParams.additionalParams,
                searchColumns: appExtn.extensionParams.searchColumns,
                translationKey: appExtn.extensionParams.translationKey,
                linkColumn: appExtn.extensionParams.linkColumn,
                links: appExtn.extensionParams.links,
                templateUrl: appExtn.extensionParams.templateUrl || null
            };
        };

        var debounceGetPatientCount = _.debounce(function (currentSearchType, patientListSpinner) {
            getPatientCount(currentSearchType, patientListSpinner);
        }, (patientSearchConfig && patientSearchConfig.fetchDelay) || DEFAULT_FETCH_DELAY, {});

        var showSpinner = function (spinnerObj, container) {
            $(container).children('patient-list-spinner').show();
            return spinnerObj.show(container);
        };

        var fetchPatients = function (currentSearchType) {
            if (patientListSpinner !== undefined) {
                hideSpinner(spinner, patientListSpinner, $(".tab-content"));
            }
            $rootScope.currentSearchType = currentSearchType;
            if ($scope.search.isCurrentSearchLookUp()) {
                patientListSpinner = showSpinner(spinner, $(".tab-content"));
                if (patientSearchConfig && patientSearchConfig.debounceSearch) {
                    debounceGetPatientCount(currentSearchType, patientListSpinner);
                }
                else {
                    getPatientCount(currentSearchType, patientListSpinner);
                }
            }
        };

        $scope.forwardPatient = function (patient, heading) {
            var options = $.extend({}, $stateParams);
            $rootScope.patientAdmitLocationStatus = patient.Status;
            $.extend(options, {
                patientUuid: patient.uuid,
                visitUuid: patient.activeVisitUuid || null,
                encounterUuid: $stateParams.encounterUuid || 'active',
                programUuid: patient.programUuid || null,
                enrollment: patient.enrollment || null,
                forwardUrl: patient.forwardUrl || null,
                dateEnrolled: patient.dateEnrolled || null
            });
            var link = options.forwardUrl ? {
                url: options.forwardUrl,
                newTab: true
            } : {url: $scope.search.searchType.forwardUrl, newTab: false};
            if ($scope.search.searchType.links) {
                link = _.find($scope.search.searchType.links, {linkColumn: heading}) || _.find($scope.search.searchType.links, { linkColumn: heading.name }) || link;
            }
            if ($scope.search.searchType.targetedTab) {
                link.targetedTab = $scope.search.searchType.targetedTab;
            }
            if (link.url && link.url !== null) {
                var redirectUrl = link.url;
                if (typeof link.url === 'object') {
                    const rowName = patient[heading.name] ? patient[heading.name].replace(/\s/g, "").toLowerCase() : "";
                    redirectUrl = rowName && link.url[rowName] ? link.url[rowName] : link.url.default;
                }
                var newWindow = $window.open(
                appService.getAppDescriptor().formatUrl(redirectUrl, options, true),
                link.newTab ? '_blank' : link.targetedTab ? link.targetedTab : '_self');
                if (link.targetedTab) {
                    $timeout(function () {
                        newWindow.document.title = link.targetedTab;
                        newWindow.location.reload();
                    }, 1000);
                }
            }
        };
        var getPatientCountSeriallyBySearchIndex = function (index) {
            if (index === $scope.search.searchTypes.length) {
                return;
            }
            var searchType = $scope.search.searchTypes[index];
            if (searchType.handler) {
                var params = {
                    q: searchType.handler,
                    v: "full",
                    location_uuid: $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName).uuid,
                    provider_uuid: $rootScope.currentProvider.uuid
                };
                if (searchType.additionalParams) {
                    params["additionalParams"] = searchType.additionalParams;
                }
                patientService.findPatients(params).then(function (response) {
                    searchType.patientCount = response.data.length;
                    if ($scope.search.isSelectedSearch(searchType)) {
                        $scope.search.updatePatientList(response.data);
                    }
                    return getPatientCountSeriallyBySearchIndex(index + 1);
                });
            }
        };
        initialize();
    }
]);
