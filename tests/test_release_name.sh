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
    local tag="$4"
    local expected="$5"
    
    test_count=$((test_count + 1))
    local result
    result=$(generate_release_name "$template" "$version" "$tag")
    
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

# Helper to check for trailing stray characters (especially })
run_trailing_test() {
    local test_name="$1"
    local template="$2"
    local version="$3"
    local tag="$4"
    
    test_count=$((test_count + 1))
    local result
    result=$(generate_release_name "$template" "$version" "$tag")
    
    # Check for trailing } or other brace characters that shouldn't be there
    if [[ "$result" =~ \}$ ]] || [[ "$result" =~ \{$ ]]; then
        echo -e "${RED}✗${NC} Test $test_count: $test_name"
        echo "  Result has trailing brace character: [$result]"
        failed_count=$((failed_count + 1))
    elif [[ "$result" =~ \{ ]] || [[ "$result" =~ \} ]]; then
        echo -e "${RED}✗${NC} Test $test_count: $test_name"
        echo "  Result contains unresolved brace characters: [$result]"
        failed_count=$((failed_count + 1))
    else
        echo -e "${GREEN}✓${NC} Test $test_count: $test_name"
        passed_count=$((passed_count + 1))
    fi
}

echo "=== Testing generate_release_name function ==="
echo ""

# Test 1: Default template with {tag} placeholder
run_test "Default template with tag" \
    "{tag}" \
    "0.1.0" \
    "v0.1.0" \
    "v0.1.0"

# Test 2: Template with {version} placeholder
run_test "Template with version placeholder" \
    "Release {version}" \
    "1.2.3" \
    "v1.2.3" \
    "Release 1.2.3"

# Test 3: Template with {tag} and text
run_test "Tag with surrounding text" \
    "Release {tag}" \
    "2.0.0" \
    "v2.0.0" \
    "Release v2.0.0"

# Test 4: Template with date
test_count=$((test_count + 1))
result=$(generate_release_name "{tag} - {date}" "2.0.0" "v2.0.0")
if [[ "$result" =~ ^v2\.0\.0\ -\ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$ ]]; then
    echo -e "${GREEN}✓${NC} Test $test_count: Template with date placeholder"
    passed_count=$((passed_count + 1))
else
    echo -e "${RED}✗${NC} Test $test_count: Template with date placeholder"
    echo "  Expected format: v2.0.0 - YYYY-MM-DD"
    echo "  Got:            [$result]"
    failed_count=$((failed_count + 1))
fi

# Test 5: Multiple version placeholders
run_test "Multiple version placeholders" \
    "{version} - Version {version}" \
    "3.1.4" \
    "v3.1.4" \
    "3.1.4 - Version 3.1.4"

# Test 6: Template without placeholders remains unchanged
run_test "Template without placeholders unchanged" \
    "MyRelease" \
    "0.1.0" \
    "v0.1.0" \
    "MyRelease"

# Test 7: Mixed {tag} and {version} placeholders
run_test "Mixed tag and version placeholders" \
    "{tag} (version {version})" \
    "1.0.0" \
    "v1.0.0" \
    "v1.0.0 (version 1.0.0)"

# =============================================================================
# REGRESSION TESTS: Trailing character bugs
# =============================================================================
echo ""
echo "=== Trailing Character Regression Tests ==="
echo ""

# Test 8: No trailing } after {version} replacement
run_trailing_test "No trailing brace after {version}" \
    "Release {version}" \
    "1.0.1" \
    "v1.0.1"

# Test 9: No trailing } after {tag} replacement
run_trailing_test "No trailing brace after {tag}" \
    "{tag}" \
    "1.0.1" \
    "v1.0.1"

# Test 10: No trailing } with mixed placeholders
run_trailing_test "No trailing brace with mixed placeholders" \
    "{tag} - {version}" \
    "2.0.0" \
    "v2.0.0"

# Test 11: No trailing } with default-like template
run_trailing_test "No trailing brace with Release prefix" \
    "Release {version}" \
    "0.1.0" \
    "v0.1.0"

# Test 12: No trailing characters after {tag} at end of template
test_count=$((test_count + 1))
result=$(generate_release_name "{tag}" "5.0.0" "v5.0.0")
if [[ "$result" == "v5.0.0" ]] && [[ ! "$result" =~ \}$ ]]; then
    echo -e "${GREEN}✓${NC} Test $test_count: Exact match with no trailing characters for {tag}"
    passed_count=$((passed_count + 1))
else
    echo -e "${RED}✗${NC} Test $test_count: Exact match with no trailing characters for {tag}"
    echo "  Expected: [v5.0.0]"
    echo "  Got:      [$result]"
    echo "  (checked for trailing } or other stray characters)"
    failed_count=$((failed_count + 1))
fi

# Test 13: No trailing characters after {version} at end of template
test_count=$((test_count + 1))
result=$(generate_release_name "v{version}" "3.2.1" "v3.2.1")
if [[ "$result" == "v3.2.1" ]] && [[ ! "$result" =~ \}$ ]]; then
    echo -e "${GREEN}✓${NC} Test $test_count: Exact match with no trailing characters for {version}"
    passed_count=$((passed_count + 1))
else
    echo -e "${RED}✗${NC} Test $test_count: Exact match with no trailing characters for {version}"
    echo "  Expected: [v3.2.1]"
    echo "  Got:      [$result]"
    echo "  (checked for trailing } or other stray characters)"
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
