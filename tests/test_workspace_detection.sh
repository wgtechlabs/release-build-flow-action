#!/bin/bash
# Test for workspace detection and monorepo WORKSPACE_PACKAGES handling
#
# Verifies that:
# 1. get_package_info produces valid JSON objects (not strings)
# 2. WORKSPACE_PACKAGES is properly built as an array of objects
# 3. jq .[].path works correctly on the output
# 4. build_scope_mapping produces valid JSON
# 5. Multiple packages (simulating a large monorepo) produce correct output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_SCRIPT="${SCRIPT_DIR}/../scripts/detect-workspace.sh"

if [ ! -f "${WORKSPACE_SCRIPT}" ]; then
    echo "Error: cannot find detect-workspace.sh at ${WORKSPACE_SCRIPT}" >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

pass_test() {
    local test_name="$1"
    test_count=$((test_count + 1))
    passed_count=$((passed_count + 1))
    echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
}

fail_test() {
    local test_name="$1"
    local detail="${2:-}"
    test_count=$((test_count + 1))
    failed_count=$((failed_count + 1))
    echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
    if [[ -n "${detail}" ]]; then
        echo "  ${detail}"
    fi
}

# Check jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required for these tests" >&2
    exit 1
fi

echo "=== Testing workspace detection and WORKSPACE_PACKAGES format ==="
echo ""

# Extract get_package_info function
get_func() {
    local func_name="$1"
    awk "/^${func_name}[[:space:]]*\\(\\)[[:space:]]*\\{/ { in_func=1 }
         in_func { print }
         in_func && /^\\}/ { exit }" "${WORKSPACE_SCRIPT}"
}

get_package_info_def="$(get_func "get_package_info")"
build_scope_mapping_def="$(get_func "build_scope_mapping")"

if [ -z "${get_package_info_def}" ]; then
    echo "Error: could not extract get_package_info from ${WORKSPACE_SCRIPT}" >&2
    exit 1
fi

if [ -z "${build_scope_mapping_def}" ]; then
    echo "Error: could not extract build_scope_mapping from ${WORKSPACE_SCRIPT}" >&2
    exit 1
fi

# Create temp directory for test packages
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# =============================================================================
# Test 1: get_package_info produces a valid JSON object
# =============================================================================

mkdir -p "${TMPDIR}/packages/core"
cat > "${TMPDIR}/packages/core/package.json" << 'EOF'
{
  "name": "@myapp/core",
  "version": "1.0.0",
  "private": true
}
EOF

RESULT=$(bash << BASH_EOF 2>/dev/null
set -euo pipefail
${get_package_info_def}
get_package_info "${TMPDIR}/packages/core"
BASH_EOF
)

if echo "${RESULT}" | jq -e 'type == "object"' > /dev/null 2>&1; then
    pass_test "get_package_info produces JSON object"
else
    fail_test "get_package_info produces JSON object" "Got: ${RESULT}"
fi

# =============================================================================
# Test 2: get_package_info output is compact (single line)
# =============================================================================

LINE_COUNT=$(echo "${RESULT}" | wc -l | tr -d ' ')
if [[ "${LINE_COUNT}" == "1" ]]; then
    pass_test "get_package_info produces compact single-line JSON"
else
    fail_test "get_package_info produces compact single-line JSON" "Expected 1 line, got ${LINE_COUNT} lines"
fi

# =============================================================================
# Test 3: get_package_info has correct fields
# =============================================================================

HAS_PATH=$(echo "${RESULT}" | jq -r '.path')
HAS_NAME=$(echo "${RESULT}" | jq -r '.name')
HAS_SCOPE=$(echo "${RESULT}" | jq -r '.scope')

# Check name and scope (skip exact path check as it varies across OS)
if [[ "${HAS_NAME}" == "@myapp/core" ]] && [[ "${HAS_SCOPE}" == "core" ]] && [[ "${HAS_PATH}" == *"/packages/core" ]]; then
    pass_test "get_package_info has correct name, path, and scope"
else
    fail_test "get_package_info has correct name, path, and scope" "path=${HAS_PATH}, name=${HAS_NAME}, scope=${HAS_SCOPE}"
fi

# =============================================================================
# Test 4: Multiple packages build correct JSON array
# =============================================================================

# Create multiple packages simulating a monorepo
for pkg in core cli web config logger types secrets; do
    mkdir -p "${TMPDIR}/packages/${pkg}"
    cat > "${TMPDIR}/packages/${pkg}/package.json" << PKGEOF
{
  "name": "@myapp/${pkg}",
  "version": "1.1.0",
  "private": true
}
PKGEOF
done

