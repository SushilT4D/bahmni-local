#!/bin/bash

# Script to generate sink connector configurations from tables.conf
# For REMOTE setup - generates individual sink connector configs for each table

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."

echo "Setting up sink connector configurations..."
echo ""
echo "This script generates individual connector configs from tables.conf"
echo "For better control and isolation, each table gets its own connector."
echo ""

# Use the dedicated script
"${SCRIPT_DIR}/generate-sink-connectors.sh"

