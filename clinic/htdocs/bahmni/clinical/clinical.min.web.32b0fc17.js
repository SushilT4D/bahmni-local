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
angular.module('bahmni.common.services')
    .factory('pacsService', ['$http', function ($http) {
        var search = function (patientId) {
            var params = {
                patientId: patientId
            };
            return $http.get('/openmrs/ws/rest/v1/pacs/studies', {
                method: "GET",
                params: params,
                withCredentials: true
            });
        };

        var getAccessionNumber = function (identifier) {
            if (identifier.system.indexOf("urn:bahmni:accession") < 0) {
                return null;
            }
            var parts = identifier.value.split("urn:oid:");
            return parts && parts.length === 2 ? parts[1] : "";
        };

        return {
            search: search,
            getAccessionNumber: getAccessionNumber
        };
    }]);

'use strict';
angular.module('bahmni.common.services')
    .factory('virtualConsultService', ['$http', '$rootScope', function ($http, $rootScope) {
        var launchMeeting = function (uuid, link) {
            $rootScope.$broadcast("event:launchVirtualConsult", {"uuid": uuid, "link": link});
        };

        return {
            launchMeeting: launchMeeting
        };
    }]);

 'use strict';

 angular.module('bahmni.common.util')
    .factory('transmissionService', ['$http', '$q', '$rootScope', 'locationService', '$bahmniCookieStore', '$translate', 'appService', 'visitService', '$filter', 'messagingService', function ($http, $q, $rootScope, locationService, $bahmniCookieStore, $translate, appService, visitService, $filter, messagingService) {
        var sendEmail = function (attachments, subject, body, emailUrl, cc, bcc) {
            var params = {
                "mailAttachments": attachments,
                "subject": subject,
                "body": body,
                "cc": cc,
                "bcc": bcc
            };
            var deferred = $q.defer();

            $http.post(emailUrl, params, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            }).then(function (response) {
                if (response.data.statusLine.statusCode != 200) {
                    messagingService.showMessage("error", response.data.statusLine.reasonPhrase);
                } else {
                    messagingService.showMessage("info", response.data.statusLine.reasonPhrase);
                }
                deferred.resolve(response);
            });
            return deferred.promise;
        };

        var getSharePrescriptionMailContent = function (prescriptionDetails) {
            var message = $translate.instant(Bahmni.Clinical.Constants.sharePrescriptionMailContent);
            message = message.replace("#recipientName", prescriptionDetails.patient.name);
            message = message.replaceAll("#locationName", $rootScope.facilityLocation.name);
            message = message.replace("#locationAddress", $rootScope.facilityLocation.attributes[0] ? $rootScope.facilityLocation.attributes[0].display.split(":")[1].trim() : "");
            message = message.replace("#visitDate", $filter("bahmniDate")(prescriptionDetails.visitDate));
            return message;
        };

        return {
            sendEmail: sendEmail,
            getSharePrescriptionMailContent: getSharePrescriptionMailContent
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

angular.module('bahmni.common.domain')
    .service('conditionsService', ['$http', function ($http) {
        this.save = function (conditions, patientUuid) {
            var conditionsToBeSaved = _.reject(conditions, function (condition) {
                return condition.onSetDate === null || Number.isInteger(condition.onSetDate);
            });
            var body = _.map(conditionsToBeSaved, function (condition) {
                return {
                    uuid: condition.uuid,
                    patientUuid: patientUuid,
                    concept: condition.concept,
                    conditionNonCoded: condition.conditionNonCoded,
                    status: condition.status,
                    onSetDate: condition.onSetDate,
                    endDate: condition.endDate,
                    endReason: condition.endReason,
                    additionalDetail: condition.additionalDetail,
                    voided: condition.voided,
                    voidReason: condition.voidReason
                };
            });

            return $http.post(Bahmni.Common.Constants.conditionUrl, body, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };
        this.getConditionHistory = function (patientUuid) {
            var params = {
                patientUuid: patientUuid
            };
            return $http.get(Bahmni.Common.Constants.conditionHistoryUrl, {
                params: params,
                headers: {
                    withCredentials: true
                }
            });
        };
        this.getFollowUpConditionConcept = function () {
            return $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                params: {
                    name: Bahmni.Common.Constants.followUpConditionConcept,
                    v: "custom:(uuid,name:(name))"
                },
                cache: true
            });
        };
        var getLatestActiveCondition = function (conditionHistories, latestCondition) {
            var conditionHistory = _.find(conditionHistories, {
                conceptUuid: latestCondition.concept.uuid,
                conditionNonCoded: latestCondition.conditionNonCoded
            });
            return Bahmni.Common.Domain.Conditions.getPreviousActiveCondition(latestCondition, conditionHistory.conditions);
        };
        this.getConditions = function (patientUuid) {
            return this.getConditionHistory(patientUuid).then(function (response) {
                var conditionHistories = response.data;
                var conditions = Bahmni.Common.Domain.Conditions.fromConditionHistories(conditionHistories);
                _.forEach(conditions, function (condition) {
                    condition.activeSince = getLatestActiveCondition(conditionHistories, condition).onSetDate;
                });
                return conditions;
            });
        };
    }]);

'use strict';

angular.module('bahmni.common.orders')
    .service('orderTypeService', ['$http', function ($http) {
        var self = this;
        self.orderTypes = [];
        self.loadAll = function () {
            return $http.get("/openmrs/ws/rest/v1/ordertype", {
                params: {v: "custom:(uuid,display,conceptClasses:(uuid,display,name))"}
            }).then(function (response) {
                self.orderTypes = response.data.results;
                return self.orderTypes;
            });
        };

        self.getOrderTypeUuid = function (orderTypeName) {
            return _.result(_.find(self.orderTypes, {display: orderTypeName}), 'uuid');
        };
    }]);

'use strict';

angular.module('bahmni.common.patient')
    .service('patientService', ['$http', 'sessionService', 'appService', function ($http, sessionService, appService) {
        this.getPatient = function (uuid, rep) {
            if (!rep) {
                rep = "full";
            }
            var patient = $http.get(Bahmni.Common.Constants.openmrsUrl + "/ws/rest/v1/patient/" + uuid, {
                method: "GET",
                params: {v: rep},
                withCredentials: true
            });
            return patient;
        };

        this.getRelationships = function (patientUuid) {
            return $http.get(Bahmni.Common.Constants.openmrsUrl + "/ws/rest/v1/relationship", {
                method: "GET",
                params: {person: patientUuid, v: "full"},
                withCredentials: true
            });
        };

        this.findPatients = function (params) {
            return $http.get(Bahmni.Common.Constants.sqlUrl, {
                method: "GET",
                params: params,
                withCredentials: true
            });
        };

        this.search = function (query, offset, identifier) {
            offset = offset || 0;
            identifier = identifier || query;
            var searchParams = {
                filterOnAllIdentifiers: true,
                q: query,
                startIndex: offset,
                identifier: identifier,
                loginLocationUuid: sessionService.getLoginLocationUuid()
            };
            var filterOutAttributeForAllSearch = appService.getAppDescriptor().getConfigValue("filterOutAttributeForAllSearch") || [];
            if (filterOutAttributeForAllSearch && filterOutAttributeForAllSearch.length > 0) {
                searchParams.attributeToFilterOut = filterOutAttributeForAllSearch[0].attrName;
                searchParams.attributeValueToFilterOut = filterOutAttributeForAllSearch[0].attrValue;
            }
            return $http.get(Bahmni.Common.Constants.bahmniCommonsSearchUrl + "/patient/lucene", {
                method: "GET",
                params: searchParams,
                withCredentials: true
            });
        };

        this.getPatientContext = function (patientUuid, programUuid, personAttributes, programAttributes, patientIdentifiers) {
            return $http.get('/openmrs/ws/rest/v1/bahmnicore/patientcontext', {
                params: {
                    patientUuid: patientUuid,
                    programUuid: programUuid,
                    personAttributes: personAttributes,
                    programAttributes: programAttributes,
                    patientIdentifiers: patientIdentifiers
                },
                withCredentials: true
            });
        };
    }]);

'use strict';

angular.module('bahmni.common.domain')
    .factory('locationService', ['$http', '$bahmniCookieStore', 'appService', function ($http, $bahmniCookieStore, appService) {
        var getAllByTag = function (tags, operator) {
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    return getLoginUserLocations(tags);
                }
            }
            return $http.get(Bahmni.Common.Constants.locationUrl, {
                params: {s: "byTags", tags: tags || "", v: "default", operator: operator || "ALL"},
                cache: true
            });
        };

        var getByUuid = function (locationUuid) {
            return $http.get(Bahmni.Common.Constants.locationUrl + "/" + locationUuid, {
                cache: true
            }).then(function (response) {
                return response.data;
            });
        };

        var getLoggedInLocation = function () {
            var cookie = $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName);
            return getByUuid(cookie.uuid);
        };

        var getVisitLocation = function (locationUuid) {
            return $http.get(Bahmni.Common.Constants.bahmniVisitLocationUrl + "/" + locationUuid, {
                headers: {"Accept": "application/json"}
            });
        };

        var getFacilityVisitLocation = function () {
            var cookie = $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName);
            return $http.get(Bahmni.Common.Constants.bahmniFacilityLocationUrl + "/" + cookie.uuid, {
                cache: true
            }).then(function (response) {
                return response.data;
            });
        };

        var getLoginUserLocations = function (byTag) {
            return $http.get(Bahmni.Common.Constants.distroLoginUserLocationsUrl, {
                params: {byTag: byTag || ""}
            });
        };

        return {
            getAllByTag: getAllByTag,
            getLoggedInLocation: getLoggedInLocation,
            getByUuid: getByUuid,
            getVisitLocation: getVisitLocation,
            getFacilityVisitLocation: getFacilityVisitLocation
        };
    }]);

