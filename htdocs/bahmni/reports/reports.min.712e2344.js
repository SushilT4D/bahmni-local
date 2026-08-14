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


'use strict';

angular.module('bahmni.common.routeErrorHandler', ['ui.router'])
    .run(['$rootScope', function ($rootScope) {
        $rootScope.$on('$stateChangeError', function (event) {
            event.preventDefault();
        });
    }]);

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

Modernizr.addTest('ios', function () {
    return navigator.userAgent.match(/(iPad|iPhone|iPod)/i) ? true : false;
});

Modernizr.addTest('windowOS', function () {
    return navigator.appVersion.indexOf("Win") != -1;
});

'use strict';

$(function () {
    if (Modernizr.ios) {
        // This fix is needed when we use fastclick.js on ipad
        $(document).on("click", "label[for]", function () {
            var $inputElement = $('input#' + $(this).attr('for'));
            var elementType = $inputElement.attr('type');
            if (elementType === 'radio') {
                $inputElement.prop('checked', true);
            } else if (elementType === 'checkbox') {
                $inputElement.prop('checked', !$inputElement.prop('checked'));
            } else {
                $inputElement.focus();
            }
        });
    }
});

'use strict';

Bahmni.Common.Util.DateTimeFormatter = {

    getDateWithoutTime: function (datetime) {
        return datetime ? moment(datetime).format("YYYY-MM-DD") : null;
    }
};

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Models = Bahmni.Common.Models || {};

angular.module('bahmni.common.models', []);

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

'use strict';

