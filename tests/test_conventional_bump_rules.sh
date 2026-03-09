#!/bin/bash
# Test Conventional Commit release-trigger defaults in detect-version-bump.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_VERSION_SCRIPT="${SCRIPT_DIR}/../scripts/detect-version-bump.sh"

determine_bump_type_definition="$(
    awk '
        /^determine_bump_type[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^}/ { exit }
    ' "${DETECT_VERSION_SCRIPT}"
)"

if [ -z "${determine_bump_type_definition}" ]; then
    echo "Error: could not extract determine_bump_type from ${DETECT_VERSION_SCRIPT}" >&2
    exit 1
fi

eval "${determine_bump_type_definition}"

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local expected="$2"
    local commit_subject="$3"
    local commit_body="${4:-}"

    test_count=$((test_count + 1))

    local result
    result=$(printf 'deadbeef\0%s\0%s\0' "${commit_subject}" "${commit_body}" | determine_bump_type)

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

echo "=== Testing conventional bump rules ==="
echo ""

MAJOR_KEYWORDS='BREAKING CHANGE,BREAKING-CHANGE,breaking'
MINOR_KEYWORDS='feat'
PATCH_KEYWORDS='fix,perf'

run_test "feat triggers minor" "minor" "feat: add parser support"
run_test "fix triggers patch" "patch" "fix: resolve parser bug"
run_test "perf triggers patch" "patch" "perf: improve parse speed"
run_test "refactor does not trigger release" "none" "refactor: simplify parser internals"
run_test "revert does not trigger release" "none" "revert: undo parser change"
run_test "docs does not trigger release" "none" "docs: update parser docs"
run_test "breaking chore triggers major" "major" "chore!: drop Node 18"
run_test "breaking revert triggers major" "major" "revert!: undo public API" "BREAKING CHANGE: restore old behavior with incompatible API"

echo ""
echo "=== Test Summary ==="
echo "Total: ${test_count}"
echo -e "${GREEN}Passed: ${passed_count}${NC}"
if [ "${failed_count}" -gt 0 ]; then
    echo -e "${RED}Failed: ${failed_count}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
fi