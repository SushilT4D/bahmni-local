#!/usr/bin/env bash
# The hub's sources each heartbeat, so a clinic operator can tell a live hub from
# a dead one source by source; sync/tests/test_hub_source_heartbeat.sh checks the
# templates and runs with this suite too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
bash "$RP/sync/tests/test_hub_source_heartbeat.sh"
