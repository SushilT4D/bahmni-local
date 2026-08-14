#!/bin/bash

ENV_FILE=".env"

set -a
source "${ENV_FILE}"
set +a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ${SCRIPT_DIR}
podman build -t bahmni-local/systemdate:1.0 .