'use strict';

angular.module('bahmni.clinical')
    .service('cdssService', ['drugService', '$rootScope', function (drugService, $rootScope) {
        var createMedicationRequest = function (medication, patientUuid, conceptSource) {
            return extractCodeInfo(medication, conceptSource).then(function (coding) {
                var medicationRequest = {
                    resourceType: 'MedicationRequest',
                    id: medication.uuid,
                    status: 'active',
                    intent: 'order',
                    subject: {
                        reference: 'Patient/' + patientUuid
                    },
                    medicationCodeableConcept: {
                        id: medication.drug.uuid,
                        coding: coding,
                        text: medication.drugNameDisplay
                    },
                    "dosageInstruction": [
                        {
                            "text": angular.toJson({ "instructions": medication.instructions }),
                            "timing": {
                                "event": [medication.effectiveStartDate],
                                "repeat": {
                                    "duration": medication.durationInDays,
                                    "durationUnit": 'd'
                                },
                                "code": {
                                    "coding": [
                                        {
                                            "code": medication.drug.uuid,
                                            "display": medication.uniformDosingType.frequency
                                        }
                                    ],
                                    "text": medication.uniformDosingType.frequency
                                }
                            },
                            "asNeededBoolean": medication.asNeeded,
                            "doseAndRate": [
                                {
                                    "doseQuantity": {
                                        "value": medication.uniformDosingType.dose,
                                        "unit": medication.doseUnits,
                                        "code": medication.drug.uuid
                                    }
                                }
                            ],
                            "route": {
                                "coding": [{
                                    "system": conceptSource,
                                    "code": "",
                                    "display": medication.route
                                }
                                ],
                                "text": medication.route
                            }
                        }
                    ]

                };
                return {
                    resource: medicationRequest
                };
            });
        };

        var extractConditionInfo = function (condition) {
            var uuid = condition.concept.uuid.split('/');
            var code = uuid[uuid.length - 1];
            uuid.pop();
            var system = uuid.join('/');
            return {
                code: code,
                system: system,
                display: condition.concept.name
            };
        };

        var extractCodeInfo = function (medication, conceptSource) {
            if (!(medication.drug.drugReferenceMaps && medication.drug.drugReferenceMaps.length > 0)) {
                return Promise.resolve([{
                    code: medication.drug.uuid,
                    display: medication.drug.name,
                    system: 'https://fhir.openmrs.org'
                }]);
            } else {
                var drugReferenceMap = medication.drug.drugReferenceMaps[0];
                if (!conceptSource) {
                    return drugService.getDrugConceptSourceMapping(medication.drug.uuid).then(function (response) {
                        var bundle = response.data;
                        var code = bundle.entry && bundle.entry.length > 0 && bundle.entry[0].resource.code;
                        var conceptCode = code.coding.find(function (coding) {
                            return coding.system;
                        });
                        if (conceptCode) {
                            localStorage.setItem("conceptSource", conceptCode.system);
                            conceptSource = conceptCode.system;
                            return [{
                                system: conceptSource,
                                code: drugReferenceMap.conceptReferenceTerm && drugReferenceMap.conceptReferenceTerm.display && drugReferenceMap.conceptReferenceTerm.display.split(':')[1].trim(),
                                display: medication.drug.name
                            }, {
                                code: medication.drug.uuid,
                                system: 'https://fhir.openmrs.org',
                                display: medication.drug.name
                            }];
                        } else {
                            return [{
                                code: medication.drug.uuid,
                                display: medication.drug.name,
                                system: 'https://fhir.openmrs.org'
                            }];
                        }
                    });
                } else {
                    return Promise.resolve([{
                        system: conceptSource,
                        code: drugReferenceMap.conceptReferenceTerm && drugReferenceMap.conceptReferenceTerm.display && drugReferenceMap.conceptReferenceTerm.display.split(':')[1].trim(),
                        display: medication.drug.name
                    }, {
                        code: medication.drug.uuid,
                        system: 'https://fhir.openmrs.org',
                        display: medication.drug.name
                    }]);
                }
            }
        };

        var createConditionResource = function (condition, patientUuid, isDiagnosis) {
            var conceptLimitIndex = isDiagnosis ? -1 : condition.concept.uuid.lastIndexOf('/');
            var conditionStatus = condition.status || condition.diagnosisStatus || condition.certainty;
            var activeConditions = ['CONFIRMED', 'PRESUMED', 'ACTIVE'];
            var status = (!conditionStatus || activeConditions.indexOf(conditionStatus) > -1) ? 'active' : 'inactive';
            var conditionCoding = condition.concept ? extractConditionInfo(condition) : {
                system: isDiagnosis ? condition.codedAnswer.conceptSystem : (conceptLimitIndex > -1 ? (condition.concept.uuid.substring(0, conceptLimitIndex) || '') : ''),
                code: isDiagnosis ? condition.codedAnswer.uuid : (conceptLimitIndex > -1 ? condition.concept.uuid.substring(conceptLimitIndex + 1) : condition.concept.uuid),
                display: isDiagnosis ? condition.codedAnswer.name : condition.concept.name
            };

            var conditionResource = {
                resourceType: 'Condition',
                id: condition.uuid,
                clinicalStatus: {
                    coding: [
                        {
                            code: status,
                            display: status,
                            system: 'http://terminology.hl7.org/CodeSystem/condition-clinical'
                        }
                    ]
                },
                code: {
                    coding: [ conditionCoding ],
                    text: isDiagnosis ? condition.codedAnswer.name : condition.concept.name
                },
                subject: {
                    reference: 'Patient/' + patientUuid
                }
            };
            if (angular.isNumber(condition.onSetDate) === 'number') {
                conditionResource.onsetDateTime = new Date(condition.onSetDate).toLocaleDateString('en-CA');
            }
            if (!conditionResource.onsetDateTime) {
                delete conditionResource.onsetDateTime;
            }
            return {
                resource: conditionResource
            };
        };

        function createPatientResource (patient) {
            var patientResource = {
                resourceType: 'Patient',
                id: patient.uuid
            };
            return {
                resource: patientResource
            };
        }

        var createFhirBundle = function (patient, conditions, medications, diagnosis, conceptSource) {
            var encounterResource = conditions.filter(function (condition) {
                return !condition.uuid;
            }).map(function (condition) {
                return createConditionResource(condition, patient.uuid, false);
            });
            encounterResource = encounterResource.concat(diagnosis.map(function (condition) {
                return createConditionResource(condition, patient.uuid, true);
            }));

            medications = medications.filter(function (medication) {
                return angular.isDefined(medication.include) && medication.include || medication.include === undefined;
            });

            return Promise.all(medications.map(function (medication) {
                return createMedicationRequest(medication, patient.uuid, conceptSource).then(function (medicationResource) {
                    return medicationResource;
                });
            })).then(function (medicationResources) {
                var bundleResource = {
                    resourceType: 'Bundle',
                    type: 'collection',
                    entry: []
                };
                if (medicationResources.length === 0 && encounterResource.length === 0) {
                    var patientResource = createPatientResource(patient);
                    bundleResource.entry = bundleResource.entry.concat(patientResource);
                    return bundleResource;
                }
                bundleResource.entry = bundleResource.entry.concat(encounterResource, medicationResources);
                return bundleResource;
            });
        };

        var getAlerts = function (cdssEnabled, consultation, patient) {
            if (cdssEnabled) {
                var consultationData = angular.copy(consultation);
                consultationData.patient = patient;

                var orderSetTreatments = consultationData.newlyAddedTabTreatments ? consultationData.newlyAddedTabTreatments.allMedicationTabConfig.orderSetTreatments : [];
                var drafts = consultationData.newlyAddedTabTreatments ? consultationData.newlyAddedTabTreatments.allMedicationTabConfig.treatments : [];
                consultationData.draftDrug = drafts.concat(orderSetTreatments);
                var params = createParams(consultationData);
                createFhirBundle(params.patient, params.conditions, params.medications, params.diagnosis)
                .then(function (bundle) {
                    var cdssAlerts = drugService.sendDiagnosisDrugBundle(bundle);
                    cdssAlerts.then(function (response) {
                        var alerts = response.data;
                        var existingAlerts = $rootScope.cdssAlerts || [];
                        $rootScope.cdssAlerts = addNewAlerts(alerts, existingAlerts, bundle);
                    });
                });
            }
        };

        var createParams = function (consultationData) {
            var patient = consultationData.patient;
            var conditions = consultationData.condition && consultationData.condition.concept.uuid ? consultationData.conditions.concat(consultationData.condition) : consultationData.conditions;
            var diagnosis = consultationData.newlyAddedDiagnoses && consultationData.newlyAddedDiagnoses.filter(function (diagnosis) {
                return diagnosis.codedAnswer && diagnosis.codedAnswer.name;
            }) || [];
            var medications = consultationData.draftDrug;
            return {
                patient: patient,
                conditions: conditions,
                diagnosis: diagnosis,
                medications: medications
            };
        };

        var getAlertMedicationCodes = function (alert) {
            if (alert.referenceMedications) {
                var codeList = [];
                alert.referenceMedications.forEach(function (med) {
                    var extractedCodes = med.coding.map(function (coding) {
                        return coding.code;
                    });
                    codeList = codeList.concat(extractedCodes);
                });
                return codeList;
            }
            return [];
        };

        var getAlertConditionCodes = function (alert) {
            if (alert.referenceConditions) {
                var codeList = [];
                alert.referenceConditions.forEach(function (med) {
                    var extractedCodes = med.coding.filter(function (cond) {
                        return !localStorage.getItem("conceptSource") || cond.system.includes(localStorage.getItem("conceptSource"));
                    }).map(function (coding) {
                        return coding.code;
                    });
                    codeList = codeList.concat(extractedCodes);
                });
                return codeList;
            }
            return [];
        };

        var getMedicationCodesFromEntry = function (entry) {
            return entry.resource.medicationCodeableConcept.coding[0].code;
        };

        var getConditionCodesFromEntry = function (entry) {
            return entry.resource.code.coding[0].code;
        };

        var isMedicationRequest = function (entry) {
            return entry.resource.resourceType === 'MedicationRequest';
        };

        var isCondition = function (entry) {
            return entry.resource.resourceType === 'Condition';
        };

        var checkAlertBundleMatch = function (alert, bundle) {
            var alertMedicationCodes = getAlertMedicationCodes(alert);
            var alertConditionCodes = getAlertConditionCodes(alert);

            var bundleMedicationCodes = bundle.entry
              .filter(isMedicationRequest)
              .map(getMedicationCodesFromEntry);

            var bundleConditionCodes = bundle.entry
              .filter(isCondition)
              .map(getConditionCodesFromEntry);

            return (
              alertMedicationCodes.some(function (code) {
                  return bundleMedicationCodes.includes(code);
              }) ||
              alertConditionCodes.some(function (code) {
                  return bundleConditionCodes.includes(code);
              })
            );
        };

        var addNewAlerts = function (newAlerts, currentAlerts, bundle) {
            var activeAlerts = newAlerts.map(function (item) {
                var isAlertInBundle = checkAlertBundleMatch(item, bundle);
                if (isAlertInBundle) {
                    item.isActive = true;
                }
                item.detail = item.detail.indexOf('\n') > -1 ? marked.parse(item.detail) : item.detail;
                return item;
            });
            if (!currentAlerts || (currentAlerts && currentAlerts.length === 0)) {
                return activeAlerts;
            }
            var alerts = activeAlerts.map(function (alert) {
                var getAlert = currentAlerts.find(function (currentAlert) {
                    return currentAlert.uuid === alert.uuid;
                });
                if (getAlert) {
                    if (alert.indicator !== getAlert.indicator || (alert.alertType === "High Dosage" && alert.summary.match(/\d+/g).sort().join('') !== getAlert.summary.match(/\d+/g).sort().join(''))) {
                        alert.isActive = true;
                    } else if (!isSubset(getAlertConditionCodes(getAlert), getAlertConditionCodes(alert)) || !isSubset(getAlertMedicationCodes(getAlert), getAlertMedicationCodes(alert))) {
                        alert.isActive = true;
                    } else {
                        alert.isActive = getAlert.isActive;
                    }
                }
                return alert;
            });

            return alerts;
        };
        var isSubset = function (oldList, newList) {
            return newList.every(function (newItem) {
                return oldList.includes(newItem);
            });
        };

        var sortInteractionsByStatus = function (alerts) {
            var order = { "critical": 0, "warning": 1, "info": 2 };
            return alerts.sort(function (a, b) {
                return order[a.indicator] - order[b.indicator];
            });
        };

        return {
            createFhirBundle: createFhirBundle,
            createParams: createParams,
            addNewAlerts: addNewAlerts,
            sortInteractionsByStatus: sortInteractionsByStatus,
            getAlerts: getAlerts
        };
    }]);