angular.module('bahmni.common.appFramework')
    .directive('appExtensionList', ['appService', function (appService) {
        var appDescriptor = appService.getAppDescriptor();
        return {
            restrict: 'EA',
            template: '<ul><li ng-repeat="appExtn in appExtensions">' +
            '<a href="{{formatUrl(appExtn.url, extnParams)}}" class="{{appExtn.icon}}" ' +
            ' onclick="return false;" title="{{appExtn.label}}" ng-click="extnLinkClick(appExtn, extnParams)">' +
            ' <span ng-show="showLabel">{{appExtn.label}}</span>' +
            '</a></li></ul>',
            scope: {
                extnPointId: '@',
                showLabel: '@',
                onExtensionClick: '&',
                contextModel: '&'
            },
            compile: function (cElement, cAttrs) {
                var extnList = appDescriptor.getExtensions(cAttrs.extnPointId);
                return function (scope) {
                    scope.appExtensions = extnList;
                    var model = scope.contextModel();
                    scope.extnParams = model || {};
                };
            },
            controller: function ($scope, $location) {
                $scope.formatUrl = appDescriptor.formatUrl;
                $scope.extnLinkClick = function (extn, params) {
                    var proceedWithDefault = true;
                    var clickHandler = $scope.onExtensionClick();
                    var target = appDescriptor.formatUrl(extn.url, params);
                    if (clickHandler) {
                        var event = {
                            'src': extn,
                            'target': target,
                            'params': params,
                            'preventDefault': function () {
                                proceedWithDefault = false;
                            }
                        };
                        clickHandler(event);
                    }
                    if (proceedWithDefault) {
                        $location.url(target);
                    }
                };
            }
        };
    }]);

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
    .service('loadConfigService', ['$http', function ($http) {
        this.loadConfig = function (url) {
            return $http.get(url, {withCredentials: true});
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

angular.module('bahmni.common.config')
    .directive('showIfPrivilege', ['$rootScope', function ($rootScope) {
        return {
            scope: {
                showIfPrivilege: "@"
            },
            link: function (scope, element) {
                var privileges = scope.showIfPrivilege.split(',');
                var requiredPrivilege = false;
                if ($rootScope.currentUser) {
                    var allTypesPrivileges = _.map($rootScope.currentUser.privileges, _.property('name'));
                    var intersect = _.intersectionWith(allTypesPrivileges, privileges, _.isEqual);
                    intersect.length > 0 ? requiredPrivilege = true : requiredPrivilege = false;
                }
                if (!requiredPrivilege) {
                    element.hide();
                }
            }
        };
    }]);


'use strict';
var Bahmni = Bahmni || {};
Bahmni.ConceptSet = Bahmni.ConceptSet || {};
Bahmni.ConceptSet.FormConditions = Bahmni.ConceptSet.FormConditions || {};

angular.module('bahmni.common.conceptSet', ['bahmni.common.uiHelper', 'ui.select2', 'pasvaz.bindonce', 'ngSanitize', 'ngTagsInput']);

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
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Domain = Bahmni.Common.Domain || {};
Bahmni.Common.Domain.Helper = Bahmni.Common.Domain.Helper || {};

angular.module('bahmni.common.domain', []);

'use strict';

Bahmni.Common.Domain.RetrospectiveEntry = function () {
    var self = this;

    Object.defineProperty(this, 'encounterDate', {
        get: function () {
            return self._encounterDate;
        },
        set: function (value) {
            if (value) {
                self._encounterDate = value;
            }
        }
    });
};

Bahmni.Common.Domain.RetrospectiveEntry.createFrom = function (retrospectiveEncounterDateCookie) {
    var obj = new Bahmni.Common.Domain.RetrospectiveEntry();
    obj.encounterDate = retrospectiveEncounterDateCookie;
    return obj;
};


'use strict';

angular.module('bahmni.common.domain')
    .service('retrospectiveEntryService', ['$rootScope', '$bahmniCookieStore', function ($rootScope, $bahmniCookieStore) {
        var retrospectiveEntryService = this;
        var dateUtil = Bahmni.Common.Util.DateUtil;

        this.getRetrospectiveEntry = function () {
            return $rootScope.retrospectiveEntry;
        };

        this.isRetrospectiveMode = function () {
            return !_.isEmpty(retrospectiveEntryService.getRetrospectiveEntry());
        };

        this.getRetrospectiveDate = function () {
            return $rootScope.retrospectiveEntry && $rootScope.retrospectiveEntry.encounterDate;
        };

        this.initializeRetrospectiveEntry = function () {
            var retrospectiveEncounterDateCookie = $bahmniCookieStore.get(Bahmni.Common.Constants.retrospectiveEntryEncounterDateCookieName);
            if (retrospectiveEncounterDateCookie) {
                $rootScope.retrospectiveEntry = Bahmni.Common.Domain.RetrospectiveEntry.createFrom(dateUtil.getDate(retrospectiveEncounterDateCookie));
            }
        };

        this.resetRetrospectiveEntry = function (date) {
            $bahmniCookieStore.remove(Bahmni.Common.Constants.retrospectiveEntryEncounterDateCookieName, {path: '/', expires: 1});
            $rootScope.retrospectiveEntry = undefined;

            if (date && !dateUtil.isSameDate(date, dateUtil.today())) {
                $rootScope.retrospectiveEntry = Bahmni.Common.Domain.RetrospectiveEntry.createFrom(dateUtil.getDate(date));
                $bahmniCookieStore.put(Bahmni.Common.Constants.retrospectiveEntryEncounterDateCookieName, date, {path: '/', expires: 1});
            }
        };
    }]
);

'use strict';

angular.module('bahmni.common.domain')
    .service('encounterService', ['$http', '$q', '$rootScope', 'configurations', '$bahmniCookieStore',
        function ($http, $q, $rootScope, configurations, $bahmniCookieStore) {
            this.buildEncounter = function (encounter) {
                encounter.observations = encounter.observations || [];
                encounter.observations.forEach(function (obs) {
                    stripExtraConceptInfo(obs);
                });
                var bacterilogyMembers = getBacteriologyGroupMembers(encounter);
                bacterilogyMembers = bacterilogyMembers.reduce(function (mem1, mem2) {
                    return mem1.concat(mem2);
                }, []);
                bacterilogyMembers.forEach(function (mem) {
                    deleteIfImageOrVideoObsIsVoided(mem);
                });
                encounter.providers = encounter.providers || [];
                var providerData = $bahmniCookieStore.get(Bahmni.Common.Constants.grantProviderAccessDataCookieName);
                if (_.isEmpty(encounter.providers)) {
                    if (providerData && providerData.uuid) {
                        encounter.providers.push({"uuid": providerData.uuid});
                    } else if ($rootScope.currentProvider && $rootScope.currentProvider.uuid) {
                        encounter.providers.push({"uuid": $rootScope.currentProvider.uuid});
                    }
                }
                return encounter;
            };

            var getBacteriologyGroupMembers = function (encounter) {
                var addBacteriologyMember = function (bacteriologyGroupMembers, member) {
                    bacteriologyGroupMembers = member.groupMembers.length ? bacteriologyGroupMembers.concat(member.groupMembers) :
                        bacteriologyGroupMembers.concat(member);
                    return bacteriologyGroupMembers;
                };
                return encounter.extensions && encounter.extensions.mdrtbSpecimen ? encounter.extensions.mdrtbSpecimen.map(function (observation) {
                    var bacteriologyGroupMembers = [];
                    observation.sample.additionalAttributes && observation.sample.additionalAttributes.groupMembers.forEach(function (member) {
                        bacteriologyGroupMembers = addBacteriologyMember(bacteriologyGroupMembers, member);
                    });

                    observation.report.results && observation.report.results.groupMembers.forEach(function (member) {
                        bacteriologyGroupMembers = addBacteriologyMember(bacteriologyGroupMembers, member);
                    });
                    return bacteriologyGroupMembers;
                }) : [];
            };

            var getDefaultEncounterType = function () {
                var url = Bahmni.Common.Constants.encounterTypeUrl;
                return $http.get(url + '/' + configurations.defaultEncounterType()).then(function (response) {
                    return response.data;
                });
            };

            var getEncounterTypeBasedOnLoginLocation = function (loginLocationUuid) {
                return $http.get(Bahmni.Common.Constants.entityMappingUrl, {
                    params: {
                        entityUuid: loginLocationUuid,
                        mappingType: 'location_encountertype',
                        s: 'byEntityAndMappingType'
                    },
                    withCredentials: true
                });
            };

            var getEncounterTypeBasedOnProgramUuid = function (programUuid) {
                return $http.get(Bahmni.Common.Constants.entityMappingUrl, {
                    params: {
                        entityUuid: programUuid,
                        mappingType: 'program_encountertype',
                        s: 'byEntityAndMappingType'
                    },
                    withCredentials: true
                });
            };

            var getDefaultEncounterTypeIfMappingNotFound = function (entityMappings) {
                var encounterType = entityMappings.data.results[0] && entityMappings.data.results[0].mappings[0];
                if (!encounterType) {
                    encounterType = getDefaultEncounterType();
                }
                return encounterType;
            };

            this.getEncounterType = function (programUuid, loginLocationUuid) {
                if (programUuid) {
                    return getEncounterTypeBasedOnProgramUuid(programUuid).then(function (response) {
                        return getDefaultEncounterTypeIfMappingNotFound(response);
                    });
                } else if (loginLocationUuid) {
                    return getEncounterTypeBasedOnLoginLocation(loginLocationUuid).then(function (response) {
                        return getDefaultEncounterTypeIfMappingNotFound(response);
                    });
                } else {
                    return getDefaultEncounterType();
                }
            };

            this.create = function (encounter) {
                encounter = this.buildEncounter(encounter);

                return $http.post(Bahmni.Common.Constants.bahmniEncounterUrl, encounter, {
                    withCredentials: true
                });
            };

            this.delete = function (encounterUuid, reason) {
                return $http.delete(Bahmni.Common.Constants.bahmniEncounterUrl + "/" + encounterUuid, {
                    params: {reason: reason}
                });
            };

            function isObsConceptClassVideoOrImage (obs) {
                return (obs.concept.conceptClass === 'Video' || obs.concept.conceptClass === 'Image');
            }

            var deleteIfImageOrVideoObsIsVoided = function (obs) {
                if (obs.voided && obs.groupMembers && !obs.groupMembers.length && obs.value
                    && isObsConceptClassVideoOrImage(obs)) {
                    var url = Bahmni.Common.Constants.RESTWS_V1 + "/bahmnicore/visitDocument?filename=" + obs.value;
                    $http.delete(url, {withCredentials: true});
                }
            };

            var stripExtraConceptInfo = function (obs) {
                deleteIfImageOrVideoObsIsVoided(obs);
                obs.concept = {uuid: obs.concept.uuid, name: obs.concept.name, dataType: obs.concept.dataType};
                obs.groupMembers = obs.groupMembers || [];
                obs.groupMembers.forEach(function (groupMember) {
                    stripExtraConceptInfo(groupMember);
                });
            };

            var searchWithoutEncounterDate = function (visitUuid) {
                return $http.post(Bahmni.Common.Constants.bahmniEncounterUrl + '/find', {
                    visitUuids: [visitUuid],
                    includeAll: Bahmni.Common.Constants.includeAllObservations
                }, {
                    withCredentials: true
                });
            };

            this.search = function (visitUuid, encounterDate) {
                if (!encounterDate) {
                    return searchWithoutEncounterDate(visitUuid);
                }

                return $http.get(Bahmni.Common.Constants.emrEncounterUrl, {
                    params: {
                        visitUuid: visitUuid,
                        encounterDate: encounterDate,
                        includeAll: Bahmni.Common.Constants.includeAllObservations
                    },
                    withCredentials: true
                });
            };

            this.find = function (params, getPreviousVisitData, conceptsToGetFromPrevVisit, filterBasedOnLocation) {
                if (getPreviousVisitData && conceptsToGetFromPrevVisit && conceptsToGetFromPrevVisit.length > 0) {
                    return $http.post(Bahmni.Common.Constants.bahmniEncounterUrl +
                        '/findWith?getPreviousVisitData=' + getPreviousVisitData + '&getPreviousObs=' + conceptsToGetFromPrevVisit + '&filterBasedOnLocation=' + filterBasedOnLocation, params, {
                            withCredentials: true
                        });
                }
                return $http.post(Bahmni.Common.Constants.bahmniEncounterUrl + '/find', params, {
                    withCredentials: true
                });
            };

            this.findByEncounterUuid = function (encounterUuid, params) {
                params = params || {includeAll: true};
                return $http.get(Bahmni.Common.Constants.bahmniEncounterUrl + '/' + encounterUuid, {
                    params: params,
                    withCredentials: true
                });
            };

            this.getEncountersForEncounterType = function (patientUuid, encounterTypeUuid) {
                return $http.get(Bahmni.Common.Constants.encounterUrl, {
                    params: {
                        patient: patientUuid,
                        order: "desc",
                        encounterType: encounterTypeUuid,
                        v: "custom:(uuid,provider,visit:(uuid,startDatetime,stopDatetime),obs:(uuid,concept:(uuid,name),groupMembers:(id,uuid,obsDatetime,value,comment)))"
                    },
                    withCredentials: true
                });
            };

            this.getDigitized = function (patientUuid) {
                var patientDocumentEncounterTypeUuid = configurations.encounterConfig().getPatientDocumentEncounterTypeUuid();
                return $http.get(Bahmni.Common.Constants.encounterUrl, {
                    params: {
                        patient: patientUuid,
                        encounterType: patientDocumentEncounterTypeUuid,
                        v: "custom:(uuid,obs:(uuid))"
                    },
                    withCredentials: true
                });
            };

            this.discharge = function (encounterData) {
                var encounter = this.buildEncounter(encounterData);
                return $http.post(Bahmni.Common.Constants.dischargeUrl, encounter, {
                    withCredentials: true
                });
            };
        }]);


'use strict';

angular.module('bahmni.common.domain')
    .service('observationsService', ['$http', '$bahmniCookieStore', 'appService', function ($http, $bahmniCookieStore, appService) {
        this.fetch = function (patientUuid, conceptNames, scope, numberOfVisits, visitUuid, obsIgnoreList, filterObsWithOrders, patientProgramUuid) {
            var params = {concept: conceptNames};
            if (obsIgnoreList) {
                params.obsIgnoreList = obsIgnoreList;
            }
            if (filterObsWithOrders != null) {
                params.filterObsWithOrders = filterObsWithOrders;
            }

            if (visitUuid) {
                params.visitUuid = visitUuid;
                params.scope = scope;
            } else {
                params.patientUuid = patientUuid;
                params.numberOfVisits = numberOfVisits;
                params.scope = scope;
                params.patientProgramUuid = patientProgramUuid;
            }
            var observationsUrl = Bahmni.Common.Constants.observationsUrl;
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    observationsUrl = Bahmni.Common.Constants.bahmniDistroObservationsUrl;
                }
            }
            return $http.get(observationsUrl, {
                params: params,
                withCredentials: true
            });
        };

        this.getByUuid = function (observationUuid) {
            return $http.get(Bahmni.Common.Constants.observationsUrl, {
                params: {observationUuid: observationUuid},
                withCredentials: true
            });
        };

        this.getRevisedObsByUuid = function (observationUuid) {
            return $http.get(Bahmni.Common.Constants.observationsUrl, {
                params: {observationUuid: observationUuid, revision: "latest"},
                withCredentials: true
            });
        };

        this.fetchForEncounter = function (encounterUuid, conceptNames) {
            return $http.get(Bahmni.Common.Constants.observationsUrl, {
                params: {encounterUuid: encounterUuid, concept: conceptNames},
                withCredentials: true
            });
        };

        this.fetchForPatientProgram = function (patientProgramUuid, conceptNames, scope, obsIgnoreList) {
            return $http.get(Bahmni.Common.Constants.observationsUrl, {
                params: {patientProgramUuid: patientProgramUuid, concept: conceptNames, scope: scope, obsIgnoreList: obsIgnoreList},
                withCredentials: true
            });
        };

        this.getObsRelationship = function (targetObsUuid) {
            return $http.get(Bahmni.Common.Constants.obsRelationshipUrl, {
                params: {
                    targetObsUuid: targetObsUuid
                },
                withCredentials: true
            });
        };

        this.getObsInFlowSheet = function (patientUuid, conceptSet, groupByConcept, orderByConcept, conceptNames,
                                           numberOfVisits, initialCount, latestCount, groovyExtension,
                                           startDate, endDate, patientProgramUuid, formNames) {
            var params = {
                patientUuid: patientUuid,
                conceptSet: conceptSet,
                groupByConcept: groupByConcept,
                orderByConcept: orderByConcept,
                conceptNames: conceptNames,
                numberOfVisits: numberOfVisits,
                initialCount: initialCount,
                latestCount: latestCount,
                name: groovyExtension,
                startDate: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(startDate),
                endDate: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(endDate),
                enrollment: patientProgramUuid,
                formNames: formNames
            };
            return $http.get(Bahmni.Common.Constants.observationsUrl + "/flowSheet", {
                params: params,
                withCredentials: true
            });
        };
    }]);

'use strict';

angular.module('bahmni.common.domain')
    .factory('dispositionService', ['$http', '$rootScope', '$bahmniCookieStore', 'appService', function ($http, $rootScope, $bahmniCookieStore, appService) {
        var getDispositionActions = function () {
            return $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl +
                "&name=" + Bahmni.Common.Constants.dispositionConcept +
                "&v=custom:(uuid,name,answers:(uuid,name,mappings))", {cache: true});
        };

        var getDispositionNoteConcept = function () {
            return $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl +
                "&name=" + Bahmni.Common.Constants.dispositionNoteConcept +
                "&v=custom:(uuid,name:(name))", {cache: true});
        };

        var getDispositionByVisit = function (visitUuid) {
            return $http.get(Bahmni.Common.Constants.bahmniDispositionByVisitUrl, {
                params: {visitUuid: visitUuid,
                    locale: $rootScope.currentUser.userProperties.defaultLocale}
            });
        };

        var getDispositionByPatient = function (patientUuid, numberOfVisits) {
            var dispositionUrl = Bahmni.Common.Constants.bahmniDispositionByPatientUrl;
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    dispositionUrl = Bahmni.Common.Constants.bahmniDistroDispositionByPatientUrl;
                }
            }
            return $http.get(dispositionUrl, {
                params: {
                    patientUuid: patientUuid,
                    numberOfVisits: numberOfVisits,
                    locale: $rootScope.currentUser.userProperties.defaultLocale
                }
            });
        };

        return {
            getDispositionActions: getDispositionActions,
            getDispositionNoteConcept: getDispositionNoteConcept,
            getDispositionByVisit: getDispositionByVisit,
            getDispositionByPatient: getDispositionByPatient
        };
    }]);

