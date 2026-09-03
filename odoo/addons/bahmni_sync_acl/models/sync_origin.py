# -*- coding: utf-8 -*-
"""Expose the sync_origin column to the ORM, and give res.users a home clinic.

sync_origin is written by a PostgreSQL BEFORE trigger (odoo/apply-odoo-write-origin-
guard.sql), never by Odoo. The field is therefore readonly and, crucially, declared with
store=True and no compute: Odoo must read the existing column rather than manage it.

WHY NOT A NEW COLUMN: the column already exists on all twelve tables and carries live
sync semantics. Declaring the field with the same name binds the ORM to it. Odoo's
schema updater will see a matching column of matching type and leave it alone.
"""
from odoo import models, fields

SYNCED_MODELS = [
    'res.partner',
    'product.template', 'product.product', 'product.category', 'product.uom',
    'sale.order', 'sale.order.line',
    'stock.move', 'stock.quant', 'stock.picking',
    'account.invoice', 'account.invoice.line',
]


class SyncOriginMixin(models.AbstractModel):
    _name = 'bahmni.sync.origin.mixin'

    sync_origin = fields.Char(
        string='Origin Node',
        size=16,
        readonly=True,
        index=True,
        help="Node that authored this row. Written by a database trigger during the "
             "write, never by Odoo. Used by the clinic visibility record rules.",
    )


def _inject(model_name):
    """Attach the field to an existing model without touching its own source."""
    class _Injected(models.Model):
        _inherit = model_name

        sync_origin = fields.Char(
            string='Origin Node', size=16, readonly=True, index=True,
            help="Node that authored this row; maintained by a database trigger.",
        )
    _Injected.__name__ = 'SyncOrigin_' + model_name.replace('.', '_')
    return _Injected


for _m in SYNCED_MODELS:
    _inject(_m)


class ResUsers(models.Model):
    _inherit = 'res.users'

    clinic_code = fields.Char(
        string='Home Clinic Code',
        size=16,
        help="Must match the sync_origin value this clinic stamps -- e.g. 'rawach', "
             "'ghated', 'cloud'. The clinic visibility rule compares the two directly, "
             "so a mismatch or a blank value means the user sees NOTHING rather than "
             "everything. That is the intended failure direction.",
    )
