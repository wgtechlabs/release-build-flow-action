#!/bin/bash
# Test for sync_version_files functionality in scripts/sync-version-files.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/../scripts/sync-version-files.sh"

if [ ! -f "${SYNC_SCRIPT}" ]; then
    echo "Error: cannot find sync-version-files script at ${SYNC_SCRIPT}" >&2
    exit 1
fi

# Extract helper functions for testing
get_func() {
    local func_name="$1"
    awk "/^${func_name}[[:space:]]*\\(\\)[[:space:]]*\\{/ { in_func=1 }
         in_func { print }
         in_func && /^\\}/ { exit }" "${SYNC_SCRIPT}"
}

update_package_json_def="$(get_func "update_package_json")"
update_cargo_toml_def="$(get_func "update_cargo_toml")"
update_pyproject_toml_def="$(get_func "update_pyproject_toml")"
update_pubspec_yaml_def="$(get_func "update_pubspec_yaml")"
detect_version_files_def="$(get_func "detect_version_files")"

if [ -z "${update_package_json_def}" ]; then
    echo "Error: could not extract update_package_json from ${SYNC_SCRIPT}" >&2; exit 1
fi
if [ -z "${update_cargo_toml_def}" ]; then
    echo "Error: could not extract update_cargo_toml from ${SYNC_SCRIPT}" >&2; exit 1
fi
if [ -z "${update_pyproject_toml_def}" ]; then
    echo "Error: could not extract update_pyproject_toml from ${SYNC_SCRIPT}" >&2; exit 1
fi
if [ -z "${update_pubspec_yaml_def}" ]; then
    echo "Error: could not extract update_pubspec_yaml from ${SYNC_SCRIPT}" >&2; exit 1
fi
if [ -z "${detect_version_files_def}" ]; then
    echo "Error: could not extract detect_version_files from ${SYNC_SCRIPT}" >&2; exit 1
fi

# Stubs for log helpers used inside the extracted functions
log_info()    { :; }
log_warning() { echo "WARN: $1" >&2; }
log_success() { :; }
log_error()   { echo "ERR: $1" >&2; }

eval "${update_package_json_def}"
eval "${update_cargo_toml_def}"
eval "${update_pyproject_toml_def}"
eval "${update_pubspec_yaml_def}"
eval "${detect_version_files_def}"

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

echo "=== Testing sync-version-files helper functions ==="
echo ""

# =============================================================================
# package.json tests
# =============================================================================

# Test 1: update_package_json basic
PKG_FILE="${TMPDIR_TEST}/package.json"
cat > "${PKG_FILE}" <<'EOF'
{
  "name": "my-app",
  "version": "1.0.0"
}
EOF
update_package_json "${PKG_FILE}" "2.3.4"
result="$(jq -r '.version' "${PKG_FILE}")"
run_test "update_package_json: basic version bump" "${result}" "2.3.4"

# Test 2: update_package_json preserves other fields
result_name="$(jq -r '.name' "${PKG_FILE}")"
run_test "update_package_json: preserves other fields" "${result_name}" "my-app"

# Test 3: update_package_json no-op when already at target version
update_package_json "${PKG_FILE}" "2.3.4"
result="$(jq -r '.version' "${PKG_FILE}")"
run_test "update_package_json: no-op when already at target" "${result}" "2.3.4"

# Test 4: update_package_json with pre-existing complex version
cat > "${PKG_FILE}" <<'EOF'
{
  "name": "pkg",
  "version": "0.2.4",
  "description": "test"
}
EOF
update_package_json "${PKG_FILE}" "0.3.0"
result="$(jq -r '.version' "${PKG_FILE}")"
run_test "update_package_json: updates from 0.2.4 to 0.3.0" "${result}" "0.3.0"

# =============================================================================
# Cargo.toml tests
# =============================================================================

# Test 5: update_cargo_toml basic (version under [package])
CARGO_FILE="${TMPDIR_TEST}/Cargo.toml"
cat > "${CARGO_FILE}" <<'EOF'
[package]
name = "my-crate"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = "1.0"
EOF
update_cargo_toml "${CARGO_FILE}" "1.2.0"
result="$(awk '/^\[package\]/{in_pkg=1;next} /^\[/{in_pkg=0} in_pkg && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${CARGO_FILE}")"
run_test "update_cargo_toml: basic version bump" "${result}" "1.2.0"

