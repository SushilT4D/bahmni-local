# -*- coding: utf-8 -*-
{
    'name': 'Bahmni Sync ACL',
    'version': '10.0.1.0.0',
    'category': 'Bahmni',
    'summary': 'Empty shell: sync_origin column dropped 2026-09-09 (F-049); kept installed so -u all cleans its fields',
    'description': """
Every Bahmni node holds every node's Odoo data, because the CDC pipeline replicates the
twelve synced business tables in full. This module binds the trigger-maintained
sync_origin column to the ORM (so Odoo's schema updater leaves it alone) and gives
res.users a Home Clinic Code.

ACL DROPPED 2026-09-07 (operator decision, lab-verified). The clinic-visibility record
rules that shipped on 2026-09-04 keyed on sync_origin, which means LAST WRITER, not
owner: a head-office edit restamped a Rawach partner 'cloud' and Rawach users lost
sight of their own patient (F-040). Rather than scope on a mutable column, Odoo is
now treated like OpenELIS: every node's users see every node's rows, and per-clinic
stock isolation comes from Odoo's own warehouse/location model. If BHS later asks for
clinic isolation, add a STABLE ownership column (set on insert, never on update) and
key rules on that -- never on sync_origin.

The module stays installed rather than uninstalled on purpose: uninstalling would make
Odoo drop the sync_origin columns, which the publication row filters and the
write-origin triggers depend on.
""",
    'depends': ['base', 'sale', 'stock', 'account'],
    'data': [],
    'installable': True,
    'auto_install': False,
}
