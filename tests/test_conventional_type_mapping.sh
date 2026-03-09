#!/bin/bash
# Test convention-aware fallback mapping for conventional commits

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_COMMITS_SCRIPT="${SCRIPT_DIR}/../scripts/parse-commits.sh"

get_changelog_section_definition="$({
    awk '
        /^get_changelog_section[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^}/ { exit }
    ' "${PARSE_COMMITS_SCRIPT}"
})"

if [ -z "${get_changelog_section_definition}" ]; then
    echo "Error: could not extract get_changelog_section definition from ${PARSE_COMMITS_SCRIPT}" >&2
    exit 1
fi

export COMMIT_CONVENTION='conventional'
export COMMIT_TYPE_MAPPING=''

eval "${get_changelog_section_definition}"

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local commit_type="$2"
    local expected="$3"

    test_count=$((test_count + 1))

    local result
    result=$(get_changelog_section "${commit_type}")

    if [ "${result}" = "${expected}" ]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected: [${expected}]"
        echo "  Got:      [${result}]"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing conventional type mapping ==="
echo ""

run_test "feat maps to Added" "feat" "Added"
run_test "fix maps to Fixed" "fix" "Fixed"
run_test "revert maps to Fixed" "revert" "Fixed"
run_test "docs maps to Changed" "docs" "Changed"
run_test "refactor maps to Changed" "refactor" "Changed"
run_test "new is not treated as conventional" "new" ""
run_test "bugfix is not treated as conventional" "bugfix" ""
run_test "remove is not treated as conventional" "remove" ""
run_test "security is not treated as conventional" "security" ""

echo ""
echo "=== Test Summary ==="
echo "Total: ${test_count}"
echo -e "${GREEN}Passed: ${passed_count}${NC}"
if [ "${failed_count}" -gt 0 ]; then
    echo -e "${RED}Failed: ${failed_count}${NC}"
    exit 1
fi

echo -e "${GREEN}All tests passed!${NC}"