# Test 6: update_cargo_toml does not change dependency version
dep_version="$(grep 'serde' "${CARGO_FILE}" | sed 's/.*= *"\(.*\)"/\1/')"
run_test "update_cargo_toml: does not change dependency versions" "${dep_version}" "1.0"

# Test 7: update_cargo_toml scoped - version before [package] is untouched
cat > "${CARGO_FILE}" <<'EOF'
[workspace]
version = "0.0.1"

[package]
name = "my-crate"
version = "0.2.0"
edition = "2021"

[dependencies]
dep = { version = "1.5.0" }
EOF
update_cargo_toml "${CARGO_FILE}" "0.3.0"
pkg_version="$(awk '/^\[package\]/{in_pkg=1;next} /^\[/{in_pkg=0} in_pkg && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${CARGO_FILE}")"
ws_version="$(awk '/^\[workspace\]/{in_ws=1;next} /^\[/{in_ws=0} in_ws && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${CARGO_FILE}")"
dep_ver="$(grep 'dep = ' "${CARGO_FILE}" | sed 's/.*version = *"\([^"]*\)".*/\1/')"
run_test "update_cargo_toml: [package] version updated" "${pkg_version}" "0.3.0"
run_test "update_cargo_toml: [workspace] version unchanged" "${ws_version}" "0.0.1"
run_test "update_cargo_toml: dependency version unchanged" "${dep_ver}" "1.5.0"

# =============================================================================
# pyproject.toml tests
# =============================================================================

# Test 10: update_pyproject_toml [project] style
PYPROJECT_FILE="${TMPDIR_TEST}/pyproject.toml"
cat > "${PYPROJECT_FILE}" <<'EOF'
[project]
name = "my-package"
version = "0.5.0"
description = "A package"
EOF
update_pyproject_toml "${PYPROJECT_FILE}" "1.0.0"
result="$(awk '/^\[project\]/{in_s=1;next} /^\[/{in_s=0} in_s && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${PYPROJECT_FILE}")"
run_test "update_pyproject_toml: [project] version bump" "${result}" "1.0.0"

# Test 11: update_pyproject_toml [tool.poetry] style
cat > "${PYPROJECT_FILE}" <<'EOF'
[tool.poetry]
name = "my-lib"
version = "2.0.0"
EOF
update_pyproject_toml "${PYPROJECT_FILE}" "2.1.0"
result="$(awk '/^\[tool\.poetry\]/{in_s=1;next} /^\[/{in_s=0} in_s && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${PYPROJECT_FILE}")"
run_test "update_pyproject_toml: [tool.poetry] version bump" "${result}" "2.1.0"

# Test 12: update_pyproject_toml scoped - earlier unrelated version is untouched
cat > "${PYPROJECT_FILE}" <<'EOF'
[tool.black]
line-length = 88
version = "23.1.0"

[project]
name = "my-package"
version = "0.5.0"
description = "A package"
EOF
update_pyproject_toml "${PYPROJECT_FILE}" "1.0.0"
project_version="$(awk '/^\[project\]/{in_s=1;next} /^\[/{in_s=0} in_s && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${PYPROJECT_FILE}")"
black_version="$(awk '/^\[tool\.black\]/{in_s=1;next} /^\[/{in_s=0} in_s && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${PYPROJECT_FILE}")"
run_test "update_pyproject_toml: [project] scoped version bump" "${project_version}" "1.0.0"
run_test "update_pyproject_toml: [tool.black] version unchanged" "${black_version}" "23.1.0"

# Test 14: update_pyproject_toml [tool.poetry] with earlier dependency version
cat > "${PYPROJECT_FILE}" <<'EOF'
[tool.poetry.dependencies]
python = "^3.10"
my-lib = { version = "3.0.0" }

[tool.poetry]
name = "my-lib"
version = "2.0.0"
EOF
update_pyproject_toml "${PYPROJECT_FILE}" "2.1.0"
poetry_version="$(awk '/^\[tool\.poetry\]/{in_s=1;next} /^\[/{in_s=0} in_s && /^version[[:space:]]*=/{match($0,/"[^"]*"/);print substr($0,RSTART+1,RLENGTH-2);exit}' "${PYPROJECT_FILE}")"
dep_version="$(sed -n 's/.*my-lib[[:space:]]*=[[:space:]]*{[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${PYPROJECT_FILE}")"
run_test "update_pyproject_toml: [tool.poetry] scoped version bump" "${poetry_version}" "2.1.0"
run_test "update_pyproject_toml: [tool.poetry.dependencies] version unchanged" "${dep_version}" "3.0.0"

