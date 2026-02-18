#!/bin/bash
# Test for generate_release_name function to ensure no extra braces in output

set -euo pipefail

# Load the generate_release_name function from scripts/create-release.sh
# Extract just the function definition to avoid executing the script's main logic.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_RELEASE_SCRIPT="${SCRIPT_DIR}/../scripts/create-release.sh"

if [ ! -f "${CREATE_RELEASE_SCRIPT}" ]; then
    echo "Error: cannot find create-release script at ${CREATE_RELEASE_SCRIPT}" >&2
    exit 1
fi

generate_release_name_definition="$(
    awk '
        /^generate_release_name[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^\}/ { exit }
    ' "${CREATE_RELEASE_SCRIPT}"
)"

if [ -z "${generate_release_name_definition}" ]; then
    echo "Error: could not extract generate_release_name definition from ${CREATE_RELEASE_SCRIPT}" >&2
    exit 1
fi

eval "${generate_release_name_definition}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local template="$2"
    local version="$3"
    local expected="$4"
    
    test_count=$((test_count + 1))
    local result
    result=$(generate_release_name "$template" "$version")
    
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

echo "=== Testing generate_release_name function ==="
echo ""

# Test 1: Basic template - ensure no extra brace
run_test "Basic template with version" \
    "Release {version}" \
    "0.1.0" \
    "Release 0.1.0"

# Test 2: Template with custom format
run_test "Custom format template" \
    "v{version} Release" \
    "1.2.3" \
    "v1.2.3 Release"

# Test 3: Template with date
test_count=$((test_count + 1))
result=$(generate_release_name "Release {version} - {date}" "2.0.0")
if [[ "$result" =~ ^Release\ 2\.0\.0\ -\ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$ ]]; then
    echo -e "${GREEN}✓${NC} Test $test_count: Template with date placeholder"
    passed_count=$((passed_count + 1))
else
    echo -e "${RED}✗${NC} Test $test_count: Template with date placeholder"
    echo "  Expected format: Release 2.0.0 - YYYY-MM-DD"
    echo "  Got:            [$result]"
    failed_count=$((failed_count + 1))
fi

# Test 4: Multiple version placeholders
run_test "Multiple version placeholders" \
    "{version} - Version {version}" \
    "3.1.4" \
    "3.1.4 - Version 3.1.4"

# Test 5: Regression test - template without placeholders remains unchanged
run_test "Template without placeholders unchanged" \
    "Release" \
    "0.1.0" \
    "Release"

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