'use strict';

angular.module('bahmni.common.domain')
    .service('visitService', ['$http', 'appService', function ($http, appService) {
        this.getVisit = function (uuid, params) {
            var parameters = params ? params : "custom:(uuid,visitId,visitType,patient,encounters:(uuid,encounterType,voided,orders:(uuid,orderType,voided,concept:(uuid,set,name),),obs:(uuid,value,concept,obsDatetime,groupMembers:(uuid,concept:(uuid,name),obsDatetime,value:(uuid,name),groupMembers:(uuid,concept:(uuid,name),value:(uuid,name),groupMembers:(uuid,concept:(uuid,name),value:(uuid,name)))))))";
            return $http.get(Bahmni.Common.Constants.visitUrl + '/' + uuid,
                {
                    params: {
                        v: parameters
                    }
                }
            );
        };

        this.print = function (visitDetails) {
            return $http.post(Bahmni.Common.Constants.bahmniDistroVisitPrintUrl, visitDetails, {
                withCredentials: true,
                responseType: 'arraybuffer',
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.endVisit = function (visitUuid) {
            return $http.post(Bahmni.Common.Constants.endVisitUrl + '?visitUuid=' + visitUuid, {
                withCredentials: true
            });
        };

        this.endVisitAndCreateEncounter = function (visitUuid, bahmniEncounterTransaction) {
            return $http.post(Bahmni.Common.Constants.endVisitAndCreateEncounterUrl + '?visitUuid=' + visitUuid, bahmniEncounterTransaction, {
                withCredentials: true
            });
        };

        this.updateVisit = function (visitUuid, attributes) {
            return $http.post(Bahmni.Common.Constants.visitUrl + '/' + visitUuid, attributes, {
                withCredentials: true
            });
        };

        this.createVisit = function (visitDetails) {
            return $http.post(Bahmni.Common.Constants.visitUrl, visitDetails, {
                withCredentials: true
            });
        };

        this.checkIfActiveVisitExists = function (patientUuid, visitLocationUuid) {
            return $http.get(Bahmni.Common.Constants.visitUrl,
                {
                    params: {
                        includeInactive: false,
                        patient: patientUuid,
                        location: visitLocationUuid
                    },
                    withCredentials: true
                }
            );
        };

        this.getVisitSummary = function (visitUuid) {
            return $http.get(Bahmni.Common.Constants.visitSummaryUrl,
                {
                    params: {
                        visitUuid: visitUuid
                    },
                    withCredentials: true
                }
            );
        };

        this.search = function (parameters) {
            var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
            if (restrictLocationToUser) {
                return $http.get(Bahmni.Common.Constants.distroLocVisitUrl, {
                    params: parameters,
                    withCredentials: true
                });
            }
            return $http.get(Bahmni.Common.Constants.visitUrl, {
                params: parameters,
                withCredentials: true
            });
        };

        this.getVisitType = function () {
            return $http.get(Bahmni.Common.Constants.visitTypeUrl, {
                withCredentials: true
            });
        };
    }]);

'use strict';

angular.module('bahmni.common.domain')
    .factory('configurationService', ['$http', '$q', function ($http, $q) {
        var configurationFunctions = {};

        configurationFunctions.encounterConfig = function () {
            return $http.get(Bahmni.Common.Constants.encounterConfigurationUrl, {
                params: {"callerContext": "REGISTRATION_CONCEPTS"},
                withCredentials: true
            });
        };

        configurationFunctions.patientConfig = function () {
            var patientConfig = $http.get(Bahmni.Common.Constants.patientConfigurationUrl, {
                withCredentials: true
            });
            return patientConfig;
        };

        configurationFunctions.patientAttributesConfig = function () {
            return $http.get(Bahmni.Common.Constants.personAttributeTypeUrl, {
                params: {v: 'custom:(uuid,name,sortWeight,description,format,concept)'},
                withCredentials: true
            });
        };

        configurationFunctions.dosageFrequencyConfig = function () {
            var dosageFrequencyConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name,answers)', name: Bahmni.Common.Constants.dosageFrequencyConceptName},
                withCredentials: true
            });
            return dosageFrequencyConfig;
        };

        configurationFunctions.dosageInstructionConfig = function () {
            var dosageInstructionConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name,answers)', name: Bahmni.Common.Constants.dosageInstructionConceptName},
                withCredentials: true
            });
            return dosageInstructionConfig;
        };

        configurationFunctions.stoppedOrderReasonConfig = function () {
            var stoppedOrderReasonConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name,answers)', name: Bahmni.Common.Constants.stoppedOrderReasonConceptName},
                withCredentials: true
            });
            return stoppedOrderReasonConfig;
        };

        configurationFunctions.consultationNoteConfig = function () {
            var consultationNoteConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name,answers)', name: Bahmni.Common.Constants.consultationNoteConceptName},
                withCredentials: true
            });
            return consultationNoteConfig;
        };

        configurationFunctions.radiologyObservationConfig = function () {
            var radiologyObservationConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: { v: 'custom:(uuid,name)', name: Bahmni.Common.Constants.radiologyResultConceptName },
                withCredentials: true
            });
            return radiologyObservationConfig;
        };

        configurationFunctions.labOrderNotesConfig = function () {
            var labOrderNotesConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name)', name: Bahmni.Common.Constants.labOrderNotesConcept},
                withCredentials: true
            });
            return labOrderNotesConfig;
        };

        configurationFunctions.defaultEncounterType = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'bahmni.encounterType.default'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        configurationFunctions.radiologyImpressionConfig = function () {
            var radiologyImpressionConfig = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {v: 'custom:(uuid,name)', name: Bahmni.Common.Constants.impressionConcept},
                withCredentials: true
            });
            return radiologyImpressionConfig;
        };

        configurationFunctions.addressLevels = function () {
            return $http.get(Bahmni.Common.Constants.openmrsUrl + "/module/addresshierarchy/ajax/getOrderedAddressHierarchyLevels.form", {
                withCredentials: true
            });
        };

        configurationFunctions.allTestsAndPanelsConcept = function () {
            var allTestsAndPanelsConcept = $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                method: "GET",
                params: {
                    v: 'custom:(uuid,name:(uuid,name),setMembers:(uuid,name:(uuid,name)))',
                    name: Bahmni.Common.Constants.allTestsAndPanelsConceptName
                },
                withCredentials: true
            });
            return allTestsAndPanelsConcept;
        };

        configurationFunctions.identifierTypesConfig = function () {
            return $http.get(Bahmni.Common.Constants.idgenConfigurationURL, {
                withCredentials: true
            });
        };

        configurationFunctions.genderMap = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                method: "GET",
                params: {
                    property: 'mrs.genders'
                },
                withCredentials: true
            });
        };

        configurationFunctions.relationshipTypeMap = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                method: "GET",
                params: {
                    property: 'bahmni.relationshipTypeMap'
                },
                withCredentials: true
            });
        };

        configurationFunctions.relationshipTypeConfig = function () {
            return $http.get(Bahmni.Common.Constants.relationshipTypesUrl, {
                withCredentials: true,
                params: {v: "custom:(aIsToB,bIsToA,uuid)"}
            });
        };

        configurationFunctions.loginLocationToVisitTypeMapping = function () {
            var url = Bahmni.Common.Constants.entityMappingUrl;
            return $http.get(url, {
                params: {
                    mappingType: 'loginlocation_visittype',
                    s: 'byEntityAndMappingType'
                }
            });
        };

        configurationFunctions.enableAuditLog = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                method: "GET",
                params: {
                    property: 'bahmni.enableAuditLog'
                },
                withCredentials: true
            });
        };

        configurationFunctions.helpDeskNumber = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'clinic.helpDeskNumber'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        configurationFunctions.maxStorageSpace = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'admin.maxStorageSpace'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        configurationFunctions.prescriptionEmailToggle = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'bahmni.enableEmailPrescriptionOption'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        configurationFunctions.quickLogoutComboKey = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'bahmni.quickLogoutComboKey'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        configurationFunctions.contextCookieExpirationTimeInMinutes = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                params: {
                    property: 'bahmni.contextCookieExpirationTimeInMinutes'
                },
                withCredentials: true,
                transformResponse: [function (data) {
                    return data;
                }]
            });
        };

        var existingPromises = {};
        var configurations = {};

        var getConfigurations = function (configurationNames) {
            var configurationsPromiseDefer = $q.defer();
            var promises = [];

            configurationNames.forEach(function (configurationName) {
                if (!existingPromises[configurationName]) {
                    existingPromises[configurationName] = configurationFunctions[configurationName]().then(function (response) {
                        configurations[configurationName] = response.data;
                    });
                    promises.push(existingPromises[configurationName]);
                }
            });

            $q.all(promises).then(function () {
                configurationsPromiseDefer.resolve(configurations);
            });

            return configurationsPromiseDefer.promise;
        };

        return {
            getConfigurations: getConfigurations
        };
    }]);

