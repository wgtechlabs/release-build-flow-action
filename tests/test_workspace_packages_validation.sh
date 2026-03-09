#!/bin/bash
# Regression test: WORKSPACE_PACKAGES validation in monorepo mode
#
# Verifies that when WORKSPACE_PACKAGES contains strings (flat array) or a
# non-array JSON value (e.g., a scope-mapping object), the validation logic
# resets it to "[]" and prevents jq from failing with
# "Cannot index string with string 'path'" (exit code 5).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

# run_validation_test runs the WORKSPACE_PACKAGES validation block in an
# isolated subprocess and returns the effective WORKSPACE_PACKAGES value.
# Input is passed via the exported _TEST_WP variable to avoid bash quoting
# issues with JSON content in heredoc strings.
run_validation_test() {
    local test_name="$1"
    local input_packages="$2"
    local expected_output="$3"

    test_count=$((test_count + 1))

    export _TEST_WP="${input_packages}"
    result=$(bash << 'BASH_EOF' 2>/dev/null
set -euo pipefail
WORKSPACE_PACKAGES="${_TEST_WP}"

# --- Exact validation block from parse-commits.sh / detect-version-bump.sh ---
if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
    pkg_valid=$(echo "${WORKSPACE_PACKAGES}" | jq -r '
        if type != "array" then "false"
        elif length == 0 then "true"
        elif .[0] | type == "object" then "true"
        else "false"
        end
    ' 2>/dev/null || echo "false")
    if [[ "${pkg_valid}" != "true" ]]; then
        WORKSPACE_PACKAGES="[]"
    fi
fi

echo "${WORKSPACE_PACKAGES}"
BASH_EOF
    )

    if [ "${result}" = "${expected_output}" ]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected: [${expected_output}]"
        echo "  Got:      [${result}]"
        failed_count=$((failed_count + 1))
    fi
}

# run_jq_test verifies that jq -r '.[].path' does NOT fail (exit code 5) after
# validation, which is the core of the bug being fixed.
run_jq_test() {
    local test_name="$1"
    local input_packages="$2"

    test_count=$((test_count + 1))

    export _TEST_WP="${input_packages}"
    bash << 'BASH_EOF' 2>/dev/null
set -euo pipefail
WORKSPACE_PACKAGES="${_TEST_WP}"

# Apply validation
if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
    pkg_valid=$(echo "${WORKSPACE_PACKAGES}" | jq -r '
        if type != "array" then "false"
        elif length == 0 then "true"
        elif .[0] | type == "object" then "true"
        else "false"
        end
    ' 2>/dev/null || echo "false")
    if [[ "${pkg_valid}" != "true" ]]; then
        WORKSPACE_PACKAGES="[]"
    fi
fi

# This is the jq call that used to crash with "Cannot index string with string 'path'"
echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path' > /dev/null
BASH_EOF
    local exit_code=$?

    if [ ${exit_code} -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name} (jq failed with exit code ${exit_code})"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing WORKSPACE_PACKAGES validation (regression: Cannot index string with string 'path') ==="
echo ""

# --- Format validation ---

run_validation_test "Valid array of objects: unchanged" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false}]' \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false}]'

run_validation_test "Empty array: unchanged" \
    '[]' \
    '[]'

run_validation_test "Flat string array: reset to []" \
    '["packages/core","src/app"]' \
    '[]'

run_validation_test "Scope-mapping object (string values): reset to []" \
    '{"core":"packages/core","app":"src/app"}' \
    '[]'

run_validation_test "Single string value: reset to []" \
    '"packages/core"' \
    '[]'

run_validation_test "null: reset to []" \
    'null' \
    '[]'

run_validation_test "Multi-package valid array: unchanged" \
    '[{"name":"@org/core","path":"packages/core","scope":"core"},{"name":"@org/api","path":"packages/api","scope":"api"}]' \
    '[{"name":"@org/core","path":"packages/core","scope":"core"},{"name":"@org/api","path":"packages/api","scope":"api"}]'

echo ""
echo "--- jq safety tests (regression: exit code 5) ---"
echo ""

# --- jq safety (regression for the actual crash) ---

run_jq_test "Valid objects: jq .path succeeds" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false}]'

run_jq_test "Empty array: jq .path is a no-op" \
    '[]'

run_jq_test "Flat string array: validation prevents jq crash" \
    '["packages/core","src/app"]'

run_jq_test "Scope-mapping object: validation prevents jq crash" \
    '{"core":"packages/core","app":"src/app"}'

run_jq_test "null: validation prevents jq crash" \
    'null'

echo ""
echo "=== Test Summary ==="
echo "Total: ${test_count}"
echo -e "${GREEN}Passed: ${passed_count}${NC}"
if [ "${failed_count}" -gt 0 ]; then
    echo -e "${RED}Failed: ${failed_count}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
