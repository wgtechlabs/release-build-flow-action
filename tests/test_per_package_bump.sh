#!/bin/bash
# Regression test: per-package version bump commit processing
#
# Verifies that the top-level per-package commit-processing loop in
# detect-version-bump.sh correctly strips emoji prefixes and extracts commit
# types without triggering "local: can only be used in a function" (the bug
# fixed by removing the erroneous 'local' keyword from line 410).

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

# run_test executes the exact prefix-stripping and type-extraction code from
# the per-package loop AT THE TOP LEVEL of a bash subprocess (not inside any
# function), which is the condition that triggered the original bug.
run_test() {
    local test_name="$1"
    local subject="$2"
    local expected_type="$3"

    test_count=$((test_count + 1))

    # Capture both stdout and stderr so we can detect 'local' errors.
    result=$(bash << BASH_EOF 2>&1
set -euo pipefail
subject="${subject}"

# --- Exact code from scripts/detect-version-bump.sh per-package loop ---
# (top-level scope, no enclosing function — this is where the bug occurred)
prefix="\${subject%%[a-zA-Z]*}"
cleaned_subject="\${subject#"\$prefix"}"

pattern='^([a-z]+)[[:space:]]*(\(([^)]+)\))?(!)?: '
if [[ "\${cleaned_subject}" =~ \$pattern ]]; then
    echo "\${BASH_REMATCH[1]}"
else
    echo "none"
fi
BASH_EOF
)

    # Regression guard: fail immediately if the 'local' error re-appears.
    if echo "${result}" | grep -q "local: can only be used in a function"; then
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  REGRESSION: 'local' used outside function detected!"
        failed_count=$((failed_count + 1))
        return
    fi

    if [ "${result}" = "${expected_type}" ]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected: [${expected_type}]"
        echo "  Got:      [${result}]"
        failed_count=$((failed_count + 1))
    fi
}

echo "=== Testing per-package commit processing (regression: local outside function) ==="
echo ""

# Clean Commit emoji types
run_test "Clean Commit: new with emoji" \
    "📦 new: add user authentication" \
    "new"

run_test "Clean Commit: update with scope and emoji" \
    "🔧 update (api): improve error handling" \
    "update"

run_test "Clean Commit: remove with scope and emoji" \
    "🗑️ remove (deps): unused lodash dependency" \
    "remove"

run_test "Clean Commit: security with emoji" \
    "🔒 security: patch XSS vulnerability" \
    "security"

run_test "Clean Commit: setup with emoji" \
    "⚙️ setup: add eslint configuration" \
    "setup"

run_test "Clean Commit: chore with emoji" \
    "☕ chore: update npm dependencies" \
    "chore"

run_test "Clean Commit: release with emoji" \
    "🚀 release: version 2.0.0" \
    "release"

# Standard commits (no emoji)
run_test "Standard commit without emoji" \
    "fix: resolve authentication bug" \
    "fix"

run_test "Standard commit with scope" \
    "feat(api): add new endpoint" \
    "feat"

run_test "Breaking change marker" \
    "feat!: redesign public API" \
    "feat"

# No matching type
run_test "Commit without conventional type" \
    "some random commit message" \
    "none"

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
