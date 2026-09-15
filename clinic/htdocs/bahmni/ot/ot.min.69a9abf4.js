'use strict';

angular.module('bahmni.common.routeErrorHandler', ['ui.router'])
    .run(['$rootScope', function ($rootScope) {
        $rootScope.$on('$stateChangeError', function (event) {
            event.preventDefault();
        });
    }]);

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

Bahmni.Common.Util.DateTimeFormatter = {

    getDateWithoutTime: function (datetime) {
        return datetime ? moment(datetime).format("YYYY-MM-DD") : null;
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

'use strict';

Modernizr.addTest('ios', function () {
    return navigator.userAgent.match(/(iPad|iPhone|iPod)/i) ? true : false;
});

Modernizr.addTest('windowOS', function () {
    return navigator.appVersion.indexOf("Win") != -1;
});

var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.Models = Bahmni.Common.Models || {};

angular.module('bahmni.common.models', []);

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

Bahmni.Common.VisitSummary = function (visitSummary) {
    angular.extend(this, visitSummary);

    this.isAdmitted = function () {
        return this.admissionDetails && this.admissionDetails.uuid ? true : false;
    };

    this.isDischarged = function () {
        return this.dischargeDetails && this.dischargeDetails.uuid ? true : false;
    };

    this.getAdmissionEncounterUuid = function () {
        return this.isAdmitted() ? this.admissionDetails.uuid : undefined;
    };

    this.getDischargeEncounterUuid = function () {
        return this.isDischarged() ? this.dischargeDetails.uuid : undefined;
    };

    this.hasBeenAdmitted = function () {
        return this.isAdmitted() && !this.isDischarged();
    };
};


angular.module('bahmni.common.patient', []);

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

Bahmni.PatientMapper = function (patientConfig, $rootScope, $translate) {
    this.patientConfig = patientConfig;

    this.map = function (openmrsPatient) {
        var patient = this.mapBasic(openmrsPatient);
        this.mapAttributes(patient, openmrsPatient.person.attributes);
        return patient;
    };

    this.mapBasic = function (openmrsPatient) {
        var patient = {};
        patient.uuid = openmrsPatient.uuid;
        patient.givenName = openmrsPatient.person.preferredName.givenName;
        patient.familyName = openmrsPatient.person.preferredName.familyName === null ? '' : openmrsPatient.person.preferredName.familyName;
        patient.name = patient.givenName + ' ' + patient.familyName;
        patient.age = openmrsPatient.person.age;
        patient.ageText = calculateAge(Bahmni.Common.Util.DateUtil.parseServerDateToDate(openmrsPatient.person.birthdate));
        patient.gender = openmrsPatient.person.gender;
        patient.genderText = mapGenderText(patient.gender);
        patient.address = mapAddress(openmrsPatient.person.preferredAddress);
        patient.birthdateEstimated = openmrsPatient.person.birthdateEstimated;
        patient.birthtime = Bahmni.Common.Util.DateUtil.parseServerDateToDate(openmrsPatient.person.birthtime);
        patient.bloodGroupText = getPatientBloodGroupText(openmrsPatient);

        if (openmrsPatient.identifiers) {
            var primaryIdentifier = openmrsPatient.identifiers[0].primaryIdentifier;
            patient.identifier = primaryIdentifier ? primaryIdentifier : openmrsPatient.identifiers[0].identifier;
        }

        if (openmrsPatient.identifiers && openmrsPatient.identifiers.length > 1) {
            patient.additionalIdentifiers = parseIdentifiers(openmrsPatient.identifiers.slice(1));
        }

        if (openmrsPatient.person.birthdate) {
            patient.birthdate = parseDate(openmrsPatient.person.birthdate);
        }

        if (openmrsPatient.person.personDateCreated) {
            patient.registrationDate = parseDate(openmrsPatient.person.personDateCreated);
        }

        patient.image = Bahmni.Common.Constants.patientImageUrlByPatientUuid + openmrsPatient.uuid;
        return patient;
    };

    this.getPatientConfigByUuid = function (patientConfig, attributeUuid) {
        if (this.patientConfig.personAttributeTypes) {
            return patientConfig.personAttributeTypes.filter(function (item) {
                return item.uuid === attributeUuid;
            })[0];
        }
        return {};
    };

    this.mapAttributes = function (patient, attributes) {
        var self = this;
        if (this.patientConfig) {
            attributes.forEach(function (attribute) {
                var x = self.getPatientConfigByUuid(patientConfig, attribute.attributeType.uuid);
                patient[x.name] = {label: x.description, value: attribute.value, isDateField: checkIfDateField(x) };
            });
        }
    };

    var calculateAge = function (birthDate) {
        var DateUtil = Bahmni.Common.Util.DateUtil;
        var age = DateUtil.diffInYearsMonthsDays(birthDate, DateUtil.now());
        var ageInString = "";
        if (age.years) {
            ageInString += age.years + " <span> " + $translate.instant("CLINICAL_YEARS_TRANSLATION_KEY") + " </span>";
        }
        if (age.months) {
            ageInString += age.months + "<span>  " + $translate.instant("CLINICAL_MONTHS_TRANSLATION_KEY") + " </span>";
        }
        if (age.days) {
            ageInString += age.days + "<span>  " + $translate.instant("CLINICAL_DAYS_TRANSLATION_KEY") + " </span>";
        }
        return ageInString;
    };

    var mapAddress = function (preferredAddress) {
        return preferredAddress ? {
            "address1": preferredAddress.address1,
            "address2": preferredAddress.address2,
            "address3": preferredAddress.address3,
            "address4": preferredAddress.address4,
            "address5": preferredAddress.address5,
            "cityVillage": preferredAddress.cityVillage,
            "countyDistrict": preferredAddress.countyDistrict === null ? '' : preferredAddress.countyDistrict,
            "stateProvince": preferredAddress.stateProvince,
            "postalCode": preferredAddress.postalCode ? preferredAddress.postalCode : "",
            "country": preferredAddress.country ? preferredAddress.country : ""
        } : {};
    };

    var parseDate = function (dateStr) {
        if (dateStr) {
            return Bahmni.Common.Util.DateUtil.parse(dateStr.substr(0, 10));
        }
        return dateStr;
    };

    var parseIdentifiers = function (identifiers) {
        var parseIdentifiers = {};
        identifiers.forEach(function (identifier) {
            if (identifier.identifierType) {
                var label = identifier.identifierType.display;
                parseIdentifiers[label] = {"label": label, "value": identifier.identifier};
            }
        });
        return parseIdentifiers;
    };

    var mapGenderText = function (genderChar) {
        if (genderChar == null) {
            return null;
        }
        return "<span>" + $rootScope.genderMap[angular.uppercase(genderChar)] + "</span>";
    };

    var getPatientBloodGroupText = function (openmrsPatient) {
        if (openmrsPatient.person.bloodGroup) {
            return "<span>" + openmrsPatient.person.bloodGroup + "</span>";
        }
        if (openmrsPatient.person.attributes && openmrsPatient.person.attributes.length > 0) {
            var bloodGroup;
            _.forEach(openmrsPatient.person.attributes, function (attribute) {
                if (attribute.attributeType.display == "bloodGroup") {
                    bloodGroup = attribute.display;
                }
            });
            if (bloodGroup) {
                return "<span>" + bloodGroup + "</span>";
            }
        }
    };

    var checkIfDateField = function (x) {
        return x.format === Bahmni.Common.Constants.patientAttributeDateFieldFormat;
    };
};

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

angular.module('bahmni.common.patient')
.filter('gender', ['$rootScope', function ($rootScope) {
    return function (genderChar) {
        if (genderChar == null) {
            return "Unknown";
        }
        return $rootScope.genderMap[angular.uppercase(genderChar)];
    };
}]);

'use strict';

angular.module('bahmni.common.patient').directive('patientSummary', function () {
    var link = function ($scope) {
        $scope.showPatientDetails = false;
        $scope.togglePatientDetails = function () {
            $scope.showPatientDetails = !$scope.showPatientDetails;
        };

        $scope.onImageClick = function () {
            if ($scope.onImageClickHandler) {
                $scope.onImageClickHandler();
            }
        };
    };

    return {
        restrict: 'E',
        templateUrl: '../common/patient/header/views/patientSummary.html',
        link: link,
        required: 'patient',
        scope: {
            patient: "=",
            bedDetails: "=",
            onImageClickHandler: "&"
        }
    };
});

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
    .service('bedService', ['$http', '$rootScope', function ($http, $rootScope) {
        var mapBedDetails = function (response) {
            var results = response.data.results;
            if (!_.isEmpty(results)) {
                var bed = _.first(results);
                return {
                    'wardName': (bed.physicalLocation.parentLocation && bed.physicalLocation.parentLocation.display) ? bed.physicalLocation.parentLocation.display : '',
                    'wardUuid': (bed.physicalLocation.parentLocation && bed.physicalLocation.parentLocation.uuid) ? bed.physicalLocation.parentLocation.uuid : '',
                    'physicalLocationName': bed.physicalLocation.name,
                    'bedNumber': bed.bedNumber,
                    'bedId': bed.bedId
                };
            }
        };

        this.setBedDetailsForPatientOnRootScope = function (uuid) {
            var promise = this.getAssignedBedForPatient(uuid);
            promise.then(function (bedDetails) {
                $rootScope.bedDetails = bedDetails;
            });
            return promise;
        };

        this.getAssignedBedForPatient = function (patientUuid, visitUuid) {
            var params = {
                patientUuid: patientUuid,
                v: "full"
            };
            if (visitUuid) {
                params.visitUuid = visitUuid;
                params.s = 'bedDetailsFromVisit';
            }
            return $http.get(Bahmni.Common.Constants.bedFromVisit, {
                method: "GET",
                params: params,
                withCredentials: true
            }).then(mapBedDetails);
        };
        this.assignBed = function (bedId, patientUuid, encounterUuid) {
            var patientJson = {"patientUuid": patientUuid, "encounterUuid": encounterUuid};
            return $http.post(Bahmni.Common.Constants.bedFromVisit + "/" + bedId, patientJson, {
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.getBedInfo = function (bedId) {
            return $http.get(Bahmni.Common.Constants.bedFromVisit + "/" + bedId + "?v=custom:(bedId,bedNumber,patients:(uuid,person:(age,personName:(givenName,familyName),gender),identifiers:(uuid,identifier),),physicalLocation:(name))", {
                withCredentials: true
            });
        };

        this.getCompleteBedDetailsByBedId = function (bedId) {
            return $http.get(Bahmni.Common.Constants.bedFromVisit + "/" + bedId, {
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
angular.module('bahmni.common.domain')
    .factory('programService', ['$http', 'programHelper', 'appService', function ($http, programHelper, appService) {
        var PatientProgramMapper = new Bahmni.Common.Domain.PatientProgramMapper();

        var getAllPrograms = function () {
            return $http.get(Bahmni.Common.Constants.programUrl, {params: {v: 'default'}}).then(function (response) {
                var allPrograms = programHelper.filterRetiredPrograms(response.data.results);
                _.forEach(allPrograms, function (program) {
                    program.allWorkflows = programHelper.filterRetiredWorkflowsAndStates(program.allWorkflows);
                    if (program.outcomesConcept) {
                        program.outcomesConcept.setMembers = programHelper.filterRetiredOutcomes(program.outcomesConcept.setMembers);
                    }
                });
                return allPrograms;
            });
        };

        var enrollPatientToAProgram = function (patientUuid, programUuid, dateEnrolled, stateUuid, patientProgramAttributes, programAttributeTypes) {
            var attributeFormatter = new Bahmni.Common.Domain.AttributeFormatter();
            var req = {
                url: Bahmni.Common.Constants.programEnrollPatientUrl,
                content: {
                    patient: patientUuid,
                    program: programUuid,
                    dateEnrolled: moment(dateEnrolled).format(Bahmni.Common.Constants.ServerDateTimeFormat),
                    attributes: attributeFormatter.removeUnfilledAttributes(attributeFormatter.getMrsAttributes(patientProgramAttributes, (programAttributeTypes || [])))
                },
                headers: {"Content-Type": "application/json"}
            };
            if (!_.isEmpty(stateUuid)) {
                req.content.states = [
                    {
                        state: stateUuid,
                        startDate: moment(dateEnrolled).format(Bahmni.Common.Constants.ServerDateTimeFormat)
                    }
                ];
            }
            return $http.post(req.url, req.content, req.headers);
        };

        var getPatientPrograms = function (patientUuid, filterAttributesForProgramDisplayControl, patientProgramUuid) {
            var params = {
                v: "full",
                patientProgramUuid: patientProgramUuid,
                patient: patientUuid
            };
            return $http.get(Bahmni.Common.Constants.programEnrollPatientUrl, {params: params}).then(function (response) {
                var patientPrograms = response.data.results;
                return getProgramAttributeTypes().then(function (programAttributeTypes) {
                    if (filterAttributesForProgramDisplayControl) {
                        patientPrograms = programHelper.filterProgramAttributes(response.data.results, programAttributeTypes);
                    }

                    return programHelper.groupPrograms(patientPrograms);
                });
            });
        };

        var savePatientProgram = function (patientProgramUuid, content) {
            var req = {
                url: Bahmni.Common.Constants.programEnrollPatientUrl + "/" + patientProgramUuid,
                content: content,
                headers: {"Content-Type": "application/json"}
            };
            return $http.post(req.url, req.content, req.headers);
        };

        var deletePatientState = function (patientProgramUuid, patientStateUuid) {
            var req = {
                url: Bahmni.Common.Constants.programStateDeletionUrl + "/" + patientProgramUuid + "/state/" + patientStateUuid,
                content: {
                    "!purge": "",
                    "reason": "User deleted the state."
                },
                headers: {"Content-Type": "application/json"}
            };
            return $http.delete(req.url, req.content, req.headers);
        };

        var getProgramAttributeTypes = function () {
            return $http.get(Bahmni.Common.Constants.programAttributeTypes, {params: {v: 'custom:(uuid,name,description,datatypeClassname,datatypeConfig,concept)'}}).then(function (response) {
                var programAttributesConfig = appService.getAppDescriptor().getConfigValue("program");

                var mandatoryProgramAttributes = [];
                for (var attributeName in programAttributesConfig) {
                    if (programAttributesConfig[attributeName].required) {
                        mandatoryProgramAttributes.push(attributeName);
                    }
                }
                return new Bahmni.Common.Domain.AttributeTypeMapper().mapFromOpenmrsAttributeTypes(response.data.results, mandatoryProgramAttributes, programAttributesConfig).attributeTypes;
            });
        };

        var updatePatientProgram = function (patientProgram, programAttributeTypes, dateCompleted) {
            return savePatientProgram(patientProgram.uuid, PatientProgramMapper.map(patientProgram, programAttributeTypes, dateCompleted));
        };

        var getProgramStateConfig = function () {
            var config = appService.getAppDescriptor().getConfigValue('programDisplayControl');
            return config ? config.showProgramStateInTimeline : false;
        };

        var getDefaultProgram = function () {
            var defaultProgram = appService.getAppDescriptor().getConfigValue('defaultProgram') || null;
            return defaultProgram;
        };

        var getProgramRedirectionConfig = function () {
            var config = appService.getAppDescriptor().getConfigValue('programRedirection');
            return config ? config : null;
        };

        var getEnrollmentInfoFor = function (patientUuid, representation) {
            var params = {
                patient: patientUuid,
                v: representation
            };
            return $http.get(Bahmni.Common.Constants.programEnrollPatientUrl, { params: params }).then(function (response) {
                return response.data.results;
            });
        };

        var disableProgramOutcomeEditOption = function () {
            return appService.getAppDescriptor().getConfigValue('disableProgramOutcomeEditOption') || false;
        };

        var getObservationFormsConfig = function () {
            return appService.getAppDescriptor().getConfigValue('observationForms') || {};
        };

        return {
            getAllPrograms: getAllPrograms,
            enrollPatientToAProgram: enrollPatientToAProgram,
            getPatientPrograms: getPatientPrograms,
            savePatientProgram: savePatientProgram,
            updatePatientProgram: updatePatientProgram,
            deletePatientState: deletePatientState,
            getProgramAttributeTypes: getProgramAttributeTypes,
            getProgramStateConfig: getProgramStateConfig,
            getEnrollmentInfoFor: getEnrollmentInfoFor,
            getDefaultProgram: getDefaultProgram,
            getProgramRedirectionConfig: getProgramRedirectionConfig,
            disableProgramOutcomeEditOption: disableProgramOutcomeEditOption,
            getObservationFormsConfig: getObservationFormsConfig
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
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.UIControls = Bahmni.Common.UIControls || {};
Bahmni.Common.UIControls.ProgramManagement = Bahmni.Common.UIControls.ProgramManagement || {};

angular.module('bahmni.common.uicontrols.programmanagment', []);

'use strict';

angular.module('bahmni.common.uicontrols.programmanagment')
    .service('programHelper', ['appService', function (appService) {
        var self = this;
        var programConfiguration = appService.getAppDescriptor().getConfig("program") && appService.getAppDescriptor().getConfig("program").value;

        var isAttributeRequired = function (attribute) {
            var attributeName = attribute.attributeType.display;
            return programConfiguration && programConfiguration[attributeName] && programConfiguration[attributeName].required;
        };

        this.filterRetiredPrograms = function (programs) {
            return _.filter(programs, function (program) {
                return !program.retired;
            });
        };

        this.filterRetiredWorkflowsAndStates = function (workflows) {
            var allWorkflows = _.filter(workflows, function (workflow) {
                return !workflow.retired;
            });
            _.forEach(allWorkflows, function (workflow) {
                workflow.states = _.filter(workflow.states, function (state) {
                    return !state.retired;
                });
            });
            return allWorkflows;
        };

        this.filterRetiredOutcomes = function (outcomes) {
            return _.filter(outcomes, function (outcome) {
                return !outcome.retired;
            });
        };

        var mapAttributes = function (attribute) {
            attribute.name = attribute.attributeType.description ? attribute.attributeType.description : attribute.name;
            attribute.value = attribute.value;
            attribute.required = isAttributeRequired(attribute);
        };
        var mapPrograms = function (program) {
            program.dateEnrolled = Bahmni.Common.Util.DateUtil.parseServerDateToDate(program.dateEnrolled);
            program.dateCompleted = Bahmni.Common.Util.DateUtil.parseServerDateToDate(program.dateCompleted);
            program.program.allWorkflows = self.filterRetiredWorkflowsAndStates(program.program.allWorkflows);
            _.forEach(program.attributes, function (attribute) {
                mapAttributes(attribute);
            });
        };

        function shouldDisplayAllAttributes (programDisplayControlConfig) {
            return (programDisplayControlConfig && programDisplayControlConfig['programAttributes'] == undefined) || programDisplayControlConfig == undefined;
        }

        this.filterProgramAttributes = function (patientPrograms, programAttributeTypes) {
            var programDisplayControlConfig = appService.getAppDescriptor().getConfigValue('programDisplayControl');
            var config = programDisplayControlConfig ? programDisplayControlConfig['programAttributes'] : [];
            var configAttrList = [];
            if (shouldDisplayAllAttributes(programDisplayControlConfig)) {
                configAttrList = programAttributeTypes;
            } else {
                configAttrList = programAttributeTypes.filter(function (each) {
                    return config && config.indexOf(each.name) !== -1;
                });
            }

            if (_.isEmpty(configAttrList)) {
                return patientPrograms.map(function (patientProgram) {
                    patientProgram.attributes = [];
                    return patientProgram;
                });
            }

            patientPrograms.forEach(function (program) {
                var attrsToBeDisplayed = [];

                configAttrList.forEach(function (configAttr) {
                    var attr = _.find(program.attributes, function (progAttr) {
                        return progAttr.attributeType.display === configAttr.name;
                    });

                    attr = attr ? attr : {
                        value: ""
                    };
                    attr.attributeType = configAttr;
                    attr.attributeType.display = configAttr.name;
                    attrsToBeDisplayed.push(attr);
                });

                program.attributes = attrsToBeDisplayed;
            });
            return patientPrograms;
        };

        this.groupPrograms = function (patientPrograms) {
            var activePrograms = [];
            var endedPrograms = [];
            var groupedPrograms = {};
            if (patientPrograms) {
                var filteredPrograms = this.filterRetiredPrograms(patientPrograms);
                _.forEach(filteredPrograms, function (program) {
                    mapPrograms(program);
                    if (program.dateCompleted) {
                        endedPrograms.push(program);
                    } else {
                        activePrograms.push(program);
                    }
                });
                groupedPrograms.activePrograms = _.sortBy(activePrograms, function (program) {
                    return moment(program.dateEnrolled).toDate();
                }).reverse();
                groupedPrograms.endedPrograms = _.sortBy(endedPrograms, function (program) {
                    return moment(program.dateCompleted).toDate();
                }).reverse();
            }
            return groupedPrograms;
        };
    }]);


'use strict';

Bahmni.Common.Domain.PatientProgramMapper = function () {
    this.map = function (patientProgram, programAttributeTypes, dateCompleted) {
        var attributeFormatter = new Bahmni.Common.Domain.AttributeFormatter();
        return {
            dateEnrolled: moment(Bahmni.Common.Util.DateUtil.getDateWithoutTime(patientProgram.dateEnrolled)).format(Bahmni.Common.Constants.ServerDateTimeFormat),
            states: patientProgram.states,
            uuid: patientProgram.uuid,
            dateCompleted: dateCompleted ? moment(dateCompleted).format(Bahmni.Common.Constants.ServerDateTimeFormat) : null,
            outcome: patientProgram.outcomeData ? patientProgram.outcomeData.uuid : null,
            attributes: attributeFormatter.getMrsAttributesForUpdate(patientProgram.patientProgramAttributes, programAttributeTypes, patientProgram.attributes),
            voided: !!patientProgram.voided,
            voidReason: patientProgram.voidReason
        };
    };
};

'use strict';
var Bahmni = Bahmni || {};
Bahmni.ConceptSet = Bahmni.ConceptSet || {};
Bahmni.ConceptSet.FormConditions = Bahmni.ConceptSet.FormConditions || {};

angular.module('bahmni.common.conceptSet', ['bahmni.common.uiHelper', 'ui.select2', 'pasvaz.bindonce', 'ngSanitize', 'ngTagsInput']);

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

angular.module('bahmni.common.patientSearch', ['bahmni.common.patient', 'infinite-scroll']);


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

'use strict';

angular.module('bahmni.common.patientSearch')
.directive('resize', ['$window', function ($window) {
    var controller = function ($scope) {
        $scope.storeWindowDimensions = function () {
            var windowWidth = window.innerWidth;
            var windowHeight = window.innerHeight;
            var tileWidth = Bahmni.Common.PatientSearch.Constants.patientTileWidth;
            var tileHeight = Bahmni.Common.PatientSearch.Constants.patientTileHeight;
            $scope.tilesToFit = Math.ceil(windowWidth * windowHeight / (tileWidth * tileHeight));
            $scope.tilesToLoad = Math.ceil($scope.tilesToFit * Bahmni.Common.PatientSearch.Constants.tileLoadRatio);
        };

        var updateVisibleResults = function () {
            $scope.visibleResults = $scope.searchResults.slice(0, $scope.tilesToLoad);
        };

        $scope.loadMore = function () {
            var last = $scope.visibleResults.length;
            var more = ($scope.searchResults.length - last);
            var toShow = (more > $scope.tilesToLoad) ? $scope.tilesToLoad : more;
            if (toShow > 0) {
                for (var i = 1; i <= toShow; i++) {
                    $scope.visibleResults.push($scope.searchResults[last + i - 1]);
                }
            }
        };

        $scope.$watch('searchResults', updateVisibleResults);
        $scope.$watch('tilesToFit', updateVisibleResults);
    };

    var link = function ($scope) {
        $scope.storeWindowDimensions();
        angular.element($window).bind('resize', function () {
            $scope.$apply(function () {
                $scope.storeWindowDimensions();
            });
        });
    };

    return {
        restrict: 'E',
        link: link,
        controller: controller,
        transclude: true,
        scope: {
            searchResults: "=",
            visibleResults: "="
        },
        template: '<div ng-transclude infinite-scroll="loadMore()">' +
                  '</div>'
    };
}]);

'use strict';

angular.module('bahmni.common.patientSearch')
    .directive('scheduler', ['$interval', function ($interval) {
        var link = function ($scope) {
            var promise;

            var cancelSchedule = function () {
                if (promise) {
                    $interval.cancel(promise);
                    promise = null;
                }
            };

            var startSchedule = function () {
                if (!promise) {
                    promise = $interval($scope.triggerFunction, $scope.refreshTime * 1000);
                }
            };

            $scope.$watch(function () { return $scope.watchOn; }, function (value) {
                if ($scope.refreshTime > 0) {
                    if (value) {
                        cancelSchedule();
                    } else {
                        startSchedule();
                    }
                }
            });

            $scope.triggerFunction();

            $scope.$on('$destroy', function () {
                cancelSchedule();
            });
        };

        return {
            restrict: 'A',
            link: link,
            scope: {
                refreshTime: "=",
                watchOn: "=",
                triggerFunction: "&"
            }
        };
    }]);

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

angular.module('bahmni.common.uiHelper', ['ngClipboard']);

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
    .directive('providerDirective', function () {
        var template = '<span>' +
                '<span ng-if=":: creatorName && providerName && (creatorName != providerName)">{{::creatorName}} {{"ON_BEHALF_OF_TRANSLATION_KEY"|translate}} </span>' +
                '{{::providerName}} <span ng-if=":: providerDate"> {{::providerDate | bahmniTime}} </span>' +
            '</span>';

        return {
            restrict: 'EA',
            replace: true,
            scope: {
                creatorName: "@",
                providerName: "@",
                providerDate: "=?"
            },
            template: template
        };
    });

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
Bahmni.Common.DisplayControl.Dashboard = Bahmni.Common.DisplayControl.Dashboard || {};

angular.module('bahmni.common.displaycontrol.dashboard', []);

'use strict';

angular.module('bahmni.common.displaycontrol.dashboard')
    .directive('dashboard', ['appService', '$stateParams', '$bahmniCookieStore', 'configurations', 'encounterService', 'spinner', 'auditLogService', 'messagingService', '$state', '$translate', 'formPrintService', function (appService, $stateParams, $bahmniCookieStore, configurations, encounterService, spinner, auditLogService, messagingService, $state, $translate, formPrintService) {
        var controller = function ($scope, $filter, $rootScope) {
            var init = function () {
                $scope.dashboard = Bahmni.Common.DisplayControl.Dashboard.create($scope.config || {}, $filter);
            };
            $scope.tabConfigName = $stateParams.tabConfigName || 'default';

            var findFormV2ReactConfig = function (sections) {
                if (!sections || sections.length === 0) {
                    return null;
                }
                var section = Object.keys(sections).map(function (key) {
                    return sections[key];
                }).find(function (section) {
                    return section.type === Bahmni.Common.Constants.formsV2ReactDisplayControlType;
                });
                return (section && section.dashboardConfig !== undefined && section.dashboardConfig !== null) ? section.dashboardConfig : null;
            };

            if ($scope.patient !== undefined) {
                var dashboardConfig = findFormV2ReactConfig($scope.config.sections);
                $scope.formData = {
                    patientUuid: $scope.patient.uuid,
                    patient: $scope.patient,
                    encounterUuid: $scope.activeEncounterUuid,
                    showEditForActiveEncounter: dashboardConfig && dashboardConfig.showEditForActiveEncounter || false,
                    numberOfVisits: dashboardConfig && dashboardConfig.maximumNoOfVisits || undefined,
                    hasNoHierarchy: $scope.hasNoHierarchy,
                    currentUser: $rootScope.currentUser,
                    consultationMapper: new Bahmni.ConsultationMapper(configurations.dosageFrequencyConfig(), configurations.dosageInstructionConfig(),
                    configurations.consultationNoteConcept(), configurations.labOrderNotesConcept()),
                    editErrorMessage: $translate.instant('CLINICAL_FORM_ERRORS_MESSAGE_KEY'),
                    showPrintOption: (dashboardConfig && dashboardConfig.printing) ? true : false
                };
                $scope.formApi = {
                    handleEditSave: function (encounter) {
                        spinner.forPromise(encounterService.create(encounter).then(function (savedResponse) {
                            var messageParams = {
                                encounterUuid: savedResponse.data.encounterUuid,
                                encounterType: savedResponse.data.encounterType
                            };
                            auditLogService.log($scope.patient.uuid, "EDIT_ENCOUNTER", messageParams, "MODULE_LABEL_CLINICAL_KEY");
                            $rootScope.hasVisitedConsultation = false;
                            $state.go($state.current, {}, {reload: true});
                            messagingService.showMessage('info', "{{'CLINICAL_SAVE_SUCCESS_MESSAGE_KEY' | translate}}");
                        }));
                    },
                    printForm: function (observations) {
                        var printData = {};
                        var mappedObservations = new Bahmni.Common.Obs.ObservationMapper().map(observations, {}, null, $translate);
                        printData.bahmniObservations = new Bahmni.Common.DisplayControl.Observation.GroupingFunctions().groupByEncounterDate(mappedObservations);
                        observations.forEach(function (obs) {
                            if (obs.formFieldPath) {
                                printData.title = obs.formFieldPath.split(".")[0];
                                return;
                            } else if (obs.groupMembers.length > 0 && obs.groupMembers[0].formFieldPath) {
                                printData.title = obs.groupMembers[0].formFieldPath.split(".")[0];
                                return;
                            }
                        });
                        printData.patient = $scope.patient;
                        printData.printConfig = dashboardConfig ? dashboardConfig.printing : {};
                        printData.printConfig.header = printData.title;
                        formPrintService.printForm(printData, observations[0].encounterUuid, $rootScope.facilityLocation);
                    }
                };
                $scope.allergyData = {
                    patient: $scope.patient,
                    provider: $rootScope.currentProvider,
                    activeVisit: $scope.visitHistory ? $scope.visitHistory.activeVisit : null,
                    allergyControlConceptIdMap: appService.getAppDescriptor().getConfigValue("allergyControlConceptIdMap")
                };
                $scope.appService = appService;
                $bahmniCookieStore.get(Bahmni.Common.Constants.locationCookieName);
            }

            var checkDisplayType = function (sections, typeToCheck, index) {
                return sections[index] && sections[index]['displayType'] && sections[index]['displayType'] === typeToCheck;
            };

            var isDisplayTypeWrong = function (sections) {
                var allDisplayTypes = ['Full-Page', 'LAYOUT_75_25', 'LAYOUT_25_75', 'Half-Page'];
                return (allDisplayTypes.indexOf(sections[0]['displayType']) <= -1);
            };

            $scope.isFullPageSection = function (sections) {
                return checkDisplayType(sections, 'Full-Page', 0);
            };
            $scope.hasThreeFourthPageSection = function (sections, index) {
                return checkDisplayType(sections, 'LAYOUT_75_25', index);
            };
            $scope.isOneFourthPageSection = function (sections) {
                return checkDisplayType(sections, 'LAYOUT_25_75', 0);
            };
            $scope.isHalfPageSection = function (sections) {
                return (sections[0] && (checkDisplayType(sections, 'Half-Page', 0) || isDisplayTypeWrong(sections) || !(sections[0]['displayType'])));
            };

            $scope.containsThreeFourthPageSection = function (sections) {
                var hasThreeFourthSection = this.hasThreeFourthPageSection(sections, 0) || this.hasThreeFourthPageSection(sections, 1);
                if (sections.length == 1) {
                    return this.hasThreeFourthPageSection(sections, 0);
                }

                return hasThreeFourthSection;
            };

            $scope.filterOdd = function (index) {
                return function () {
                    return index++ % 2 === 0;
                };
            };

            $scope.filterEven = function (index) {
                return function () {
                    return index++ % 2 === 1;
                };
            };
            var unbindWatch = $scope.$watch('config', init);
            $scope.$on("$stateChangeStart", unbindWatch);
        };

        return {
            restrict: 'E',
            controller: controller,
            templateUrl: "../common/displaycontrols/dashboard/views/dashboard.html",
            scope: {
                config: "=",
                patient: "=",
                diseaseTemplates: "=",
                sectionGroups: "=",
                visitHistory: "=",
                activeVisitUuid: "=",
                visitSummary: "=",
                enrollment: "=",
                activeEncounterUuid: "="
            }
        };
    }]);

'use strict';

angular.module('bahmni.common.displaycontrol.dashboard')

    .directive('dashboardSection', function () {
        var controller = function ($scope) {
            $scope.$on("no-data-present-event", function () {
                $scope.section.isDataAvailable = !$scope.section.hideEmptyDisplayControl;
            });
        };

        return {
            restrict: 'E',
            controller: controller,
            templateUrl: "../common/displaycontrols/dashboard/views/dashboardSection.html"
        };
    });

'use strict';

Bahmni.Common.DisplayControl.Dashboard = function (config, $filter) {
    if (config.startDate || config.endDate) {
        _.each(config.sections, function (section) {
            section.startDate = config.startDate;
            section.endDate = config.endDate;
        });
    }

    var _sections = _.sortBy(_.map(config.sections, function (section) { return Bahmni.Common.DisplayControl.Dashboard.Section.create(section, $filter); }), function (section) {
        return section.displayOrder;
    });

    this.getSectionByType = function (name) {
        return _.find(_sections, function (section) {
            return section.type === name;
        }) || {};
    };

    this.getSections = function (diseaseTemplates) {
        var sections = _.filter(_sections, function (section) {
            return section.type !== "diseaseTemplate" || _.find(diseaseTemplates, function (diseaseTemplate) {
                return diseaseTemplate.name === section.templateName && diseaseTemplate.obsTemplates.length > 0;
            });
        });
        return this.groupSectionsByType(sections);
    };

    this.groupSectionsByType = function (sections) {
        var sectionGroups = [[]];
        for (var sectionId in sections) {
            var section = sections[sectionId];
            var nextSection = (sectionId < sections.length) ? sections[++sectionId] : null;
            var lastElement = sectionGroups.length - 1;
            if (this.isFullPageSection(section)) {
                if (_.isEmpty(sectionGroups[lastElement])) {
                    sectionGroups.pop();
                }
                sectionGroups.push([section]);
                sectionGroups.push([]);
            } else {
                sectionGroups = this.groupSectionsIfNotFullPage(section, sectionGroups, lastElement, nextSection);
            }
        }
        return sectionGroups;
    };

    this.isFullPageSection = function (section) {
        return this.checkDisplayType(section, "Full-Page");
    };
    this.isThreeFourthPageSection = function (section) {
        return this.checkDisplayType(section, "LAYOUT_75_25");
    };
    this.isOneFourthPageSection = function (section) {
        return this.checkDisplayType(section, "LAYOUT_25_75");
    };
    this.isHalfPageSection = function (section) {
        return this.checkDisplayType(section, "Half-Page") || this.isDisplayTypeWrong(section) || !(section['displayType']);
    };
    this.isDisplayTypeWrong = function (section) {
        var allDisplayTypes = ['Full-Page', 'LAYOUT_75_25', 'LAYOUT_25_75', 'Half-Page'];
        return (allDisplayTypes.indexOf(section['displayType']) <= -1);
    };
    this.checkDisplayType = function (section, typeToCheck) {
        return section && section.displayType && section.displayType === typeToCheck;
    };

    this.groupSectionsIfNotFullPage = function (section, sectionGroups, lastElement, nextSection) {
        var lastSection = sectionGroups[lastElement];
        var lastSectionIndex = _.isEmpty(lastSection) ? 0 : lastSection.length - 1;

        if (this.isThreeFourthPageSection(section)) {
            sectionGroups = this.groupThreeFourthPageSection(lastSection, lastElement, lastSectionIndex, section, sectionGroups);
        } else if (this.isOneFourthPageSection(section)) {
            sectionGroups = this.groupOneFourthPageSection(lastSection, lastElement, lastSectionIndex, section, sectionGroups, nextSection);
        } else {
            sectionGroups = this.groupHalfPageSection(lastSection, lastElement, lastSectionIndex, section, sectionGroups);
        }
        return sectionGroups;
    };

    this.groupThreeFourthPageSection = function (lastSection, lastElement, lastSectionIndex, section, sectionGroups) {
        var lastSectionLength = lastSection.length;
        var isLastSectionOneFourth = lastSectionLength == 1 && this.isOneFourthPageSection(lastSection[lastSectionIndex]);

        if (_.isEmpty(lastSection) || isLastSectionOneFourth) {
            sectionGroups[lastElement].push(section);
        } else {
            sectionGroups.push([section]);
        }
        return sectionGroups;
    };

    this.groupOneFourthPageSection = function (lastSection, lastElement, lastSectionIndex, section, sectionGroups, nextSection) {
        if (this.addOneFourthElementToLastSection(lastSection, lastElement, lastSectionIndex, nextSection)) {
            sectionGroups[lastElement].push(section);
        } else {
            sectionGroups.push([section]);
        }
        return sectionGroups;
    };

    this.addOneFourthElementToLastSection = function (lastSection, lastElement, lastSectionIndex, nextSection) {
        var lastSectionLength = lastSection.length;
        var isNextSectionThreeFourth = nextSection ? this.isThreeFourthPageSection(nextSection) : false;
        var isLastSectionNotThreeFourth = !this.isThreeFourthPageSection(lastSection[lastSectionIndex]) && !this.isThreeFourthPageSection(lastSection[0]);
        return lastSection.length <= 1 && (this.isThreeFourthPageSection(lastSection[0]) || !isNextSectionThreeFourth) || lastSectionLength >= 2 && (isLastSectionNotThreeFourth && !isNextSectionThreeFourth);
    };

    this.groupHalfPageSection = function (lastSection, lastElement, lastSectionIndex, section, sectionGroups) {
        var lastSectionLength = lastSection.length;
        var isLastSectionNotThreeFourth = !this.isThreeFourthPageSection(lastSection[lastSectionIndex]) && !this.isThreeFourthPageSection(lastSection[0]);
        if (_.isEmpty(lastSection) || lastSectionLength > 2 || isLastSectionNotThreeFourth) {
            sectionGroups[lastElement].push(section);
        } else {
            sectionGroups.push([section]);
        }
        return sectionGroups;
    };
};

Bahmni.Common.DisplayControl.Dashboard.create = function (config, $filter) {
    return new Bahmni.Common.DisplayControl.Dashboard(config, $filter);
};

'use strict';

(function () {
    var OBSERVATION_SECTION_URL = "../common/displaycontrols/dashboard/views/sections/observationSection.html";
    var COMMON_DISPLAY_CONTROL_URL = "../common/displaycontrols/dashboard/views/sections/SECTION_NAME.html";
    var CLINICAL_DISPLAY_CONTROL_URL = "../clinical/dashboard/views/dashboardSections/SECTION_NAME.html";
    var DISPLAY_CONTROL_REACT_URL = "../common/displaycontrols/dashboard/views/sections/nextUISection.html";
    var commonDisplayControlNames = [
        "admissionDetails",
        "bacteriologyResultsControl",
        "chronicTreatmentChart",
        "custom",
        "diagnosis",
        "disposition",
        "drugOrderDetails",
        "forms",
        "formsV2",
        "observationGraph",
        "obsToObsFlowSheet",
        "pacsOrders",
        "patientInformation",
        "conditionsList"
    ];
    var reactDisplayControls = [
        "allergies",
        "formsV2React"
    ];

    var getViewUrl = function (section) {
        if (reactDisplayControls.includes(section.type)) {
            return DISPLAY_CONTROL_REACT_URL;
        }
        if (section.isObservation) {
            return OBSERVATION_SECTION_URL;
        }
        var isCommonDisplayControl = _.includes(commonDisplayControlNames, section.type);
        if (isCommonDisplayControl) {
            return COMMON_DISPLAY_CONTROL_URL.replace('SECTION_NAME', section.type);
        }
        return CLINICAL_DISPLAY_CONTROL_URL.replace('SECTION_NAME', section.type);
    };

    var getId = function (section, $filter) {
        if (section.type !== "custom") {
            var key = section.translationKey || section.title;
            return !_.isUndefined($filter) && key ? $filter('titleTranslate')(key).toValidId() : key;
        }
    };

    Bahmni.Common.DisplayControl.Dashboard.Section = function (section, $filter) {
        angular.extend(this, section);
        this.displayOrder = section.displayOrder;
        this.data = section.data || {};
        this.isObservation = !!section.isObservation;
        this.patientAttributes = section.patientAttributes || [];
        this.viewName = getViewUrl(this);
        this.hideEmptyDisplayControl = section.hideEmptyDisplayControl != undefined ? section.hideEmptyDisplayControl : false;
        this.isDataAvailable = true;

        this.id = getId(this, $filter);
    };

    Bahmni.Common.DisplayControl.Dashboard.Section.create = function (section, $filter) {
        return new Bahmni.Common.DisplayControl.Dashboard.Section(section, $filter);
    };
})();

'use strict';

angular.module('bahmni.common.displaycontrol.dashboard')
    .controller('PatientDashboardDiagnosisController', ['$scope', 'ngDialog',
        function ($scope, ngDialog) {
            $scope.section = $scope.dashboard.getSectionByType("diagnosis") || {};

            $scope.openSummaryDialog = function () {
                ngDialog.open({
                    template: '../common/displaycontrols/dashboard/views/sections/diagnosisSummary.html',
                    className: "ngdialog-theme-default ng-dialog-all-details-page",
                    scope: $scope
                });
            };
            var cleanUpListener = $scope.$on('ngDialog.closing', function () {
                $("body").removeClass('ngdialog-open');
            });

            $scope.$on("$destroy", cleanUpListener);
        }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.Observation = Bahmni.Common.DisplayControl.Observation || {};

angular.module('bahmni.common.displaycontrol.observation', ['bahmni.common.conceptSet', 'pascalprecht.translate']);

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
angular.module('bahmni.common.displaycontrol.observation')
    .controller('AllObservationDetailsController', ['$scope',
        function ($scope) {
            $scope.patient = $scope.ngDialogData.patient;
            $scope.section = $scope.ngDialogData.section;
            $scope.config = $scope.ngDialogData.section ? $scope.ngDialogData.section.expandedViewConfig : {};
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
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.Disposition = Bahmni.Common.DisplayControl.Disposition || {};

angular.module('bahmni.common.displaycontrol.disposition', []);

"use strict";

angular.module('bahmni.common.displaycontrol.disposition')
    .directive('disposition', ['dispositionService', 'spinner',
        function (dispositionService, spinner) {
            var controller = function ($scope) {
                var fetchDispositionByPatient = function (patientUuid, numOfVisits) {
                    return dispositionService.getDispositionByPatient(patientUuid, numOfVisits)
                        .then(handleDispositionResponse);
                };

                var handleDispositionResponse = function (response) {
                    $scope.dispositions = response.data;

                    if (_.isEmpty($scope.dispositions)) {
                        $scope.noDispositionsMessage = Bahmni.Common.Constants.messageForNoDisposition;
                        $scope.$emit("no-data-present-event");
                    }
                };

                var fetchDispositionsByVisit = function (visitUuid) {
                    return dispositionService.getDispositionByVisit(visitUuid).then(handleDispositionResponse);
                };

                $scope.getNotes = function (disposition) {
                    if (disposition.additionalObs[0] && disposition.additionalObs[0].value) {
                        return disposition.additionalObs[0].value;
                    }
                    return "";
                };
                $scope.getDisplayName = function (disposition) {
                    if (disposition.preferredName != null) {
                        return disposition.preferredName;
                    } else {
                        return disposition.conceptName;
                    }
                };

                $scope.showDetailsButton = function (disposition) {
                    if ($scope.getNotes(disposition)) {
                        return false;
                    }
                    return $scope.params.showDetailsButton;
                };

                $scope.toggle = function (element) {
                    if ($scope.showDetailsButton(element)) {
                        element.show = !element.show;
                    } else {
                        element.show = true;
                    }
                    return false;
                };

                if ($scope.visitUuid) {
                    $scope.fetchDispositionPromise = fetchDispositionsByVisit($scope.visitUuid);
                } else if ($scope.params.numberOfVisits && $scope.patientUuid) {
                    $scope.fetchDispositionPromise = fetchDispositionByPatient($scope.patientUuid, $scope.params.numberOfVisits);
                }
            };

            var link = function (scope, element) {
                spinner.forPromise(scope.fetchDispositionPromise, element);
            };

            return {
                restrict: 'E',
                controller: controller,
                link: link,
                templateUrl: "../common/displaycontrols/disposition/views/disposition.html",
                scope: {
                    params: "=",
                    patientUuid: "=?",
                    visitUuid: "=?"
                }
            };
        }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.AdmissionDetails = Bahmni.Common.DisplayControl.AdmissionDetails || {};

angular.module('bahmni.common.displaycontrol.admissiondetails', []);

"use strict";

angular.module('bahmni.common.displaycontrol.admissiondetails')
    .directive('admissionDetails', ['bedService', function (bedService) {
        var controller = function ($scope) {
            $scope.showDetailsButton = function (encounter) {
                return $scope.params && $scope.params.showDetailsButton && !encounter.notes;
            };
            $scope.toggle = function (element) {
                element.show = !element.show;
            };
            init($scope);
        };
        var isReady = function ($scope) {
            return !_.isUndefined($scope.patientUuid) && !_.isUndefined($scope.visitSummary);
        };
        var onReady = function ($scope) {
            var visitUuid = _.get($scope.visitSummary, 'uuid');
            bedService.getAssignedBedForPatient($scope.patientUuid, visitUuid).then(function (bedDetails) {
                $scope.bedDetails = bedDetails;
            });
        };
        var init = function ($scope) {
            var stopWatching = $scope.$watchGroup(['patientUuid', 'visitSummary'], function () {
                if (isReady($scope)) {
                    stopWatching();
                    onReady($scope);
                    calculateDaysAdmitted($scope);
                }
            });

            $scope.isDataPresent = function () {
                if (!$scope.visitSummary || (!$scope.visitSummary.admissionDetails && !$scope.visitSummary.dischargeDetails)) {
                    return $scope.$emit("no-data-present-event") && false;
                }
                return true;
            };
        };
        var calculateDaysAdmitted = function ($scope) {
            if ($scope.visitSummary) {
                if ($scope.visitSummary.admissionDetails && $scope.visitSummary.dischargeDetails) {
                    var admissionDate = new Date($scope.visitSummary.admissionDetails.date);
                    var dischargeDate = new Date($scope.visitSummary.dischargeDetails.date);
                    var timeDifference = dischargeDate - admissionDate;
                    var daysAdmitted = Math.ceil(timeDifference / (1000 * 60 * 60 * 24));
                    $scope.visitSummary.daysAdmitted = daysAdmitted;
                    $scope.visitSummary.showDaysAdmitted = true;
                } else {
                    $scope.visitSummary.showDaysAdmitted = false;
                }
            }
        };
        return {
            restrict: 'E',
            controller: controller,
            templateUrl: function (element, attrs) {
                if (attrs.templateUrl) {
                    return attrs.templateUrl;
                } else {
                    return "../common/displaycontrols/admissiondetails/views/admissionDetails.html";
                }
            },
            scope: {
                params: "=",
                patientUuid: "=",
                visitSummary: "="
            }
        };
    }]);

'use strict';
var Bahmni = Bahmni || {};
Bahmni.Common = Bahmni.Common || {};
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.PatientProfile = Bahmni.Common.DisplayControl.PatientProfile || {};

angular.module('bahmni.common.displaycontrol.patientprofile', []);

'use strict';

angular.module('bahmni.common.displaycontrol.patientprofile')
    .filter('titleCase', function () {
        return function (input) {
            input = input || '';
            return input.replace(/\w\S*/g, function (txt) {
                return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();
            });
        };
    });

'use strict';

angular.module('bahmni.common.displaycontrol.patientprofile')
.filter('booleanFilter', function () {
    return function (value) {
        if (value === true) {
            return "Yes";
        } else if (value === false) {
            return "No";
        }
        return value;
    };
});

'use strict';

(function () {
    var getAddress = function ($scope) {
        var patient = $scope.patient;
        var address = [];
        if ($scope.config.addressFields != undefined && $scope.config.addressFields.length != 0) {
            $scope.config.addressFields.forEach(function (addressField) {
                if (patient.address[addressField]) {
                    address.push(patient.address[addressField]);
                }
            });
        } else if (!_.includes($scope.config, "cityVillage")) {
            address.push(patient.address["cityVillage"]);
        }
        return address.join(", ");
    };
    var getPatientAttributeTypes = function ($scope) {
        var patient = $scope.patient;
        if ($scope.config.hasOwnProperty("ageLimit") && patient.age >= $scope.config.ageLimit) {
            patient.ageText = patient.age.toString() + " <span> years </span>";
        }
        var patientAttributeTypes = [patient.genderText, patient.ageText];
        if (patient.bloodGroupText) {
            patientAttributeTypes.push(patient.bloodGroupText);
        }
        return patientAttributeTypes.join(", ");
    };
    var isAdmitted = function (admissionStatus) {
        return _.get(admissionStatus, 'value') === "Admitted";
    };
    angular.module('bahmni.common.displaycontrol.patientprofile')
        .directive('patientProfile', ['patientService', 'spinner', '$sce', '$rootScope', '$stateParams', '$window', '$translate',
            'configurations', '$q', 'visitService', 'appService',
            function (patientService, spinner, $sce, $rootScope, $stateParams, $window, $translate, configurations, $q, visitService, appService) {
                var controller = function ($scope) {
                    $scope.isProviderRelationship = function (relationship) {
                        return _.includes($rootScope.relationshipTypeMap.provider, relationship.relationshipType.aIsToB);
                    };
                    $scope.openPatientDashboard = function (patientUuid) {
                        var configName = $stateParams.configName || Bahmni.Common.Constants.defaultExtensionName;
                        $window.open("../clinical/#/" + configName + "/patient/" + patientUuid + "/dashboard");
                    };
                    $scope.iconAttributeConfig = appService.getAppDescriptor().getConfigValue('iconAttribute') || {};
                    var assignPatientDetails = function () {
                        var patientMapper = new Bahmni.PatientMapper(configurations.patientConfig(), $rootScope, $translate);
                        return patientService.getPatient($scope.patientUuid).then(function (response) {
                            var openMrsPatient = response.data;
                            $scope.patient = patientMapper.map(openMrsPatient);
                        });
                    };
                    var assignRelationshipDetails = function () {
                        return patientService.getRelationships($scope.patientUuid).then(function (response) {
                            $scope.relationships = response.data.results;
                        });
                    };
                    var assignAdmissionDetails = function () {
                        var REP = "custom:(attributes:(value,attributeType:(display,name)))";
                        var ADMISSION_STATUS_ATTRIBUTE = "Admission Status";
                        return visitService.getVisit($scope.visitUuid, REP).then(function (response) {
                            var attributes = response.data.attributes;
                            var admissionStatus = _.find(attributes, {attributeType: {name: ADMISSION_STATUS_ATTRIBUTE}});
                            $scope.hasBeenAdmitted = isAdmitted(admissionStatus);
                        });
                    };
                    var setHasBeenAdmittedOnVisitUuidChange = function () {
                        $scope.$watch('visitUuid', function (visitUuid) {
                            if (!_.isEmpty(visitUuid)) {
                                assignAdmissionDetails();
                            }
                        });
                    };
                    var setDirectiveAsReady = function () {
                        $scope.isDirectiveReady = true;
                    };
                    var onDirectiveReady = function () {
                        $scope.addressLine = getAddress($scope);
                        $scope.patientAttributeTypes = $sce.trustAsHtml(getPatientAttributeTypes($scope));
                        $scope.showBirthDate = $scope.config.showDOB !== false;
                        $scope.showBirthDate = $scope.showBirthDate && !!$scope.patient.birthdate;
                    };
                    var initPromise = $q.all([assignPatientDetails(), assignRelationshipDetails()]);
                    initPromise.then(onDirectiveReady);
                    initPromise.then(setHasBeenAdmittedOnVisitUuidChange);
                    initPromise.then(setDirectiveAsReady);
                    $scope.initialization = initPromise;
                };

                var link = function ($scope, element) {
                    spinner.forPromise($scope.initialization, element);
                };

                return {
                    restrict: 'E',
                    controller: controller,
                    link: link,
                    scope: {
                        patientUuid: "@",
                        visitUuid: "@",
                        config: "="
                    },
                    templateUrl: "../common/displaycontrols/patientprofile/views/patientProfile.html"
                };
            }]);
})();

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
Bahmni.Common.DisplayControl = Bahmni.Common.DisplayControl || {};
Bahmni.Common.DisplayControl.navigationLinks = Bahmni.Common.DisplayControl.navigationLinks || {};

angular.module('bahmni.common.displaycontrol.navigationlinks', ['ui.router', 'ui.router.util']);

"use strict";

angular.module('bahmni.common.displaycontrol.navigationlinks')
    .directive('navigationLinks', ['$state', 'appService', function ($state, appService) {
        var controller = function ($scope) {
            if ((!$scope.params.showLinks && !$scope.params.customLinks) ||
                ($scope.params.showLinks && $scope.params.customLinks &&
                $scope.params.showLinks.length == 0 && $scope.params.customLinks.length == 0)) {
                $scope.noNavigationLinksMessage = Bahmni.Common.Constants.noNavigationLinksMessage;
            }

            $scope.standardLinks = [
                {
                    "name": "home",
                    "translationKey": "HOME_DASHBOARD_KEY",
                    "url": "../home/#/dashboard",
                    "title": "Home"
                },
                {
                    "name": "visit",
                    "translationKey": "PATIENT_VISIT_PAGE_KEY",
                    "url": "../clinical/#/default/patient/{{patientUuid}}/dashboard/visit/{{visitUuid}}/?encounterUuid=active",
                    "title": "Visit"
                },
                {
                    "name": "inpatient",
                    "translationKey": "PATIENT_ADT_PAGE_KEY",
                    "url": "../adt/#/patient/{{patientUuid}}/visit/{{visitUuid}}/",
                    "title": "In Patient"
                },
                {
                    "name": "enrolment",
                    "translationKey": "PROGRAM_MANAGEMENT_PAGE_KEY",
                    "url": "../clinical/#/programs/patient/{{patientUuid}}/consultationContext",
                    "title": "Enrolment"
                },
                {
                    "name": "visitAttribute",
                    "translationKey": "PATIENT_VISIT_ATTRIBUTES_PAGE_KEY",
                    "url": "../registration/#/patient/{{patientUuid}}/visit",
                    "title": "Patient Visit Attributes"
                },
                {
                    "name": "registration",
                    "translationKey": "PATIENT_REGISTRATION_PAGE_KEY",
                    "url": "../registration/#/patient/{{patientUuid}}",
                    "title": "Registration"
                },
                {
                    "name": "labEntry",
                    "translationKey": "LAB_ENTRY_KEY",
                    "url": "/lab/patient/{{patientUuid}}",
                    "title": "Lab Entry"
                },
                {
                    "name": "ndhmHIU",
                    "translationKey": "MODULE_LABEL_NDHMHIU_KEY",
                    "url": "/hiuser",
                    "title": "HIU"
                }
            ];

            var filterLinks = function (links, showLinks) {
                var linksSpecifiedInShowLinks = function () {
                    return _.filter(links, function (link) {
                        return showLinks.indexOf(link.name) > -1;
                    });
                };

                return showLinks && linksSpecifiedInShowLinks();
            };

            $scope.getLinks = function () {
                return _.union(
                    filterLinks($scope.standardLinks, $scope.params.showLinks),
                    $scope.params.customLinks
                );
            };

            $scope.getUrl = function (link) {
                var url = getFormattedURL(link);
                window.open(url, link.title);
            };

            $scope.showUrl = function (link) {
                var params = getParamsToBeReplaced(link.url), isPropertyNotPresentInLinkParams;

                for (var i in params) {
                    var property = params[i];
                    isPropertyNotPresentInLinkParams = _.isEmpty($scope.linkParams[property]);
                    if (isPropertyNotPresentInLinkParams) {
                        return false;
                    }
                }
                return true;
            };

            var getFormattedURL = function (link) {
                return appService.getAppDescriptor().formatUrl(link.url, $scope.linkParams);
            };

            var getParamsToBeReplaced = function (link) {
                var pattern = /{{([^}]*)}}/g,
                    matches = link.match(pattern), params = [];
                if (matches) {
                    matches.forEach(function (el) {
                        var key = el.replace("{{", '').replace("}}", '');
                        params.push(key);
                    });
                }
                return params;
            };
        };

        return {
            restrict: 'E',
            controller: controller,
            templateUrl: "../common/displaycontrols/navigationlinks/views/navigationLinks.html",
            scope: {
                params: "=",
                linkParams: "="
            }
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

angular.module('bahmni.common.services', []);

'use strict';

angular.module('ot', ['bahmni.common.patient', 'bahmni.common.patientSearch', 'bahmni.common.uiHelper', 'bahmni.common.conceptSet', 'authentication', 'bahmni.common.appFramework',
    'httpErrorInterceptor', 'bahmni.common.domain', 'bahmni.ot', 'bahmni.common.config', 'ui.router', 'bahmni.common.util', 'bahmni.common.routeErrorHandler', 'bahmni.common.i18n',
    'bahmni.common.displaycontrol.dashboard', 'bahmni.common.displaycontrol.observation', 'bahmni.common.displaycontrol.disposition', 'bahmni.common.displaycontrol.admissiondetails', 'bahmni.common.displaycontrol.custom',
    'bahmni.common.obs', 'bahmni.common.displaycontrol.patientprofile', 'bahmni.common.displaycontrol.diagnosis', 'RecursionHelper', 'ngSanitize', 'bahmni.common.uiHelper', 'bahmni.common.uicontrols.programmanagment', 'bahmni.common.displaycontrol.navigationlinks', 'pascalprecht.translate',
    'bahmni.common.displaycontrol.dashboard', 'ngCookies', 'ngDialog', 'angularFileUpload', 'monospaced.elastic', 'dndLists', 'bahmni.common.services']);
angular.module('ot').config(['$stateProvider', '$httpProvider', '$urlRouterProvider', '$bahmniTranslateProvider', '$compileProvider',
    function ($stateProvider, $httpProvider, $urlRouterProvider, $bahmniTranslateProvider, $compileProvider) {
        $urlRouterProvider.otherwise('/home');

        var homeBackLink = {type: "link", name: "Home", value: "../home/", accessKey: "h", icon: "fa-home"};
        var otSchedulingLink = {type: "state", name: "OT_SCHEDULING_KEY", value: "otScheduling", accessKey: "b"};
        var queuesLink = {type: "state", name: "OT_SURGICAL_QUEUES_KEY", value: "home", accessKey: "b"};
        var navigationLinks = [queuesLink, otSchedulingLink];

        $compileProvider.debugInfoEnabled(false);


        $stateProvider
            .state('home', {
                url: '/home',
                data: {
                    homeBackLink: homeBackLink,
                    navigationLinks: navigationLinks
                },
                views: {
                    'additional-header': {
                        templateUrl: 'views/header.html'
                    },
                    'content': {
                        templateUrl: '../common/patient-search/views/patientsList.html',
                        controller: 'PatientsListController'
                    }
                },
                resolve: {
                    initialization: 'initialization'
                }
            })
            .state('otScheduling', {
                url: '/otScheduling',
                data: {
                    homeBackLink: homeBackLink,
                    navigationLinks: navigationLinks
                },
                params: {
                    viewDate: null
                },
                views: {
                    'content': {
                        templateUrl: 'views/home.html',
                        controller: 'calendarViewController'
                    },
                    'additional-header': {
                        templateUrl: 'views/header.html'
                    }
                },
                resolve: {
                    initialization: "initialization"
                }
            })
            .state('newSurgicalAppointment', {
                url: '/surgicalblock/new',
                data: {
                    homeBackLink: homeBackLink,
                    navigationLinks: navigationLinks
                },
                params: {
                    dashboardCachebuster: null,
                    context: null
                },
                views: {
                    'content': {
                        templateUrl: 'views/surgicalBlock.html',
                        controller: 'surgicalBlockController'
                    },
                    'additional-header': {
                        templateUrl: 'views/header.html'
                    }
                },
                resolve: {
                    initialization: "initialization"
                }
            })
            .state('editSurgicalAppointment', {
                url: '/surgicalblock/:surgicalBlockUuid/edit',
                data: {
                    homeBackLink: homeBackLink,
                    navigationLinks: navigationLinks
                },
                params: {
                    dashboardCachebuster: null,
                    surgicalAppointmentId: null
                },
                views: {
                    'content': {
                        templateUrl: 'views/surgicalBlock.html',
                        controller: 'surgicalBlockController'
                    },
                    'additional-header': {
                        templateUrl: 'views/header.html'
                    }
                },
                resolve: {
                    initialization: "initialization"
                }
            });

        $bahmniTranslateProvider.init({app: 'ot', shouldMerge: true});
    }]);

'use strict';

var Bahmni = Bahmni || {};
Bahmni.OT = Bahmni.OT || {};

angular.module('bahmni.ot', ['bahmni.common.conceptSet', 'bahmni.common.logging', 'bahmni.mfe.nextUi']);


'use strict';

var Bahmni = Bahmni || {};
Bahmni.OT = Bahmni.OT || {};

Bahmni.OT.Constants = (function () {
    var RESTWS_V1 = "/openmrs/ws/rest/v1";
    return {
        cancelled: "CANCELLED",
        postponed: "POSTPONED",
        completed: "COMPLETED",
        scheduled: "SCHEDULED",
        addSurgicalBlockUrl: RESTWS_V1 + "/surgicalBlock",
        updateSurgicalAppointmentUrl: RESTWS_V1 + "/surgicalAppointment",
        surgicalAppointmentAttributeTypeUrl: RESTWS_V1 + "/surgicalAppointmentAttributeType",
        defaultCalendarEndTime: '23:59',
        defaultCalendarStartTime: '00:00',
        weekDays: {"Monday": 1, "Tuesday": 2, "Wednesday": 3, "Thursday": 4, "Friday": 5, "Saturday": 6, "Sunday": 7 },
        defaultWeekStartDayName: 'Sunday',
        providerSurgicalAttributeFormat: 'org.openmrs.Provider',
        notesUrl: RESTWS_V1 + '/notes'
    };
})();


'use strict';

angular.module('bahmni.ot').factory('initialization', ['$rootScope', '$q', 'surgicalAppointmentHelper', 'appService', 'surgicalAppointmentService', 'authenticator', 'spinner', 'configurations',
    function ($rootScope, $q, surgicalAppointmentHelper, appService, surgicalAppointmentService, authenticator, spinner, configurations) {
        var loadConfigPromise = function () {
            var configNames = ['quickLogoutComboKey', 'contextCookieExpirationTimeInMinutes'];
            return configurations.load(configNames).then(function () {
                $rootScope.quickLogoutComboKey = configurations.quickLogoutComboKey() || 'Escape';
                $rootScope.cookieExpiryTime = configurations.contextCookieExpirationTimeInMinutes() || 0;
            });
        };
        var initApp = function () {
            return appService.initApp('ot', {'app': true, 'extension': true}).then(function (data) {
                var providerNames = data.getConfigValue("primarySurgeonsForOT");
                return $q.all([surgicalAppointmentService.getSurgeons(), surgicalAppointmentService.getSurgicalAppointmentAttributeTypes(), surgicalAppointmentService.getPrimaryDiagnosisConfigForOT()]).then(function (response) {
                    $rootScope.surgeons = surgicalAppointmentHelper.filterProvidersByName(providerNames, response[0].data.results);
                    $rootScope.attributeTypes = response[1].data.results;
                    $rootScope.showPrimaryDiagnosisForOT = response[2].data;
                    return response;
                });
            });
        };
        return spinner.forPromise(authenticator.authenticateUser().then(initApp).then(loadConfigPromise));
    }
]);

'use strict';

angular.module('bahmni.ot')
    .service('surgicalAppointmentHelper', [function () {
        this.filterProvidersByName = function (providerNames, providers) {
            if (!providerNames || providerNames.length === 0) {
                return _.filter(providers, function (provider) {
                    return provider.person.display != "";
                });
            }
            var validProviderNames = _.filter(providerNames, function (providerName) {
                return _.find(providers, function (provider) {
                    return providerName === provider.person.display;
                });
            });
            return _.map(validProviderNames, function (providerName) {
                return _.find(providers, function (provider) {
                    return providerName === provider.person.display;
                });
            });
        };

        this.getPatientDisplayLabel = function (display) {
            return display.split(' - ')[1] + " ( " + display.split(' - ')[0] + " )";
        };

        this.getAppointmentAttributes = function (surgicalAppointment) {
            return _.reduce(surgicalAppointment.surgicalAppointmentAttributes, function (attributes, attribute) {
                attributes[attribute.surgicalAppointmentAttributeType.name] = attribute.value;
                return attributes;
            }, {});
        };

        this.getEstimatedDurationForAppointment = function (surgicalAppointment) {
            var attributes = this.getAppointmentAttributes(surgicalAppointment);
            return this.getAppointmentDuration(attributes.estTimeHours, attributes.estTimeMinutes, attributes.cleaningTime);
        };

        this.getAppointmentDuration = function (estTimeHours, estTimeMinutes, cleaningTime) {
            return estTimeHours * 60 + (parseInt(estTimeMinutes) || 0) + (parseInt(cleaningTime) || 0);
        };

        this.filterSurgicalAppointmentsByStatus = function (surgicalAppointments, appointmentStatusList) {
            if (_.isEmpty(appointmentStatusList)) {
                return surgicalAppointments;
            }
            return _.filter(surgicalAppointments, function (appointment) {
                return appointmentStatusList.indexOf(appointment.status) >= 0;
            });
        };

        this.filterSurgicalAppointmentsByPatient = function (surgicalAppointments, patient) {
            if (!patient) {
                return surgicalAppointments;
            }
            return _.filter(surgicalAppointments, function (appointment) {
                return appointment.patient.uuid === patient.uuid;
            });
        };

        this.getAttributesFromAttributeNames = function (attributes, attributeNames) {
            const configuredAttributes = {};
            if (attributes) {
                _.each(attributeNames, function (attributeName) {
                    configuredAttributes[attributeName] = attributes[attributeName];
                });
            }
            return configuredAttributes;
        };

        this.getAttributesFromAttributeTypes = function (attributes, attributeTypes) {
            const configuredAttributes = {};
            if (attributes) {
                _.each(attributeTypes, function (attributeType) {
                    configuredAttributes[attributeType.name] = attributes[attributeType.name];
                });
            }
            return configuredAttributes;
        };

        this.getAttributeTypesByRemovingAttributeNames = function (defaultAttributeTypes, attributeNames) {
            if (!attributeNames) {
                return defaultAttributeTypes;
            }
            return _.filter(defaultAttributeTypes, function (attributeType) {
                return !attributeNames.includes(attributeType.name);
            });
        };

        this.getDefaultAttributeTranslations = function () {
            return new Map([['procedure', "OT_SURGICAL_APPOINTMENT_PROCEDURE"],
                ['estTimeHours', "OT_SURGICAL_APPOINTMENT_HOURS"], ['estTimeMinutes', "OT_SURGICAL_APPOINTMENT_MINUTES"],
                ['cleaningTime', "OT_SURGICAL_APPOINTMENT_CLEANING_TIME"], ['otherSurgeon', "OT_SURGICAL_APPOINTMENT_OTHER_SURGEON"],
                ['surgicalAssistant', "OT_SURGICAL_APPOINTMENT_SURGICAL_ASSISTANT"], ['anaesthetist', "OT_SURGICAL_APPOINTMENT_ANAESTHETIST"],
                ['scrubNurse', "OT_SURGICAL_APPOINTMENT_SCRUB_NURSE"], ['circulatingNurse', "OT_SURGICAL_APPOINTMENT_CIRCULATING_NURSE"],
                ['notes', "OT_SURGICAL_APPOINTMENT_NOTES"], ['Status', "OT_SURGICAL_APPOINTMENT_STATUS"], ['Day', "OT_SURGICAL_BLOCK_START_DAY"],
                ['Date', "OT_SURGICAL_BLOCK_START_DATE"], ['Identifier', "PATIENT_ATTRIBUTE_IDENTIFIER"],
                ['Patient Name', "PATIENT_ATTRIBUTE_PATIENT_NAME"], ['Patient Age', "PERSON_ATTRIBUTE_PATIENT_AGE"],
                ['Start Time', "OT_SURGICAL_BLOCK_START_TIME"], ['Est Time', "OT_SURGICAL_APPOINTMENT_ESTIMATED_TIME"],
                ['Actual Time', "OT_SURGICAL_APPOINTMENT_ACTUAL_TIME"], ['OT#', "OT_SURGICAL_BLOCK_LOCATION_NAME"],
                ['Surgeon', "OT_PROVIDER_SURGEON"], ['Status Change Notes', "OT_SURGICAL_APPOINTMENT_STATUS_CHANGE_NOTES"],
                ['Bed Location', "OT_SURGICAL_APPOINTMENT_BED_LOCATION"],
                ['Bed ID', "OT_SURGICAL_APPOINTMENT_BED_ID"]
            ]);
        };

        this.getSurgicalAttributes = function (surgicalAppointment) {
            return _.reduce(surgicalAppointment.surgicalAppointmentAttributes, function (attributes, attribute) {
                attributes[attribute.surgicalAppointmentAttributeType.name] = attribute.value;
                return attributes;
            }, {});
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .service('surgicalBlockHelper', ['surgicalAppointmentHelper', function (surgicalAppointmentHelper) {
        this.getAvailableBlockDuration = function (surgicalBlock) {
            var blockDuration = Bahmni.Common.Util.DateUtil.diffInMinutes(surgicalBlock.startDatetime, surgicalBlock.endDatetime);
            var appointmentsDuration = _.sumBy(_.reject(surgicalBlock.surgicalAppointments, function (appointment) {
                return (appointment.status == "POSTPONED" || appointment.status == "CANCELLED");
            }), function (surgicalAppointment) {
                return surgicalAppointmentHelper.getAppointmentDuration(surgicalAppointment.surgicalAppointmentAttributes.estTimeHours.value, surgicalAppointment.surgicalAppointmentAttributes.estTimeMinutes.value, surgicalAppointment.surgicalAppointmentAttributes.cleaningTime.value);
            });
            return blockDuration - appointmentsDuration;
        };
    }]);

"use strict";

angular.module('bahmni.ot')
    .directive('backLinksCacheBuster', ['$state', '$window', function ($state, $window) {
        var controller = function ($scope, $state, $window) {
            $scope.navigationLinks = $state.current.data.navigationLinks;
            $scope.homeBackLink = $state.current.data.homeBackLink;
            $scope.isCurrentState = function (link) {
                if ($state.current.name === link.value) {
                    return true;
                }
            };
            $scope.linkAction = function (type, value, params) {
                if (type === 'state') {
                    onClickState(value, params);
                } else {
                    $window.location.href = value;
                }
            };

            var onClickState = function (value, params) {
                if (!params) {
                    params = {};
                }
                params['dashboardCachebuster'] = Math.random();
                $state.go(value, params);
            };
        };

        return {
            restrict: 'E',
            controller: controller,
            templateUrl: "views/backLinks.html",
            scope: {
                type: "=",
                name: "=",
                value: "=",
                params: "=",
                icon: "=",
                accessKey: "="
            }
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .controller('surgicalBlockController', ['$scope', '$q', '$state', '$stateParams', 'spinner', 'surgicalAppointmentService', 'locationService', 'appService', 'messagingService', 'surgicalAppointmentHelper', 'surgicalBlockHelper', 'ngDialog',
        function ($scope, $q, $state, $stateParams, spinner, surgicalAppointmentService, locationService, appService, messagingService, surgicalAppointmentHelper, surgicalBlockHelper, ngDialog) {
            var init = function () {
                $scope.surgicalForm = {
                    surgicalAppointments: []
                };
                $scope.configuredSurgeryAttributeNames = appService.getAppDescriptor().getConfigValue("surgeryAttributes");
                $scope.defaultAttributeTranslations = surgicalAppointmentHelper.getDefaultAttributeTranslations();
                var providerNamesFromConfig = appService.getAppDescriptor().getConfigValue("primarySurgeonsForOT");
                return $q.all([surgicalAppointmentService.getSurgeons(), locationService.getAllByTag("Operation Theater"), surgicalAppointmentService.getSurgicalAppointmentAttributeTypes()]).then(function (response) {
                    $scope.surgeons = surgicalAppointmentHelper.filterProvidersByName(providerNamesFromConfig, response[0].data.results);
                    $scope.locations = response[1].data.results;
                    $scope.attributeTypes = response[2].data.results;
                    if ($stateParams.surgicalBlockUuid) {
                        return surgicalAppointmentService.getSurgicalBlockFor($stateParams.surgicalBlockUuid).then(function (response) {
                            $scope.surgicalForm = new Bahmni.OT.SurgicalBlockMapper().map(response.data, $scope.attributeTypes, $scope.surgeons);
                            $scope.surgicalForm.surgicalAppointments = surgicalAppointmentHelper.filterSurgicalAppointmentsByStatus(
                                $scope.surgicalForm.surgicalAppointments, [Bahmni.OT.Constants.scheduled, Bahmni.OT.Constants.completed]);
                            var selectedSurgicalAppointment = _.find($scope.surgicalForm.surgicalAppointments, function (appointment) {
                                return appointment.id === $stateParams.surgicalAppointmentId;
                            });
                            if (selectedSurgicalAppointment) {
                                $scope.editAppointment(selectedSurgicalAppointment);
                            }
                            getAvailableBlockDurationInHoursAndMinutesFormat();
                            return response;
                        });
                    }
                    return response;
                });
            };

            var getAppointmentDuration = function (surgicalAppointment) {
                return surgicalAppointmentHelper.getAppointmentDuration(surgicalAppointment.surgicalAppointmentAttributes.estTimeHours.value, surgicalAppointment.surgicalAppointmentAttributes.estTimeMinutes.value, surgicalAppointment.surgicalAppointmentAttributes.cleaningTime.value);
            };

            var getAvailableBlockDuration = function () {
                return surgicalBlockHelper.getAvailableBlockDuration($scope.surgicalForm);
            };

            $scope.getPatientName = function (surgicalAppointment) {
                return surgicalAppointment.patient.value || surgicalAppointmentHelper.getPatientDisplayLabel(surgicalAppointment.patient.display);
            };

            $scope.editAppointment = function (surgicalAppointment) {
                _.forEach($scope.surgicalForm.surgicalAppointments, function (surgicalAppointment) {
                    delete surgicalAppointment.isBeingEdited;
                });
                var clone = _.cloneDeep(surgicalAppointment);
                surgicalAppointment.isBeingEdited = true;
                $scope.addNewSurgicalAppointment(clone);
            };

            $scope.isFormValid = function () {
                return $scope.createSurgicalBlockForm.$valid && $scope.isStartDatetimeBeforeEndDatetime($scope.surgicalForm.startDatetime, $scope.surgicalForm.endDatetime);
            };

            $scope.isStartDatetimeBeforeEndDatetime = function (startDate, endDate) {
                if (startDate && endDate) {
                    return startDate < endDate;
                }
                return true;
            };

            $scope.closeDialog = function () {
                ngDialog.close();
            };

            $scope.saveAnywaysFlag = false;

            $scope.saveAnyways = function (surgicalForm) {
                $scope.saveAnywaysFlag = true;
                $scope.save(surgicalForm);
                ngDialog.close();
            };

            $scope.save = function (surgicalForm) {
                if (!$scope.isFormValid()) {
                    messagingService.showMessage('error', "{{'OT_ENTER_MANDATORY_FIELDS' | translate}}");
                    return;
                }
                if (getAvailableBlockDuration() < 0) {
                    messagingService.showMessage('error', "{{'OT_SURGICAL_APPOINTMENT_EXCEEDS_BLOCK_DURATION' | translate}}");
                    return;
                }
                if ($scope.saveAnywaysFlag || Bahmni.Common.Util.DateUtil.isSameDate(surgicalForm.startDatetime, surgicalForm.endDatetime)) {
                    $scope.updateSortWeight(surgicalForm);
                    var surgicalBlock = new Bahmni.OT.SurgicalBlockMapper().mapSurgicalBlockUIToDomain(surgicalForm);
                    var saveOrupdateSurgicalBlock = _.isEmpty(surgicalBlock.uuid) ? surgicalAppointmentService.saveSurgicalBlock : surgicalAppointmentService.updateSurgicalBlock;
                    spinner.forPromise(saveOrupdateSurgicalBlock(surgicalBlock)).then(function (response) {
                        $scope.surgicalForm = new Bahmni.OT.SurgicalBlockMapper().map(response.data, $scope.attributeTypes, $scope.surgeons);
                        $scope.surgicalForm.surgicalAppointments = surgicalAppointmentHelper.filterSurgicalAppointmentsByStatus(
                            $scope.surgicalForm.surgicalAppointments, [Bahmni.OT.Constants.scheduled, Bahmni.OT.Constants.completed]);
                        messagingService.showMessage('info', "{{'OT_SAVE_SUCCESS_MESSAGE_KEY' | translate}}");
                        $state.go('editSurgicalAppointment', {surgicalBlockUuid: response.data.uuid});
                    });
                    $scope.saveAnywaysFlag = false;
                } else {
                    ngDialog.open({
                        template: 'views/surgicalBlockMultipleDaysDialog.html',
                        className: 'ngdialog-theme-default',
                        closeByNavigation: true,
                        data: { surgicalForm: surgicalForm },
                        scope: $scope
                    });
                }
            };

            var addOrUpdateTheSurgicalAppointment = function (surgicalAppointment) {
                if (surgicalAppointment.sortWeight >= 0) {
                    var existingAppointment = _.find($scope.surgicalForm.surgicalAppointments, function (appointment) {
                        return appointment.isBeingEdited === true;
                    });
                    existingAppointment.notes = surgicalAppointment.notes;
                    existingAppointment.patient = surgicalAppointment.patient;
                    existingAppointment.surgicalAppointmentAttributes = surgicalAppointment.surgicalAppointmentAttributes;
                    existingAppointment.isBeingEdited = false;
                } else {
                    surgicalAppointment.sortWeight = $scope.surgicalForm.surgicalAppointments.length;
                    $scope.surgicalForm.surgicalAppointments.push(surgicalAppointment);
                }
            };

            var canBeFittedInTheSurgicalBlock = function (surgicalAppointment) {
                if (surgicalAppointment.sortWeight >= 0) {
                    var existingAppointment = _.find($scope.surgicalForm.surgicalAppointments, function (appointment) {
                        return appointment.sortWeight === surgicalAppointment.sortWeight;
                    });
                    var increasedDeltaTime = getAppointmentDuration(surgicalAppointment) - getAppointmentDuration(existingAppointment);
                    return getAvailableBlockDuration() >= increasedDeltaTime;
                }
                return getAvailableBlockDuration() >= getAppointmentDuration(surgicalAppointment);
            };

            var checkIfSurgicalAppointmentIsDirty = function (surgicalAppointment) {
                if (!surgicalAppointment.id) {
                    return;
                }
                var savedSurgicalAppointment = _.find($scope.surgicalForm.surgicalAppointments, function (appointment) {
                    return appointment.id === surgicalAppointment.id;
                });
                delete savedSurgicalAppointment.$$hashKey;
                delete savedSurgicalAppointment.isDirty;
                surgicalAppointment.isBeingEdited = savedSurgicalAppointment.isBeingEdited;
                _.isEqual(savedSurgicalAppointment, surgicalAppointment) ? savedSurgicalAppointment.isDirty = false : savedSurgicalAppointment.isDirty = true;
            };

            var getAvailableBlockDurationInHoursAndMinutesFormat = function () {
                var availableBlockDuration = getAvailableBlockDuration();
                $scope.availableBlockDuration = Math.floor(availableBlockDuration / 60) + " hr " + availableBlockDuration % 60 + " mins";
            };

            $scope.addSurgicalAppointment = function (surgicalAppointment) {
                if (canBeFittedInTheSurgicalBlock(surgicalAppointment)) {
                    checkIfSurgicalAppointmentIsDirty(surgicalAppointment);
                    addOrUpdateTheSurgicalAppointment(surgicalAppointment);
                    getAvailableBlockDurationInHoursAndMinutesFormat();
                    ngDialog.close();
                    surgicalAppointment.isBeingEdited = false;
                    surgicalAppointment.isDirty = true;

                    var appointmentIndex;
                    _.find($scope.surgicalForm.surgicalAppointments, function (appointment, index) {
                        appointmentIndex = index;
                        return surgicalAppointment.sortWeight === appointment.sortWeight;
                    });
                    $scope.surgicalForm.surgicalAppointments[appointmentIndex] = surgicalAppointment;
                }
                else {
                    messagingService.showMessage('error', "{{'OT_SURGICAL_APPOINTMENT_EXCEEDS_BLOCK_DURATION' | translate}}");
                }
            };

            $scope.updateSortWeight = function (surgicalBlock) {
                var index = 0;
                _.map(surgicalBlock && surgicalBlock.surgicalAppointments, function (appointment) {
                    if (appointment.status !== 'POSTPONED' && appointment.status !== 'CANCELLED') {
                        appointment.sortWeight = index++;
                    }
                    return appointment;
                });
            };

            $scope.gotoCalendarPage = function () {
                var options = {};
                options['dashboardCachebuster'] = Math.random();
                $state.go("otScheduling", options);
            };

            $scope.cancelSurgicalBlock = function () {
                ngDialog.open({
                    template: "views/cancelSurgicalBlock.html",
                    closeByDocument: false,
                    controller: "cancelSurgicalBlockController",
                    className: 'ngdialog-theme-default ng-dialog-adt-popUp',
                    showClose: true,
                    data: {
                        surgicalBlock: new Bahmni.OT.SurgicalBlockMapper().mapSurgicalBlockUIToDomain($scope.surgicalForm),
                        provider: $scope.surgicalForm.provider.person.display
                    }
                });
            };

            $scope.cancelAppointment = function (surgicalAppointment) {
                surgicalAppointment.isBeingEdited = true;
                var clonedAppointment = _.cloneDeep(surgicalAppointment);
                ngDialog.open({
                    template: "views/cancelAppointment.html",
                    controller: "surgicalBlockViewCancelAppointmentController",
                    closeByDocument: false,
                    showClose: true,
                    className: 'ngdialog-theme-default ng-dialog-adt-popUp',
                    scope: $scope,
                    data: {
                        surgicalAppointment: clonedAppointment,
                        surgicalForm: $scope.surgicalForm,
                        updateAvailableBlockDurationFn: getAvailableBlockDurationInHoursAndMinutesFormat
                    }
                });
            };

            $scope.cancelDisabled = function () {
                var surgicalBlockWithCompletedAppointments = function () {
                    return _.find($scope.surgicalForm.surgicalAppointments, function (appointment) {
                        return appointment.status === Bahmni.OT.Constants.completed;
                    });
                };
                return !$scope.surgicalForm.id || surgicalBlockWithCompletedAppointments();
            };

            $scope.addNewSurgicalAppointment = function (surgicalAppointment) {
                ngDialog.open({
                    template: "views/surgicalAppointment.html",
                    controller: "NewSurgicalAppointmentController",
                    closeByDocument: false,
                    className: 'ngdialog-theme-default surgical-appointment-dialog',
                    showClose: true,
                    closeByNavigation: true,
                    scope: $scope,
                    data: surgicalAppointment
                });
            };

            $scope.changeInStartDateTime = function () {
                if (_.isUndefined($scope.surgicalForm.endDatetime)) {
                    var calendarConfig = appService.getAppDescriptor().getConfigValue("calendarView");
                    var dayViewEnd = (calendarConfig.dayViewEnd || Bahmni.OT.Constants.defaultCalendarEndTime).split(':');
                    $scope.surgicalForm.endDatetime = Bahmni.Common.Util.DateUtil.addMinutes(moment($scope.surgicalForm.startDatetime).startOf('day').toDate(), (dayViewEnd[0] * 60 + parseInt(dayViewEnd[1])));
                }
            };

            $scope.getConfiguredAttributes = function (attributes) {
                return surgicalAppointmentHelper.getAttributesFromAttributeNames(attributes, $scope.configuredSurgeryAttributeNames);
            };

            $scope.isSurgeryAttributesConfigurationAvailableAndValid = function () {
                return $scope.configuredSurgeryAttributeNames && $scope.configuredSurgeryAttributeNames.length > 0;
            };

            $scope.sort = function (attributes) {
                return surgicalAppointmentHelper.getAttributesFromAttributeTypes(attributes, $scope.attributeTypes);
            };

            spinner.forPromise(init());
        }]);

'use strict';

angular.module('bahmni.ot')
    .controller('NewSurgicalAppointmentController', ['$scope', '$q', '$window', 'patientService', 'surgicalAppointmentService', 'messagingService', 'programService', 'appService', 'ngDialog', 'spinner', 'queryService', 'programHelper', 'surgicalAppointmentHelper',
        function ($scope, $q, $window, patientService, surgicalAppointmentService, messagingService, programService, appService, ngDialog, spinner, queryService, programHelper, surgicalAppointmentHelper) {
            var init = function () {
                $scope.configuredSurgeryAttributeNames = appService.getAppDescriptor().getConfigValue("surgeryAttributes");
                $scope.selectedPatient = $scope.ngDialogData && $scope.ngDialogData.patient;
                $scope.patient = $scope.ngDialogData && $scope.ngDialogData.patient && ($scope.ngDialogData.patient.value || $scope.ngDialogData.patient.display);
                $scope.otherSurgeons = _.cloneDeep($scope.surgeons);
                return $q.all([surgicalAppointmentService.getSurgicalAppointmentAttributeTypes()]).then(function (response) {
                    $scope.attributeTypes = response[0].data.results;
                    var attributes = {};
                    var mapAttributes = new Bahmni.OT.SurgicalBlockMapper().mapAttributes(attributes, $scope.attributeTypes);
                    $scope.attributes = $scope.ngDialogData && $scope.ngDialogData.surgicalAppointmentAttributes || mapAttributes;
                    if ($scope.isEditMode()) {
                        programService.getEnrollmentInfoFor($scope.ngDialogData.patient.uuid, "custom:(uuid,dateEnrolled,dateCompleted,program:(uuid),patient:(uuid))").then(function (response) {
                            var groupedPrograms = programHelper.groupPrograms(response);
                            $scope.enrollmentInfo = groupedPrograms && groupedPrograms.activePrograms[0];
                        });
                    }
                });
            };

            $scope.isEditMode = function () {
                return $scope.patient && $scope.ngDialogData && $scope.ngDialogData.id;
            };

            $scope.search = function () {
                return patientService.search($scope.patient).then(function (response) {
                    return response.data.pageOfResults;
                });
            };

            $scope.onSelectPatient = function (data) {
                $scope.selectedPatient = data;
                var sqlGlobalProperty = appService.getAppDescriptor().getConfigValue('procedureSQLGlobalProperty');
                if (!sqlGlobalProperty) {
                    return;
                }
                var params = {
                    patientUuid: data.uuid,
                    q: sqlGlobalProperty,
                    v: "full"
                };
                spinner.forPromise(queryService.getResponseFromQuery(params).then(function (response) {
                    if (response.data.length) {
                        $scope.attributes.procedure.value = response.data[0]['all_procedures'];
                        var estHrs = response.data[0]['esthrs'];
                        var estMins = response.data[0]['estmins'];
                        $scope.attributes.estTimeHours.value = estHrs ? Math.floor(parseInt(estHrs) + estMins / 60) : 0;
                        $scope.attributes.estTimeMinutes.value = estMins ? parseInt(estMins) % 60 : 0;
                    } else {
                        $scope.attributes.procedure.value = "";
                        $scope.attributes.estTimeHours.value = 0;
                        $scope.attributes.estTimeMinutes.value = 0;
                    }
                }));
            };

            $scope.responseMap = function (data) {
                return _.map(data, function (patientInfo) {
                    patientInfo.label = patientInfo.givenName + " " + patientInfo.familyName + " " + "( " + patientInfo.identifier + " )";
                    return patientInfo;
                });
            };

            $scope.createAppointmentAndAdd = function () {
                if ($scope.surgicalAppointmentForm.$valid) {
                    var appointment = {
                        id: $scope.ngDialogData && $scope.ngDialogData.id,
                        patient: $scope.selectedPatient,
                        sortWeight: $scope.ngDialogData && $scope.ngDialogData.sortWeight,
                        actualStartDatetime: $scope.ngDialogData && $scope.ngDialogData.actualStartDatetime,
                        actualEndDatetime: $scope.ngDialogData && $scope.ngDialogData.actualEndDatetime,
                        status: $scope.ngDialogData && $scope.ngDialogData.status || Bahmni.OT.Constants.scheduled,
                        notes: $scope.ngDialogData && $scope.ngDialogData.notes,
                        uuid: $scope.ngDialogData && $scope.ngDialogData.uuid,
                        voided: $scope.ngDialogData && $scope.ngDialogData.voided,
                        surgicalAppointmentAttributes: $scope.attributes
                    };
                    $scope.addSurgicalAppointment(appointment);
                }
                return $q.when({});
            };

            $scope.close = function () {
                if ($scope.ngDialogData) {
                    var appointment = _.find($scope.surgicalForm.surgicalAppointments, function (surgicalAppointment) {
                        return surgicalAppointment.isBeingEdited;
                    });

                    delete $scope.surgicalForm.surgicalAppointments[appointment.sortWeight].isBeingEdited;
                    delete $scope.ngDialogData.isBeingEdited;
                }
                ngDialog.close();
            };

            $scope.goToForwardUrl = function () {
                var forwardUrl = appService.getAppDescriptor().getConfigValue('patientDashboardUrl');
                if (isProgramDashboardUrlConfigured(forwardUrl) && !$scope.enrollmentInfo) {
                    messagingService.showMessage('error', forwardUrl.errorMessage);
                    return;
                }
                var params = getDashboardParams(forwardUrl);
                var formattedUrl = appService.getAppDescriptor().formatUrl(forwardUrl.link, params);
                $window.open(formattedUrl);
            };

            var isProgramDashboardUrlConfigured = function (forwardUrl) {
                return forwardUrl && forwardUrl.link && forwardUrl.link.includes('programs');
            };

            var getDashboardParams = function (forwardUrl) {
                if (forwardUrl && forwardUrl.link && forwardUrl.link.includes('programs')) {
                    return {
                        patientUuid: $scope.enrollmentInfo.patient.uuid,
                        dateEnrolled: $scope.enrollmentInfo.dateEnrolled,
                        programUuid: $scope.enrollmentInfo.program.uuid,
                        enrollment: $scope.enrollmentInfo.uuid
                    };
                }
                return {
                    patientUuid: $scope.selectedPatient.uuid
                };
            };

            $scope.sort = function (attributes) {
                return surgicalAppointmentHelper.getAttributesFromAttributeTypes(attributes, $scope.attributeTypes);
            };

            spinner.forPromise(init());
        }]);

'use strict';

angular.module('bahmni.ot')
    .controller('calendarViewController', ['$scope', '$rootScope', '$state', '$stateParams', 'appService', 'patientService', 'locationService', 'ngDialog', 'surgicalAppointmentHelper',
        function ($scope, $rootScope, $state, $stateParams, appService, patientService, locationService, ngDialog, surgicalAppointmentHelper) {
            var CALENDAR_VIEW = 'Calendar';
            $scope.viewDate = $stateParams.viewDate || $state.viewDate || (moment().startOf('day')).toDate();
            $state.viewDate = $scope.viewDate;
            $scope.calendarConfig = appService.getAppDescriptor().getConfigValue("calendarView");
            var weekStartDay = appService.getAppDescriptor().getConfigValue('startOfWeek') || Bahmni.OT.Constants.defaultWeekStartDayName;
            var currentDate = moment().startOf('day').toDate();
            $scope.startOfWeekCode = Bahmni.OT.Constants.weekDays[weekStartDay];
            $scope.weekStartDate = $state.weekStartDate || Bahmni.Common.Util.DateUtil.getWeekStartDate(currentDate, $scope.startOfWeekCode);
            $state.weekStartDate = $scope.weekStartDate;
            var addLocationsForFilters = function () {
                var locations = {};
                _.each($scope.locations, function (location) {
                    locations[location.name] = true;
                });
                $scope.filters.locations = locations;
            };
            var addListenersToAutoFilterResults = function () {
                $scope.$watch("filters.providers", function () {
                    if (!_.isUndefined($scope.filters.providers)) {
                        $scope.applyFilters();
                    }
                });
                $scope.$watch("filters.patient", function () {
                    if (!_.isUndefined($scope.filters.patient)) {
                        $scope.applyFilters();
                    }
                });
                $scope.$watch("filters.statusList", function () {
                    if (!_.isUndefined($scope.filters.statusList)) {
                        $scope.applyFilters();
                    }
                });
            };
            var init = function () {
                $scope.filterParams = $state.filterParams;
                $scope.filters = {};
                $scope.filters.providers = [];
                $scope.view = $state.view || CALENDAR_VIEW;
                $state.view = $scope.view;
                $scope.weekOrDay = $state.weekOrDay || 'day';
                $state.weekOrDay = $scope.weekOrDay;
                $scope.isFilterOpen = true;
                if ($scope.weekOrDay === 'week') {
                    $scope.weekStartDate = $state.weekStartDate || new Date(moment().startOf('week'));
                    $state.weekStartDate = $scope.weekStartDate;
                    $scope.weekEndDate = $state.weekEndDate || new Date(moment().endOf('week').endOf('day'));
                    $state.weekEndDate = $scope.weekEndDate;
                }
                $scope.surgicalBlockSelected = {};
                $scope.surgicalAppointmentSelected = {};
                $scope.editDisabled = true;
                $scope.moveButtonDisabled = true;
                $scope.cancelDisabled = true;
                $scope.addActualTimeDisabled = true;
                $scope.surgeonList = _.map($rootScope.surgeons, function (surgeon) {
                    var newVar = {
                        name: surgeon.person.display,
                        uuid: surgeon.uuid
                    };
                    newVar[surgeon.person.display] = false;
                    var otCalendarColorAttribute = _.find(surgeon.attributes, function (attribute) {
                        return attribute.attributeType.display === 'otCalendarColor';
                    });
                    newVar.otCalendarColor = getBackGroundHSLColorFor(otCalendarColorAttribute);
                    return newVar;
                });
                $scope.filters.statusList = [];
                $rootScope.providerToggle = appService.getAppDescriptor().getConfigValue("defaultViewAsSurgeonBased");
                setAppointmentStatusList($scope.view);
                return locationService.getAllByTag('Operation Theater').then(function (response) {
                    $scope.locations = response.data.results;
                    addLocationsForFilters();
                    $scope.filters = $scope.filterParams || $scope.filters;
                    $scope.patient = $scope.filters.patient && $scope.filters.patient.value;
                    $scope.applyFilters();
                    addListenersToAutoFilterResults();
                    return $scope.locations;
                });
            };

            var setAppointmentStatusList = function (view) {
                if (view === CALENDAR_VIEW) {
                    $scope.appointmentStatusList = [{name: Bahmni.OT.Constants.scheduled}, {name: Bahmni.OT.Constants.completed}];
                } else {
                    $scope.appointmentStatusList = [{name: Bahmni.OT.Constants.scheduled}, {name: Bahmni.OT.Constants.completed},
                        {name: Bahmni.OT.Constants.postponed}, {name: Bahmni.OT.Constants.cancelled}];
                }
            };

            $scope.calendarView = function () {
                $scope.view = CALENDAR_VIEW;
                $state.view = $scope.view;
            };

            $scope.listView = function () {
                $scope.view = 'List View';
                $state.view = $scope.view;
            };

            $scope.providerView = function (providerToggle) {
                $rootScope.providerToggle = providerToggle;
                $rootScope.$broadcast("event:providerView", providerToggle);
            };

            var getBackGroundHSLColorFor = function (otCalendarColorAttribute) {
                var hue = otCalendarColorAttribute && otCalendarColorAttribute.value ? otCalendarColorAttribute.value.toString() : "0";
                return "hsl(" + hue + ", 100%, 90%)";
            };

            $scope.isFilterApplied = function () {
                return Object.keys($state.filterParams.locations).length != $scope.locations.length
                        || !_.isEmpty($state.filterParams.providers)
                        || !_.isEmpty($state.filterParams.patient)
                        || !_.isEmpty($state.filterParams.statusList);
            };

            $scope.applyFilters = function () {
                $scope.filterParams = _.cloneDeep($scope.filters);
                $state.filterParams = $scope.filterParams;
            };

            $scope.clearFilters = function () {
                addLocationsForFilters();
                $scope.filters.providers = [];
                $scope.filters.statusList = [];
                $scope.patient = "";
                $scope.filters.patient = null;
                removeFreeTextItem();

                $scope.applyFilters();
            };

            var removeFreeTextItem = function () {
                $("input.input")[0].value = "";
                $("input.input")[1].value = "";
            };

            $scope.search = function () {
                return patientService.search($scope.patient).then(function (response) {
                    return response.data.pageOfResults;
                });
            };

            $scope.onSelectPatient = function (data) {
                $scope.filters.patient = data;
                if ($scope.view === CALENDAR_VIEW) {
                    if (_.isEmpty($scope.filters.statusList)) {
                        $scope.filters.statusList = [{name: Bahmni.OT.Constants.scheduled}, {name: Bahmni.OT.Constants.completed}];
                    }
                }
            };

            $scope.clearThePatientFilter = function () {
                $scope.filters.patient = null;
            };

            $scope.responseMap = function (data) {
                return _.map(data, function (patientInfo) {
                    patientInfo.label = patientInfo.givenName + " " + patientInfo.familyName + " " + "(" + patientInfo.identifier + ")";
                    return patientInfo;
                });
            };

            $scope.goToNewSurgicalAppointment = function () {
                var options = {};
                options['dashboardCachebuster'] = Math.random();
                $state.go("newSurgicalAppointment", options);
            };

            $scope.goToPreviousDate = function (date) {
                $scope.viewDate = Bahmni.Common.Util.DateUtil.subtractDays(date, 1);
                $state.viewDate = $scope.viewDate;
            };

            $scope.goToCurrentDate = function () {
                $scope.viewDate = moment().startOf('day').toDate();
                $state.viewDate = $scope.viewDate;
                $scope.weekOrDay = 'day';
                $state.weekOrDay = $scope.weekOrDay;

                $scope.weekStartDate = Bahmni.Common.Util.DateUtil.getWeekStartDate(currentDate, $scope.startOfWeekCode);
                $state.weekStartDate = $scope.weekStartDate;
            };

            $scope.goToNextDate = function (date) {
                $scope.viewDate = Bahmni.Common.Util.DateUtil.addDays(date, 1);
                $state.viewDate = $scope.viewDate;
            };

            $scope.goToSelectedDate = function (date) {
                $scope.viewDate = date;
                $state.viewDate = $scope.viewDate;
            };

            $scope.goToCurrentWeek = function () {
                $scope.weekStartDate = Bahmni.Common.Util.DateUtil.getWeekStartDate(currentDate, $scope.startOfWeekCode);
                $state.weekStartDate = $scope.weekStartDate;
                $scope.weekEndDate = Bahmni.Common.Util.DateUtil.getWeekEndDate($scope.weekStartDate);
                $state.weekEndDate = $scope.weekEndDate;
                $scope.weekOrDay = 'week';
                $state.weekOrDay = $scope.weekOrDay;

                $scope.viewDate = moment().startOf('day').toDate();
                $state.viewDate = $scope.viewDate;
            };

            $scope.goToNextWeek = function () {
                $scope.weekStartDate = Bahmni.Common.Util.DateUtil.addDays($scope.weekStartDate, 7);
                $scope.weekEndDate = Bahmni.Common.Util.DateUtil.addDays($scope.weekEndDate, 7);
                $state.weekStartDate = $scope.weekStartDate;
                $state.weekEndDate = $scope.weekEndDate;
            };

            $scope.goToPreviousWeek = function () {
                $scope.weekStartDate = Bahmni.Common.Util.DateUtil.subtractDays($scope.weekStartDate, 7);
                $scope.weekEndDate = Bahmni.Common.Util.DateUtil.subtractDays($scope.weekEndDate, 7);
                $state.weekStartDate = $scope.weekStartDate;
                $state.weekEndDate = $scope.weekEndDate;
            };

            $scope.goToSelectedWeek = function (date) {
                $scope.weekStartDate = date;
                $scope.weekEndDate = Bahmni.Common.Util.DateUtil.addDays($scope.weekStartDate, 7);
                $state.weekStartDate = $scope.weekStartDate;
                $state.weekEndDate = $scope.weekEndDate;
            };

            $scope.$on("event:surgicalAppointmentSelect", function (event, surgicalAppointment, surgicalBlock) {
                $scope.cancelDisabled = !(surgicalAppointment.status === Bahmni.OT.Constants.scheduled);
                $scope.moveButtonDisabled = !(surgicalAppointment.status === Bahmni.OT.Constants.scheduled);
                $scope.editDisabled = !((surgicalAppointment.status === Bahmni.OT.Constants.scheduled) || (surgicalAppointment.status === Bahmni.OT.Constants.completed));
                $scope.addActualTimeDisabled = !((surgicalAppointment.status === Bahmni.OT.Constants.scheduled) || (surgicalAppointment.status === Bahmni.OT.Constants.completed));
                $scope.surgicalAppointmentSelected = surgicalAppointment;
                $scope.surgicalBlockSelected = surgicalBlock;
                isCalendarView() && ngDialog.open({
                    template: 'views/surgicalAppointmentDialog.html',
                    className: 'ngdialog-theme-default',
                    closeByNavigation: true,
                    preCloseCallback: nullifySurgicalBlockData,
                    scope: $scope,
                    data: surgicalAppointment
                });
            });

            var isCalendarView = function () {
                return $scope.view === CALENDAR_VIEW;
            };

            $scope.$on("event:surgicalBlockSelect", function (event, surgicalBlock) {
                $scope.editDisabled = false;
                $scope.moveButtonDisabled = true;
                $scope.addActualTimeDisabled = true;
                $scope.cancelDisabled = true;
                $scope.surgicalBlockSelected = surgicalBlock;
                $scope.surgicalAppointmentSelected = {};
                $scope.showEndDate = (Bahmni.Common.Util.DateUtil.diffInDaysRegardlessOfTime(surgicalBlock.startDatetime, surgicalBlock.endDatetime) != 0);

                var surgicalBlockWithCompletedAppointments = function () {
                    return _.find(surgicalBlock.surgicalAppointments, function (appointment) {
                        return appointment.status === Bahmni.OT.Constants.completed;
                    });
                };

                if (!surgicalBlockWithCompletedAppointments()) {
                    $scope.cancelDisabled = false;
                }
                ngDialog.open({
                    template: 'views/surgicalBlockDialog.html',
                    className: 'ngdialog-theme-default',
                    closeByNavigation: true,
                    preCloseCallback: nullifySurgicalBlockData,
                    scope: $scope,
                    data: surgicalBlock
                });
            });

            var nullifySurgicalBlockData = function () {
                $scope.editDisabled = true;
                $scope.cancelDisabled = true;
                $scope.moveButtonDisabled = true;
                $scope.addActualTimeDisabled = true;
                $scope.surgicalBlockSelected = {};
                $scope.surgicalAppointmentSelected = {};
                $scope.showEndDate = false;
            };

            $scope.$on("event:surgicalBlockDeselect", function (event) {
                nullifySurgicalBlockData();
            });

            $scope.goToEdit = function ($event) {
                if (Object.keys($scope.surgicalBlockSelected).length !== 0) {
                    var options = {
                        surgicalBlockUuid: $scope.surgicalBlockSelected.uuid
                    };
                    if (Object.keys($scope.surgicalAppointmentSelected).length !== 0) {
                        options['surgicalAppointmentId'] = $scope.surgicalAppointmentSelected.id;
                    }
                    options['dashboardCachebuster'] = Math.random();
                    $state.go("editSurgicalAppointment", options);
                    $event.stopPropagation();
                }
            };

            $scope.gotoMove = function () {
                var cancelSurgicalBlockDialog = ngDialog.open({
                    template: "views/moveAppointment.html",
                    closeByDocument: false,
                    controller: "moveSurgicalAppointmentController",
                    className: "ngdialog-theme-default ot-dialog",
                    showClose: true,
                    data: {
                        surgicalBlock: $scope.surgicalBlockSelected,
                        surgicalAppointment: $scope.surgicalAppointmentSelected
                    }
                });
                closeSubsequentActiveDialogs(cancelSurgicalBlockDialog);
            };

            $scope.addActualTime = function () {
                ngDialog.open({
                    template: "views/addActualTimeDialog.html",
                    closeByDocument: false,
                    controller: "surgicalAppointmentActualTimeController",
                    className: 'ngdialog-theme-default ot-dialog',
                    showClose: true,
                    data: {
                        surgicalBlock: $scope.surgicalBlockSelected,
                        surgicalAppointment: $scope.surgicalAppointmentSelected
                    }
                });
            };

            var cancelSurgicalAppointment = function () {
                ngDialog.open({
                    template: "views/cancelAppointment.html",
                    closeByDocument: false,
                    controller: "calendarViewCancelAppointmentController",
                    className: 'ngdialog-theme-default ot-dialog',
                    showClose: true,
                    data: {
                        surgicalBlock: $scope.surgicalBlockSelected,
                        surgicalAppointment: $scope.surgicalAppointmentSelected
                    }
                });
            };

            var cancelSurgicalBlock = function () {
                var cancelSurgicalBlockDialog = ngDialog.open({
                    template: "views/cancelSurgicalBlock.html",
                    closeByDocument: false,
                    controller: "cancelSurgicalBlockController",
                    className: 'ngdialog-theme-default ot-dialog',
                    showClose: true,
                    data: {
                        surgicalBlock: $scope.surgicalBlockSelected,
                        provider: $scope.surgicalBlockSelected.provider.person.display
                    }
                });
                closeSubsequentActiveDialogs(cancelSurgicalBlockDialog);
            };

            var closeSubsequentActiveDialogs = function (currentDialog) {
                currentDialog.closePromise.then(function () {
                    ngDialog.close();
                });
            };

            $scope.minimizeFilter = function () {
                $scope.isFilterOpen = false;
            };

            $scope.expandFilter = function () {
                $scope.isFilterOpen = true;
            };

            function getLocationNames () {
                return _.map($scope.locations, function (location) {
                    return location.name;
                });
            }

            function isAnyLocationDeselected () {
                if ($scope.filters.locations) {
                    var locationNames = getLocationNames();
                    return _.some(locationNames, function (loc) {
                        return !$scope.filters.locations[loc];
                    });
                } return false;
            }

            function isAnyFilterOtherThanLocationsSelected () {
                return !(_.isEmpty($scope.filters.providers) && _.isEmpty($scope.filters.patient) && _.isEmpty($scope.filters.statusList));
            }

            $scope.isFilterApplied = function () {
                return isAnyFilterOtherThanLocationsSelected() || isAnyLocationDeselected();
            };

            $scope.cancelSurgicalBlockOrSurgicalAppointment = function () {
                if (!_.isEmpty($scope.surgicalAppointmentSelected)) {
                    cancelSurgicalAppointment();
                } else {
                    cancelSurgicalBlock();
                }
            };

            $scope.getAttributes = function (surgicalAppointment) {
                return surgicalAppointmentHelper.getSurgicalAttributes(surgicalAppointment);
            };

            $scope.getPatientDisplayLabel = function (surgicalAppointment) {
                return surgicalAppointmentHelper.getPatientDisplayLabel(surgicalAppointment.patient.display);
            };

            init();

            $scope.$watch('view', function (newValue, oldValue) {
                if (oldValue !== newValue) {
                    if (newValue === CALENDAR_VIEW) {
                        setAppointmentStatusList(newValue);
                        $scope.filters.statusList = _.filter($scope.filters.statusList, function (status) {
                            return status.name === Bahmni.OT.Constants.scheduled || status.name === Bahmni.OT.Constants.completed;
                        });
                    }
                    if (newValue === 'List View') {
                        setAppointmentStatusList(newValue);
                    }
                    $scope.applyFilters();
                }
            });
        }]);

'use strict';

angular.module('bahmni.ot')
    .controller('otCalendarController', ['$scope', '$rootScope', '$q', '$interval', '$state', 'spinner', 'locationService', 'surgicalAppointmentService', '$timeout', 'appService', 'surgicalAppointmentHelper',
        function ($scope, $rootScope, $q, $interval, $state, spinner, locationService, surgicalAppointmentService, $timeout, appService, surgicalAppointmentHelper) {
            var updateCurrentDayTimeline = function () {
                $scope.currentTimeLineHeight = heightPerMin * Bahmni.Common.Util.DateUtil.diffInMinutes($scope.calendarStartDatetime, new Date());
            };
            var updateBlocksStartDatetimeAndBlocksEndDatetime = function () {
                $scope.blocksStartDatetime = $scope.weekOrDay === 'day' ? $scope.viewDate : moment($scope.weekStartDate).startOf('day');
                $scope.blocksEndDatetime = $scope.weekOrDay === 'day' ? moment($scope.viewDate).endOf('day') : moment(Bahmni.Common.Util.DateUtil.getWeekEndDate($scope.weekStartDate)).endOf('day');
            };
            $scope.isModalVisible = false;
            $scope.notesStartDate = false;
            $scope.notesEndDate = false;
            $scope.isEdit = false;
            $scope.showDeletePopUp = false;
            $scope.styleForBlock = function (index) {
                if (index === 6) {
                    return { 'border-right': '.5px solid lightgrey'};
                }
            };
            var setValidStartDate = function (viewDate) {
                const currentDate = new Date(viewDate);
                $scope.validStartDate = $scope.weekDates[0];
                while (currentDate > new Date($scope.weekDates[0])) {
                    const prev = new Date(currentDate);
                    currentDate.setDate(currentDate.getDate() - 1);
                    if ($scope.notesForWeek[currentDate]) {
                        $scope.validStartDate = prev;
                        break;
                    }
                }
            };
            var setValidEndDate = function (viewDate) {
                const currentDate = new Date(viewDate);
                $scope.validEndDate = $scope.weekDates[6];
                while (currentDate < new Date($scope.weekDates[6])) {
                    const prev = new Date(currentDate);
                    currentDate.setDate(currentDate.getDate() + 1);
                    if ($scope.notesForWeek[currentDate]) {
                        $scope.validEndDate = prev;
                        break;
                    }
                }
            };

            $scope.showNotesPopup = function (weekStartDate, addIndex) {
                const currentDate = new Date(weekStartDate);
                const isDayView = addIndex === undefined;
                if (isDayView) {
                    addIndex = 0;
                }
                currentDate.setDate(currentDate.getDate() + addIndex);
                $scope.notesStartDate = currentDate;
                $scope.notesEndDate = currentDate;
                $scope.isModalVisible = true;
                $scope.isDayView = $state.weekOrDay === 'day';
                if (!$scope.isDayView) {
                    setValidStartDate(currentDate);
                    setValidEndDate(currentDate);
                }
                $scope.hostData = {
                    notes: '',
                    noteId: '',
                    isDayView: isDayView,
                    weekStartDateTime: $scope.validStartDate,
                    weekEndDateTime: $scope.validEndDate,
                    noteDate: currentDate
                };
            };
            $scope.showNotesPopupEdit = function (weekStartDate, addIndex) {
                $scope.isModalVisible = true;
                const getNoteForTheDay = $scope.getNotesForWeek(weekStartDate, addIndex);
                $scope.hostData = {
                    notes: getNoteForTheDay[0].noteText,
                    noteId: getNoteForTheDay[0].noteId,
                    isDayView: $state.weekOrDay === 'day',
                    weekStartDateTime: $scope.validStartDate,
                    weekEndDateTime: $scope.validEndDate,
                    noteDate: new Date(getNoteForTheDay[0].noteDate),
                    providerUuid: $rootScope.currentProvider.uuid
                };
            };

            $scope.openDeletePopup = function (weekStartDate, index) {
                if (weekStartDate) {
                    $scope.currentDate = new Date(weekStartDate);
                    $scope.currentDate.setDate($scope.currentDate.getDate() + index);
                    $scope.hostData = {
                        noteId: $scope.getNotesForWeek(weekStartDate, index)[0].noteId
                    };
                } else {
                    $scope.hostData = {
                        noteId: $scope.noteId
                    };
                }
                $scope.showDeletePopUp = true;
            };

            $scope.hostApi = {
                onSuccess: function () {
                    $state.go("otScheduling", {viewDate: $scope.viewDate}, {reload: true});
                },
                onClose: function () {
                    $scope.$apply(function () {
                        $scope.showDeletePopUp = false;
                        $scope.isModalVisible = false;
                    });
                }
            };
            var heightPerMin = 120 / $scope.dayViewSplit;
            var showToolTipForNotes = function () {
                $('.notes-text').tooltip({
                    content: function () {
                        var vm = (this);
                        return $(vm).prop('title');
                    },
                    track: true
                });
            };
            const getNotes = function () {
                if ($scope.weekOrDay === 'day') {
                    return surgicalAppointmentService.getBulkNotes(new Date($scope.viewDate));
                } else if ($scope.weekOrDay === 'week') {
                    return surgicalAppointmentService.getBulkNotes($scope.weekStartDate, getWeekDate(7));
                }
            };
            var init = function () {
                var dayStart = ($scope.dayViewStart || Bahmni.OT.Constants.defaultCalendarStartTime).split(':');
                var dayEnd = ($scope.dayViewEnd || Bahmni.OT.Constants.defaultCalendarEndTime).split(':');
                $scope.surgicalBlockSelected = {};
                $scope.surgicalAppointmentSelected = {};
                $scope.editDisabled = true;
                $scope.cancelDisabled = true;
                $scope.addActualTimeDisabled = true;
                $scope.isModalVisible = false;
                $scope.showDeletePopUp = false;
                $scope.dayViewSplit = parseInt($scope.dayViewSplit) > 0 ? parseInt($scope.dayViewSplit) : 60;
                $scope.calendarStartDatetime = Bahmni.Common.Util.DateUtil.addMinutes($scope.viewDate, (dayStart[0] * 60 + parseInt(dayStart[1])));
                $scope.calendarEndDatetime = Bahmni.Common.Util.DateUtil.addMinutes($scope.viewDate, (dayEnd[0] * 60 + parseInt(dayEnd[1])));
                updateCurrentDayTimeline();
                updateBlocksStartDatetimeAndBlocksEndDatetime();
                $scope.rows = $scope.getRowsForCalendar();
                return $q.all([locationService.getAllByTag('Operation Theater'),
                    surgicalAppointmentService.getSurgicalBlocksInDateRange($scope.blocksStartDatetime, $scope.blocksEndDatetime, false, true),
                    surgicalAppointmentService.getSurgeons(),
                    getNotes()]).then(function (response) {
                        $scope.locations = response[0].data.results;
                        $scope.weekDates = $scope.getAllWeekDates();
                        var surgicalBlocksByLocation = _.map($scope.locations, function (location) {
                            return _.filter(response[1].data.results, function (surgicalBlock) {
                                return surgicalBlock.location.uuid === location.uuid;
                            });
                        });
                        if (response[3] && response[3].status === 200) {
                            $scope.noteForTheDay = response[3].data.length > 0 ? response[3].data[0].noteText : '';
                            $scope.noteId = response[3].data.length > 0 ? response[3].data[0].noteId : '';
                        } else {
                            $scope.noteForTheDay = '';
                            $scope.noteId = '';
                        }
                        var providerNames = appService.getAppDescriptor().getConfigValue("primarySurgeonsForOT");
                        $scope.surgeons = surgicalAppointmentHelper.filterProvidersByName(providerNames, response[2].data.results);
                        var surgicalBlocksBySurgeons = _.map($scope.surgeons, function (surgeon) {
                            return _.filter(response[1].data.results, function (surgicalBlock) {
                                return surgicalBlock.provider.uuid === surgeon.uuid;
                            });
                        });
                        $scope.surgicalBlocksByDate = _.map($scope.weekDates, function (weekDate) {
                            return _.filter(response[1].data.results, function (surgicalBlock) {
                                return $scope.isSurgicalBlockActiveOnGivenDate(surgicalBlock, weekDate);
                            });
                        });

                        $scope.getNotesForWeek = function (weekStartDate, index) {
                            const date = new Date(weekStartDate);
                            if (index === undefined) {
                                const notesForAWeek = {};
                                response[3].data.map(function (note) {
                                    notesForAWeek[new Date(note.noteDate)] = note;
                                });
                                return notesForAWeek;
                            }
                            return _.filter(response[3].data, function (note) {
                                const currentDate = new Date(date);
                                currentDate.setDate(date.getDate() + index);
                                return new Date(note.noteDate).getDate() === (currentDate).getDate();
                            });
                        };

                        if ($scope.weekOrDay === 'week') {
                            $scope.notesForWeek = $scope.getNotesForWeek();
                        }

                        $scope.getNotesForDay = function (weekStartDate, index) {
                            var notes = $scope.getNotesForWeek(weekStartDate, index);
                            return notes.length > 0 ? notes[0].noteText : '';
                        };

                        $scope.blockedOtsOfTheWeek = getBlockedOtsOfTheWeek();
                        showToolTipForNotes();

                        var setOTView = function (providerToggle) {
                            $scope.providerToggle = providerToggle;
                            if (providerToggle) {
                                $scope.surgicalBlocks = surgicalBlocksBySurgeons;
                            } else {
                                $scope.surgicalBlocks = surgicalBlocksByLocation;
                            }
                        };
                        setOTView($rootScope.providerToggle);
                        $scope.$on("event:providerView", function (event, providerToggle) {
                            setOTView(providerToggle);
                        });
                    });
            };

            $scope.isSurgicalBlockActiveOnGivenDate = function (surgicalBlock, weekDate) {
                return Bahmni.Common.Util.DateUtil.isSameDate(moment(surgicalBlock.startDatetime).startOf('day').toDate(), weekDate) ||
                    moment(surgicalBlock.endDatetime).toDate() > weekDate;
            };

            $scope.intervals = function () {
                var dayStart = ($scope.dayViewStart || '00:00').split(':');
                var dayEnd = ($scope.dayViewEnd || '23:59').split(':');
                var noOfIntervals = ((dayEnd[0] * 60 + parseInt(dayEnd[1])) - (dayStart[0] * 60 + parseInt(dayStart[1]))) / $scope.dayViewSplit;
                return Math.ceil(noOfIntervals);
            };

            $scope.getRowsForCalendar = function () {
                var rows = [];
                for (var i = 0; i < $scope.intervals(); i++) {
                    var row = {
                        date: Bahmni.Common.Util.DateUtil.addMinutes($scope.calendarStartDatetime, i * ($scope.dayViewSplit))
                    };
                    rows.push(row);
                }
                return rows;
            };

            $scope.shouldDisplayCurrentTimeLine = function () {
                return moment().isBefore($scope.calendarEndDatetime) && moment().isAfter($scope.calendarStartDatetime);
            };

            $scope.updateBlockedOtsOfTheDay = function (dayIndex) {
                $scope.blockedOtsOfTheDay = $scope.blockedOtsOfTheWeek[dayIndex];
            };

            var getWeekDate = function (index) {
                return moment($scope.weekStartDate).add(index, 'days').toDate();
            };

            $scope.getAllWeekDates = function () {
                if ($scope.weekStartDate != null) {
                    var weekDates = [];
                    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
                        weekDates.push(getWeekDate(dayIndex));
                    }
                    return weekDates;
                }
            };

            var getBlockedOtsOfTheWeek = function () {
                var blockedOtsOfWeeks = [];
                for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
                    blockedOtsOfWeeks.push(getBlockedOtsOftheDay(dayIndex));
                }
                return blockedOtsOfWeeks;
            };

            var getBlockedOtsOftheDay = function (dayIndex) {
                var otsOfDay = [];
                if ($scope.weekOrDay === 'week') {
                    var blocksCount = $scope.surgicalBlocksByDate[dayIndex].length;
                    for (var blockIndex = 0; blockIndex < blocksCount; blockIndex++) {
                        if (!otsOfDay.includes($scope.surgicalBlocksByDate[dayIndex][blockIndex].location.uuid)) {
                            otsOfDay.push($scope.surgicalBlocksByDate[dayIndex][blockIndex].location.uuid);
                        }
                    }
                }
                return getOrderedOtsByLocation(otsOfDay);
            };

            var getOrderedOtsByLocation = function (otsOfDay) {
                var orderedOts = [];
                if ($scope.locations != null) {
                    orderedOts = _.map(_.filter($scope.locations, function (location) {
                        return otsOfDay.includes(location.uuid);
                    }), function (ot) {
                        return ot.uuid;
                    });
                }
                return orderedOts;
            };

            var timer = $interval(updateCurrentDayTimeline, 3000000);

            $scope.$on('$destroy', function () {
                $interval.cancel(timer);
            });

            $scope.$watch("viewDate", function (newValue, oldValue) {
                if ($scope.weekOrDay === 'day') {
                    if (!Bahmni.Common.Util.DateUtil.isSameDate(oldValue, newValue)) {
                        spinner.forPromise(init());
                    }
                }
            });
            $scope.$watch("weekStartDate", function (newValue, oldValue) {
                if ($scope.weekOrDay === 'week') {
                    if (!Bahmni.Common.Util.DateUtil.isSameDate(moment(oldValue).toDate(), moment(newValue).toDate())) {
                        spinner.forPromise(init());
                    }
                }
            });
            spinner.forPromise(init());
        }]);

'use strict';

angular.module('bahmni.ot').controller('surgicalAppointmentActualTimeController', [
    '$scope', 'ngDialog', 'surgicalAppointmentService', 'messagingService', 'surgicalAppointmentHelper', '$translate',
    function ($scope, ngDialog, surgicalAppointmentService, messagingService, surgicalAppointmentHelper, $translate) {
        var surgicalBlock = $scope.ngDialogData.surgicalBlock;
        var surgicalAppointment = $scope.ngDialogData.surgicalAppointment;

        var calculateActualEndTime = function () {
            var totalAppointmentsDuration = 0;
            var sortedAppointments = _.sortBy(surgicalBlock.surgicalAppointments, 'sortWeight');
            _.find(sortedAppointments, function (appointment) {
                totalAppointmentsDuration += surgicalAppointmentHelper.getEstimatedDurationForAppointment(appointment);
                return appointment.id === surgicalAppointment.id;
            });
            var appointmentEndTime = moment(surgicalBlock.startDatetime).toDate();
            appointmentEndTime = Bahmni.Common.Util.DateUtil.addMinutes(appointmentEndTime, totalAppointmentsDuration);
            return appointmentEndTime;
        };

        var init = function () {
            var calculatedAppointmentEndTime = calculateActualEndTime();
            var appointmentDuration = surgicalAppointmentHelper.getEstimatedDurationForAppointment(surgicalAppointment);
            $scope.actualStartTime = (surgicalAppointment.actualStartDatetime && moment(surgicalAppointment.actualStartDatetime).toDate()) ||
                Bahmni.Common.Util.DateUtil.subtractSeconds(calculatedAppointmentEndTime, appointmentDuration * 60);
            $scope.actualEndTime = (surgicalAppointment.actualEndDatetime && moment(surgicalAppointment.actualEndDatetime).toDate())
                || calculatedAppointmentEndTime;
            $scope.notes = surgicalAppointment.notes;
            $scope.patientDisplayLabel = surgicalAppointmentHelper.getPatientDisplayLabel(surgicalAppointment.patient.display);
        };

        $scope.isStartDatetimeBeforeEndDatetime = function (startDate, endDate) {
            if (startDate && endDate) {
                return startDate < endDate;
            }
            return true;
        };

        $scope.add = function () {
            if (!$scope.isStartDatetimeBeforeEndDatetime($scope.actualStartTime, $scope.actualEndTime)) {
                messagingService.showMessage('error', 'ACTUAL_START_TIME_GREATER_THAN_END_TIME_MESSAGE');
                return;
            }
            var surgicalAppointment = {};
            surgicalAppointment.id = $scope.ngDialogData.surgicalAppointment.id;
            surgicalAppointment.uuid = $scope.ngDialogData.surgicalAppointment.uuid;
            surgicalAppointment.actualStartDatetime = $scope.actualStartTime;
            surgicalAppointment.actualEndDatetime = $scope.actualEndTime;
            surgicalAppointment.status = $scope.actualStartTime && Bahmni.OT.Constants.completed || Bahmni.OT.Constants.scheduled;
            surgicalAppointment.notes = $scope.notes;
            surgicalAppointment.surgicalBlock = {uuid: $scope.ngDialogData.surgicalBlock.uuid};
            surgicalAppointment.patient = {uuid: $scope.ngDialogData.surgicalAppointment.patient.uuid};
            surgicalAppointment.sortWeight = $scope.ngDialogData.surgicalAppointment.sortWeight;
            surgicalAppointmentService.updateSurgicalAppointment(surgicalAppointment).then(function (response) {
                $scope.ngDialogData.surgicalAppointment.actualStartDatetime = response.data.actualStartDatetime;
                $scope.ngDialogData.surgicalAppointment.actualEndDatetime = response.data.actualEndDatetime;
                $scope.ngDialogData.surgicalAppointment.status = response.data.status;
                $scope.ngDialogData.surgicalAppointment.notes = response.data.notes;
                var message = $translate.instant('ACTUAL_TIME_ADDED_TO_KEY') + surgicalAppointmentHelper.getPatientDisplayLabel($scope.ngDialogData.surgicalAppointment.patient.display) + ' - ' + $scope.ngDialogData.surgicalBlock.location.name;
                messagingService.showMessage('info', message);
                ngDialog.close();
            });
        };

        $scope.isActualTimeRequired = function () {
            return $scope.actualStartTime || $scope.actualEndTime || $scope.notes;
        };

        $scope.close = function () {
            ngDialog.close();
        };
        init();
    }]);

'use strict';

angular.module('bahmni.ot').controller('calendarViewCancelAppointmentController', [
    '$scope', '$translate', '$q', 'ngDialog', 'surgicalAppointmentService', 'messagingService', 'surgicalAppointmentHelper',
    function ($scope, $translate, $q, ngDialog, surgicalAppointmentService, messagingService, surgicalAppointmentHelper) {
        var ngDialogSurgicalAppointment = $scope.ngDialogData.surgicalAppointment;
        var attributes = surgicalAppointmentHelper.getAppointmentAttributes(ngDialogSurgicalAppointment);
        $scope.appointment = {
            estTimeHours: attributes.estTimeHours,
            estTimeMinutes: attributes.estTimeMinutes,
            patient: surgicalAppointmentHelper.getPatientDisplayLabel(ngDialogSurgicalAppointment.patient.display),
            notes: ngDialogSurgicalAppointment.notes,
            status: ngDialogSurgicalAppointment.status
        };

        $scope.confirmCancelAppointment = function () {
            var surgicalAppointment = {};
            surgicalAppointment.id = $scope.ngDialogData.surgicalAppointment.id;
            surgicalAppointment.uuid = $scope.ngDialogData.surgicalAppointment.uuid;
            surgicalAppointment.notes = $scope.appointment.notes;
            surgicalAppointment.status = $scope.appointment.status;
            surgicalAppointment.surgicalBlock = {uuid: $scope.ngDialogData.surgicalBlock.uuid};
            surgicalAppointment.patient = {uuid: ngDialogSurgicalAppointment.patient.uuid};
            surgicalAppointment.sortWeight = null;
            $q.all([surgicalAppointmentService.updateSurgicalAppointment(surgicalAppointment), updateSortWeightOfSurgicalAppointments()]).then(function (response) {
                ngDialogSurgicalAppointment.patient = response[0].data.patient;
                ngDialogSurgicalAppointment.status = response[0].data.status;
                ngDialogSurgicalAppointment.notes = response[0].data.notes;
                ngDialogSurgicalAppointment.sortWeight = response[0].data.sortWeight;
                var message = '';
                if (ngDialogSurgicalAppointment.status === Bahmni.OT.Constants.postponed) {
                    message = $translate.instant("OT_SURGICAL_APPOINTMENT_POSTPONED_MESSAGE");
                } else if (ngDialogSurgicalAppointment.status === Bahmni.OT.Constants.cancelled) {
                    message = $translate.instant("OT_SURGICAL_APPOINTMENT_CANCELLED_MESSAGE");
                }
                message = message + surgicalAppointmentHelper.getPatientDisplayLabel($scope.ngDialogData.surgicalAppointment.patient.display) + ' - ' + $scope.ngDialogData.surgicalBlock.location.name;
                messagingService.showMessage('info', message);
                ngDialog.close();
            });
        };

        var updateSortWeightOfSurgicalAppointments = function () {
            var surgicalBlock = _.cloneDeep($scope.ngDialogData.surgicalBlock);
            var surgicalAppointments = _.filter(surgicalBlock.surgicalAppointments, function (appointment) {
                return appointment.uuid !== $scope.ngDialogData.surgicalAppointment.uuid && appointment.status !== 'POSTPONED' && appointment.status !== 'CANCELLED';
            });
            surgicalBlock.surgicalAppointments = _.map(surgicalAppointments, function (appointment, index) {
                appointment.sortWeight = index;
                return appointment;
            });
            surgicalBlock.provider = {uuid: surgicalBlock.provider.uuid};
            surgicalBlock.location = {uuid: surgicalBlock.location.uuid};
            surgicalBlock.surgicalAppointments = _.map(surgicalBlock.surgicalAppointments, function (appointment) {
                appointment.patient = {uuid: appointment.patient.uuid};
                appointment.surgicalAppointmentAttributes = _.values(appointment.surgicalAppointmentAttributes).filter(function (attribute) {
                    return !_.isUndefined(attribute.value);
                });
                return _.omit(appointment, ['derivedAttributes', 'surgicalBlock', 'bedNumber', 'bedLocation']);
            });

            return surgicalAppointmentService.updateSurgicalBlock(surgicalBlock);
        };

        $scope.closeDialog = function () {
            ngDialog.close();
        };
    }]);

'use strict';

angular.module('bahmni.ot').controller('surgicalBlockViewCancelAppointmentController', ['$scope', 'ngDialog', 'surgicalAppointmentHelper',
    function ($scope, ngDialog, surgicalAppointmentHelper) {
        var surgicalAppointment = $scope.ngDialogData.surgicalAppointment;
        $scope.appointment = {
            estTimeHours: surgicalAppointment.surgicalAppointmentAttributes.estTimeHours.value,
            estTimeMinutes: surgicalAppointment.surgicalAppointmentAttributes.estTimeMinutes.value,
            patient: surgicalAppointment.patient.label || surgicalAppointmentHelper.getPatientDisplayLabel(surgicalAppointment.patient.display),
            notes: surgicalAppointment.notes,
            status: surgicalAppointment.status
        };

        $scope.confirmCancelAppointment = function () {
            var actualAppointment = _.find($scope.ngDialogData.surgicalForm.surgicalAppointments, function (appointment) {
                return appointment.isBeingEdited;
            });
            if (actualAppointment.id == null) {
                _.remove($scope.ngDialogData.surgicalForm.surgicalAppointments, actualAppointment);
                ngDialog.close();
            }
            actualAppointment.status = $scope.appointment.status;
            actualAppointment.notes = $scope.appointment.notes;
            actualAppointment.sortWeight = null;
            delete actualAppointment.isBeingEdited;
            $scope.ngDialogData.updateAvailableBlockDurationFn();
            ngDialog.close();
        };

        $scope.closeDialog = function () {
            var actualAppointment = _.find($scope.ngDialogData.surgicalForm.surgicalAppointments, function (appointment) {
                return appointment.isBeingEdited;
            });
            delete actualAppointment.isBeingEdited;
            ngDialog.close();
        };
    }]);

'use strict';

angular.module('bahmni.ot').controller('cancelSurgicalBlockController', [
    '$scope', '$state', '$translate', 'ngDialog', 'surgicalAppointmentService', 'messagingService',
    function ($scope, $state, $translate, ngDialog, surgicalAppointmentService, messagingService) {
        var surgicalBlock = $scope.ngDialogData.surgicalBlock;

        $scope.confirmCancelSurgicalBlock = function () {
            _.forEach(surgicalBlock.surgicalAppointments, function (appointment) {
                if (appointment.status === 'SCHEDULED') {
                    appointment.status = $scope.surgicalBlock.status;
                    appointment.notes = $scope.surgicalBlock.notes;
                    appointment.sortWeight = null;
                }
                appointment.patient = {uuid: appointment.patient.uuid};
            });
            surgicalBlock.voided = true;
            surgicalBlock.voidReason = $scope.surgicalBlock.notes;
            surgicalBlock.provider = {uuid: surgicalBlock.provider.uuid};
            surgicalBlock.location = {uuid: surgicalBlock.location.uuid};

            surgicalBlock.surgicalAppointments = _.map(surgicalBlock.surgicalAppointments, function (appointment) {
                return _.omit(appointment, ['derivedAttributes', 'bedNumber', 'bedLocation']);
            });

            surgicalAppointmentService.updateSurgicalBlock(surgicalBlock).then(function (response) {
                var message = '';
                if ($scope.surgicalBlock.status === Bahmni.OT.Constants.postponed) {
                    message = $translate.instant("OT_SURGICAL_BLOCK_POSTPONED_MESSAGE");
                } else if ($scope.surgicalBlock.status === Bahmni.OT.Constants.cancelled) {
                    message = $translate.instant("OT_SURGICAL_BLOCK_CANCELLED_MESSAGE");
                }
                message += response.data.provider.person.display;
                messagingService.showMessage('info', message);
                ngDialog.close();
                var options = {};
                options['dashboardCachebuster'] = Math.random();
                $state.go("otScheduling", options);
            });
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .controller('listViewController', ['$scope', '$rootScope', '$q', 'spinner', 'surgicalAppointmentService', 'appService', 'surgicalAppointmentHelper', 'surgicalBlockFilter', 'printer',
        function ($scope, $rootScope, $q, spinner, surgicalAppointmentService, appService, surgicalAppointmentHelper, surgicalBlockFilter, printer) {
            var startDatetime = moment($scope.viewDate).toDate();
            var surgicalBlockMapper = new Bahmni.OT.SurgicalBlockMapper();
            var endDatetime = moment(startDatetime).endOf('day').toDate();
            $scope.defaultAttributeTranslations = surgicalAppointmentHelper.getDefaultAttributeTranslations();
            $scope.filteredSurgicalAttributeTypes = getFilteredSurgicalAttributeTypes();
            $scope.tableInfo = getTableInfo();

            function getTableInfo () {
                var listViewAttributes = [
                    {heading: 'Status', sortInfo: 'status'},
                    {heading: 'Day', sortInfo: 'derivedAttributes.expectedStartDate'},
                    {heading: 'Date', sortInfo: 'derivedAttributes.expectedStartDate'},
                    {heading: 'Identifier', sortInfo: 'derivedAttributes.patientIdentifier'},
                    {heading: 'Patient Name', sortInfo: 'derivedAttributes.patientName'},
                    {heading: 'Patient Age', sortInfo: 'derivedAttributes.patientAge'},
                    {heading: 'Start Time', sortInfo: 'derivedAttributes.expectedStartTime'},
                    {heading: 'Est Time', sortInfo: 'derivedAttributes.duration'},
                    {heading: 'Actual Time', sortInfo: 'actualStartDatetime'},
                    {heading: 'OT#', sortInfo: 'surgicalBlock.location.name'},
                    {heading: 'Surgeon', sortInfo: 'surgicalBlock.provider.person.display'}];

                var attributesRelatedToBed = [{heading: 'Status Change Notes', sortInfo: 'notes'},
                    {heading: 'Bed Location', sortInfo: 'bedLocation'},
                    {heading: 'Bed ID', sortInfo: 'bedNumber'}];
                if ($rootScope.showPrimaryDiagnosisForOT != null && $rootScope.showPrimaryDiagnosisForOT != "") {
                    var primaryDiagnosisInfo = [{heading: 'Primary Diagnoses', sortInfo: 'patientObservations'}];
                    return listViewAttributes.concat(getSurgicalAttributesTableInfo(), attributesRelatedToBed, primaryDiagnosisInfo);
                } else {
                    return listViewAttributes.concat(getSurgicalAttributesTableInfo(), attributesRelatedToBed);
                }
            }

            function getFilteredSurgicalAttributeTypes () {
                var derivedSurgicalAttributes = ['estTimeHours', 'estTimeMinutes', 'cleaningTime'];
                return surgicalAppointmentHelper.getAttributeTypesByRemovingAttributeNames($rootScope.attributeTypes, derivedSurgicalAttributes);
            }

            function getSurgicalAttributesTableInfo () {
                return _.map($scope.filteredSurgicalAttributeTypes, function (attributeType) {
                    var attributeName = 'surgicalAppointmentAttributes.'.concat(attributeType.name, '.value');
                    return {
                        heading: attributeType.name,
                        sortInfo: attributeType.format === Bahmni.OT.Constants.providerSurgicalAttributeFormat ?
                            attributeName.concat('.person.display') : attributeName
                    };
                });
            }

            var filterSurgicalBlocksAndMapAppointmentsForDisplay = function (surgicalBlocks) {
                var clonedSurgicalBlocks = _.cloneDeep(surgicalBlocks);
                var filteredSurgicalBlocks = surgicalBlockFilter(clonedSurgicalBlocks, $scope.filterParams);
                var mappedSurgicalBlocks = _.map(filteredSurgicalBlocks, function (surgicalBlock) {
                    return surgicalBlockMapper.map(surgicalBlock, $rootScope.attributeTypes, $rootScope.surgeons);
                });
                mappedSurgicalBlocks = _.map(mappedSurgicalBlocks, function (surgicalBlock) {
                    var blockStartDatetime = surgicalBlock.startDatetime;
                    surgicalBlock.surgicalAppointments = _.map(surgicalBlock.surgicalAppointments, function (appointment) {
                        var mappedAppointment = _.cloneDeep(appointment);
                        mappedAppointment.surgicalBlock = surgicalBlock;
                        mappedAppointment.derivedAttributes = {};

                        var estTimeHours = mappedAppointment.surgicalAppointmentAttributes['estTimeHours'] && mappedAppointment.surgicalAppointmentAttributes['estTimeHours'].value;
                        var estTimeMinutes = mappedAppointment.surgicalAppointmentAttributes['estTimeMinutes'] && mappedAppointment.surgicalAppointmentAttributes['estTimeMinutes'].value;
                        var cleaningTime = mappedAppointment.surgicalAppointmentAttributes['cleaningTime'] && mappedAppointment.surgicalAppointmentAttributes['cleaningTime'].value;

                        mappedAppointment.derivedAttributes.duration = surgicalAppointmentHelper.getAppointmentDuration(
                            estTimeHours, estTimeMinutes, cleaningTime
                        );
                        mappedAppointment.derivedAttributes.expectedStartDate = moment(blockStartDatetime).startOf('day').toDate();
                        mappedAppointment.derivedAttributes.patientIdentifier = mappedAppointment.patient.display.split(' - ')[0];
                        mappedAppointment.derivedAttributes.patientAge = mappedAppointment.patient.person.age;
                        mappedAppointment.derivedAttributes.patientName = mappedAppointment.patient.display.split(' - ')[1];
                        if (mappedAppointment.status === Bahmni.OT.Constants.completed || mappedAppointment.status === Bahmni.OT.Constants.scheduled) {
                            mappedAppointment.derivedAttributes.expectedStartTime = blockStartDatetime;
                            blockStartDatetime = Bahmni.Common.Util.DateUtil.addMinutes(blockStartDatetime, mappedAppointment.derivedAttributes.duration);
                        }
                        return mappedAppointment;
                    });
                    surgicalBlock.surgicalAppointments = _.filter(surgicalBlock.surgicalAppointments, function (surgicalAppointment) {
                        if (surgicalAppointment.derivedAttributes.expectedStartTime) {
                            var surgicalAppointmentStartDateTime = surgicalAppointment.derivedAttributes.expectedStartTime;
                            var surgicalAppointmentEndDateTime = Bahmni.Common.Util.DateUtil.addMinutes(surgicalAppointmentStartDateTime, surgicalAppointment.derivedAttributes.duration);
                            return surgicalAppointmentStartDateTime < endDatetime && surgicalAppointmentEndDateTime > startDatetime;
                        }
                        return surgicalAppointment.derivedAttributes.expectedStartDate <= endDatetime
                            && surgicalAppointment.derivedAttributes.expectedStartDate >= startDatetime;
                    });
                    return surgicalBlock;
                });

                var surgicalAppointmentList = _.reduce(mappedSurgicalBlocks, function (surgicalAppointmentList, block) {
                    return surgicalAppointmentList.concat(block.surgicalAppointments);
                }, []);

                var filteredSurgicalAppointmentsByStatus = surgicalAppointmentHelper.filterSurgicalAppointmentsByStatus(
                    surgicalAppointmentList, _.map($scope.filterParams.statusList, function (status) {
                        return status.name;
                    }));

                var filteredSurgicalAppointmentsByPatient = surgicalAppointmentHelper.filterSurgicalAppointmentsByPatient(
                    filteredSurgicalAppointmentsByStatus, $scope.filterParams.patient);
                $scope.surgicalAppointmentList = _.sortBy(filteredSurgicalAppointmentsByPatient, ["derivedAttributes.expectedStartDate", "surgicalBlock.location.name", "derivedAttributes.expectedStartDatetime"]);
            };

            var init = function (startDatetime, endDatetime) {
                $scope.addActualTimeDisabled = true;
                $scope.editDisabled = true;
                $scope.cancelDisabled = true;
                $scope.reverseSort = false;
                $scope.sortColumn = "";
                return $q.all([surgicalAppointmentService.getSurgicalBlocksInDateRange(startDatetime, endDatetime, true, true)]).then(function (response) {
                    $scope.surgicalBlocks = response[0].data.results;
                    filterSurgicalBlocksAndMapAppointmentsForDisplay($scope.surgicalBlocks);
                });
            };

            $scope.isCurrentDateinWeekView = function (appointmentDate) {
                return _.isEqual(moment().startOf('day').toDate(), appointmentDate) && $scope.weekOrDay === 'week';
            };
            $scope.printPage = function () {
                var printTemplateUrl = appService.getAppDescriptor().getConfigValue("printListViewTemplateUrl") || 'views/listView.html';
                printer.print(printTemplateUrl, {
                    surgicalAppointmentList: $scope.surgicalAppointmentList,
                    weekStartDate: $scope.weekStartDate,
                    weekEndDate: $scope.weekEndDate,
                    viewDate: $scope.viewDate,
                    weekOrDay: $scope.weekOrDay,
                    isCurrentDate: $scope.isCurrentDateinWeekView
                });
            };

            $scope.sortSurgicalAppointmentsBy = function (sortColumn) {
                var emptyObjects = _.filter($scope.surgicalAppointmentList, function (appointment) {
                    return !_.property(sortColumn)(appointment);
                });
                var nonEmptyObjects = _.difference($scope.surgicalAppointmentList, emptyObjects);
                var sortedNonEmptyObjects = _.sortBy(nonEmptyObjects, sortColumn);
                if ($scope.reverseSort) {
                    sortedNonEmptyObjects.reverse();
                }
                $scope.surgicalAppointmentList = sortedNonEmptyObjects.concat(emptyObjects);
                $scope.sortColumn = sortColumn;
                $scope.reverseSort = !$scope.reverseSort;
            };

            $scope.selectSurgicalAppointment = function ($event, appointment) {
                $scope.$emit("event:surgicalAppointmentSelect", appointment, appointment.surgicalBlock);
                $event.stopPropagation();
            };

            $scope.deselectSurgicalAppointment = function ($event) {
                $scope.$emit("event:surgicalBlockDeselect");
                $event.stopPropagation();
            };

            $scope.$watch("viewDate", function () {
                if ($scope.weekOrDay === 'day') {
                    startDatetime = moment($scope.viewDate).toDate();
                    endDatetime = moment(startDatetime).endOf('day').toDate();
                    spinner.forPromise(init(startDatetime, endDatetime));
                }
            });

            $scope.$watch("weekStartDate", function () {
                if ($scope.weekOrDay === 'week') {
                    startDatetime = moment($scope.weekStartDate).toDate();
                    endDatetime = moment($scope.weekEndDate).endOf('day').toDate();
                    spinner.forPromise(init(startDatetime, endDatetime));
                }
            });

            $scope.$watch("filterParams", function (oldValue, newValue) {
                if (oldValue !== newValue) {
                    filterSurgicalBlocksAndMapAppointmentsForDisplay($scope.surgicalBlocks);
                }
            });

            $scope.isStatusPostponed = function (status) {
                return status === Bahmni.OT.Constants.postponed;
            };

            $scope.isStatusCancelled = function (status) {
                return status === Bahmni.OT.Constants.cancelled;
            };

            spinner.forPromise(init(startDatetime, endDatetime));
        }]);

'use strict';

angular.module('bahmni.ot').controller('moveSurgicalAppointmentController', ['$rootScope', '$scope', '$state', '$q', 'ngDialog', 'surgicalAppointmentService', 'surgicalAppointmentHelper', 'surgicalBlockHelper', 'messagingService',
    function ($rootScope, $scope, $state, $q, ngDialog, surgicalAppointmentService, surgicalAppointmentHelper, surgicalBlockHelper, messagingService) {
        var init = function () {
            $scope.surgicalAppointment = $scope.ngDialogData.surgicalAppointment;
            $scope.sourceSurgicalBlock = $scope.ngDialogData.surgicalBlock;
            $scope.appointmentDuration = surgicalAppointmentHelper.getEstimatedDurationForAppointment($scope.surgicalAppointment);
        };

        var surgicalBlockMapper = new Bahmni.OT.SurgicalBlockMapper();
        $scope.changeInSurgeryDate = function () {
            if (!$scope.dateForMovingSurgery) {
                $scope.availableSurgicalBlocksForGivenDate = [];
                return;
            }
            var startDateTime = $scope.dateForMovingSurgery;
            var endDateTime = moment($scope.dateForMovingSurgery).endOf("day").toDate();
            surgicalAppointmentService.getSurgicalBlocksInDateRange(startDateTime, endDateTime, false).then(function (response) {
                var surgicalBlocksOfThatDate = _.map(response.data.results, function (surgicalBlock) {
                    return surgicalBlockMapper.map(surgicalBlock, $rootScope.attributeTypes, $rootScope.surgeons);
                });
                $scope.availableBlocks = _.filter(surgicalBlocksOfThatDate, function (surgicalBlock) {
                    return surgicalBlockHelper.getAvailableBlockDuration(surgicalBlock) >= $scope.appointmentDuration && surgicalBlock.uuid !== $scope.ngDialogData.surgicalBlock.uuid;
                });
                $scope.availableSurgicalBlocksForGivenDate = _.map($scope.availableBlocks, function (surgicalBlock) {
                    var blockStartTime = Bahmni.Common.Util.DateUtil.formatTime(surgicalBlock.startDatetime);
                    var blockEndTime = Bahmni.Common.Util.DateUtil.formatTime(surgicalBlock.endDatetime);
                    var providerName = surgicalBlock.provider.person.display;
                    var operationTheatre = surgicalBlock.location.name;
                    var validAppointments = _.filter(surgicalBlock.surgicalAppointments, function (appointment) {
                        return appointment.status !== 'POSTPONED' && appointment.status !== 'CANCELLED';
                    });

                    var destinationBlockDetails = {
                        displayName: providerName + ", " + operationTheatre + " (" + blockStartTime + " - " + blockEndTime + ")",
                        uuid: surgicalBlock.uuid,
                        surgicalAppointment: {sortWeight: validAppointments.length}
                    };
                    return destinationBlockDetails;
                });
            });
        };

        $scope.cancel = function () {
            ngDialog.close();
        };

        var updateSortWeightOfSurgicalAppointments = function () {
            var surgicalBlock = _.cloneDeep($scope.sourceSurgicalBlock);
            var surgicalAppointments = _.filter(surgicalBlock.surgicalAppointments, function (appointment) {
                return appointment.uuid !== $scope.ngDialogData.surgicalAppointment.uuid && appointment.status !== 'POSTPONED' && appointment.status !== 'CANCELLED';
            });
            surgicalBlock.surgicalAppointments = _.map(surgicalAppointments, function (appointment, index) {
                appointment.sortWeight = index;
                return appointment;
            });
            surgicalBlock.provider = {uuid: surgicalBlock.provider.uuid};
            surgicalBlock.location = {uuid: surgicalBlock.location.uuid};
            surgicalBlock.surgicalAppointments = _.map(surgicalBlock.surgicalAppointments, function (appointment) {
                appointment.patient = {uuid: appointment.patient.uuid};
                appointment.surgicalAppointmentAttributes = _.values(appointment.surgicalAppointmentAttributes).filter(function (attribute) {
                    return !_.isUndefined(attribute.value);
                });
                return _.omit(appointment, ['derivedAttributes', 'surgicalBlock', 'bedNumber', 'bedLocation', 'patientObservations', 'primaryDiagnosis']);
            });

            return surgicalAppointmentService.updateSurgicalBlock(surgicalBlock);
        };

        $scope.moveSurgicalAppointment = function () {
            var surgicalAppointment = {
                uuid: $scope.surgicalAppointment.uuid,
                patient: {uuid: $scope.surgicalAppointment.patient.uuid},
                sortWeight: $scope.destinationBlock.surgicalAppointment.sortWeight,
                surgicalBlock: {uuid: $scope.destinationBlock.uuid}
            };
            surgicalAppointmentService.updateSurgicalAppointment(surgicalAppointment).then(function () {
                updateSortWeightOfSurgicalAppointments().then(function () {
                    messagingService.showMessage('info', "Surgical Appointment moved to the block " + $scope.destinationBlock.displayName + " Successfully");
                    ngDialog.close();
                    $state.go("otScheduling", {viewDate: $scope.dateForMovingSurgery}, {reload: true});
                });
            });
        };

        init();
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('otCalendar', [function () {
        return {
            restrict: 'E',
            controller: "otCalendarController",
            scope: {
                weekOrDay: "=",
                viewDate: "=",
                dayViewStart: "=",
                dayViewEnd: "=",
                dayViewSplit: "=",
                filterParams: "="
            },
            templateUrl: "../ot/views/otCalendar.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('otWeeklyCalendar', [function () {
        return {
            restrict: 'E',
            controller: "otCalendarController",
            scope: {
                weekOrDay: "=",
                weekStartDate: "=",
                viewDate: "=",
                dayViewStart: "=",
                dayViewEnd: "=",
                dayViewSplit: "=",
                filterParams: "="
            },
            templateUrl: "../ot/views/otWeeklyCalendar.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('otCalendarSurgicalBlock', ['surgicalAppointmentHelper', function (surgicalAppointmentHelper) {
        var link = function ($scope) {
            var totalWidthInPercentile = 96;
            var gridCellHeight = 120;
            var heightForSurgeonName = 21;
            var surgicalBlockHeightPerMin = gridCellHeight / $scope.dayViewSplit;
            $scope.operationTheatre = $scope.surgicalBlock.location.name;

            var getViewPropertiesForSurgicalBlock = function () {
                var surgicalBlockHeight = getHeightForSurgicalBlock();
                $scope.blockDimensions = {
                    height: surgicalBlockHeight,
                    width: $scope.weekOrDay === 'week' ? getWidthForSurgicalBlock() : totalWidthInPercentile,
                    top: getTopForSurgicalBlock(),
                    left: $scope.weekOrDay === 'week' ? getLeftPositionForSurgicalBlock() : 0,
                    color: getColorForProvider(),
                    appointmentHeightPerMin: (surgicalBlockHeight - heightForSurgeonName) / Bahmni.Common.Util.DateUtil.diffInMinutes(
                        getSurgicalBlockStartDateTimeBasedOnCalendarStartDateTime(), getSurgicalBlockEndDateTimeBasedOnCalendarEndDateTime())
                };
            };

            var getColorForProvider = function () {
                var otCalendarColorAttribute = _.find($scope.surgicalBlock.provider.attributes, function (attribute) {
                    return attribute.attributeType.display === 'otCalendarColor';
                });

                var hue = otCalendarColorAttribute && otCalendarColorAttribute.value ? otCalendarColorAttribute.value.toString() : "0";
                var backgroundColor = "hsl(" + hue + ", 100%, 90%)";
                var borderColor = "hsl(" + hue + ",100%, 60%)";
                return {
                    backgroundColor: backgroundColor,
                    borderColor: borderColor
                };
            };
            var getWidthForSurgicalBlock = function () {
                if ($scope.blockedOtsOfTheDay != null) {
                    return totalWidthInPercentile / $scope.blockedOtsOfTheDay.length;
                }
            };

            var getLeftPositionForSurgicalBlock = function () {
                var index = 1;
                if ($scope.blockedOtsOfTheDay != null) {
                    index = $scope.blockedOtsOfTheDay.indexOf(($scope.surgicalBlock.location.uuid));
                }
                return (index * getWidthForSurgicalBlock()) + 1;
            };
            var getHeightForSurgicalBlock = function () {
                return Bahmni.Common.Util.DateUtil.diffInMinutes(
                    getSurgicalBlockStartDateTimeBasedOnCalendarStartDateTime(), getSurgicalBlockEndDateTimeBasedOnCalendarEndDateTime()) * surgicalBlockHeightPerMin;
            };

            var getTopForSurgicalBlock = function () {
                var top = Bahmni.Common.Util.DateUtil.diffInMinutes(
                    getCalendarStartDateTime($scope.viewDate), $scope.surgicalBlock.startDatetime) * surgicalBlockHeightPerMin;
                return top > 0 ? top : 0;
            };
            var getCalendarStartDateTime = function (date) {
                var dayStart = ($scope.dayViewStart || Bahmni.OT.Constants.defaultCalendarStartTime).split(':');
                return Bahmni.Common.Util.DateUtil.addMinutes(moment(date).startOf('day'), (dayStart[0] * 60 + parseInt(dayStart[1])));
            };

            var getCalendarEndDateTime = function (date) {
                var dayEnd = ($scope.dayViewEnd || Bahmni.OT.Constants.defaultCalendarEndTime).split(':');
                return Bahmni.Common.Util.DateUtil.addMinutes(moment(date).startOf('day'), (dayEnd[0] * 60 + parseInt(dayEnd[1])));
            };

            var getSurgicalBlockStartDateTimeBasedOnCalendarStartDateTime = function () {
                return moment($scope.surgicalBlock.startDatetime).toDate() < getCalendarStartDateTime($scope.viewDate)
                    ? getCalendarStartDateTime($scope.viewDate) : $scope.surgicalBlock.startDatetime;
            };

            var getSurgicalBlockEndDateTimeBasedOnCalendarEndDateTime = function () {
                return getCalendarEndDateTime($scope.viewDate) < moment($scope.surgicalBlock.endDatetime).toDate()
                    ? getCalendarEndDateTime($scope.viewDate) : $scope.surgicalBlock.endDatetime;
            };

            var calculateEstimatedAppointmentDuration = function () {
                var surgicalAppointments = _.filter($scope.surgicalBlock.surgicalAppointments, function (surgicalAppointment) {
                    return $scope.isValidSurgicalAppointment(surgicalAppointment);
                });
                surgicalAppointments = _.sortBy(surgicalAppointments, ['sortWeight']);
                var nextAppointmentStartDatetime = moment($scope.surgicalBlock.startDatetime).toDate();
                $scope.surgicalBlock.surgicalAppointments = _.map(surgicalAppointments, function (surgicalAppointment) {
                    surgicalAppointment.derivedAttributes = {};
                    surgicalAppointment.derivedAttributes.duration = surgicalAppointmentHelper.getEstimatedDurationForAppointment(surgicalAppointment);
                    surgicalAppointment.derivedAttributes.expectedStartDatetime = nextAppointmentStartDatetime;
                    surgicalAppointment.derivedAttributes.expectedEndDatetime = Bahmni.Common.Util.DateUtil.addMinutes(nextAppointmentStartDatetime,
                        surgicalAppointment.derivedAttributes.duration);
                    surgicalAppointment.derivedAttributes.height = Bahmni.Common.Util.DateUtil.diffInMinutes(
                        surgicalAppointment.derivedAttributes.expectedStartDatetime < getCalendarStartDateTime($scope.viewDate)
                            ? getCalendarStartDateTime($scope.viewDate) : surgicalAppointment.derivedAttributes.expectedStartDatetime,
                        getCalendarEndDateTime($scope.viewDate) < surgicalAppointment.derivedAttributes.expectedEndDatetime
                            ? getCalendarEndDateTime($scope.viewDate) : surgicalAppointment.derivedAttributes.expectedEndDatetime
                    );
                    surgicalAppointment.primaryDiagnosis = new Bahmni.OT.SurgicalBlockMapper().mapPrimaryDiagnoses(surgicalAppointment.patientObservations);

                    nextAppointmentStartDatetime = surgicalAppointment.derivedAttributes.expectedEndDatetime;
                    return surgicalAppointment;
                });
            };

            $scope.isValidSurgicalAppointment = function (surgicalAppointment) {
                return surgicalAppointment.status !== Bahmni.OT.Constants.cancelled && surgicalAppointment.status !== Bahmni.OT.Constants.postponed;
            };

            $scope.canShowInCalendarView = function (surgicalAppointment) {
                return $scope.isValidSurgicalAppointment(surgicalAppointment)
                    && surgicalAppointment.derivedAttributes.expectedStartDatetime < getCalendarEndDateTime($scope.viewDate)
                    && surgicalAppointment.derivedAttributes.expectedEndDatetime > getCalendarStartDateTime($scope.viewDate);
            };

            $scope.selectSurgicalBlock = function ($event) {
                $scope.$emit("event:surgicalBlockSelect", $scope.surgicalBlock);
                $event.stopPropagation();
            };

            $scope.surgicalBlockExceedsCalendar = function () {
                return moment($scope.surgicalBlock.endDatetime).toDate() > getCalendarEndDateTime($scope.surgicalBlock.endDatetime);
            };

            var showToolTipForSurgicalBlock = function () {
                $('.surgical-block').tooltip({
                    content: function () {
                        return $(this).prop('title');
                    },
                    track: true
                });
            };

            getViewPropertiesForSurgicalBlock();
            calculateEstimatedAppointmentDuration();
            showToolTipForSurgicalBlock();
        };
        return {
            restrict: 'E',
            link: link,
            scope: {
                surgicalBlock: "=",
                blockedOtsOfTheDay: "=",
                dayViewStart: "=",
                dayViewEnd: "=",
                dayViewSplit: "=",
                filterParams: "=",
                weekOrDay: "=",
                viewDate: "="
            },
            templateUrl: "../ot/views/calendarSurgicalBlock.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('otNotes', [function () {
        return {
            restrict: 'E',
            require: '^otCalendar',
            templateUrl: "../ot/views/notesModal.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('otCalendarSurgicalAppointment', ['surgicalAppointmentHelper', 'appService', '$window', function (surgicalAppointmentHelper, appService, $window) {
        var link = function ($scope) {
            $scope.attributes = surgicalAppointmentHelper.getSurgicalAttributes($scope.surgicalAppointment);
            var patientUrls = appService.getAppDescriptor().getConfigValue("patientDashboardUrl");
            $scope.patientDashboardUrl = patientUrls && patientUrls.link && appService.getAppDescriptor().formatUrl(patientUrls.link, {'patientUuid': $scope.surgicalAppointment.patient.uuid});
            $scope.goToForwardUrl = function ($event) {
                $window.open($scope.patientDashboardUrl);
                $event.stopPropagation();
            };

            var hasAppointmentStatusInFilteredStatusList = function () {
                if (_.isEmpty($scope.filterParams.statusList)) {
                    return true;
                }
                return _.find($scope.filterParams.statusList, function (selectedStatus) {
                    return selectedStatus.name === $scope.surgicalAppointment.status;
                });
            };

            var hasAppointmentIsOfTheFilteredPatient = function () {
                if (_.isEmpty($scope.filterParams.patient)) {
                    return true;
                }
                return $scope.surgicalAppointment.patient.uuid === $scope.filterParams.patient.uuid;
            };

            $scope.canTheSurgicalAppointmentBeShown = function () {
                return hasAppointmentIsOfTheFilteredPatient() && hasAppointmentStatusInFilteredStatusList();
            };

            var getDataForSurgicalAppointment = function () {
                $scope.height = getHeightForSurgicalAppointment();
                $scope.patient = surgicalAppointmentHelper.getPatientDisplayLabel($scope.surgicalAppointment.patient.display);
            };

            var getHeightForSurgicalAppointment = function () {
                return $scope.surgicalAppointment.derivedAttributes.height * $scope.heightPerMin;
            };

            $scope.selectSurgicalAppointment = function ($event) {
                $scope.$emit("event:surgicalAppointmentSelect", $scope.surgicalAppointment, $scope.$parent.surgicalBlock);
                $event.stopPropagation();
            };

            var showToolTipForSurgery = function () {
                $('.surgical-block-appointment').tooltip({
                    content: function () {
                        return $(this).prop('title');
                    },
                    track: true
                });
            };

            getDataForSurgicalAppointment();
            showToolTipForSurgery();
        };
        return {
            restrict: 'E',
            link: link,
            scope: {
                surgicalAppointment: "=",
                weekOrDay: "=",
                operationTheatre: "=",
                heightPerMin: "=",
                backgroundColor: "=",
                filterParams: "="

            },
            templateUrl: "../ot/views/calendarSurgicalAppointment.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('multiSelectAutocomplete', [function () {
        var link = function ($scope, element) {
            $scope.focusOnTheTest = function () {
                var autoselectInput = $("input.input");
                autoselectInput[0].focus();
            };
            $scope.addItem = function (item) {
                item[item.name] = true;
                $scope.selectedValues = _.union($scope.selectedValues, item, $scope.keyProperty);
            };

            $scope.removeItem = function (item) {
                $scope.selectedValues = _.filter($scope.selectedValues, function (value) {
                    return value[$scope.keyProperty] !== item[$scope.keyProperty];
                });
            };

            $scope.search = function (query) {
                var matchingAnswers = [];
                var unselectedValues = _.xorBy($scope.inputItems, $scope.selectedValues, $scope.keyProperty);
                _.forEach(unselectedValues, function (answer) {
                    if (typeof answer.name != "object" && answer.name.toLowerCase().indexOf(query.toLowerCase()) !== -1) {
                        matchingAnswers.push(answer);
                    }
                });
                return _.uniqBy(matchingAnswers, $scope.keyProperty);
            };
        };
        return {
            restrict: 'E',
            link: link,
            scope: {
                inputItems: "=",
                selectedValues: "=",
                displayProperty: "=",
                keyProperty: "=",
                placeholder: "=",
                loadOnDownArrow: "=",
                autoCompleteMinLength: "="
            },
            templateUrl: "../ot/views/multiSelectAutocomplete.html"
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .directive('stringToNumber', function () {
        return {
            require: 'ngModel',
            link: function (scope, elem, attrs, ngModel) {
                if (attrs.type === 'number') {
                    ngModel.$formatters.push(function (value) {
                        return parseFloat(value);
                    });
                }
            }
        };
    });

'use strict';

angular.module('bahmni.ot')
    .directive('listView', [function () {
        return {
            restrict: 'E',
            controller: "listViewController",
            scope: {
                viewDate: "=",
                filterParams: "=",
                weekStartDate: "=",
                weekEndDate: "=",
                weekOrDay: "="
            },
            templateUrl: "../ot/views/listView.html"
        };
    }]);

'use strict';

angular.module("bahmni.ot")
    .directive("onScroll", [function () {
        var link = function ($scope, $element, attrs) {
            $element.bind('scroll', function (evt) {
                // Please dont remove or alter the below class name
                $('.calendar-location').css("top", $element.scrollTop());
                $('.calendar-time-container').css("left", $element.scrollLeft());
            });
        };
        return {
            restrict: "A",
            link: link
        };
    }]);

'use strict';

angular.module("bahmni.ot")
    .directive("onHorizontalScroll", [function () {
        var link = function (scope, element, attrs) {
            var divTag = document.getElementsByClassName(attrs.onHorizontalScroll)[0];
            element.on('scroll', function () {
                divTag.scrollLeft = element[0].scrollLeft;
            });
        };
        return {
            restrict: "A",
            link: link
        };
    }]);

'use strict';

Bahmni.OT.SurgicalBlockMapper = function () {
    var mapSelectedOtherSurgeon = function (otherSurgeonAttribute, surgeonList) {
        var selectedOtherSurgeon = _.filter(surgeonList, function (surgeon) {
            return surgeon.id === parseInt(otherSurgeonAttribute.value);
        });
        otherSurgeonAttribute.value = _.isEmpty(selectedOtherSurgeon) ? null : selectedOtherSurgeon[0];
    };

    var mapOpenMrsSurgicalAppointmentAttributes = function (openMrsSurgicalAppointmentAttributes, surgeonsList) {
        var mappedAttributes = {};
        _.each(openMrsSurgicalAppointmentAttributes, function (attribute) {
            var attributeName = attribute.surgicalAppointmentAttributeType.name;
            mappedAttributes[attributeName] = {
                id: attribute.id,
                uuid: attribute.uuid,
                value: attribute.value,
                surgicalAppointmentAttributeType: {
                    uuid: attribute.surgicalAppointmentAttributeType.uuid,
                    name: attribute.surgicalAppointmentAttributeType.name
                }
            };
        });
        var otherSurgeonnAttribute = mappedAttributes['otherSurgeon'];
        if (otherSurgeonnAttribute) {
            mapSelectedOtherSurgeon(otherSurgeonnAttribute, surgeonsList);
        }
        return mappedAttributes;
    };

    var mapPrimaryDiagnoses = function (diagnosisObs) {
        var uniqueDiagnoses = new Map();
        _.each(diagnosisObs, function (diagnosis) {
            var existingDiagnosis = uniqueDiagnoses.get(diagnosis.display);
            if (existingDiagnosis) {
                if (existingDiagnosis.obsDatetime < diagnosis.obsDatetime) {
                    uniqueDiagnoses.set(diagnosis.display, diagnosis);
                }
            } else {
                uniqueDiagnoses.set(diagnosis.display, diagnosis);
            }
        });
        var primaryDiagnosesNames = _.filter(Array.from(uniqueDiagnoses.values()), function (diagnosis) {
            var obsGroupList = diagnosis.obsGroup.display.split(": ")[1].split(", ");
            return _.includes(obsGroupList, "Primary") && !(_.includes(obsGroupList, "Ruled Out Diagnosis"));
        }).map(function (diagnosis) {
            if (diagnosis.concept.display == "Non-coded Diagnosis") {
                return diagnosis.value;
            }
            return diagnosis.value.display;
        }).join(", ");
        return primaryDiagnosesNames;
    };

    var mapSurgicalAppointment = function (openMrsSurgicalAppointment, attributeTypes, surgeonsList) {
        var surgicalAppointmentAttributes = mapOpenMrsSurgicalAppointmentAttributes(openMrsSurgicalAppointment.surgicalAppointmentAttributes, surgeonsList);
        return {
            id: openMrsSurgicalAppointment.id,
            uuid: openMrsSurgicalAppointment.uuid,
            voided: openMrsSurgicalAppointment.voided || false,
            patient: openMrsSurgicalAppointment.patient,
            sortWeight: openMrsSurgicalAppointment.sortWeight,
            actualStartDatetime: Bahmni.Common.Util.DateUtil.parseServerDateToDate(openMrsSurgicalAppointment.actualStartDatetime),
            actualEndDatetime: Bahmni.Common.Util.DateUtil.parseServerDateToDate(openMrsSurgicalAppointment.actualEndDatetime),
            notes: openMrsSurgicalAppointment.notes,
            status: openMrsSurgicalAppointment.status,
            bedLocation: (openMrsSurgicalAppointment.bedLocation || ""),
            bedNumber: (openMrsSurgicalAppointment.bedNumber || ""),
            surgicalAppointmentAttributes: new Bahmni.OT.SurgicalBlockMapper().mapAttributes(surgicalAppointmentAttributes, attributeTypes),
            primaryDiagnosis: mapPrimaryDiagnoses(openMrsSurgicalAppointment.patientObservations) || ""
        };
    };

    this.map = function (openMrsSurgicalBlock, attributeTypes, surgeonsList) {
        var surgicalAppointments = _.map(openMrsSurgicalBlock.surgicalAppointments, function (surgicalAppointment) {
            return mapSurgicalAppointment(surgicalAppointment, attributeTypes, surgeonsList);
        });
        return {
            id: openMrsSurgicalBlock.id,
            uuid: openMrsSurgicalBlock.uuid,
            voided: openMrsSurgicalBlock.voided || false,
            startDatetime: Bahmni.Common.Util.DateUtil.parseServerDateToDate(openMrsSurgicalBlock.startDatetime),
            endDatetime: Bahmni.Common.Util.DateUtil.parseServerDateToDate(openMrsSurgicalBlock.endDatetime),
            provider: openMrsSurgicalBlock.provider,
            location: openMrsSurgicalBlock.location,
            surgicalAppointments: _.sortBy(surgicalAppointments, 'sortWeight')
        };
    };

    var mapSurgicalAppointmentAttributesUIToDomain = function (appointmentAttributes) {
        var attributes = _.cloneDeep(appointmentAttributes);
        var otherSurgeon = attributes['otherSurgeon'];
        otherSurgeon.value = otherSurgeon.value && otherSurgeon.value.id;
        return _.values(attributes).filter(function (attribute) {
            return !_.isUndefined(attribute.value);
        }).map(function (attribute) {
            attribute.value = !_.isNull(attribute.value) && attribute.value.toString() || "";
            return attribute;
        });
    };

    var mapSurgicalAppointmentUIToDomain = function (surgicalAppointmentUI) {
        return {
            id: surgicalAppointmentUI.id,
            uuid: surgicalAppointmentUI.uuid,
            voided: surgicalAppointmentUI.voided || false,
            patient: {uuid: surgicalAppointmentUI.patient.uuid},
            actualStartDatetime: surgicalAppointmentUI.actualStartDatetime,
            actualEndDatetime: surgicalAppointmentUI.actualEndDatetime,
            sortWeight: surgicalAppointmentUI.sortWeight,
            notes: surgicalAppointmentUI.notes,
            status: surgicalAppointmentUI.status,
            surgicalAppointmentAttributes: mapSurgicalAppointmentAttributesUIToDomain(surgicalAppointmentUI.surgicalAppointmentAttributes)
        };
    };

    this.mapSurgicalBlockUIToDomain = function (surgicalBlockUI) {
        return {
            id: surgicalBlockUI.id,
            uuid: surgicalBlockUI.uuid,
            voided: surgicalBlockUI.voided || false,
            startDatetime: surgicalBlockUI.startDatetime,
            endDatetime: surgicalBlockUI.endDatetime,
            provider: {uuid: surgicalBlockUI.provider.uuid},
            location: {uuid: surgicalBlockUI.location.uuid},
            surgicalAppointments: _.map(surgicalBlockUI.surgicalAppointments, function (surgicalAppointment) {
                return mapSurgicalAppointmentUIToDomain(surgicalAppointment);
            })
        };
    };

    var getAttributeTypeByName = function (attributeTypes, name) {
        return _.find(attributeTypes, function (attributeType) {
            return attributeType.name === name;
        });
    };

    this.mapAttributes = function (attributes, attributeTypes) {
        _.each(attributeTypes, function (attributeType) {
            var existingAttribute = attributes[attributeType.name];
            if (!existingAttribute) {
                attributes[attributeType.name] = {
                    surgicalAppointmentAttributeType: getAttributeTypeByName(attributeTypes, attributeType.name)
                };
                if (attributeType.name === "cleaningTime") {
                    attributes[attributeType.name].value = 15;
                } else if (attributeType.name === "estTimeMinutes") {
                    attributes[attributeType.name].value = 0;
                } else if (attributeType.name === "estTimeHours") {
                    attributes[attributeType.name].value = 0;
                } else {
                    attributes[attributeType.name].value = "";
                }
            }
        });
        return attributes;
    };

    this.mapPrimaryDiagnoses = mapPrimaryDiagnoses;
};

'use strict';

angular.module('bahmni.ot')
    .filter('surgicalBlock', [function () {
        var filterByLocation = function (surgicalBlocks, filters) {
            var blocksFilteredByLocation = [];
            _.forEach(surgicalBlocks, function (block) {
                filters.locations[block.location.name] ? blocksFilteredByLocation.push(block) : '';
            });
            return blocksFilteredByLocation;
        };

        var filterByProvider = function (blocksFilteredByLocation, filters) {
            if (_.isEmpty(filters.providers)) {
                return blocksFilteredByLocation;
            }
            var blocksFilteredByProvider = _.filter(blocksFilteredByLocation, function (block) {
                return _.find(filters.providers, function (provider) {
                    return provider.uuid === block.provider.uuid;
                });
            });
            return blocksFilteredByProvider;
        };

        var filterByPatientUuid = function (blocksFilteredByProviders, filters) {
            if (_.isEmpty(filters.patient)) {
                return blocksFilteredByProviders;
            }
            return _.filter(blocksFilteredByProviders, function (block) {
                return _.find(block.surgicalAppointments, function (appointment) {
                    return appointment.patient.uuid === filters.patient.uuid;
                });
            });
        };

        var filterByAppointmentStatus = function (blocksFilteredByPatient, filters) {
            if (_.isEmpty(filters.statusList)) {
                return blocksFilteredByPatient;
            }
            return _.filter(blocksFilteredByPatient, function (block) {
                return _.find(block.surgicalAppointments, function (appointment) {
                    return _.find(filters.statusList, function (status) {
                        return status.name === appointment.status;
                    });
                });
            });
        };

        var filterByPatientAndStatus = function (blocksFilteredByProviders, filters) {
            if (_.isEmpty(filters.statusList) || _.isEmpty(filters.patient)) {
                var blocksFilteredByPatient = filterByPatientUuid(blocksFilteredByProviders, filters);
                return filterByAppointmentStatus(blocksFilteredByPatient, filters);
            }
            return _.filter(blocksFilteredByProviders, function (block) {
                return _.find(block.surgicalAppointments, function (appointment) {
                    return appointment.patient.uuid === filters.patient.uuid && _.find(filters.statusList, function (status) {
                        return status.name === appointment.status;
                    });
                });
            });
        };
        return function (surgicalBlocks, filters) {
            if (!filters) {
                return surgicalBlocks;
            }
            var blocksFilteredByLocation = filterByLocation(surgicalBlocks, filters);
            var blocksFilteredByProviders = filterByProvider(blocksFilteredByLocation, filters);
            return filterByPatientAndStatus(blocksFilteredByProviders, filters);
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .service('surgicalAppointmentService', ['$http', 'appService', function ($http, appService) {
        this.getSurgeons = function () {
            return $http.get(Bahmni.Common.Constants.providerUrl, {
                method: "GET",
                params: {v: "custom:(id,uuid,person:(uuid,display),attributes:(attributeType:(display),value))"},
                withCredentials: true
            });
        };

        this.saveSurgicalBlock = function (data) {
            return $http.post(Bahmni.OT.Constants.addSurgicalBlockUrl, data, {
                params: {v: "full"},
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.updateSurgicalBlock = function (data) {
            return $http.post(Bahmni.OT.Constants.addSurgicalBlockUrl + '/' + data.uuid, data, {
                params: {v: "full"},
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.updateSurgicalAppointment = function (data) {
            return $http.post(Bahmni.OT.Constants.updateSurgicalAppointmentUrl + "/" + data.uuid, data, {
                params: {v: "full"},
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.getSurgicalAppointmentAttributeTypes = function () {
            return $http.get(Bahmni.OT.Constants.surgicalAppointmentAttributeTypeUrl, {
                method: "GET",
                params: {v: "custom:(uuid,name,format)"},
                withCredentials: true
            });
        };

        this.getSurgicalBlockFor = function (surgicalBlockUuid) {
            return $http.get(Bahmni.OT.Constants.addSurgicalBlockUrl + "/" + surgicalBlockUuid, {
                params: {v: "full"},
                withCredentials: true,
                headers: {"Accept": "application/json", "Content-Type": "application/json"}
            });
        };

        this.getSurgicalBlocksInDateRange = function (startDatetime, endDatetime, includeVoided, activeBlocks) {
            var additionalCustomParam = appService.getAppDescriptor().getConfigValue("additionalCustomParam");
            return $http.get(Bahmni.OT.Constants.addSurgicalBlockUrl, {
                method: "GET",
                params: {
                    startDatetime: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(startDatetime),
                    endDatetime: Bahmni.Common.Util.DateUtil.parseLongDateToServerFormat(endDatetime),
                    includeVoided: includeVoided || false,
                    activeBlocks: activeBlocks || false,
                    v: "custom:(id,uuid," +
                    "provider:(uuid,person:(uuid,display),attributes:(attributeType:(display),value,voided))," +
                    "location:(uuid,name),startDatetime,endDatetime,surgicalAppointments:(id,uuid,patient:(uuid,display,person:(age,gender,birthdate))," +
                    "actualStartDatetime,actualEndDatetime,status,notes,sortWeight,bedNumber,bedLocation,surgicalAppointmentAttributes" +
                    (additionalCustomParam ? "," + additionalCustomParam : "") + "))"
                },
                withCredentials: true
            });
        };

        this.getPrimaryDiagnosisConfigForOT = function () {
            return $http.get(Bahmni.Common.Constants.globalPropertyUrl, {
                method: "GET",
                params: {
                    property: 'obs.conceptMappingsForOT'
                },
                withCredentials: true,
                headers: {
                    Accept: 'text/plain'
                }
            });
        };
        this.getBulkNotes = function (startDate, endDate) {
            return $http.get(Bahmni.OT.Constants.notesUrl, {
                method: 'GET',
                params: {
                    noteType: 'OT Module',
                    noteStartDate: startDate,
                    noteEndDate: endDate
                },
                withCredentials: true
            });
        };
    }]);

'use strict';

angular.module('bahmni.ot')
    .service('queryService', ['$http', function ($http) {
        this.getResponseFromQuery = function (params) {
            return $http.get(Bahmni.Common.Constants.sqlUrl, {
                method: "GET",
                params: params,
                withCredentials: true
            });
        };
    }]);