'use strict';

angular.module('bahmni.common.domain')
    .service('visitDocumentService', ['$http', 'auditLogService', 'configurations', '$q', 'messagingService', '$translate', function ($http, auditLogService, configurations, $q, messagingService, $translate) {
        var removeVoidedDocuments = function (documents) {
            documents.forEach(function (document) {
                if (document.voided && document.image) {
                    var url = Bahmni.Common.Constants.RESTWS_V1 + "/bahmnicore/visitDocument?filename=" + document.image;
                    $http.delete(url, {withCredentials: true});
                }
            });
        };

        this.save = function (visitDocument) {
            var url = Bahmni.Common.Constants.RESTWS_V1 + "/bahmnicore/visitDocument";
            var isNewVisit = !visitDocument.visitUuid;
            removeVoidedDocuments(visitDocument.documents);
            var visitTypeName = configurations.encounterConfig().getVisitTypeByUuid(visitDocument.visitTypeUuid)['name'];
            var encounterTypeName = configurations.encounterConfig().getEncounterTypeByUuid(visitDocument.encounterTypeUuid)['name'];
            return $http.post(url, visitDocument).then(function (response) {
                var promise = isNewVisit ? auditLogService.log(visitDocument.patientUuid, "OPEN_VISIT",
                    {visitUuid: response.data.visitUuid, visitType: visitTypeName}, encounterTypeName) : $q.when();
                return promise.then(function () {
                    return auditLogService.log(visitDocument.patientUuid, "EDIT_ENCOUNTER",
                        {
                            encounterUuid: response.data.encounterUuid,
                            encounterType: encounterTypeName
                        }, encounterTypeName).then(function () {
                            return response;
                        }
                    );
                });
            });
        };

        this.saveFile = function (file, patientUuid, encounterTypeName, fileName, fileType) {
            var searchStr = ";base64";
            var format = file.split(searchStr)[0].split("/")[1];
            if (fileType === "video") {
                format = _.last(_.split(fileName, "."));
            }
            var url = Bahmni.Common.Constants.RESTWS_V1 + "/bahmnicore/distro/visitDocument/mt/uploadDocument";
            return $http.post(url, {
                content: file.substring(file.indexOf(searchStr) + searchStr.length, file.length),
                format: format,
                patientUuid: patientUuid,
                encounterTypeName: encounterTypeName,
                fileType: fileType || "file",
                fileName: fileName.substring(0, fileName.lastIndexOf('.'))
            }, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            }).then(function (response) {
                return response;
            }, function (error) {
                if (error.status === 413) {
                    if (!isNaN(error.data.maxDocumentSizeMB)) {
                        var maxAllowedSize = roundToNearestHalf(error.data.maxDocumentSizeMB * 0.70);
                        messagingService.showMessage("error", $translate.instant("FILE_SIZE_LIMIT_EXCEEDED_MESSAGE", { maxAllowedSize: maxAllowedSize }));
                    } else {
                        messagingService.showMessage("error", $translate.instant("SIZE_LIMIT_EXCEEDED_MESSAGE"));
                    }
                }
                return $q.reject(error);
            });
        };

        var roundToNearestHalf = function (value) {
            var floorValue = Math.floor(value);
            if ((value - floorValue) < 0.5) {
                return floorValue;
            }
            return floorValue + 0.5;
        };

        this.getFileType = function (fileType) {
            var pdfType = "pdf";
            var imageType = "image";
            if (fileType.indexOf(pdfType) !== -1) {
                return pdfType;
            }
            if (fileType.indexOf(imageType) !== -1) {
                return imageType;
            }
            return "not_supported";
        };
    }]);

'use strict';

