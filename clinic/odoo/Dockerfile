# Native arm64 build of ODOO_BAHMNI_IMAGE, which Bahmni publishes for amd64 only.
ARG ODOO_BAHMNI_IMAGE
ARG ODOO_BASE_IMAGE

FROM --platform=linux/amd64 ${ODOO_BAHMNI_IMAGE} AS bahmni

FROM ${ODOO_BASE_IMAGE}

USER root
COPY --from=bahmni --chown=odoo:odoo /opt/bahmni-erp/bahmni-addons /opt/bahmni-erp/bahmni-addons
COPY --from=bahmni --chown=odoo:odoo /etc/odoo/odoo.conf /etc/odoo/odoo.conf
RUN pip3 install python-decouple

ENV ADDON_PATH=/opt/bahmni-erp/bahmni-addons
USER odoo
CMD ["odoo", "-u", "all", "-i", "sale_management,purchase,stock,point_of_sale,l10n_generic_coa,bahmni_account,bahmni_product,bahmni_api_feed,bahmni_stock,bahmni_purchase,bahmni_address_mapping,bahmni_sale,restful_api,bahmni_reports,bahmni_auto_payment_reconciliation", "--without-demo", "-d odoo"]
