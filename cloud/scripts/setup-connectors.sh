#!/bin/bash
# Generates the hub's up sinks, three per clinic: runs generate-sink-connectors.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Generating sink connector configurations from sync/clinics.json..."
echo ""

"${SCRIPT_DIR}/generate-sink-connectors.sh"
