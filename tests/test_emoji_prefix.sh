#!/bin/bash
# Test for emoji prefix handling in parse_commit function

set -euo pipefail

# Load the parse_commit function from scripts/parse-commits.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_COMMITS_SCRIPT="${SCRIPT_DIR}/../scripts/parse-commits.sh"

if [ ! -f "${PARSE_COMMITS_SCRIPT}" ]; then
    echo "Error: cannot find parse-commits script at ${PARSE_COMMITS_SCRIPT}" >&2
    exit 1
fi

# Extract parse_commit function
parse_commit_definition="$(
    awk '
        /^parse_commit[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^\}/ { exit }
    ' "${PARSE_COMMITS_SCRIPT}"
)"

if [ -z "${parse_commit_definition}" ]; then
    echo "Error: could not extract parse_commit definition from ${PARSE_COMMITS_SCRIPT}" >&2
    exit 1
fi

eval "${parse_commit_definition}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local subject="$2"
    local body="$3"
    local expected_type="$4"
    local expected_description="$5"
    
    test_count=$((test_count + 1))
    
    # Parse commit - returns NUL-delimited output
    # Read directly from parse_commit using process substitution to handle NUL bytes
    local type scope breaking description
    {
        IFS= read -r -d $'\0' type
        IFS= read -r -d $'\0' scope
        IFS= read -r -d $'\0' breaking
        IFS= read -r -d $'\0' description
    } < <(parse_commit "${subject}" "${body}"; echo -n $'\0')  # Extra NUL ensures last read exits successfully
    
    local success=true
    
    if [ "$type" != "$expected_type" ]; then
        success=false
    fi
    
    if [ "$description" != "$expected_description" ]; then
        success=false
    fi
    
    if [ "$success" = true ]; then
        echo -e "${GREEN}✓${NC} Test $test_count: $test_name"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test $test_count: $test_name"
        echo "  Expected type:        [$expected_type]"
        echo "  Got type:             [$type]"
        echo "  Expected description: [$expected_description]"
        echo "  Got description:      [$description]"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing parse_commit function with emoji prefixes ==="
echo ""

# Test 1: Clean Commit - new type with emoji
run_test "Clean Commit: new type with emoji" \
    "📦 new: add user authentication system" \
    "" \
    "new" \
    "add user authentication system"

# Test 2: Clean Commit - update type with scope and emoji
run_test "Clean Commit: update type with scope and emoji" \
    "🔧 update (api): improve error handling" \
    "" \
    "update" \
    "improve error handling"

# Test 3: Clean Commit - remove type with scope and emoji
run_test "Clean Commit: remove type with scope and emoji" \
    "🗑️ remove (deps): unused lodash dependency" \
    "" \
    "remove" \
    "unused lodash dependency"

# Test 4: Clean Commit - security type with emoji
run_test "Clean Commit: security type with emoji" \
    "🔒 security: patch XSS vulnerability" \
    "" \
    "security" \
    "patch XSS vulnerability"

# Test 5: Clean Commit - setup type with emoji
run_test "Clean Commit: setup type with emoji" \
    "⚙️ setup: add eslint configuration" \
    "" \
    "setup" \
    "add eslint configuration"

# Test 6: Clean Commit - chore type with emoji
run_test "Clean Commit: chore type with emoji" \
    "☕ chore: update npm dependencies" \
    "" \
    "chore" \
    "update npm dependencies"

# Test 7: Clean Commit - test type with emoji
run_test "Clean Commit: test type with emoji" \
    "🧪 test: add unit tests for auth service" \
    "" \
    "test" \
    "add unit tests for auth service"

# Test 8: Clean Commit - docs type with emoji
run_test "Clean Commit: docs type with emoji" \
    "📖 docs: update installation instructions" \
    "" \
    "docs" \
    "update installation instructions"

# Test 9: Clean Commit - release type with emoji
run_test "Clean Commit: release type with emoji" \
    "🚀 release: version 1.0.0" \
    "" \
    "release" \
    "version 1.0.0"

# Test 10: Standard commit without emoji
run_test "Standard commit without emoji" \
    "fix: resolve authentication bug" \
    "" \
    "fix" \
    "resolve authentication bug"

# Test 11: Standard commit with scope
run_test "Standard commit with scope" \
    "feat(api): add new endpoint" \
    "" \
    "feat" \
    "add new endpoint"

# Test 12: Multiple emojis before type
run_test "Multiple emojis before type" \
    "✨🎉 feat: celebrate new feature" \
    "" \
    "feat" \
    "celebrate new feature"

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
