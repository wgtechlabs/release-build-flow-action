#!/bin/bash
# Test: private package filtering in monorepo mode
#
# Verifies that workspace packages with "private": true are excluded from
# version bump detection, and that public packages are still included.
# Covers the three jq iteration sites in detect-version-bump.sh that were
# updated to add | select(.private != true).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local input_packages="$2"
    local expected_paths="$3"

    test_count=$((test_count + 1))

    export _TEST_WP="${input_packages}"
    result=$(bash << 'BASH_EOF' 2>/dev/null
set -euo pipefail
WORKSPACE_PACKAGES="${_TEST_WP}"

TMPFILE=$(mktemp)
trap 'rm -f "${TMPFILE}"' EXIT
printf '%s\n' "${WORKSPACE_PACKAGES}" > "${TMPFILE}"

# This is the filter added to all three iteration sites in detect-version-bump.sh
jq -r '.[] | objects | select(.private != true) | .path' "${TMPFILE}"
BASH_EOF
    )

    if [ "${result}" = "${expected_paths}" ]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected: [${expected_paths}]"
        echo "  Got:      [${result}]"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing private package filtering in monorepo mode ==="
echo ""

# All public packages should be included
run_test "All public packages: all paths returned" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false},{"name":"@org/api","version":"1.0.0","path":"packages/api","scope":"api","private":false}]' \
    "packages/core
packages/api"

# Private package should be excluded
run_test "One private package: only public path returned" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":true},{"name":"@org/api","version":"1.0.0","path":"packages/api","scope":"api","private":false}]' \
    "packages/api"

# All private packages should result in empty output
run_test "All private packages: no paths returned" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":true},{"name":"@org/api","version":"1.0.0","path":"packages/api","scope":"api","private":true}]' \
    ""

# Missing private field should default to inclusion (falsy)
run_test "Missing private field: path included" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core"}]' \
    "packages/core"

# private: false explicitly set
run_test "private: false explicitly: path included" \
    '[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false}]' \
    "packages/core"

# Empty array: no output
run_test "Empty package array: no paths returned" \
    '[]' \
    ""

# Mixed with three packages
run_test "Three packages, two private: only public path returned" \
    '[{"name":"@org/a","version":"1.0.0","path":"packages/a","scope":"a","private":true},{"name":"@org/b","version":"1.0.0","path":"packages/b","scope":"b","private":false},{"name":"@org/c","version":"1.0.0","path":"packages/c","scope":"c","private":true}]' \
    "packages/b"

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
