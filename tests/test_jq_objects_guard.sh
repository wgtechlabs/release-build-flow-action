#!/bin/bash
# =============================================================================
# TEST: jq `objects` type guard prevents "Cannot index string with string 'path'"
# =============================================================================
# Regression test for the jq crash that occurs when WORKSPACE_PACKAGES JSON
# contains non-object elements (e.g., strings mixed into the array).
#
# The fix adds `| objects` after every `.[]` in jq filters so that non-object
# elements are silently skipped instead of crashing with exit code 5.
#
# This test exercises ALL jq filter patterns used across:
#   - detect-version-bump.sh
#   - parse-commits.sh
#   - commit-changelog.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

test_count=0
passed_count=0
failed_count=0

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    # Normalize CR/LF to LF for consistent comparison across platforms
    expected=$(printf '%s' "${expected}" | tr -d '\r')
    actual=$(printf '%s' "${actual}" | tr -d '\r')
    test_count=$((test_count + 1))
    if [[ "${actual}" == "${expected}" ]]; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected: [${expected}]"
        echo "  Got:      [${actual}]"
        failed_count=$((failed_count + 1))
    fi
}

assert_exit_ok() {
    local test_name="$1"
    shift
    test_count=$((test_count + 1))
    if "$@" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        local rc=$?
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name} (exit code ${rc})"
        failed_count=$((failed_count + 1))
    fi
}

# ---- Test data ----
# Valid packages array (objects only)
VALID_PACKAGES='[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false},{"name":"@org/cli","version":"2.0.0","path":"src/cli","scope":"cli","private":false}]'
# Mixed array: objects + trailing string (reproduces the CI failure)
MIXED_PACKAGES='[{"name":"@org/core","version":"1.0.0","path":"packages/core","scope":"core","private":false},"stray_string","another_string"]'
# All-strings array
STRINGS_ONLY='["packages/core","src/cli"]'
# Empty array
EMPTY='[]'

# Write each to temp files (mirrors WORKSPACE_TMPFILE approach in scripts)
VALID_FILE=$(mktemp)
MIXED_FILE=$(mktemp)
STRINGS_FILE=$(mktemp)
EMPTY_FILE=$(mktemp)
echo "${VALID_PACKAGES}" > "${VALID_FILE}"
echo "${MIXED_PACKAGES}" > "${MIXED_FILE}"
echo "${STRINGS_ONLY}" > "${STRINGS_FILE}"
echo "${EMPTY}" > "${EMPTY_FILE}"
trap 'rm -f "${VALID_FILE}" "${MIXED_FILE}" "${STRINGS_FILE}" "${EMPTY_FILE}"' EXIT

echo "=== Testing jq 'objects' type guard (regression: Cannot index string with string 'path') ==="
echo ""

# =========================================================================
# Section 1: .[] | objects | .path  (used to enumerate all package paths)
# =========================================================================
echo "--- Filter: .[] | objects | .path ---"
echo ""

# Without the guard, MIXED_PACKAGES causes exit code 5
assert_exit_ok "Mixed array: no crash with objects guard" \
    jq -r '.[] | objects | .path' "${MIXED_FILE}"

assert_eq "Valid array: returns all paths" \
    "packages/core
src/cli" \
    "$(jq -r '.[] | objects | .path' "${VALID_FILE}")"

assert_eq "Mixed array: returns only object paths, skips strings" \
    "packages/core" \
    "$(jq -r '.[] | objects | .path' "${MIXED_FILE}")"

assert_eq "Strings-only array: returns nothing" \
    "" \
    "$(jq -r '.[] | objects | .path' "${STRINGS_FILE}")"

assert_eq "Empty array: returns nothing" \
    "" \
    "$(jq -r '.[] | objects | .path' "${EMPTY_FILE}")"

echo ""

# =========================================================================
# Section 2: .[] | objects | select(.scope == $scope) | .path
#            (scope-based package lookup)
# =========================================================================
echo "--- Filter: .[] | objects | select(.scope == \$scope) | .path ---"
echo ""

assert_eq "Valid array: finds scope" \
    "src/cli" \
    "$(jq -r --arg scope "cli" '.[] | objects | select(.scope == $scope) | .path' "${VALID_FILE}" | head -1)"

assert_eq "Mixed array: finds scope from objects, ignores strings" \
    "packages/core" \
    "$(jq -r --arg scope "core" '.[] | objects | select(.scope == $scope) | .path' "${MIXED_FILE}" | head -1)"

assert_exit_ok "Mixed array: scope lookup does not crash" \
    jq -r --arg scope "core" '.[] | objects | select(.scope == $scope) | .path' "${MIXED_FILE}"

