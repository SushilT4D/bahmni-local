#!/bin/bash

# Build script for custom OpenMRS using extracted WAR file
# This works around Podman's MIME type compatibility issues with the source image
#
# Usage: ./build.sh SOURCE_IMAGE BASE_IMAGE OUTPUT_IMAGE
#
# Arguments:
#   SOURCE_IMAGE  - Image to extract WAR file from (required)
#   BASE_IMAGE    - Base image to build upon (required)
#   OUTPUT_IMAGE  - Tag for the output image (required)

set -e

# Usage function
usage() {
    cat << EOF
Usage: $0 SOURCE_IMAGE BASE_IMAGE OUTPUT_IMAGE

Build a custom OpenMRS image by extracting WAR file from a source image.

Arguments:
  SOURCE_IMAGE  - Image to extract WAR file from (e.g., infoiplitin/openmrs:iplit-1.0.0-662-4)
  BASE_IMAGE    - Base image to build upon (e.g., openmrs-base:latest)
  OUTPUT_IMAGE  - Tag for the output image (e.g., openmrs-custom:latest)

Example:
  $0 infoiplitin/openmrs:iplit-1.0.0-662-4 openmrs-base:latest openmrs-custom:latest

EOF
    exit 1
}

# Check if all required arguments are provided
if [ $# -ne 3 ]; then
    echo "Error: All three arguments are required."
    echo ""
    usage
fi

ENV_FILE=".env"

set -a
source "${ENV_FILE}"
set +a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# cd ${SCRIPT_DIR}

# Parse arguments
CUSTOM_IMAGE="$1"
BASE_IMAGE="$2"
OUTPUT_IMAGE="$3"
WAR_PATH="/openmrs/distribution/openmrs_core/openmrs.war"
DATA_PATH="/data"
BAHMNI_CONFIG_PATH="/etc/bahmni_config"
TEMP_CONTAINER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Custom OpenMRS Build Process${NC}"
echo "=========================================="
echo "Source Image:  $CUSTOM_IMAGE"
echo "Base Image:    $BASE_IMAGE"
echo "Output Image:  $OUTPUT_IMAGE"
echo "=========================================="

# Cleanup function
cleanup() {
    if [ -n "$TEMP_CONTAINER" ]; then
        echo -e "${YELLOW}Cleaning up temporary container...${NC}"
        podman rm -f "$TEMP_CONTAINER" 2>/dev/null || true
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Step 1: Create a temporary container from the custom image
echo -e "\n${GREEN}Step 1: Creating temporary container from $CUSTOM_IMAGE${NC}"
TEMP_CONTAINER=$(podman create "$CUSTOM_IMAGE")
echo "Created container: $TEMP_CONTAINER"

# Step 2: Extract the WAR file
echo -e "\n${GREEN}Step 2: Extracting openmrs.war from container${NC}"
mkdir -p "$SCRIPT_DIR/temp-build"
podman cp "$TEMP_CONTAINER:$WAR_PATH" "$SCRIPT_DIR/temp-build/openmrs.war"
podman cp "$TEMP_CONTAINER:/openmrs" "$SCRIPT_DIR/temp-build/openmrs"
echo "Extracted WAR file to: $SCRIPT_DIR/temp-build/openmrs.war"

# Verify the WAR file was extracted
if [ ! -f "$SCRIPT_DIR/temp-build/openmrs.war" ]; then
    echo -e "${RED}Error: Failed to extract WAR file${NC}"
    exit 1
fi

echo "Extracting data directory from container"
rm -rf "$SCRIPT_DIR/data"
podman cp "$TEMP_CONTAINER:/openmrs/data" "$SCRIPT_DIR/data"
echo "Extracted data to: $SCRIPT_DIR/data"


WAR_SIZE=$(du -h "$SCRIPT_DIR/temp-build/openmrs.war" | cut -f1)
echo "WAR file size: $WAR_SIZE"

# Step 3: Verify Dockerfile exists
echo -e "\n${GREEN}Step 3: Verifying Dockerfile exists${NC}"
if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in $SCRIPT_DIR${NC}"
    echo "Please ensure Dockerfile exists in the script directory."
    exit 1
fi
echo "Using Dockerfile: $SCRIPT_DIR/Dockerfile"

# Step 4: Copy WAR file to openmrs directory
echo -e "\n${GREEN}Step 4: Copying WAR file to openmrs distribution directory${NC}"
mkdir -p "$SCRIPT_DIR/openmrs/distribution/openmrs_core"
cp "$SCRIPT_DIR/temp-build/openmrs.war" "$SCRIPT_DIR/openmrs/distribution/openmrs_core/openmrs.war"
echo "Copied WAR file to: $SCRIPT_DIR/openmrs/distribution/openmrs_core/openmrs.war"

# Step 5: Build the image
echo -e "\n${GREEN}Step 5: Building custom OpenMRS image${NC}"
podman build \
    --format docker \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    -f "$SCRIPT_DIR/Dockerfile" \
    -t "$OUTPUT_IMAGE" \
    "$SCRIPT_DIR"

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}=========================================="
    echo "Build completed successfully!"
    echo "==========================================${NC}"
    echo -e "Image: ${GREEN}$OUTPUT_IMAGE${NC}"

    # Show image details
    echo -e "\n${YELLOW}Image details:${NC}"
    podman images "$OUTPUT_IMAGE"

    # Cleanup temp files
    echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
    rm "$SCRIPT_DIR/openmrs/distribution/openmrs_core/openmrs.war"
    rm -rf "$SCRIPT_DIR/temp-build"
    echo "Done!"
else
    echo -e "\n${RED}Build failed!${NC}"
    exit 1
fi
