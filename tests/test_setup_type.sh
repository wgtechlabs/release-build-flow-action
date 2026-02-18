#!/bin/bash
# Test for setup type mapping in get_changelog_section function

set -euo pipefail

# Load the get_changelog_section function from scripts/parse-commits.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_COMMITS_SCRIPT="${SCRIPT_DIR}/../scripts/parse-commits.sh"

if [ ! -f "${PARSE_COMMITS_SCRIPT}" ]; then
    echo "Error: cannot find parse-commits script at ${PARSE_COMMITS_SCRIPT}" >&2
    exit 1
fi

# Extract get_changelog_section function
get_changelog_section_definition="$(
    awk '
        /^get_changelog_section[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^}/ { exit }
    ' "${PARSE_COMMITS_SCRIPT}"
)"

if [ -z "${get_changelog_section_definition}" ]; then
    echo "Error: could not extract get_changelog_section definition from ${PARSE_COMMITS_SCRIPT}" >&2
    exit 1
fi

# Set up environment for testing
export COMMIT_TYPE_MAPPING='{
  "feat": "Added",
  "new": "Added",
  "add": "Added",
  "fix": "Fixed",
  "bugfix": "Fixed",
  "security": "Security",
  "perf": "Changed",
  "refactor": "Changed",
  "update": "Changed",
  "change": "Changed",
  "chore": "Changed",
  "setup": "Changed",
  "deprecate": "Deprecated",
  "remove": "Removed",
  "delete": "Removed"
}'

eval "${get_changelog_section_definition}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local commit_type="$2"
    local expected="$3"
    
    test_count=$((test_count + 1))
    local result
    result=$(get_changelog_section "$commit_type")
    
    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} Test $test_count: $test_name"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test $test_count: $test_name"
        echo "  Expected: [$expected]"
        echo "  Got:      [$result]"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing get_changelog_section function with setup type ==="
echo ""

# Test setup type specifically
run_test "setup maps to Changed" \
    "setup" \
    "Changed"

# Test other standard types to ensure they still work
run_test "new maps to Added" \
    "new" \
    "Added"

run_test "fix maps to Fixed" \
    "fix" \
    "Fixed"

run_test "security maps to Security" \
    "security" \
    "Security"

run_test "chore maps to Changed" \
    "chore" \
    "Changed"

run_test "remove maps to Removed" \
    "remove" \
    "Removed"

run_test "deprecate maps to Deprecated" \
    "deprecate" \
    "Deprecated"

echo ""
echo "=== Test Summary ==="
echo "Total: $test_count"
echo -e "${GREEN}Passed: $passed_count${NC}"
if [ $failed_count -gt 0 ]; then
    echo -e "${RED}Failed: $failed_count${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
