#!/usr/bin/env bash
# Lab results entered at the hub reach the clinic whose patient they belong to;
# the test lives with the sync tests and runs with this suite too.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; RP="$(cd "${HERE}/../../.." && pwd)"
bash "$RP/sync/tests/test_lab_result_path.sh"
