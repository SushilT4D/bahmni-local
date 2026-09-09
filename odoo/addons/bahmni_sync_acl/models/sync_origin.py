# -*- coding: utf-8 -*-
"""bahmni_sync_acl -- now an empty shell, kept installed on purpose.

History: this module bound the trigger-maintained sync_origin column to the ORM and
carried the clinic-visibility record rules (2026-09-04). The rules were dropped on
2026-09-07 (sync-core F-040). On 2026-09-09 the sync_origin column itself was dropped
from all twelve synced tables on every node (F-049): the loop guard is the engine's
replication origin, and the last-writer rule uses sync_updated_at alone.

No fields are declared here any more, deliberately. If this file declared sync_origin,
Odoo's schema updater would recreate the column on the next `odoo -u all` (the
container's start command) and silently reintroduce the dependency. The module stays
installed rather than uninstalled so that its removal from the registry happens through
a normal update, which deletes the stale ir.model.fields rows, and never through
button_immediate_uninstall over XML-RPC, which self-deadlocks on res_partner (see the
2026-09-09 upgrade notes). Safe to uninstall from the UI later.
"""
