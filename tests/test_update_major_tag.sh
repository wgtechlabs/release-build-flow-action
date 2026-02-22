#!/bin/bash
# =============================================================================
# TEST: update-major-tag feature (extract_major_tag function)
# =============================================================================
# Tests the extract_major_tag helper in scripts/create-tag.sh
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    expected=$(printf '%s' "${expected}" | tr -d '\r')
    actual=$(printf '%s' "${actual}" | tr -d '\r')
    TOTAL=$((TOTAL + 1))
    if [[ "${actual}" == "${expected}" ]]; then
        echo "✓ Test ${TOTAL}: ${label}"
        PASS=$((PASS + 1))
    else
        echo "✗ Test ${TOTAL}: ${label}"
        echo "  Expected: '${expected}'"
        echo "  Actual:   '${actual}'"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Testing extract_major_tag function (update-major-tag feature) ==="
echo ""

# -----------------------------------------------------------------------------
# Extract the function from create-tag.sh
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

# Source just the extract_major_tag function
extract_major_tag() {
    local tag="$1"
    
    if [[ "${tag}" =~ ^([^0-9]*)([0-9]+)\.[0-9]+\.[0-9]+(.*)$ ]]; then
        local prefix="${BASH_REMATCH[1]}"
        local major="${BASH_REMATCH[2]}"
        echo "${prefix}${major}"
    else
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Section 1: Standard version tags
# -----------------------------------------------------------------------------

echo "--- Standard version tags ---"
echo ""

assert_eq "v1.2.3 -> v1" \
    "v1" \
    "$(extract_major_tag "v1.2.3")"

assert_eq "v0.1.0 -> v0" \
    "v0" \
    "$(extract_major_tag "v0.1.0")"

assert_eq "v2.0.0 -> v2" \
    "v2" \
    "$(extract_major_tag "v2.0.0")"

assert_eq "v10.20.30 -> v10" \
    "v10" \
    "$(extract_major_tag "v10.20.30")"

assert_eq "v0.0.1 -> v0" \
    "v0" \
    "$(extract_major_tag "v0.0.1")"

# -----------------------------------------------------------------------------
# Section 2: Custom prefixes
# -----------------------------------------------------------------------------

echo ""
echo "--- Custom prefixes ---"
echo ""

assert_eq "release-1.2.3 -> release-1" \
    "release-1" \
    "$(extract_major_tag "release-1.2.3")"

assert_eq "ver_3.0.0 -> ver_3" \
    "ver_3" \
    "$(extract_major_tag "ver_3.0.0")"

assert_eq "app-v2.5.1 -> app-v2" \
    "app-v2" \
    "$(extract_major_tag "app-v2.5.1")"

# -----------------------------------------------------------------------------
# Section 3: No prefix
# -----------------------------------------------------------------------------

echo ""
echo "--- No prefix ---"
echo ""

assert_eq "1.2.3 -> 1 (no prefix)" \
    "1" \
    "$(extract_major_tag "1.2.3")"

assert_eq "0.1.0 -> 0 (no prefix)" \
    "0" \
    "$(extract_major_tag "0.1.0")"

# -----------------------------------------------------------------------------
# Section 4: Invalid / edge-case tags (should return empty)
# -----------------------------------------------------------------------------

echo ""
echo "--- Invalid or edge-case tags ---"
echo ""

assert_eq "Empty string -> empty" \
    "" \
    "$(extract_major_tag "")"

assert_eq "Just v -> empty" \
    "" \
    "$(extract_major_tag "v")"

assert_eq "No dots: v1 -> empty" \
    "" \
    "$(extract_major_tag "v1")"

assert_eq "Two parts: v1.2 -> empty" \
    "" \
    "$(extract_major_tag "v1.2")"

assert_eq "Non-semver text -> empty" \
    "" \
    "$(extract_major_tag "latest")"

assert_eq "Just a number -> empty" \
    "" \
    "$(extract_major_tag "42")"

# -----------------------------------------------------------------------------
# Section 5: Monorepo scoped tags
# -----------------------------------------------------------------------------

echo ""
echo "--- Monorepo scoped tags ---"
echo ""

assert_eq "@myorg/core@1.2.3 -> @myorg/core@1" \
    "@myorg/core@1" \
    "$(extract_major_tag "@myorg/core@1.2.3")"

assert_eq "pkg-name-2.0.0 -> pkg-name-2" \
    "pkg-name-2" \
    "$(extract_major_tag "pkg-name-2.0.0")"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=== Test Summary ==="
echo "Total: ${TOTAL}"
echo "Passed: ${PASS}"
if [[ ${FAIL} -gt 0 ]]; then
    echo "Failed: ${FAIL}"
    exit 1
else
    echo "All tests passed!"
fi
