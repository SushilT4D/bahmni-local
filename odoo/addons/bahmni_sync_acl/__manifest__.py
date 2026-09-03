# -*- coding: utf-8 -*-
{
    'name': 'Bahmni Sync ACL',
    'version': '10.0.1.0.0',
    'category': 'Bahmni',
    'summary': 'Expose sync_origin to the ORM and restrict clinic visibility with record rules',
    'description': """
Every Bahmni node holds every node's Odoo data, because the CDC pipeline replicates the
twelve synced business tables in full. Physical possession is therefore NOT the access
boundary -- Odoo's own record rules are.

The write-origin guard already stamps each row with the node that authored it, in a
sync_origin column maintained by a database trigger. That column is the only clinic
dimension present on ALL twelve tables: stock_move and sale_order carry location_id and
warehouse_id, but res_partner carries neither, so no stock-based rule can scope patients.

This module makes sync_origin visible to the ORM (a raw column is invisible to record
rules) and adds one rule per model: a user sees rows their own clinic authored, unless
they hold the 'All Clinics' group.

DELIBERATE LIMITATION, STATED RATHER THAN HIDDEN. sync_origin records who CREATED a row,
not who may legitimately need it. A patient registered at Rawach and later seen at
Ghated stays sync_origin='rawach', so Ghated staff will not see them by default. That is
the unresolved catchment question, not an implementation defect -- and the fix is a
policy decision about cross-clinic access, not a different column. Until that is
decided, the escape hatch is the All Clinics group.
""",
    'depends': ['base', 'sale', 'stock', 'account'],
    'data': [
        'security/sync_acl_groups.xml',
        'security/sync_acl_rules.xml',
    ],
    'installable': True,
    'auto_install': False,
}
