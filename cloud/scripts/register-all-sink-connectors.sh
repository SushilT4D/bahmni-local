#!/bin/bash
# Registers (or updates) every up sink in ./connectors/*-sink.json with Kafka Connect
# (openmrs-, odoo- and clinlims-<slug>-sink per clinic), after check-clinical-fks.sh passes
# against HUB_MYSQL_CONTAINER, then prints each one's state.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
CONNECTORS_DIR="${CONNECTORS_DIR:-$PWD/connectors}"
CONNECT_URL="${KAFKA_CONNECT_URL:-http://localhost:8083}"

echo "Registering all sink connectors..."

# the generated sink configs
connector_files=("${CONNECTORS_DIR}"/*-sink.json)

if [ ${#connector_files[@]} -eq 0 ] || [ ! -f "${connector_files[0]}" ]; then
    echo "Error: No sink connector configurations found!"
    echo "Please run: ./scripts/generate-sink-connectors.sh first"
    exit 1
fi

# every OpenMRS sink writes obs, orders, drug_order and test_order: check their foreign keys first
if [ -z "${HUB_MYSQL_CONTAINER:-}" ]; then
    echo "Error: set HUB_MYSQL_CONTAINER to the hub's OpenMRS MySQL container, so the foreign keys on obs, orders, drug_order and test_order are checked before the sinks are registered. Nothing was registered."
    exit 1
fi
fk_rc=0
bash "${SCRIPT_DIR}/check-clinical-fks.sh" --container "${HUB_MYSQL_CONTAINER}" || fk_rc=$?
case "${fk_rc}" in
    0) ;;
    2) echo "Note: the foreign keys into the clinical tables differ from cloud/scripts/clinical-fks-in.conf (listed above); a clinic's delete of a row they reference will stop that sink." ;;
    *) echo "Error: check-clinical-fks.sh failed (exit ${fk_rc}, reason above): the sinks would stop on a row that arrives before its parent. Nothing was registered."; exit 1 ;;
esac

# create each connector, or update its config when it exists
success_count=0
fail_count=0

for config_file in "${connector_files[@]}"; do
    connector_name=$(basename "${config_file}" .json)

    echo ""
    echo "Registering ${connector_name}..."

    status_code=$(curl -s -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors/${connector_name}")

    if [ "${status_code}" = "200" ]; then
        echo "  • Connector exists, updating configuration..."
        tmp_config=$(mktemp)
        if ! jq '.config' "${config_file}" > "${tmp_config}" 2>/dev/null; then
            echo "  ✗ Failed: Unable to extract config from ${config_file}"
            rm -f "${tmp_config}"
            fail_count=$((fail_count + 1))
            continue
        fi
        response=$(curl -s -X PUT "${CONNECT_URL}/connectors/${connector_name}/config" \
            -H "Content-Type: application/json" \
            -d @"${tmp_config}")
        rm -f "${tmp_config}"
    else
        response=$(curl -s -X POST "${CONNECT_URL}/connectors" \
            -H "Content-Type: application/json" \
            -d @"${config_file}")
    fi

    if echo "$response" | grep -q "error_code"; then
        echo "  ✗ Failed: $(echo "$response" | jq -r '.message' 2>/dev/null || echo "$response")"
        fail_count=$((fail_count + 1))
    else
        if [ "${status_code}" = "200" ]; then
            echo "  ✓ Updated successfully"
        else
            echo "  ✓ Registered successfully"
        fi
        success_count=$((success_count + 1))
    fi
done

echo ""
echo "=========================================="
echo "Registration complete!"
echo "  Success: ${success_count}"
echo "  Failed: ${fail_count}"
echo "=========================================="

# all registered: show each connector's and task's state
if [ ${fail_count} -eq 0 ]; then
    echo ""
    echo "Checking connector status..."
    sleep 2
    for config_file in "${connector_files[@]}"; do
        connector_name=$(basename "${config_file}" .json)
        echo ""
        echo "${connector_name}:"
        status_json=$(curl -s "${CONNECT_URL}/connectors/${connector_name}/status")
        if [ -z "${status_json}" ]; then
            echo "  (no response from Kafka Connect)"
            continue
        fi

        connector_state=$(echo "${status_json}" | jq -r '.connector.state // empty' 2>/dev/null)
        if [ -z "${connector_state}" ]; then
            connector_state="unknown"
        fi
        echo "  Connector: ${connector_state}"

        task_states=$(echo "${status_json}" | jq -r '.tasks[] | "  - Task \(.id): \(.state)"' 2>/dev/null)
        if [ -z "${task_states}" ]; then
            echo "  Tasks: unavailable"
        else
            echo "${task_states}"
        fi
    done
fi
