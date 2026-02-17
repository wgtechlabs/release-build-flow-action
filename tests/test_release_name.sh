#!/bin/bash
# Test for generate_release_name function to ensure no extra braces in output

set -euo pipefail

# Source the function from create-release.sh
# Extract just the function definition
generate_release_name() {
    local template="$1"
    local version="$2"
    local date
    date=$(date +%Y-%m-%d)
    
    # Replace placeholders
    local name="${template//\{version\}/${version}}"
    name="${name//\{date\}/${date}}"
    
    echo "${name}"
}

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
date_value=$(date +%Y-%m-%d)
run_test "Template with date placeholder" \
    "Release {version} - {date}" \
    "2.0.0" \
    "Release 2.0.0 - $date_value"

# Test 4: Multiple version placeholders
run_test "Multiple version placeholders" \
    "{version} - Version {version}" \
    "3.1.4" \
    "3.1.4 - Version 3.1.4"

# Test 5: Regression test for issue - NO extra closing brace
result=$(generate_release_name "Release {version}" "0.1.0")
test_count=$((test_count + 1))
if [[ ! "$result" =~ \}$ ]]; then
    echo -e "${GREEN}✓${NC} Test $test_count: No trailing brace (regression test)"
    passed_count=$((passed_count + 1))
else
    echo -e "${RED}✗${NC} Test $test_count: No trailing brace (regression test)"
    echo "  Result should not end with }: [$result]"
    failed_count=$((failed_count + 1))
fi

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