Bahmni.Common.Domain.ProviderMapper = function () {
    this.map = function (openMrsProvider) {
        if (!openMrsProvider) {
            return null;
        }
        return {
            uuid: openMrsProvider.uuid,
            name: openMrsProvider.preferredName ? openMrsProvider.preferredName.display : openMrsProvider.person.preferredName.display
        };
    };
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

Bahmni.Common.Domain.ObservationMapper = function () {
    this.map = function (openMrsObs) {
        var conceptMapper = new Bahmni.Common.Domain.ConceptMapper();
        var groupMembers = openMrsObs.groupMembers || [];
        return {
            uuid: openMrsObs.uuid,
            concept: conceptMapper.map(openMrsObs.concept),
            value: openMrsObs.value,
            voided: openMrsObs.voided,
            voidedReason: openMrsObs.voidedReason,
            observationDateTime: openMrsObs.obsDatetime,
            orderUuid: openMrsObs.orderUuid,
            groupMembers: groupMembers.map(this.map)
        };
    };
};

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


var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Obs = Bahmni.Common.Obs || {};

angular.module('bahmni.common.obs', []);

'use strict';

Bahmni.Common.Obs.ImageObservation = function (observation, concept, provider) {
    this.concept = concept;
    this.imageObservation = observation;
    this.dateTime = observation.observationDateTime;
    this.provider = provider;
};

angular.module('bahmni.common.uiHelper', ['ngClipboard']);

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
    .directive('datetimepicker', function () {
        var link = function ($scope) {
            if (!$scope.allowFutureDates) {
                $scope.maxDate = Bahmni.Common.Util.DateTimeFormatter.getDateWithoutTime();
            }
            var getSelectedDateStr = function () {
                return $scope.selectedDate != null ? moment($scope.selectedDate).format("YYYY-MM-DD") : "";
            };

            var getSelectedTimeStr = function () {
                return $scope.selectedTime != null ? moment($scope.selectedTime).format("HH:mm") : "";
            };

            var valueNotFilled = function () {
                return $scope.selectedDate == null && $scope.selectedTime == null;
            };

            var valueCompletelyFilled = function () {
                return ($scope.selectedDate != null && $scope.selectedTime != null);
            };

            $scope.updateModel = function () {
                if (valueCompletelyFilled()) {
                    $scope.model = getSelectedDateStr() + " " + getSelectedTimeStr();
                } else if (!$scope.isValid()) {
                    $scope.model = "Invalid Datetime";
                } else {
                    $scope.model = "";
                }
            };

            $scope.isValid = function () {
                return valueNotFilled() || valueCompletelyFilled();
            };

            if ($scope.model) {
                var date = moment($scope.model).toDate();
                $scope.selectedDate = date;
                $scope.selectedTime = date;
                $scope.updateModel();
            }
        };

        return {
            restrict: 'E',
            link: link,
            scope: {
                model: '=',
                observation: "=",
                showTime: '=',
                illegalValue: '=',
                allowFutureDates: '='
            },
            template:
                "<div>" +
                    "<input type='date' ng-change='updateModel()' ng-class=\"{'illegalValue': illegalValue}\" ng-attr-max='{{maxDate || undefined}}' ng-model='selectedDate' ng-disabled='observation.disabled' />" +
                "</div>" +
                "<div>" +
                    "<input type='time' ng-change='updateModel()' ng-class= \"{'illegalValue': !isValid()}\" ng-model='selectedTime' ng-disabled='observation.disabled' />" +
                "</div>"
        };
    });

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
    .directive('bmGallery', ['$location', '$rootScope', '$compile', function ($location, $rootScope, $compile) {
        var controller = function ($scope) {
            $scope.albums = [];
            $scope.imagePosition = {
                tag: undefined,
                index: 0
            };
            this.image = function (record) {
                var provider = record.provider;
                return {
                    src: Bahmni.Common.Constants.documentsPath + '/' + record.imageObservation.value,
                    title: record.concept.name,
                    commentOnUpload: record.comment || record.imageObservation.comment,
                    date: record.imageObservation.observationDateTime,
                    uuid: record.imageObservation.uuid,
                    providerName: provider ? provider.name : null
                };
            };

            this.addImageObservation = function (record, tag) {
                return this.addImage(this.image(record), tag);
            };

            this.addImage = function (image, tag, tagOrder) {
                var matchedAlbum = getMatchingAlbum(tag);
                if (!matchedAlbum) {
                    var newAlbum = {};
                    newAlbum.tag = tag;
                    newAlbum.images = [image];
                    $scope.albums.splice(tagOrder, 0, newAlbum);
                } else {
                    var index = image.imageIndex ? image.imageIndex : matchedAlbum.images.length;
                    matchedAlbum.images.splice(index, 0, image);
                }
                return $scope.albums[0].images.length - 1;
            };

            var getMatchingAlbum = function (tag) {
                return _.find($scope.albums, function (album) {
                    return album.tag == tag;
                });
            };

            this.removeImage = function (image, tag, index) {
                var matchedAlbum = getMatchingAlbum(tag);

                if (matchedAlbum) {
                    if (matchedAlbum.images) {
                        matchedAlbum.images.splice(index, 1);
                    }
                }
            };

            this.setIndex = function (tag, index) {
                $scope.imagePosition.tag = tag;
                $scope.imagePosition.index = index;
            };

            this.open = function () {
                $compile("<div bm-gallery-pane id='gallery-pane'></div>")($scope);
            };
        };

        return {
            controller: controller,
            scope: {
                patient: "=",
                accessImpression: "=?"
            }
        };
    }])
    .directive('bmGalleryItem', function () {
        var link = function ($scope, element, attrs, imageGalleryController) {
            var image = {
                src: $scope.image.encodedValue,
                title: $scope.image.concept ? $scope.image.concept.name : "",
                date: $scope.image.obsDatetime,
                uuid: $scope.image.obsUuid,
                providerName: $scope.image.provider ? $scope.image.provider.name : "",
                imageIndex: $scope.image.imageIndex,
                commentOnUpload: $scope.image.comment
            };
            imageGalleryController.addImage(image, $scope.visitUuid, $scope.visitOrder);

            element.click(function (e) {
                e.stopPropagation();
                imageGalleryController.setIndex($scope.visitUuid, $scope.index);
                imageGalleryController.open();
            });

            element.on('$destroy', function () {
                imageGalleryController.removeImage(image, $scope.visitUuid, $scope.index);
            });
        };
        return {
            link: link,
            scope: {
                image: '=',
                index: "@",
                visitUuid: "=",
                visitOrder: "@"
            },
            require: '^bmGallery'
        };
    })
    .directive('bmImageObservationGalleryItem', function () {
        var link = function (scope, element, attrs, imageGalleryController) {
            scope.imageIndex = imageGalleryController.addImageObservation(scope.observation, 'defaultTag');
            element.click(function (e) {
                e.stopPropagation();
                imageGalleryController.setIndex('defaultTag', scope.imageIndex);
                imageGalleryController.open();
            });
        };
        return {
            link: link,
            scope: {
                observation: '='
            },
            require: '^bmGallery'
        };
    })
    .directive('bmObservationGalleryItem', function () {
        var link = function (scope, element, attrs, imageGalleryController) {
            scope.imageObservation = new Bahmni.Common.Obs.ImageObservation(scope.observation, scope.observation.concept, scope.observation.provider);
            scope.imageIndex = imageGalleryController.addImageObservation(scope.imageObservation, 'defaultTag');
            element.click(function (e) {
                e.stopPropagation();
                imageGalleryController.setIndex('defaultTag', scope.imageIndex);
                imageGalleryController.open();
            });
        };
        return {
            link: link,
            scope: {
                observation: '='
            },
            require: '^bmGallery'
        };
    })
    .directive("bmImageObservationGalleryItems", function () {
        var link = function (scope, elem, attrs, imageGalleryController) {
            angular.forEach(scope.list, function (record) {
                imageGalleryController.addImageObservation(record, 'defaultTag');
            });

            $(elem).click(function () {
                imageGalleryController.open();
            });
        };
        return {
            link: link,
            scope: {
                list: "="
            },
            require: '^bmGallery'
        };
    })
    .directive("bmLazyImageObservationGalleryItems", function () {
        var link = function (scope, elem, attrs, imageGalleryController) {
            scope.promise.then(function (response) {
                angular.forEach(response, function (record) {
                    var index = imageGalleryController.addImageObservation(record, 'defaultTag');
                    if (scope.currentObservation && scope.currentObservation.imageObservation.uuid == record.imageObservation.uuid) {
                        imageGalleryController.setIndex('defaultTag', index);
                    }
                });

                $(elem).click(function () {
                    imageGalleryController.open();
                });
            });
        };
        return {
            link: link,
            scope: {
                promise: "=",
                currentObservation: "=?index"
            },
            require: '^bmGallery'
        };
    });

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

angular.module('bahmni.common.uiHelper').filter('reverse', function () {
    return function (items) {
        return items && items.slice().reverse();
    };
});

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
.filter('formatDecimalValues', function () {
    return function (value) {
        return value ? value.toString().replace(/.0(\s+)/g, "$1") : null;
    };
});

'use strict';

angular.module('bahmni.common.uiHelper')
    .service('backlinkService', ['$window', function ($window) {
        var self = this;

        var urls = [];
        self.reset = function () {
            urls = [];
        };

        self.setUrls = function (backLinks) {
            self.reset();
            angular.forEach(backLinks, function (backLink) {
                self.addUrl(backLink);
            });
        };

        self.addUrl = function (backLink) {
            urls.push(backLink);
        };

        self.addBackUrl = function (label) {
            var backLabel = label || "Back";
            urls.push({label: backLabel, action: $window.history.back});
        };

        self.getUrlByLabel = function (label) {
            return urls.filter(function (url) {
                return url.label === label;
            });
        };

        self.getAllUrls = function () {
            return urls;
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

'use strict';

angular.module('bahmni.common.uiHelper')
    .service('stateChangeSpinner', ['$rootScope', 'spinner', function ($rootScope, spinner) {
        var showSpinner = function (event, toState) { toState.spinnerToken = spinner.show(); };
        var hideSpinner = function (event, toState) { spinner.hide(toState.spinnerToken); };

        this.activate = function () {
            $rootScope.$on('$stateChangeStart', showSpinner);
            $rootScope.$on('$stateChangeSuccess', hideSpinner);
            $rootScope.$on('$stateChangeError', hideSpinner);
        };
    }]);

'use strict';

angular.module('bahmni.common.uiHelper')
 .directive('bmBackLinks', function () {
     return {
         template: '<ul>' +
                        '<li ng-repeat="backLink in backLinks">' +
                            '<a class="back-btn" ng-if="backLink.action" accesskey="{{backLink.accessKey}}" ng-click="closeAllDialogs();backLink.action()" id="{{backLink.id}}"> <span ng-bind-html="backLink.label"></span> </a>' +
                            '<a class="back-btn" ng-class="{\'dashboard-link\':backLink.image}" ng-if="backLink.url" accesskey="{{backLink.accessKey}}" ng-href="{{backLink.url}}" ng-click="closeAllDialogs()" id="{{backLink.id}}"  title="{{backLink.title}}"> ' +
                                '<img ng-if="backLink.image" ng-src="{{backLink.image}}" onerror="this.onerror=null; this.src=\'../images/blank-user.gif\'"/>' +
                                '<i ng-if="backLink.icon && !backLink.image" class="fa {{backLink.icon}}"></i></a>' +
                            '<a class="back-btn" ng-if="backLink.state && !backLink.text" accesskey="{{backLink.accessKey}}" ui-sref="{{backLink.state}}" ng-click="displayConfirmationDialog($event);closeAllDialogs()" id="{{backLink.id}}">' +
                                '<i ng-if="backLink.icon" class="fa {{backLink.icon}}"></i></a>' +
         '<a ng-if="backLink.text && backLink.requiredPrivilege" show-if-privilege="{{backLink.requiredPrivilege}}" accesskey="{{backLink.accessKey}}" ui-sref="{{backLink.state}}" id="{{backLink.id}}" class="back-btn-noIcon" ui-sref-active="active">' +
         '<span>{{backLink.text | translate}}</span>' +
         '        </a>' +
                '<a ng-if="backLink.text && !backLink.requiredPrivilege" accesskey="{{backLink.accessKey}}" ui-sref="{{backLink.state}}" id="{{backLink.id}}" class="back-btn-noIcon" ui-sref-active="active">' +
                 '<span>{{backLink.text | translate}}</span>' +
        '        </a>' +
                        '</li>' +
                    '</ul>',
         controller: function ($scope, backlinkService) {
             $scope.backLinks = backlinkService.getAllUrls();
             $scope.$on('$stateChangeSuccess', function (event, state) {
                 if (state.data && state.data.backLinks) {
                     backlinkService.setUrls(state.data.backLinks);
                     $scope.backLinks = backlinkService.getAllUrls();
                 }
             });

             $scope.$on("$destroy", function () {
                 window.onbeforeunload = undefined;
             });
         },
         restrict: 'E'
     };
 });

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

'use strict';

angular.module('bahmni.common.uiHelper').directive('dateConverter', [function () {
    return {
        require: 'ngModel',
        link: function (scope, element, attrs, ngModelController) {
            var DateUtil = Bahmni.Common.Util.DateUtil;
            ngModelController.$parsers.push(function (date) {
                return DateUtil.parse(date);
            });

            ngModelController.$formatters.push(function (date) {
                return DateUtil.parse(DateUtil.getDateWithoutTime(date));
            });
        }
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

String.prototype.format = function () { // eslint-disable-line no-extend-native
    var content = this;
    for (var i = 0; i < arguments.length; i++) {
        var replacement = '{' + i + '}';
        content = content.replace(replacement, arguments[i]);
    }
    return content;
};

String.prototype.toValidId = function () { // eslint-disable-line no-extend-native
    var content = this;
    return content.replace(/\s/g, '-');
};

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

'use strict';

// Tip from http://stackoverflow.com/a/20786262/69362
/* exported debugUiRouter */
var debugUiRouter = function ($rootScope) {
//    var $rootScope = angular.element(document.getElementById("debug")).injector().get('$rootScope');

    $rootScope.$on('$stateChangeStart', function (event, toState, toParams) {
        console.log('$stateChangeStart to ' + toState.to + '- fired when the transition begins. toState,toParams : \n', toState, toParams);
    });

    $rootScope.$on('$stateChangeError', function () {
        console.log('$stateChangeError - fired when an error occurs during transition.');
        console.log(arguments);
    });

    $rootScope.$on('$stateChangeSuccess', function (event, toState) {
        console.log('$stateChangeSuccess to ' + toState.name + '- fired once the state transition is complete.');
    });

    $rootScope.$on('$viewContentLoaded', function (event) {
        console.log('$viewContentLoaded - fired after dom rendered', event);
    });

    $rootScope.$on('$stateNotFound', function (event, unfoundState, fromState, fromParams) {
        console.log('$stateNotFound ' + unfoundState.to + '  - fired when a state cannot be found by its name.');
        console.log(unfoundState, fromState, fromParams);
    });

    // $rootScope.$on('$viewContentLoading',function(event, viewConfig){
    //   // runs on individual scopes, so putting it in "run" doesn't work.
    //   console.log('$viewContentLoading - view begins loading - dom not rendered',viewConfig);
    // });
};

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

angular.module('bahmni.common.logging')
    .service('loggingService', function () {
        var log = function (errorDetails) {
            $.ajax({
                type: "POST",
                url: "/log",
                contentType: "application/json",
                data: angular.toJson(errorDetails)
            });
        };

        return {
            log: log
        };
    });

'use strict';
angular.module('bahmni.common.logging')
    .service('auditLogService', ['$http', '$translate', 'configurationService', function ($http, $translate, configurationService) {
        var DateUtil = Bahmni.Common.Util.DateUtil;

        var convertToLocalDate = function (date) {
            var localDate = DateUtil.parseLongDateToServerFormat(date);
            return DateUtil.getDateTimeInSpecifiedFormat(localDate, 'MMMM Do, YYYY [at] h:mm:ss A');
        };

        this.getLogs = function (params) {
            params = params || {};
            return $http.get(Bahmni.Common.Constants.auditLogUrl, {params: params}).then(function (response) {
                return response.data.map(function (log) {
                    log.dateCreated = convertToLocalDate(log.dateCreated);
                    var entity = log.message ? log.message.split("~")[1] : undefined;
                    log.params = entity ? JSON.parse(entity) : entity;
                    log.message = log.message.split("~")[0];
                    log.displayMessage = $translate.instant(log.message, log);
                    return log;
                });
            });
        };

        this.log = function (patientUuid, eventType, messageParams, module) {
            return configurationService.getConfigurations(['enableAuditLog']).then(function (result) {
                if (result.enableAuditLog) {
                    var params = {};
                    params.patientUuid = patientUuid;
                    params.eventType = Bahmni.Common.AuditLogEventDetails[eventType].eventType;
                    params.message = Bahmni.Common.AuditLogEventDetails[eventType].message;
                    params.message = messageParams ? params.message + '~' + JSON.stringify(messageParams) : params.message;
                    params.module = module;
                    return $http.post(Bahmni.Common.Constants.auditLogUrl, params, {withCredentials: true});
                }
            });
        };
    }]);

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

'use strict';

var Bahmni = Bahmni || {};
Bahmni.Reports = Bahmni.Reports || {};

angular.module('bahmni.reports', ['ui.router', 'bahmni.common.config', 'bahmni.common.uiHelper', 'bahmni.common.i18n',
    'bahmni.common.domain', 'authentication', 'bahmni.common.appFramework', 'bahmni.common.routeErrorHandler',
    'httpErrorInterceptor', 'pasvaz.bindonce', 'infinite-scroll', 'bahmni.common.util', 'ngSanitize',
    'pascalprecht.translate', 'ngCookies', 'angularFileUpload', 'bahmni.common.logging', 'ngDialog']);

'use strict';

angular.module('bahmni.reports').factory('initialization',
    ['$rootScope', 'authenticator', 'appService', 'spinner', 'configurations',
        function ($rootScope, authenticator, appService, spinner, configurations) {
            return function (appName) {
                var loadConfigPromise = function () {
                    var configNames = ['quickLogoutComboKey', 'contextCookieExpirationTimeInMinutes'];
                    return configurations.load(configNames).then(function () {
                        $rootScope.quickLogoutComboKey = configurations.quickLogoutComboKey() || 'Escape';
                        $rootScope.cookieExpiryTime = configurations.contextCookieExpirationTimeInMinutes() || 0;
                    });
                };
                var initApp = function () {
                    return appService.initApp(appName || 'reports', {'app': true, 'extension': true }, null, ["reports"]);
                };

                return spinner.forPromise(authenticator.authenticateUser()
                    .then(initApp)
                    .then(loadConfigPromise));
            };
        }
    ]
);

'use strict';

angular.module('bahmni.reports')
    .service('reportService', ['appService', '$bahmniCookieStore', '$http', function (appService, $bahmniCookieStore, $http) {
        var paperSize = appService.getAppDescriptor().getConfigValue("paperSize");
        var appName = appService.getAppName() ? appService.getAppName() : "reports";
        var currentDate = new Date();
        var availableFormats = {
            "CSV": "text/csv",
            "HTML": "text/html",
            "EXCEL": "application/vnd.ms-excel",
            "PDF": "application/pdf",
            "CUSTOM EXCEL": "application/vnd.ms-excel-custom",
            "ODS": "application/vnd.oasis.opendocument.spreadsheet"
        };
        var avaialbleDateRange = {
            "Today": currentDate,
            "This Month": new Date(currentDate.getFullYear(), currentDate.getMonth(), 1),
            "Previous Month": new Date(currentDate.getFullYear(), currentDate.getMonth() - 1, 1),
            "This Quarter": new Date(currentDate.getFullYear(), Math.floor(currentDate.getMonth() / 3) * 3, 1),
            "This Year": new Date(currentDate.getFullYear(), 0, 1),
            "Last 7 days": new Date(new Date().setDate(currentDate.getDate() - 7)),
            "Last 30 days": new Date(new Date().setDate(currentDate.getDate() - 30))
        };

        var scheduleReport = function (report) {
            var url = Bahmni.Common.Constants.reportsUrl + "/schedule";
            url = (url + "?name={0}&startDate={1}&endDate={2}&responseType={3}&paperSize={4}&appName={5}&userName={6}").format(report.name, report.startDate, report.stopDate, report.responseType, paperSize, appName, currentUser());
            if (report.reportTemplateLocation && report.responseType == 'application/vnd.ms-excel-custom') {
                url = (url + "&macroTemplateLocation=" + report.reportTemplateLocation);
            }
            return $http.get(url);
        };

        var currentUser = function () {
            return $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
        };

        var getScheduledReports = function () {
            var url = Bahmni.Common.Constants.reportsUrl + "/getReports?user={0}";
            url = url.format(currentUser());
            return $http.get(url);
        };
        var getAvailableFormats = function () {
            return availableFormats;
        };
        var getMimeTypeForFormat = function (format) {
            return availableFormats[format];
        };
        var getFormatForMimeType = function (mimeType) {
            return _.findKey(availableFormats, function (value) {
                if (value === mimeType) {
                    return true;
                }
            });
        };
        var getAvailableDateRange = function () {
            return avaialbleDateRange;
        };
        var deleteReport = function (id) {
            var url = Bahmni.Common.Constants.reportsUrl + "/delete/{0}";
            url = url.format(id);
            return $http.get(url);
        };

        var generateReport = function (report) {
            var url = Bahmni.Common.Constants.reportsUrl + "/report";
            url = (url + "?name={0}&startDate={1}&endDate={2}&responseType={3}&paperSize={4}&appName={5}").format(report.name, report.startDate, report.stopDate, report.responseType, paperSize, appName);
            if (report.reportTemplateLocation && report.responseType == 'application/vnd.ms-excel-custom') {
                url = (url + "&macroTemplateLocation=" + report.reportTemplateLocation);
            }
            window.open(url);
        };

        return {
            getFormatForMimeType: getFormatForMimeType,
            getMimeTypeForFormat: getMimeTypeForFormat,
            getAvailableFormats: getAvailableFormats,
            getAvailableDateRange: getAvailableDateRange,
            scheduleReport: scheduleReport,
            getScheduledReports: getScheduledReports,
            deleteReport: deleteReport,
            generateReport: generateReport
        };
    }]);

'use strict';

angular.module('bahmni.reports')
    .controller('ReportsController', ['$scope', '$filter', 'appService', 'reportService', 'FileUploader', 'messagingService', 'spinner', '$rootScope', '$translate', 'auditLogService', function ($scope, $filter, appService, reportService, FileUploader, messagingService, spinner, $rootScope, $translate, auditLogService) {
        const format = _.values(reportService.getAvailableFormats());
        const dateRange = _.values(reportService.getAvailableDateRange());

        var getTranslatedMessage = function (key) {
            return $translate.instant(key);
        };

        $scope.uploader = new FileUploader({
            url: Bahmni.Common.Constants.uploadReportTemplateUrl,
            removeAfterUpload: true,
            autoUpload: true
        });
        $scope.uploader.onSuccessItem = function (fileItem, response) {
            fileItem.report.reportTemplateLocation = response;
        };

        $rootScope.default = $rootScope.default || {
            reportsRequiringDateRange: {
                responseType: format[1],
                dateRangeType: dateRange[0],
                startDate: dateRange[0],
                stopDate: dateRange[0],
                report: { responseType: format[1] }
            },
            reportsNotRequiringDateRange: {}
        };

        $scope.reportsDefined = true;
        $scope.enableReportQueue = appService.getAppDescriptor().getConfigValue("enableReportQueue");

        $scope.setDefault = function (item, header) {
            var setToChange = (header === 'reportsRequiringDateRange') ? $rootScope.reportsRequiringDateRange : $rootScope.reportsNotRequiringDateRange;
            var isPreviousMonth = $rootScope.default[header][item] === dateRange[2];
            for (var i = 0; i < setToChange.length; i++) {
                var report = setToChange[i];
                if (item === 'dateRangeType') {
                    $rootScope.default.reportsRequiringDateRange.startDate = $rootScope.default[header][item];
                    $rootScope.default.reportsRequiringDateRange.stopDate = isPreviousMonth ? getPreviousMonthEndDate() : dateRange[0];
                    report.startDate = $rootScope.default[header][item];
                    report.stopDate = isPreviousMonth ? getPreviousMonthEndDate() : dateRange[0];
                } else if (_.isUndefined($rootScope.default[header][item])) {
                    $rootScope.default.reportsRequiringDateRange.startDate = dateRange[0];
                    $rootScope.reportsRequiringDateRange.forEach(function (report) {
                        report.startDate = $filter('date')(dateRange[0], 'yyyy-MM-dd');
                        report.stopDate = isPreviousMonth ? getPreviousMonthEndDate() : dateRange[0];
                        report.responseType = format[1];
                    });
                    break;
                } else {
                    report[item] = $rootScope.default[header][item];
                }
            }
        };

        var getPreviousMonthEndDate = function () {
            return new Date(new Date().getFullYear(), new Date().getMonth(), 0);
        };

        var isDateRangeRequiredFor = function (report) {
            return _.find($rootScope.reportsRequiringDateRange, { name: report.name });
        };

        var validateReport = function (report) {
            if (!report.responseType) {
                messagingService.showMessage("error", "Select format for the report: " + report.name);
                return false;
            }
            if (report.responseType === 'application/vnd.ms-excel-custom' && !report.reportTemplateLocation) {
                if (!report.config.macroTemplatePath) {
                    messagingService.showMessage("error", "Workbook template should be selected for generating report: " + report.name);
                    return false;
                }
                report.reportTemplateLocation = report.config.macroTemplatePath;
            }
            report.startDate = Bahmni.Common.Util.DateUtil.getDateWithoutTime(report.startDate);
            report.stopDate = Bahmni.Common.Util.DateUtil.getDateWithoutTime(report.stopDate);
            if (isDateRangeRequiredFor(report) && (!report.startDate || !report.stopDate)) {
                var msg = [];
                if (!report.startDate) {
                    msg.push("start date");
                }
                if (!report.stopDate) {
                    msg.push("end date");
                }
                if ((report.startDate > report.stopDate)) {
                    msg.push(getTranslatedMessage("START_DATE_CANNOT_LATER_THAN_STOP_DATE"));
                }
                messagingService.showMessage("error", "Please select the " + msg.join(" and "));
                return false;
            }
            if (report.type == 'concatenated' && report.responseType == reportService.getMimeTypeForFormat('CSV')) {
                messagingService.showMessage('error', 'CSV format is not supported for concatenated reports');
                return false;
            }
            return true;
        };

        $scope.downloadReport = function (report) {
            if (validateReport(report)) {
                reportService.generateReport(report);
                if (report.responseType === 'application/vnd.ms-excel-custom') {
                    report.reportTemplateLocation = undefined;
                    report.responseType = _.values($scope.formats)[0];
                }
                log(report.name);
            }
        };

        var log = function (reportName) {
            auditLogService.log(undefined, 'RUN_REPORT', { reportName: reportName }, "MODULE_LABEL_REPORTS_KEY");
        };

        $scope.scheduleReport = function (report) {
            if (validateReport(report)) {
                spinner.forPromise(reportService.scheduleReport(report)).then(function () {
                    messagingService.showMessage("info", report.name + " added to My Reports");
                }, function () {
                    messagingService.showMessage("error", "Error in scheduling report");
                });
                if (report.responseType === 'application/vnd.ms-excel-custom') {
                    report.reportTemplateLocation = undefined;
                    report.responseType = _.values($scope.formats)[0];
                }
                log(report.name);
            }
        };

        var initializeFormats = function () {
            var supportedFormats = appService.getAppDescriptor().getConfigValue("supportedFormats") || _.keys(reportService.getAvailableFormats());
            supportedFormats = _.map(supportedFormats, function (format) {
                return format.toUpperCase();
            });
            $scope.formats = _.pick(reportService.getAvailableFormats(), supportedFormats);
        };

        var initializeDateRange = function () {
            var supportedDateRange = appService.getAppDescriptor().getConfigValue("supportedDateRange") || _.keys(reportService.getAvailableDateRange());
            $scope.dateRange = _.pick(reportService.getAvailableDateRange(), supportedDateRange);
        };

        var initialization = function () {
            var reportList = appService.getAppDescriptor().getConfigForPage("reports");
            $rootScope.reportsRequiringDateRange = _.isUndefined($rootScope.reportsRequiringDateRange) ? _.values(reportList).filter(function (report) {
                return !(report.config && report.config.dateRangeRequired === false);
            }) : $rootScope.reportsRequiringDateRange;
            $rootScope.reportsNotRequiringDateRange = _.isUndefined($rootScope.reportsNotRequiringDateRange) ? _.values(reportList).filter(function (report) {
                return (report.config && report.config.dateRangeRequired === false);
            }) : $rootScope.reportsNotRequiringDateRange;
            $scope.reportsDefined = _.values(reportList).length > 0;

            initializeFormats();
            initializeDateRange();
        };

        initialization();
    }]);

'use strict';

angular.module('bahmni.reports')
    .controller('MyReportsController', ['$scope', 'reportService', 'messagingService', 'spinner', 'ngDialog', function ($scope, reportService, messagingService, spinner, ngDialog) {
        $scope.reports = null;
        $scope.days = null;
        $scope.searchString = "";

        var init = function () {
            spinner.forPromise(reportService.getScheduledReports()).then(function (response) {
                $scope.reports = sortAllGroupedReports(getReportsGroupedByDay(response.data));
                $scope.days = getDaysInSortedOrder($scope.reports);
            }, function (response) {

            });
        };

        var sortAllGroupedReports = function (reports) {
            _.forOwn(reports, function (value, key) {
                reports[key] = _.sortBy(value, ['requestDatetime']).reverse();
            });
            return reports;
        };

        var getReportsGroupedByDay = function (reports) {
            return _.groupBy(reports, function (report) {
                report.hidden = false;
                var dateFormat = "MMM D YYYY";
                var date = moment(report.requestDatetime).format(dateFormat);
                return moment(date, dateFormat).unix() * 1000;
            });
        };

        var getDaysInSortedOrder = function (reports) {
            var days = Object.keys(reports).sort().reverse();
            return _.map(days, function (day) {
                return {
                    unixTimeStamp: parseInt(day, 10),
                    hidden: false
                };
            });
        };

        $scope.getDownloadLink = function (report) {
            return Bahmni.Common.Constants.reportsUrl + '/download/' + report.id;
        };

        $scope.convertToDate = function (unixTimeStamp, format) {
            return moment(unixTimeStamp).format(format);
        };

        $scope.getFormat = function (mimeType) {
            return reportService.getFormatForMimeType(mimeType);
        };

        $scope.search = function () {
            _.forEach($scope.days, function (day) {
                var hiddenReports = 0;
                _.forEach($scope.reports[day.unixTimeStamp], function (report) {
                    if (report.name.match(new RegExp($scope.searchString, "i")) === null) {
                        report.hidden = true;
                        hiddenReports++;
                    } else {
                        report.hidden = false;
                    }
                });
                day.hidden = hiddenReports === $scope.reports[day.unixTimeStamp].length;
            });
        };

        $scope.delete = function (reportToDelete, day) {
            spinner.forPromise(reportService.deleteReport(reportToDelete.id)).then(function () {
                _.remove($scope.reports[day.unixTimeStamp], function (report) {
                    return reportToDelete.id === report.id;
                });
                messagingService.showMessage("info", "REPORT_DELETE_SUCCESSFUL");
            }, function () {
                messagingService.showMessage("error", "REPORT_DELETE_ERROR");
            });
        };

        $scope.displayErrorPopup = function (report) {
            ngDialog.open({
                template: 'views/errorMessagePopup.html',
                className: "ngdialog-theme-default report",
                data: report.errorMessage
            });
        };

        init();
    }]);

'use strict';

angular.module('bahmni.reports')
    .controller('DashboardHeaderController', ['$scope', 'appService', '$state',
        function ($scope, appService, $state) {
            var setBackLinks = function () {
                var backLinks = [{label: "Home", url: "../home/", accessKey: "h", icon: "fa-home"}];
                if (appService.getAppDescriptor().getConfigValue("enableReportQueue")) {
                    backLinks.push({text: "REPORTS_HEADER_REPORTS", state: "dashboard.reports", accessKey: "d"});
                    backLinks.push({text: "REPORTS_HEADER_MY_REPORTS", state: "dashboard.myReports", accessKey: "m"});
                }
                $state.get('dashboard').data.backLinks = backLinks;
            };
            var init = function () {
                setBackLinks();
            };
            return init();
        }]);

'use strict';

angular
    .module('bahmni.reports')
    .config(['$urlRouterProvider', '$stateProvider', '$httpProvider', '$bahmniTranslateProvider', '$compileProvider',
        function ($urlRouterProvider, $stateProvider, $httpProvider, $bahmniTranslateProvider, $compileProvider) {
            $httpProvider.defaults.headers.common['Disable-WWW-Authenticate'] = true;

            $urlRouterProvider.otherwise('/dashboard/reports');
            $urlRouterProvider.when('/dashboard', '/dashboard/reports');
            $compileProvider.debugInfoEnabled(false);

            $stateProvider
            .state('dashboard', {
                url: '/dashboard',
                abstract: true,
                views: {
                    'additional-header': {
                        templateUrl: 'views/dashboardHeader.html',
                        controller: 'DashboardHeaderController'
                    },
                    'mainContent': {
                        template: '<div class="opd-wrapper">' +
                        '<div ui-view="content" class="opd-content-wrapper"></div>' +
                        '</div>'
                    }
                },
                data: {
                    backLinks: []
                },
                resolve: {
                    initializeConfig: function (initialization, $stateParams) {
                        return initialization($stateParams.appName);
                    }
                }
            }).state('dashboard.reports', {
                url: '/reports?appName',
                views: {
                    'content': {
                        templateUrl: 'views/reports.html',
                        controller: 'ReportsController'
                    }
                }
            }).state('dashboard.myReports', {
                url: '/myReports?appName',
                views: {
                    'content': {
                        templateUrl: 'views/myReports.html',
                        controller: 'MyReportsController'
                    }
                }
            });

            var getAppName = function () {
                var val = location.hash.indexOf("appName=");
                return location.hash.substr(val).split("&")[0].split("=")[1] || 'reports';
            };

            $bahmniTranslateProvider.init({app: getAppName(), shouldMerge: true});
        }]).run(['$rootScope', '$templateCache', '$window', function ($rootScope, $templateCache, $window) {
            moment.locale($window.localStorage["NG_TRANSLATE_LANG_KEY"] || "en");
            $rootScope.$on('$viewContentLoaded', function () {
                $templateCache.removeAll();
            }
        );
        }]);
