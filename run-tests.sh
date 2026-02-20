#!/bin/bash
# =============================================================================
# RUN ALL TESTS
# =============================================================================
# Runs all test scripts in the tests/ directory and reports overall results.
#
# Usage: bash run-tests.sh
#
# Environment Variables: (none required)
# Outputs: Exit code 0 if all tests pass, 1 if any fail
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests"

total=0
passed=0
failed=0
failed_tests=()

echo -e "${BLUE}=== Running all tests ===${NC}"
echo ""

for f in "${TEST_DIR}"/test_*.sh; do
    test_name="$(basename "${f}")"
    total=$((total + 1))

    if bash "${f}"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_tests+=("${test_name}")
    fi
    echo ""
done

echo -e "${BLUE}=== Overall Summary ===${NC}"
echo "Total test files: ${total}"
echo -e "${GREEN}Passed: ${passed}${NC}"

if [[ ${failed} -gt 0 ]]; then
    echo -e "${RED}Failed: ${failed}${NC}"
    for t in "${failed_tests[@]}"; do
        echo -e "${RED}  - ${t}${NC}"
    done
    exit 1
else
    echo -e "${GREEN}All test files passed!${NC}"
    exit 0
fi
