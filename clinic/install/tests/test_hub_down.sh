#!/usr/bin/env bash
# The hub sends down only master tables, all rendered from sync/hub-down.conf;
# the test lives with the sync tests and runs with this suite too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
bash "$RP/sync/tests/test_hub_down.sh"