'use strict';

angular.module('bahmni.clinical')
    .factory('labOrderResultService', ['$http', '$q', 'configurationService', 'appService', '$bahmniCookieStore', function ($http, $q, configurationService, appService, $bahmniCookieStore) {
        var allTestsAndPanelsConcept = {};
        configurationService.getConfigurations(['allTestsAndPanelsConcept']).then(function (configurations) {
            allTestsAndPanelsConcept = configurations.allTestsAndPanelsConcept.results[0];
        });
        var sanitizeData = function (labOrderResults) {
            labOrderResults.forEach(function (result) {
                result.accessionDateTime = Bahmni.Common.Util.DateUtil.parse(result.accessionDateTime);
                result.hasRange = result.minNormal || result.maxNormal;
            });
        };

        var groupLabOrdersByPanel = function (labOrders) {
            var panels = {};
            var accessionGroup = [];
            if (labOrders) {
                labOrders.forEach(function (labOrder) {
                    if (!labOrder.panelName) {
                        labOrder.isPanel = false;
                        labOrder.orderName = labOrder.testName;
                        accessionGroup.push(labOrder);
                    } else {
                        panels[labOrder.panelName] = panels[labOrder.panelName] || {
                            accessionDateTime: labOrder.accessionDateTime,
                            orderName: labOrder.panelName,
                            tests: [],
                            isPanel: true
                        };
                        panels[labOrder.panelName].tests.push(labOrder);
                    }
                });
            }
            _.values(panels).forEach(function (value) {
                accessionGroup.push(value);
            });
            return accessionGroup;
        };

        var groupByPanel = function (accessions) {
            var grouped = [];
            accessions.forEach(function (labOrders) {
                grouped.push(groupLabOrdersByPanel(labOrders));
            });
            return grouped;
        };

        var flattened = function (accessions) {
            return accessions.map(
                function (results) {
                    var flattenedResults = _(results).map(
                        function (result) {
                            return result.isPanel === true ? [result, result.tests] : result;
                        }).flattenDeep().value();
                    return flattenedResults;
                }
            );
        };

        var flattenedTabularData = function (results) {
            var flattenedResults = _(results).map(
                function (result) {
                    return result.isPanel === true ? [result, result.tests] : result;
                }
            ).flattenDeep().value();
            return flattenedResults;
        };

        var transformGroupSort = function (results, initialAccessionCount, latestAccessionCount, sortResultColumnsLatestFirst, groupOrdersByPanel) {
            var labOrderResults = results.results;
            sanitizeData(labOrderResults);

            var accessionConfig = {
                initialAccessionCount: initialAccessionCount,
                latestAccessionCount: latestAccessionCount
            };

            var tabularResult = new Bahmni.Clinical.TabularLabOrderResults(results.tabularResult, accessionConfig, sortResultColumnsLatestFirst);
            if (groupOrdersByPanel) {
                tabularResult.tabularResult.orders = groupLabOrdersByPanel(tabularResult.tabularResult.orders);
            }
            var accessions = _.groupBy(labOrderResults, function (labOrderResult) {
                return labOrderResult.accessionUuid;
            });
            accessions = _.sortBy(accessions, function (accession) {
                return accession[0].accessionDateTime;
            });

            if (accessionConfig.initialAccessionCount || accessionConfig.latestAccessionCount) {
                var initial = _.take(accessions, accessionConfig.initialAccessionCount || 0);
                var latest = _.takeRight(accessions, accessionConfig.latestAccessionCount || 0);

                accessions = _.union(initial, latest);
            }
            accessions.reverse();
            return {
                accessions: groupByPanel(accessions),
                tabularResult: tabularResult
            };
        };
        var getAllForPatient = function (params) {
            var deferred = $q.defer();
            var paramsToBeSent = {};
            if (params.visitUuids) {
                paramsToBeSent.visitUuids = params.visitUuids;
            } else {
                if (!params.patientUuid) {
                    deferred.reject('patient uuid is mandatory');
                }
                paramsToBeSent.patientUuid = params.patientUuid;
                if (params.numberOfVisits !== 0) {
                    paramsToBeSent.numberOfVisits = params.numberOfVisits;
                }
            }
            var labResultsUrl = Bahmni.Common.Constants.bahmniLabOrderResultsUrl;
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    labResultsUrl = Bahmni.Common.Constants.bahmniDistroLabOrderResultsUrl;
                }
            }
            $http.get(labResultsUrl, {
                method: "GET",
                params: paramsToBeSent,
                withCredentials: true
            }).then(function (response) {
                var results = transformGroupSort(response.data, params.initialAccessionCount, params.latestAccessionCount, params.sortResultColumnsLatestFirst, params.groupOrdersByPanel);
                var sortedConceptSet = new Bahmni.Clinical.ConceptWeightBasedSorter(allTestsAndPanelsConcept);
                results.tabularResult.tabularResult.orders = sortedConceptSet.sortTestResults(results.tabularResult.tabularResult.orders);
                var resultObject = {
                    labAccessions: flattened(results.accessions.map(sortedConceptSet.sortTestResults)),
                    tabular: results.tabularResult
                };
                if (params.groupOrdersByPanel) {
                    resultObject.tabular.tabularResult.orders = flattenedTabularData(resultObject.tabular.tabularResult.orders);
                }
                deferred.resolve(resultObject);
            });

            return deferred.promise;
        };

        return {
            getAllForPatient: getAllForPatient
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

angular.module('bahmni.common.appFramework')
    .service('loadConfigService', ['$http', function ($http) {
        this.loadConfig = function (url) {
            return $http.get(url, {withCredentials: true});
        };
    }]);

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

angular.module('bahmni.clinical')
    .service('diseaseTemplateService', ['$http', '$q', 'clinicalAppConfigService', function ($http, $q, clinicalAppConfigService) {
        this.getLatestDiseaseTemplates = function (patientUuid, diseaseTemplates, startDate, endDate) {
            var url = Bahmni.Common.Constants.diseaseTemplateUrl;
            var params = {"patientUuid": patientUuid, "diseaseTemplateConfigList": diseaseTemplates};
            params.startDate = startDate && moment(startDate).format(Bahmni.Common.Constants.ServerDateTimeFormat);
            params.endDate = endDate && moment(endDate).format(Bahmni.Common.Constants.ServerDateTimeFormat);
            var deferred = $q.defer();
            $http.post(url, params, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            }).then(function (response) {
                var diseaseTemplates = mapDiseaseTemplates(response.data, clinicalAppConfigService.getAllConceptsConfig());
                deferred.resolve(diseaseTemplates);
            });
            return deferred.promise;
        };

        this.getAllDiseaseTemplateObs = function (patientUuid, diseaseName, startDate, endDate) {
            var url = Bahmni.Common.Constants.AllDiseaseTemplateUrl;
            var params = {patientUuid: patientUuid, diseaseTemplateConfigList: [{"templateName": diseaseName}]};
            params.startDate = startDate && moment(startDate).format(Bahmni.Common.Constants.ServerDateTimeFormat);
            params.endDate = endDate && moment(endDate).format(Bahmni.Common.Constants.ServerDateTimeFormat);
            var deferred = $q.defer();
            $http.post(url,
                params, {
                    withCredentials: true,
                    headers: {"Accept": "application/json", "Content-Type": "application/json"}
                }).then(function (diseaseTemplateResponse) {
                    var diseaseTemplates = mapDiseaseTemplates([diseaseTemplateResponse.data], clinicalAppConfigService.getAllConceptsConfig());
                    deferred.resolve(diseaseTemplates[0]);
                });
            return deferred.promise;
        };

        var mapDiseaseTemplates = function (diseaseTemplates, allConceptsConfig) {
            var mappedDiseaseTemplates = [];
            diseaseTemplates.forEach(function (diseaseTemplate) {
                mappedDiseaseTemplates.push(new Bahmni.Clinical.DiseaseTemplateMapper(diseaseTemplate, allConceptsConfig));
            });
            return mappedDiseaseTemplates;
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

angular.module('bahmni.common.conceptSet')
    .factory('conceptSetService', ['$http', '$q', '$bahmniTranslate', function ($http, $q, $bahmniTranslate) {
        var getConcept = function (params, cache) {
            return $http.get(Bahmni.Common.Constants.conceptSearchByFullNameUrl, {
                params: params,
                cache: cache
            });
        };

        var getComputedValue = function (encounterData) {
            var url = Bahmni.Common.Constants.encounterModifierUrl;
            return $http.post(url, encounterData, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        var getObsTemplatesForProgram = function (programUuid) {
            var url = Bahmni.Common.Constants.entityMappingUrl;
            return $http.get(url, {
                params: {
                    entityUuid: programUuid,
                    mappingType: 'program_obstemplate',
                    s: 'byEntityAndMappingType'
                }
            });
        };

        return {
            getConcept: getConcept,
            getComputedValue: getComputedValue,
            getObsTemplatesForProgram: getObsTemplatesForProgram
        };
    }]);


'use strict';

Bahmni.Common.Util.DateTimeFormatter = {

    getDateWithoutTime: function (datetime) {
        return datetime ? moment(datetime).format("YYYY-MM-DD") : null;
    }
};

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

angular.module('bahmni.clinical')
    .factory('treatmentService', ['$http', '$q', '$compile', '$timeout', 'spinner', 'appService', '$rootScope', 'transmissionService', '$filter', 'printer', '$bahmniCookieStore', function ($http, $q, $compile, $timeout, spinner, appService, $rootScope, transmissionService, $filter, printer, $bahmniCookieStore) {
        var createDrugOrder = function (drugOrder) {
            return Bahmni.Clinical.DrugOrder.create(drugOrder);
        };
        var getActiveDrugOrdersFromServer = function (patientUuid, startDate, endDate) {
            return $http.get(Bahmni.Common.Constants.bahmniDrugOrderUrl + "/active", {
                params: {
                    patientUuid: patientUuid,
                    startDate: startDate,
                    endDate: endDate
                },
                withCredentials: true
            });
        };

        var getPrescribedAndActiveDrugOrders = function (patientUuid, numberOfVisits, getOtherActive, visitUuids, startDate, endDate, getEffectiveOrdersOnly) {
            var drugOrderUrl = Bahmni.Common.Constants.bahmniDrugOrderUrl + "/prescribedAndActive";
            var userInSession = $bahmniCookieStore.get(Bahmni.Common.Constants.currentUser);
            if (userInSession) {
                var restrictLocationToUser = (appService.getAppDescriptor() && appService.getAppDescriptor().getConfigValue('restrictLocationToUser')) || false;
                if (restrictLocationToUser) {
                    drugOrderUrl = Bahmni.Common.Constants.bahmniDistroDrugOrderUrl + "/prescribedAndActive";
                }
            }
            return $http.get(drugOrderUrl, {
                params: {
                    patientUuid: patientUuid,
                    numberOfVisits: numberOfVisits,
                    getOtherActive: getOtherActive,
                    visitUuids: visitUuids,
                    startDate: startDate,
                    endDate: endDate,
                    getEffectiveOrdersOnly: getEffectiveOrdersOnly,
                    preferredLocale: $rootScope.currentUser.userProperties.defaultLocale
                },
                withCredentials: true
            }).success(function (response) {
                for (var key in response) {
                    response[key] = response[key].map(createDrugOrder);
                }
            });
        };

        var getMedicationSchedulesForOrders = function (patientUuid, orderUuids) {
            return $http.get(Bahmni.Common.Constants.medicationSchedulesForOrders, {
                params: {
                    patientUuid: patientUuid,
                    orderUuids: orderUuids
                },
                withCredentials: true
            });
        };

        var getConfig = function () {
            return $http.get(Bahmni.Common.Constants.drugOrderConfigurationUrl, {
                withCredentials: true
            });
        };

        var getProgramConfig = function () {
            var programConfig = appService.getAppDescriptor() ? appService.getAppDescriptor().getConfigValue("program") || {} : {};
            return programConfig;
        };

        var getActiveDrugOrders = function (patientUuid, fromDate, toDate) {
            var programConfig = getProgramConfig();
            var startDate = programConfig.showDetailsWithinDateRange ? fromDate : null;
            var endDate = programConfig.showDetailsWithinDateRange ? toDate : null;

            var deferred = $q.defer();
            getActiveDrugOrdersFromServer(patientUuid, startDate, endDate).success(function (response) {
                var activeDrugOrders = response.map(createDrugOrder);
                deferred.resolve(activeDrugOrders);
            });
            return deferred.promise;
        };

        var getPrescribedDrugOrders = function (patientUuid, includeActiveVisit, numberOfVisits, fromDate, toDate) {
            var programConfig = getProgramConfig();
            var startDate = programConfig.showDetailsWithinDateRange ? fromDate : null;
            var endDate = programConfig.showDetailsWithinDateRange ? toDate : null;

            var deferred = $q.defer();
            $http.get(Bahmni.Common.Constants.bahmniDrugOrderUrl, {
                method: "GET",
                params: {
                    patientUuid: patientUuid,
                    numberOfVisits: numberOfVisits,
                    includeActiveVisit: includeActiveVisit,
                    startDate: startDate,
                    endDate: endDate
                },
                withCredentials: true
            }).success(function (response) {
                var activeDrugOrders = response.map(createDrugOrder);
                deferred.resolve(activeDrugOrders);
            });
            return deferred.promise;
        };

        var getNonCodedDrugConcept = function () {
            var deferred = $q.defer();
            $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                method: "GET",
                params: {
                    property: 'drugOrder.drugOther'
                },
                withCredentials: true,
                headers: {
                    Accept: 'text/plain'
                }
            }).success(function (conceptUuid) {
                deferred.resolve(conceptUuid);
            });
            return deferred.promise;
        };

        var getAllDrugOrdersFor = function (patientUuid, conceptSetToBeIncluded, conceptSetToBeExcluded, isActive, patientProgramUuid) {
            var deferred = $q.defer();
            var params = {patientUuid: patientUuid};
            if (conceptSetToBeIncluded) {
                params.includeConceptSet = conceptSetToBeIncluded;
            }
            if (conceptSetToBeExcluded) {
                params.excludeConceptSet = conceptSetToBeExcluded;
            }
            if (isActive !== undefined) {
                params.isActive = isActive;
            }
            if (patientProgramUuid) {
                params.patientProgramUuid = patientProgramUuid;
            }

            $http.get(Bahmni.Common.Constants.bahmniDrugOrderUrl + "/drugOrderDetails", {
                params: params,
                withCredentials: true
            }).success(function (response) {
                deferred.resolve(response);
            });
            return deferred.promise;
        };

        var voidDrugOrder = function (drugOrder) {
            var deferred = $q.defer();

            $http.delete([Bahmni.Common.Constants.ordersUrl, '/', drugOrder.uuid].join('')).success(function (response) {
                deferred.resolve(response);
            });

            return deferred.promise;
        };

        var sharePrescriptions = function (prescriptionDetails) {
            $http.get('common/views/prescriptionPrint.html').then(function (templateData) {
                var template = templateData.data;
                var printScope = $rootScope.$new();
                angular.extend(printScope, prescriptionDetails);
                var element = $compile($('<div>' + template + '</div>'))(printScope);
                var renderAndSendPromise = $q.defer();
                var waitForRenderAndSend = function () {
                    if (printScope.$$phase || $http.pendingRequests.length) {
                        $timeout(waitForRenderAndSend, 1000);
                    } else {
                        html2pdf().from(element.html()).outputPdf().then(function (pdfContent) {
                            var attachments = [{
                                "contentType": "application/pdf",
                                "name": "Precription_" + $filter("bahmniDate")(prescriptionDetails.visitDate).split(" ").join("-") + ".pdf",
                                "data": btoa(pdfContent),
                                "url": null
                            }];
                            var subject = "Prescription for consultation at " + $rootScope.facilityLocation.name + " on " + $filter("bahmniDate")(prescriptionDetails.visitDate);
                            var body = transmissionService.getSharePrescriptionMailContent(prescriptionDetails);
                            var emailUrl = appService.getAppDescriptor().formatUrl(Bahmni.Common.Constants.sendViaEmailUrl, { 'patientUuid': prescriptionDetails.patient.uuid });
                            transmissionService.sendEmail(attachments, subject, body, emailUrl, [], []);
                        });
                        renderAndSendPromise.resolve();
                        printScope.$destroy();
                    }
                    return renderAndSendPromise.promise;
                };
                spinner.forPromise(waitForRenderAndSend());
            });
        };

        var getOrderedProviderAttributesForPrint = function (attributeData, attributeTypesToFilter) {
            if (!attributeTypesToFilter) return;
            var filteredAttributes = attributeData.filter(function (attribute) {
                return attributeTypesToFilter.includes(attribute.attributeType.display);
            });
            filteredAttributes.sort(function (a, b) {
                return attributeTypesToFilter.indexOf(a.attributeType.display) - attributeTypesToFilter.indexOf(b.attributeType.display);
            });
            return filteredAttributes;
        };

        var printSelectedPrescriptions = function (printPrescriptionFeatureConfig, drugOrdersForPrint, patient, additionalInfo, diagnosesCodes, dispenserInfo, observationsEntries, allergiesData, visitDate) {
            if (drugOrdersForPrint.length > 0) {
                var encounterDrugOrderMap = Object.values(drugOrdersForPrint.reduce(function (orderMap, item) {
                    const providerUuid = item.provider.uuid;
                    if (!orderMap[providerUuid]) {
                        orderMap[providerUuid] = {
                            providerUuid: providerUuid,
                            drugOrders: []
                        };
                    }
                    orderMap[providerUuid].drugOrders.push(item);
                    return orderMap;
                }, {}));

                var printParams = {
                    title: printPrescriptionFeatureConfig.title || "",
                    header: printPrescriptionFeatureConfig.header || "",
                    logo: printPrescriptionFeatureConfig.logo || ""
                };
                var templateUrl = printPrescriptionFeatureConfig.templateUrl || '../common/displaycontrols/prescription/views/prescription.html';
                var fileName = patient.givenName + patient.familyName + "_" + patient.identifier + "_Prescription";
                const printData = {
                    patient: patient,
                    encounterDrugOrderMap: encounterDrugOrderMap,
                    printParams: printParams,
                    additionalInfo: additionalInfo,
                    diagnosesCodes: diagnosesCodes,
                    dispenserInfo: dispenserInfo,
                    observationsEntries: observationsEntries,
                    allergies: allergiesData,
                    visitDate: visitDate
                };
                printer.print(templateUrl, printData, fileName);
            }
        };

        return {
            getActiveDrugOrders: getActiveDrugOrders,
            getConfig: getConfig,
            getPrescribedDrugOrders: getPrescribedDrugOrders,
            getPrescribedAndActiveDrugOrders: getPrescribedAndActiveDrugOrders,
            getMedicationSchedulesForOrders: getMedicationSchedulesForOrders,
            getNonCodedDrugConcept: getNonCodedDrugConcept,
            getAllDrugOrdersFor: getAllDrugOrdersFor,
            voidDrugOrder: voidDrugOrder,
            sharePrescriptions: sharePrescriptions,
            printSelectedPrescriptions: printSelectedPrescriptions,
            getOrderedProviderAttributesForPrint: getOrderedProviderAttributesForPrint
        };
    }]);

Bahmni.Clinical.StateNameEvenTypeMap = {
    "search.patientsearch": "VIEWED_CLINICAL_PATIENT_SEARCH",
    "patient.dashboard.show": "VIEWED_CLINICAL_DASHBOARD",
    "patient.dashboard.show.observations": "VIEWED_OBSERVATIONS_TAB",
    "patient.dashboard.show.diagnosis": "VIEWED_DIAGNOSIS_TAB",
    "patient.dashboard.show.treatment.page": "VIEWED_TREATMENT_TAB",
    "patient.dashboard.show.disposition": "VIEWED_DISPOSITION_TAB",
    "patient.dashboard.show.summary": "VIEWED_DASHBOARD_SUMMARY",
    "patient.dashboard.show.orders": "VIEWED_ORDERS_TAB",
    "patient.dashboard.show.followup": "VIEWED_FOLLOWUP_TAB",
    "patient.dashboard.show.bacteriology": "VIEWED_BACTERIOLOGY_TAB",
    "patient.dashboard.show.investigation": "VIEWED_INVESTIGATION_TAB",
    "patient.visit.summaryprint": "VIEWED_SUMMARY_PRINT",
    "patient.dashboard.visit": "VIEWED_VISIT_DASHBOARD",
    "patient.dashboard.ipdVisit": "VIEWED_VISIT_DASHBOARD",
    "patient.dashboard.visitPrint": "VIEWED_VISIT_PRINT",
    "patient.dashboard.observation": "VIEWED_DASHBOARD_OBSERVATION",
    "patient.patientProgram.show": "VIEWED_PATIENTPROGRAM"
};

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
