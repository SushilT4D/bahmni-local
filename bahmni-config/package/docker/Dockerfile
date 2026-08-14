FROM infoiplitin/clinic-config-indiadistro:1.1.0-44

# this command to build bahmni-config image locally before starting service on any server
# docker compose stop bahmni-config
# docker compose build bahmni-config
# docker compose up -d bahmni-config

USER root

RUN apk add acl

RUN chmod -R 0777 /etc/bahmni_config/openmrs/

RUN echo 'Running some bahmni_config commands'

COPY bahmni-config/resources/apps/home/whiteLabel.json /etc/bahmni_config/openmrs/apps/home/

COPY bahmni-config/resources/bahmniforms/*.* /etc/bahmni_config/masterdata/configuration/bahmniforms/

RUN rm -rf /etc/bahmni_config/masterdata/configuration/addresshierarchy

# RUN mkdir -p /etc/bahmni_config/openmrs/apps/ipd
# RUN mkdir -p /etc/bahmni_config/openmrs/apps/adt

# COPY  bahmni-config/resources/apps/ipd/*.* /etc/bahmni_config/openmrs/apps/ipd/
# COPY  bahmni-config/resources/apps/adt/*.* /etc/bahmni_config/openmrs/apps/adt/

COPY bahmni-config/resources/apps/home/extension.json /etc/bahmni_config/openmrs/apps/home/extension.json

COPY bahmni-config/resources/apps/admin/extension.json /etc/bahmni_config/openmrs/apps/admin/extension.json

COPY bahmni-config/resources/apps/clinical/visit.json /etc/bahmni_config/openmrs/apps/clinical/visit.json

#COPY bahmni-config/resources/apps/registration/registrationCardLayout/print.html /etc/bahmni_config/openmrs/apps/registration/registrationCardLayout/

COPY bahmni-config/resources/apps/registration/registrationCardLayout/bahmniLogo.png /etc/bahmni_config/openmrs/apps/registration/registrationCardLayout/images/

#COPY bahmni-config/resources/apps/registration/locale_en.json /etc/bahmni_config/openmrs/i18n/registration/locale_en.json

 COPY bahmni-config/resources/apps/registration/app.json /etc/bahmni_config/openmrs/apps/registration/app.json

 COPY bahmni-config/resources/apps/clinical/app.json /etc/bahmni_config/openmrs/apps/clinical/app.json

 COPY bahmni-config/resources/apps/clinical/extension.json /etc/bahmni_config/openmrs/apps/clinical/extension.json

 COPY bahmni-config/resources/apps/clinical/locale_en.json /etc/bahmni_config/openmrs/i18n/clinical/locale_en.json

 COPY bahmni-config/resources/apps/clinical/dashboard.json /etc/bahmni_config/openmrs/apps/clinical/dashboard.json

#COPY bahmni-config/resources/apps/clinical/medication.json /etc/bahmni_config/openmrs/apps/clinical/medication.json

COPY bahmni-config/resources/apps/reports/app.json /etc/bahmni_config/openmrs/apps/reports/app.json

COPY bahmni-config/resources/apps/reports/extension.json /etc/bahmni_config/openmrs/apps/reports/extension.json

COPY bahmni-config/resources/apps/reports/reports.json /etc/bahmni_config/openmrs/apps/reports/reports.json

COPY bahmni-config/resources/apps/home/whiteLabel.json /etc/bahmni_config/openmrs/apps/home/whiteLabel.json

COPY bahmni-config/resources/apps/reports/sql /etc/bahmni_config/openmrs/apps/reports/sql

RUN chmod -R 0777 /etc/bahmni_config/openmrs/
RUN setfacl -dR -m o::rwx -m g::rwx /etc/bahmni_config/openmrs/