assert_eq "Strings-only: scope lookup returns nothing" \
    "" \
    "$(jq -r --arg scope "core" '.[] | objects | select(.scope == $scope) | .path' "${STRINGS_FILE}" | head -1)"

echo ""

# =========================================================================
# Section 3: .[] | objects | select(path match) | .path
#            (file-path-based package lookup)
# =========================================================================
echo "--- Filter: .[] | objects | select(.path as \$p | startswith) | .path ---"
echo ""

assert_eq "Valid array: matches file to package" \
    "packages/core" \
    "$(jq -r --arg file "packages/core/src/index.ts" '.[] | objects | select(.path as $p | ($file == $p) or ($file | startswith($p + "/"))) | .path' "${VALID_FILE}" | head -1)"

assert_eq "Mixed array: matches file, ignores strings" \
    "packages/core" \
    "$(jq -r --arg file "packages/core/lib/utils.ts" '.[] | objects | select(.path as $p | ($file == $p) or ($file | startswith($p + "/"))) | .path' "${MIXED_FILE}" | head -1)"

assert_exit_ok "Mixed array: file path lookup does not crash" \
    jq -r --arg file "packages/core/lib/utils.ts" '.[] | objects | select(.path as $p | ($file == $p) or ($file | startswith($p + "/"))) | .path' "${MIXED_FILE}"

echo ""

# =========================================================================
# Section 4: .[] | objects | select(.path == $path)
#            (lookup package info by path)
# =========================================================================
echo "--- Filter: .[] | objects | select(.path == \$path) ---"
echo ""

assert_eq "Valid array: selects package by path" \
    "@org/core" \
    "$(jq -r --arg path "packages/core" '.[] | objects | select(.path == $path) | .name' "${VALID_FILE}")"

assert_eq "Mixed array: selects package by path, ignores strings" \
    "@org/core" \
    "$(jq -r --arg path "packages/core" '.[] | objects | select(.path == $path) | .name' "${MIXED_FILE}")"

assert_exit_ok "Mixed array: select by path does not crash" \
    jq --arg path "packages/core" '.[] | objects | select(.path == $path)' "${MIXED_FILE}"

echo ""

# =========================================================================
# Section 5: [.[] | objects | {(.scope): .path}] | add // {}
#            (build scope-to-path lookup object)
# =========================================================================
echo "--- Filter: [.[] | objects | {(.scope): .path}] | add // {} ---"
echo ""

assert_eq "Valid array: builds scope mapping" \
    '{"core":"packages/core","cli":"src/cli"}' \
    "$(jq -c '[.[] | objects | {(.scope): .path}] | add // {}' "${VALID_FILE}")"

assert_eq "Mixed array: builds scope mapping from objects only" \
    '{"core":"packages/core"}' \
    "$(jq -c '[.[] | objects | {(.scope): .path}] | add // {}' "${MIXED_FILE}")"

assert_eq "Strings-only array: returns empty object" \
    '{}' \
    "$(jq -c '[.[] | objects | {(.scope): .path}] | add // {}' "${STRINGS_FILE}")"

assert_eq "Empty array: returns empty object" \
    '{}' \
    "$(jq -c '[.[] | objects | {(.scope): .path}] | add // {}' "${EMPTY_FILE}")"

echo ""

# =========================================================================
# Section 6: [.[] | objects | .path] | map({(.): []}) | add // {}
#            (initialize per-package commits map)
# =========================================================================
echo "--- Filter: [.[] | objects | .path] | map({(.): []}) | add // {} ---"
echo ""

assert_eq "Valid array: builds per-package commit map" \
    '{"packages/core":[],"src/cli":[]}' \
    "$(jq -c '[.[] | objects | .path] | map({(.): []}) | add // {}' "${VALID_FILE}")"

assert_eq "Mixed array: builds map from objects only" \
    '{"packages/core":[]}' \
    "$(jq -c '[.[] | objects | .path] | map({(.): []}) | add // {}' "${MIXED_FILE}")"

assert_eq "Strings-only array: returns empty object" \
    '{}' \
    "$(jq -c '[.[] | objects | .path] | map({(.): []}) | add // {}' "${STRINGS_FILE}")"

echo ""

# =========================================================================
# Section 7: all(type == "object") validation
#            (improved validation catches mixed arrays)
# =========================================================================
echo "--- Filter: all(type == \"object\") validation ---"
echo ""

assert_eq "Valid array: all objects -> true" \
    "true" \
    "$(echo "${VALID_PACKAGES}" | jq -r 'if type == "array" and all(type == "object") then "true" else "false" end')"

