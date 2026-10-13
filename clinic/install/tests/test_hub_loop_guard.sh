#!/usr/bin/env bash
# A clinic receives from the hub only rows written at the hub. That depends on
# the hub's Postgres sources and up-sink templates in this repo, so the test that
# checks them (sync/tests/test_hub_loop_guard.sh) runs with this suite too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
bash "$RP/sync/tests/test_hub_loop_guard.sh"