# Simulate the PACKAGES_JSON construction using jq (as in fixed detect-workspace.sh)
PACKAGES_JSON=$(bash << BASH_EOF 2>/dev/null
set -euo pipefail
${get_package_info_def}

PACKAGES_JSON="[]"
for pkg_dir in "${TMPDIR}"/packages/*; do
    [[ -d "\${pkg_dir}" ]] || continue
    PKG_INFO=\$(get_package_info "\${pkg_dir}")
    if [[ -n "\${PKG_INFO}" ]]; then
        PACKAGES_JSON=\$(echo "\${PACKAGES_JSON}" | jq -c --argjson pkg "\${PKG_INFO}" '. += [\$pkg]')
    fi
done
echo "\${PACKAGES_JSON}"
BASH_EOF
)

PKG_COUNT=$(echo "${PACKAGES_JSON}" | jq 'length')
if [[ "${PKG_COUNT}" == "7" ]]; then
    pass_test "Multiple packages: correct count (${PKG_COUNT})"
else
    fail_test "Multiple packages: correct count" "Expected 7, got ${PKG_COUNT}"
fi

# =============================================================================
# Test 5: .[].path works on the built array
# =============================================================================

PATHS=$(echo "${PACKAGES_JSON}" | jq -r '.[].path' 2>&1)
PATH_EXIT=$?

if [[ "${PATH_EXIT}" == "0" ]] && [[ -n "${PATHS}" ]]; then
    pass_test "jq '.[].path' works on packages array"
else
    fail_test "jq '.[].path' works on packages array" "Exit code: ${PATH_EXIT}, Output: ${PATHS}"
fi

# =============================================================================
# Test 6: Elements are objects, not strings
# =============================================================================

FIRST_TYPE=$(echo "${PACKAGES_JSON}" | jq -r '.[0] | type')
if [[ "${FIRST_TYPE}" == "object" ]]; then
    pass_test "Array elements are objects (type: ${FIRST_TYPE})"
else
    fail_test "Array elements are objects" "First element type: ${FIRST_TYPE}"
fi

# =============================================================================
# Test 7: Compact JSON survives echo + jq -c round-trip
# =============================================================================

COMPACT=$(echo "${PACKAGES_JSON}" | jq -c '.')
COMPACT_LINE_COUNT=$(echo "${COMPACT}" | wc -l | tr -d ' ')
COMPACT_TYPE=$(echo "${COMPACT}" | jq -r '.[0] | type')

if [[ "${COMPACT_LINE_COUNT}" == "1" ]] && [[ "${COMPACT_TYPE}" == "object" ]]; then
    pass_test "Compact JSON round-trip preserves object types"
else
    fail_test "Compact JSON round-trip preserves object types" "Lines: ${COMPACT_LINE_COUNT}, Type: ${COMPACT_TYPE}"
fi

# =============================================================================
# Test 8: build_scope_mapping produces valid JSON object
# =============================================================================

SCOPE_MAP=$(bash << BASH_EOF 2>/dev/null
set -euo pipefail
${build_scope_mapping_def}
build_scope_mapping '${PACKAGES_JSON}'
BASH_EOF
)

SCOPE_MAP_TYPE=$(echo "${SCOPE_MAP}" | jq -r 'type' 2>/dev/null || echo "invalid")
if [[ "${SCOPE_MAP_TYPE}" == "object" ]]; then
    pass_test "build_scope_mapping produces JSON object"
else
    fail_test "build_scope_mapping produces JSON object" "Type: ${SCOPE_MAP_TYPE}, Value: ${SCOPE_MAP}"
fi

# =============================================================================
# Test 9: Unscoped package name (like 'tinyclaw') gets correct scope
# =============================================================================

mkdir -p "${TMPDIR}/src/cli"
cat > "${TMPDIR}/src/cli/package.json" << 'EOF'
{
  "name": "tinyclaw",
  "version": "1.1.0"
}
EOF

UNSCOPED_RESULT=$(bash << BASH_EOF 2>/dev/null
set -euo pipefail
${get_package_info_def}
get_package_info "${TMPDIR}/src/cli"
BASH_EOF
)

UNSCOPED_SCOPE=$(echo "${UNSCOPED_RESULT}" | jq -r '.scope')
if [[ "${UNSCOPED_SCOPE}" == "tinyclaw" ]]; then
    pass_test "Unscoped package name gets correct scope: ${UNSCOPED_SCOPE}"
else
    fail_test "Unscoped package name gets correct scope" "Expected: tinyclaw, Got: ${UNSCOPED_SCOPE}"
fi

# =============================================================================
# Test 10: Package without private field gets private=false
# =============================================================================

UNSCOPED_PRIVATE=$(echo "${UNSCOPED_RESULT}" | jq -r '.private')
if [[ "${UNSCOPED_PRIVATE}" == "false" ]]; then
    pass_test "Package without private field defaults to false"
else
    fail_test "Package without private field defaults to false" "Got: ${UNSCOPED_PRIVATE}"
fi

# =============================================================================
# Test 11: Large monorepo (25 packages) produces valid output
# =============================================================================

# Create 25 packages simulating tinyclaw structure
rm -rf "${TMPDIR}/large_mono"
mkdir -p "${TMPDIR}/large_mono"

pkg_names=(compactor config core delegation heartware intercom learning logger
    matcher memory plugins pulse queue router sandbox secrets shell shield types)
for pkg in "${pkg_names[@]}"; do
    mkdir -p "${TMPDIR}/large_mono/packages/${pkg}"
    cat > "${TMPDIR}/large_mono/packages/${pkg}/package.json" << PKGEOF
{
  "name": "@tinyclaw/${pkg}",
  "version": "1.1.0",
  "private": true
}
PKGEOF
done

for app in cli web landing; do
    mkdir -p "${TMPDIR}/large_mono/src/${app}"
    if [[ "${app}" == "cli" ]]; then
        cat > "${TMPDIR}/large_mono/src/${app}/package.json" << 'PKGEOF'
{
  "name": "tinyclaw",
  "version": "1.1.0"
}
PKGEOF
    else
        cat > "${TMPDIR}/large_mono/src/${app}/package.json" << PKGEOF
{
  "name": "@tinyclaw/${app}",
  "version": "1.1.0",
  "private": true
}
PKGEOF
    fi
done

# Plugins with nested paths
mkdir -p "${TMPDIR}/large_mono/plugins/channel/plugin-channel-discord"
cat > "${TMPDIR}/large_mono/plugins/channel/plugin-channel-discord/package.json" << 'EOF'
{
  "name": "@tinyclaw/plugin-channel-discord",
  "version": "1.1.0"
}
EOF

mkdir -p "${TMPDIR}/large_mono/plugins/channel/plugin-channel-friends"
cat > "${TMPDIR}/large_mono/plugins/channel/plugin-channel-friends/package.json" << 'EOF'
{
  "name": "@tinyclaw/plugin-channel-friends",
  "version": "1.1.0"
}
EOF

mkdir -p "${TMPDIR}/large_mono/plugins/provider/plugin-provider-openai"
cat > "${TMPDIR}/large_mono/plugins/provider/plugin-provider-openai/package.json" << 'EOF'
{
  "name": "@tinyclaw/plugin-provider-openai",
  "version": "1.1.0"
}
EOF

LARGE_PACKAGES_JSON=$(bash << BASH_EOF 2>/dev/null
set -euo pipefail
${get_package_info_def}

PACKAGES_JSON="[]"
for pkg_dir in "${TMPDIR}"/large_mono/packages/* "${TMPDIR}"/large_mono/src/* "${TMPDIR}"/large_mono/plugins/channel/* "${TMPDIR}"/large_mono/plugins/provider/*; do
    [[ -d "\${pkg_dir}" ]] || continue
    [[ -f "\${pkg_dir}/package.json" ]] || continue
    PKG_INFO=\$(get_package_info "\${pkg_dir}")
    if [[ -n "\${PKG_INFO}" ]]; then
        PACKAGES_JSON=\$(echo "\${PACKAGES_JSON}" | jq -c --argjson pkg "\${PKG_INFO}" '. += [\$pkg]')
    fi
done
echo "\${PACKAGES_JSON}"
BASH_EOF
)

LARGE_COUNT=$(echo "${LARGE_PACKAGES_JSON}" | jq 'length')
LARGE_FIRST_TYPE=$(echo "${LARGE_PACKAGES_JSON}" | jq -r '.[0] | type')
LARGE_PATHS_OK=$(echo "${LARGE_PACKAGES_JSON}" | jq -r '.[].path' > /dev/null 2>&1 && echo "yes" || echo "no")

if [[ "${LARGE_COUNT}" == "25" ]] && [[ "${LARGE_FIRST_TYPE}" == "object" ]] && [[ "${LARGE_PATHS_OK}" == "yes" ]]; then
    pass_test "Large monorepo (25 packages): valid output, all objects, paths accessible"
else
    fail_test "Large monorepo (25 packages)" "Count: ${LARGE_COUNT}, Type: ${LARGE_FIRST_TYPE}, Paths OK: ${LARGE_PATHS_OK}"
fi

# =============================================================================
# Test 12: Compact JSON round-trip for large monorepo
# =============================================================================

LARGE_COMPACT=$(echo "${LARGE_PACKAGES_JSON}" | jq -c '.')
LARGE_COMPACT_LINES=$(echo "${LARGE_COMPACT}" | wc -l | tr -d ' ')
LARGE_COMPACT_TYPE=$(echo "${LARGE_COMPACT}" | jq -r '.[0] | type')
LARGE_COMPACT_COUNT=$(echo "${LARGE_COMPACT}" | jq 'length')

if [[ "${LARGE_COMPACT_LINES}" == "1" ]] && [[ "${LARGE_COMPACT_TYPE}" == "object" ]] && [[ "${LARGE_COMPACT_COUNT}" == "25" ]]; then
    pass_test "Large monorepo compact round-trip: 1 line, 25 objects"
else
    fail_test "Large monorepo compact round-trip" "Lines: ${LARGE_COMPACT_LINES}, Type: ${LARGE_COMPACT_TYPE}, Count: ${LARGE_COMPACT_COUNT}"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "=== Results: ${passed_count}/${test_count} tests passed ==="

if [[ "${failed_count}" -gt 0 ]]; then
    echo -e "${RED}${failed_count} tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
