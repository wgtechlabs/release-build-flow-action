#!/bin/bash
# Test for detect_manifest_version function in scripts/detect-version-bump.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="${SCRIPT_DIR}/../scripts/detect-version-bump.sh"

if [ ! -f "${DETECT_SCRIPT}" ]; then
    echo "Error: cannot find detect-version-bump script at ${DETECT_SCRIPT}" >&2
    exit 1
fi

# Extract detect_manifest_version function
detect_manifest_version_def="$(
    awk '
        /^detect_manifest_version[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^}/ { exit }
    ' "${DETECT_SCRIPT}"
)"

if [ -z "${detect_manifest_version_def}" ]; then
    echo "Error: could not extract detect_manifest_version from ${DETECT_SCRIPT}" >&2
    exit 1
fi

# Stubs for log helpers
log_info()    { :; }
log_warning() { :; }
log_success() { :; }
log_error()   { :; }
log_debug()   { :; }

eval "${detect_manifest_version_def}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local result="$2"
    local expected="$3"

    test_count=$((test_count + 1))

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

# =============================================================================
# SETUP: temporary working directory
# =============================================================================
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_TEST}"' EXIT

echo "=== Testing detect_manifest_version function ==="
echo ""

# =============================================================================
# package.json tests
# =============================================================================

# Test 1: Detect version from package.json
pushd "${TMPDIR_TEST}" > /dev/null
cat > package.json <<'EOF'
{
  "name": "my-app",
  "version": "2.3.4"
}
EOF
result=$(detect_manifest_version)
run_test "package.json: detect version" "${result}" "2.3.4"
rm -f package.json
popd > /dev/null

# Test 2: package.json with no version field
pushd "${TMPDIR_TEST}" > /dev/null
cat > package.json <<'EOF'
{
  "name": "my-app"
}
EOF
result=$(detect_manifest_version)
run_test "package.json: no version field returns empty" "${result}" ""
rm -f package.json
popd > /dev/null

# Test 3: package.json with non-semver version returns empty
pushd "${TMPDIR_TEST}" > /dev/null
cat > package.json <<'EOF'
{
  "name": "my-app",
  "version": "latest"
}
EOF
result=$(detect_manifest_version)
run_test "package.json: non-semver version returns empty" "${result}" ""
rm -f package.json
popd > /dev/null

# =============================================================================
# Cargo.toml tests
# =============================================================================

# Test 4: Detect version from Cargo.toml [package] section
pushd "${TMPDIR_TEST}" > /dev/null
cat > Cargo.toml <<'EOF'
[package]
name = "my-crate"
version = "1.5.0"

[dependencies]
serde = "1.0"
EOF
result=$(detect_manifest_version)
run_test "Cargo.toml: detect version from [package]" "${result}" "1.5.0"
rm -f Cargo.toml
popd > /dev/null

# Test 5: Cargo.toml ignores version in [dependencies]
pushd "${TMPDIR_TEST}" > /dev/null
cat > Cargo.toml <<'EOF'
[package]
name = "my-crate"

[dependencies]
version = "2.0.0"
EOF
result=$(detect_manifest_version)
run_test "Cargo.toml: no version in [package] returns empty" "${result}" ""
rm -f Cargo.toml
popd > /dev/null

# =============================================================================
# pyproject.toml tests
# =============================================================================

# Test 6: Detect version from pyproject.toml [project] section
pushd "${TMPDIR_TEST}" > /dev/null
cat > pyproject.toml <<'EOF'
[project]
name = "my-package"
version = "3.0.1"
EOF
result=$(detect_manifest_version)
run_test "pyproject.toml: detect version from [project]" "${result}" "3.0.1"
rm -f pyproject.toml
popd > /dev/null

# Test 7: Detect version from pyproject.toml [tool.poetry] section
pushd "${TMPDIR_TEST}" > /dev/null
cat > pyproject.toml <<'EOF'
[tool.poetry]
name = "my-package"
version = "0.9.0"
EOF
result=$(detect_manifest_version)
run_test "pyproject.toml: detect version from [tool.poetry]" "${result}" "0.9.0"
rm -f pyproject.toml
popd > /dev/null

# =============================================================================
# pubspec.yaml tests
# =============================================================================

# Test 8: Detect version from pubspec.yaml
pushd "${TMPDIR_TEST}" > /dev/null
cat > pubspec.yaml <<'EOF'
name: my_app
version: 1.2.3+4
EOF
result=$(detect_manifest_version)
run_test "pubspec.yaml: detect version (strips build metadata)" "${result}" "1.2.3"
rm -f pubspec.yaml
popd > /dev/null

# Test 9: Detect plain version from pubspec.yaml
pushd "${TMPDIR_TEST}" > /dev/null
cat > pubspec.yaml <<'EOF'
name: my_app
version: 4.0.0
EOF
result=$(detect_manifest_version)
run_test "pubspec.yaml: detect plain version" "${result}" "4.0.0"
rm -f pubspec.yaml
popd > /dev/null

# =============================================================================
# Fallback / priority tests
# =============================================================================

# Test 10: No manifest files returns empty
pushd "${TMPDIR_TEST}" > /dev/null
rm -f package.json Cargo.toml pyproject.toml pubspec.yaml
result=$(detect_manifest_version)
run_test "No manifest files: returns empty" "${result}" ""
popd > /dev/null

# Test 11: package.json takes priority over other files
pushd "${TMPDIR_TEST}" > /dev/null
cat > package.json <<'EOF'
{
  "name": "my-app",
  "version": "1.0.0"
}
EOF
cat > Cargo.toml <<'EOF'
[package]
name = "my-crate"
version = "2.0.0"
EOF
result=$(detect_manifest_version)
run_test "Priority: package.json wins over Cargo.toml" "${result}" "1.0.0"
rm -f package.json Cargo.toml
popd > /dev/null

# =============================================================================
# RESULTS
# =============================================================================

echo ""
echo "=== Results: ${passed_count}/${test_count} passed ==="

if [ "${failed_count}" -gt 0 ]; then
    echo -e "${RED}${failed_count} test(s) failed${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
fi
