#!/bin/bash
# Test validate-inputs.sh behavior

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="${SCRIPT_DIR}/../scripts/validate-inputs.sh"

test_count=0
passed_count=0
failed_count=0

run_success_test() {
    local test_name="$1"
    shift

    test_count=$((test_count + 1))

    if "$@" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        failed_count=$((failed_count + 1))
    fi
}

run_failure_test() {
    local test_name="$1"
    shift

    test_count=$((test_count + 1))

    if "$@" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        failed_count=$((failed_count + 1))
    else
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    fi
}

run_validate() {
    env "$@" bash "${VALIDATE_SCRIPT}"
}

echo "=== Testing validate-inputs.sh ==="
echo ""

run_success_test "Validation passes on configured production branch" \
    run_validate \
    MAIN_BRANCH=main \
    CURRENT_BRANCH=main \
    INITIAL_VERSION=1.2.3

run_failure_test "Validation fails on non-production branch" \
    run_validate \
    MAIN_BRANCH=main \
    CURRENT_BRANCH=dev \
    INITIAL_VERSION=1.2.3

run_success_test "Validation skips branch guard when branch is unavailable" \
    run_validate \
    MAIN_BRANCH=main \
    GITHUB_HEAD_REF= \
    GITHUB_REF_NAME= \
    INITIAL_VERSION=1.2.3

run_failure_test "Validation fails when main-branch is missing" \
    run_validate \
    INITIAL_VERSION=1.2.3

run_failure_test "Validation fails for invalid initial-version" \
    run_validate \
    MAIN_BRANCH=main \
    CURRENT_BRANCH=main \
    INITIAL_VERSION=1.2

echo ""
echo "=== Results: ${passed_count}/${test_count} passed ==="

if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi

echo "All tests passed!"