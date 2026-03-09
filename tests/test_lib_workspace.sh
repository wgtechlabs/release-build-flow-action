#!/bin/bash
# Test for load_workspace_packages() in scripts/lib-workspace.sh
#
# Verifies that:
# 1. When WORKSPACE_PACKAGES_FILE is set and contains valid JSON, WORKSPACE_PACKAGES
#    is loaded from the file, bypassing the env var.
# 2. When the file contains invalid JSON, WORKSPACE_PACKAGES falls back to the env var.
# 3. When the file doesn't exist, WORKSPACE_PACKAGES falls back to the env var.
# 4. When neither file nor env var is set, WORKSPACE_PACKAGES defaults to "[]".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_WORKSPACE="${SCRIPT_DIR}/../scripts/lib-workspace.sh"

if [ ! -f "${LIB_WORKSPACE}" ]; then
    echo "Error: cannot find lib-workspace.sh at ${LIB_WORKSPACE}" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

pass_test() {
    local test_name="$1"
    test_count=$((test_count + 1))
    passed_count=$((passed_count + 1))
    echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
}

fail_test() {
    local test_name="$1"
    local detail="${2:-}"
    test_count=$((test_count + 1))
    failed_count=$((failed_count + 1))
    echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
    if [[ -n "${detail}" ]]; then
        echo "  ${detail}"
    fi
}

# Check jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for these tests" >&2
    exit 1
fi

# Create a temp dir for test files
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "${TEST_TMPDIR}"' EXIT

VALID_PACKAGES='[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false}]'
VALID_FILE="${TEST_TMPDIR}/valid-packages.json"
INVALID_FILE="${TEST_TMPDIR}/invalid-packages.json"
MISSING_FILE="${TEST_TMPDIR}/does-not-exist.json"

echo "${VALID_PACKAGES}" > "${VALID_FILE}"
echo "not-valid-json{{{" > "${INVALID_FILE}"

echo "=== Testing load_workspace_packages (scripts/lib-workspace.sh) ==="
echo ""

# Helper: run load_workspace_packages in a subprocess with given env vars.
# Prints the resulting WORKSPACE_PACKAGES value.
# Uses exported _TEST_WP / _TEST_WP_FILE to avoid JSON quoting issues in heredocs.
run_load() {
    local wp_file="${1:-}"
    local wp_env="${2:-}"
    export _TEST_WP_FILE="${wp_file}"
    export _TEST_WP="${wp_env}"
    bash << BASH_EOF 2>/dev/null
set -euo pipefail
WORKSPACE_PACKAGES_FILE="\${_TEST_WP_FILE}"
WORKSPACE_PACKAGES="\${_TEST_WP}"
log_warning() { echo "WARNING: \$1" >&2; }
source "${LIB_WORKSPACE}"
load_workspace_packages
echo "\${WORKSPACE_PACKAGES}"
BASH_EOF
}

# =============================================================================
# Test 1: Loads from valid file, ignoring env var value
# =============================================================================

ENV_VAR_VALUE='[{"name":"from-env"}]'
RESULT=$(run_load "${VALID_FILE}" "${ENV_VAR_VALUE}")

if [[ "${RESULT}" == "${VALID_PACKAGES}" ]]; then
    pass_test "Valid file: WORKSPACE_PACKAGES loaded from file"
else
    fail_test "Valid file: WORKSPACE_PACKAGES loaded from file" "Expected: ${VALID_PACKAGES}, Got: ${RESULT}"
fi

# =============================================================================
# Test 2: Falls back to env var when file contains invalid JSON
# =============================================================================

ENV_VAR_VALUE='[{"name":"from-env","path":"src/app"}]'
RESULT=$(run_load "${INVALID_FILE}" "${ENV_VAR_VALUE}")

if [[ "${RESULT}" == "${ENV_VAR_VALUE}" ]]; then
    pass_test "Invalid file: falls back to env var"
else
    fail_test "Invalid file: falls back to env var" "Expected: ${ENV_VAR_VALUE}, Got: ${RESULT}"
fi

# =============================================================================
# Test 3: Falls back to env var when file path doesn't exist
# =============================================================================

ENV_VAR_VALUE='[{"name":"from-env","path":"src/app"}]'
RESULT=$(run_load "${MISSING_FILE}" "${ENV_VAR_VALUE}")

if [[ "${RESULT}" == "${ENV_VAR_VALUE}" ]]; then
    pass_test "Missing file: falls back to env var"
else
    fail_test "Missing file: falls back to env var" "Expected: ${ENV_VAR_VALUE}, Got: ${RESULT}"
fi

# =============================================================================
# Test 4: Defaults to "[]" when no file and no env var
# =============================================================================

RESULT=$(run_load "" "")

if [[ "${RESULT}" == "[]" ]]; then
    pass_test "No file, no env var: defaults to []"
else
    fail_test "No file, no env var: defaults to []" "Expected: [], Got: ${RESULT}"
fi

# =============================================================================
# Test 5: File takes precedence over a non-empty env var with valid JSON
# =============================================================================

# Confirm explicitly that after loading from file, jq .path works (the core fix)
RESULT=$(run_load "${VALID_FILE}" '["packages/core"]')
PATH_RESULT=$(echo "${RESULT}" | jq -r '.[].path' 2>&1)
PATH_EXIT=$?

if [[ "${PATH_EXIT}" == "0" ]] && [[ "${PATH_RESULT}" == "packages/core" ]]; then
    pass_test "File overrides corrupt env var: jq .path succeeds"
else
    fail_test "File overrides corrupt env var: jq .path succeeds" "Exit: ${PATH_EXIT}, Paths: ${PATH_RESULT}"
fi

# =============================================================================
# Test 6: WORKSPACE_PACKAGES_FILE unset - behaves as if no file
# =============================================================================

export _TEST_WP='[{"name":"from-env","path":"src/app"}]'
export _TEST_LIB_WORKSPACE="${LIB_WORKSPACE}"
RESULT=$(bash << 'BASH_EOF' 2>/dev/null
set -euo pipefail
WORKSPACE_PACKAGES="${_TEST_WP}"
unset WORKSPACE_PACKAGES_FILE
log_warning() { echo "WARNING: $1" >&2; }
source "${_TEST_LIB_WORKSPACE}"
load_workspace_packages
echo "${WORKSPACE_PACKAGES}"
BASH_EOF
)

if [[ "${RESULT}" == '[{"name":"from-env","path":"src/app"}]' ]]; then
    pass_test "WORKSPACE_PACKAGES_FILE unset: uses env var"
else
    fail_test "WORKSPACE_PACKAGES_FILE unset: uses env var" "Got: ${RESULT}"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "=== Results: ${passed_count}/${test_count} tests passed ==="

if [[ "${failed_count}" -gt 0 ]]; then
    echo -e "${RED}${failed_count} tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
