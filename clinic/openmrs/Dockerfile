# Native arm64 OpenMRS, built only by openmrs/build.sh from trees it copies out of the amd64 image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Tools the /openmrs/*.sh scripts call, plus what the base lacks.
RUN yum install -y mysql gettext acl curl tar gzip shadow-utils procps-ng \
    && yum clean all && rm -rf /var/cache/yum

# The source image's four runtime trees.
COPY tomcat /usr/local/tomcat
COPY openmrs /openmrs
COPY bahmni-emr /etc/bahmni-emr
COPY bahmni-home /home/bahmni

# Drop Tomcat's x86-only APR connector; Tomcat falls back to NIO.
RUN rm -rf /usr/local/tomcat/native-jni-lib

# The source image's ENV, without the native-library paths.
ENV CATALINA_HOME=/usr/local/tomcat \
    PATH=/usr/local/tomcat/bin:$PATH \
    LANG=C.UTF-8 \
    TOMCAT_MAJOR=8 \
    TOMCAT_VERSION=8.5.100 \
    JMX_PROMETHEUS_JAVAAGENT_VERSION=0.18.0 \
    OPENMRS_APPLICATION_DATA_DIRECTORY=/openmrs/data \
    OMRS_DB_EXTRA_ARGS="&zeroDateTimeBehavior=convertToNull"

WORKDIR /openmrs
EXPOSE 8080
CMD ["./bahmni_startup.sh"]
