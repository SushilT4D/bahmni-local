# Use the original openmrs image as the base image
# Base image can be overridden via build arg
ARG BASE_IMAGE=openmrs:trojan-0.2
FROM ${BASE_IMAGE}

# Switch to root to modify the filesystem
USER root

# Install required packages
RUN yum install -y gettext acl mysql nc procps-ng && yum clean all

# Remove the existing /openmrs directory and copy from extracted directory
RUN rm -rf /openmrs
COPY ./temp-build/openmrs /openmrs

# Copy /etc/bahmni-emr and /etc/bahmni directories from the second image
COPY ./bahmni-emr /etc/bahmni-emr
COPY ./bahmni-config /etc/bahmni
# COPY ./bahmni_home /openmrs/bahmni_home
# COPY ./data /openmrs/data

# Set environment variables
ENV GPG_KEYS="05AB33110949707C93A279E3D3EFE6B686867BA6 07E48665A34DCAFAE522E5E6266191C37C037D42 47309207D818FFD8DCD3F83F1931D684307A10A5 541FBE7D8F78B25E055DDEE13C370389288584E7 5C3C5F3E314C866292F359A8F3AD5C94A67F707E 765908099ACF92702C7D949BFA0C35EA8AA299F1 79F7026C690BAA50B92CD8B66A3AD3F4F22C4FED 9BA44C2621385CB966EBA586F72C284D731FABEE A27677289986DB50844682F8ACB77FC2E86E29AC A9C5DF4D22E99998D9875A5110C01C5A2F6059E7 DCFD35E0BF8CA7344752DE8B6FB21E8933C60243 F3A04C595DB5B6A5F1ECA43E3B7BBB100D811BBE F7DA48BB64BCB84ECBA7EE6935CD23C10D498E23" \
    JMX_PROMETHEUS_JAVAAGENT_VERSION=0.18.0 \
    OPENMRS_APPLICATION_DATA_DIRECTORY=/openmrs/data \
    OMRS_DB_EXTRA_ARGS=&zeroDateTimeBehavior=convertToNull

# Fix permissions for user 1001 and make scripts executable
RUN chown -R 1001:0 /openmrs && \
    chmod -R g+rw /openmrs && \
    chmod +x /openmrs/*.sh

# Switch back to user 1001
USER 1001

# Set working directory
WORKDIR /openmrs

CMD ["./bahmni_startup.sh"]
