#!/usr/bin/env bash
# Builds the forms-sync image. CT=docker on a host that runs docker.
set -euo pipefail
"${CT:-podman}" build -t bahmni-local/forms-sync:1.0 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
