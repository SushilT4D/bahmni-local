# bahmni/odoo-connect plus the HttpClient 5 jars it calls but does not ship, and a quieter logback.xml.
ARG ODOO_CONNECT_IMAGE_TAG
FROM bahmni/odoo-connect:${ODOO_CONNECT_IMAGE_TAG}

COPY lib/httpclient5-5.1.4.jar lib/httpcore5-5.1.5.jar lib/httpcore5-h2-5.1.5.jar \
     /run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/lib/
COPY logback.xml /run/bahmni-erp-connect/bahmni-erp-connect/WEB-INF/classes/logback.xml