# =============================================================================
# pubspec.yaml tests
# =============================================================================

# update_pubspec_yaml basic
PUBSPEC_FILE="${TMPDIR_TEST}/pubspec.yaml"
cat > "${PUBSPEC_FILE}" <<'EOF'
name: my_flutter_app
description: A Flutter app
version: 1.0.0+1
environment:
  sdk: '>=2.17.0 <3.0.0'
EOF
update_pubspec_yaml "${PUBSPEC_FILE}" "1.1.0"
result="$(grep '^version:' "${PUBSPEC_FILE}" | sed 's/^version:[[:space:]]*//')"
run_test "update_pubspec_yaml: basic version bump" "${result}" "1.1.0"

# =============================================================================
# detect_version_files tests
# =============================================================================

# auto-detection finds package.json when present
DETECT_DIR="${TMPDIR_TEST}/detect_test"
mkdir -p "${DETECT_DIR}"
touch "${DETECT_DIR}/package.json"
result="$(cd "${DETECT_DIR}" && detect_version_files)"
run_test "detect_version_files: finds package.json" "${result}" "package.json"

# auto-detection returns empty when no manifest files present
EMPTY_DIR="${TMPDIR_TEST}/empty_test"
mkdir -p "${EMPTY_DIR}"
result="$(cd "${EMPTY_DIR}" && detect_version_files)"
run_test "detect_version_files: empty result when no manifests" "${result}" ""

# auto-detection finds multiple files
MULTI_DIR="${TMPDIR_TEST}/multi_test"
mkdir -p "${MULTI_DIR}"
touch "${MULTI_DIR}/package.json"
touch "${MULTI_DIR}/Cargo.toml"
result="$(cd "${MULTI_DIR}" && detect_version_files)"
run_test "detect_version_files: finds multiple manifests" "${result}" "package.json,Cargo.toml"

# =============================================================================
# Integration: run full sync-version-files.sh with env vars
# =============================================================================

# Integration: SYNC_VERSION_FILES=false skips updates
INT_DIR="${TMPDIR_TEST}/integration_skip"
mkdir -p "${INT_DIR}"
cat > "${INT_DIR}/package.json" <<'EOF'
{"name":"app","version":"1.0.0"}
EOF
(
    cd "${INT_DIR}"
    SYNC_VERSION_FILES="false" VERSION="2.0.0" VERSION_FILE_PATHS="package.json" \
        bash "${SYNC_SCRIPT}" > /dev/null 2>&1
)
result="$(jq -r '.version' "${INT_DIR}/package.json")"
run_test "Integration: SYNC_VERSION_FILES=false does not update" "${result}" "1.0.0"

# Full integration with package.json
INT_DIR2="${TMPDIR_TEST}/integration_run"
mkdir -p "${INT_DIR2}"
cat > "${INT_DIR2}/package.json" <<'EOF'
{"name":"app","version":"1.0.0"}
EOF
(
    cd "${INT_DIR2}"
    SYNC_VERSION_FILES="true" VERSION="3.0.0" VERSION_FILE_PATHS="package.json" \
        bash "${SYNC_SCRIPT}" > /dev/null 2>&1
)
result="$(jq -r '.version' "${INT_DIR2}/package.json")"
run_test "Integration: updates package.json version" "${result}" "3.0.0"

# Integration with auto-detection (no VERSION_FILE_PATHS)
INT_DIR3="${TMPDIR_TEST}/integration_auto"
mkdir -p "${INT_DIR3}"
cat > "${INT_DIR3}/package.json" <<'EOF'
{"name":"app","version":"0.1.0"}
EOF
(
    cd "${INT_DIR3}"
    SYNC_VERSION_FILES="true" VERSION="0.5.0" VERSION_FILE_PATHS="" \
        bash "${SYNC_SCRIPT}" > /dev/null 2>&1
)
result="$(jq -r '.version' "${INT_DIR3}/package.json")"
run_test "Integration: auto-detects and updates package.json" "${result}" "0.5.0"

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