assert_eq "Mixed array: not all objects -> false" \
    "false" \
    "$(echo "${MIXED_PACKAGES}" | jq -r 'if type == "array" and all(type == "object") then "true" else "false" end')"

assert_eq "Strings-only array: no objects -> false" \
    "false" \
    "$(echo "${STRINGS_ONLY}" | jq -r 'if type == "array" and all(type == "object") then "true" else "false" end')"

assert_eq "Empty array: vacuously true" \
    "true" \
    "$(echo "${EMPTY}" | jq -r 'if type == "array" and all(type == "object") then "true" else "false" end')"

echo ""

# =========================================================================
# Section 8: Temp file (cp from WORKSPACE_PACKAGES_FILE) vs echo piping
# =========================================================================
echo "--- Temp file copy approach ---"
echo ""

# Simulate the cp-from-file approach in detect-version-bump.sh / parse-commits.sh
SRC_FILE=$(mktemp)
echo "${MIXED_PACKAGES}" > "${SRC_FILE}"
DST_FILE=$(mktemp)
cp "${SRC_FILE}" "${DST_FILE}"

assert_eq "cp preserves JSON content" \
    "$(cat "${SRC_FILE}")" \
    "$(cat "${DST_FILE}")"

assert_exit_ok "jq on copied file with objects guard does not crash" \
    jq -r '.[] | objects | .path' "${DST_FILE}"

assert_eq "jq on copied file returns correct paths" \
    "packages/core" \
    "$(jq -r '.[] | objects | .path' "${DST_FILE}")"

rm -f "${SRC_FILE}" "${DST_FILE}"

echo ""

# =========================================================================
# Section 9: Large monorepo simulation (27 packages + stray string)
#            Reproduces the exact CI failure scenario
# =========================================================================
echo "--- Large monorepo (27 packages + stray string) ---"
echo ""

LARGE_PKGS=$(python3 -c "
import json
packages = []
for i in range(27):
    packages.append({
        'name': '@tinyclaw/pkg%d' % i,
        'version': '1.1.0',
        'path': 'packages/pkg%d' % i,
        'scope': 'pkg%d' % i,
        'private': True
    })
print(json.dumps(packages))
")

LARGE_MIXED=$(python3 -c "
import json
packages = []
for i in range(27):
    packages.append({
        'name': '@tinyclaw/pkg%d' % i,
        'version': '1.1.0',
        'path': 'packages/pkg%d' % i,
        'scope': 'pkg%d' % i,
        'private': True
    })
packages.append('stray_string_from_corruption')
print(json.dumps(packages))
")

LARGE_FILE=$(mktemp)
LARGE_MIXED_FILE=$(mktemp)
echo "${LARGE_PKGS}" > "${LARGE_FILE}"
echo "${LARGE_MIXED}" > "${LARGE_MIXED_FILE}"

assert_eq "27 valid packages: path count is 27" \
    "27" \
    "$(jq -r '.[] | objects | .path' "${LARGE_FILE}" | wc -l | tr -d ' ')"

assert_exit_ok "27 packages + stray string: no crash with objects guard" \
    jq -r '.[] | objects | .path' "${LARGE_MIXED_FILE}"

assert_eq "27 packages + stray string: still returns 27 paths" \
    "27" \
    "$(jq -r '.[] | objects | .path' "${LARGE_MIXED_FILE}" | wc -l | tr -d ' ')"

assert_eq "27 packages + stray string: scope lookup works" \
    "packages/pkg13" \
    "$(jq -r --arg scope "pkg13" '.[] | objects | select(.scope == $scope) | .path' "${LARGE_MIXED_FILE}")"

assert_eq "27 packages + stray string: file path lookup works" \
    "packages/pkg5" \
    "$(jq -r --arg file "packages/pkg5/src/index.ts" '.[] | objects | select(.path as $p | ($file == $p) or ($file | startswith($p + "/"))) | .path' "${LARGE_MIXED_FILE}" | head -1)"

assert_eq "27 packages + stray string: all(type==\"object\") catches it" \
    "false" \
    "$(echo "${LARGE_MIXED}" | jq -r 'if type == "array" and all(type == "object") then "true" else "false" end')"

rm -f "${LARGE_FILE}" "${LARGE_MIXED_FILE}"

echo ""

# =========================================================================
# Summary
# =========================================================================
echo "=== Test Summary ==="
echo "Total: ${test_count}"
echo -e "${GREEN}Passed: ${passed_count}${NC}"
if [[ "${failed_count}" -gt 0 ]]; then
    echo -e "${RED}Failed: ${failed_count}${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
