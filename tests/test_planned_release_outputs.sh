#!/bin/bash
# Test planned release output behavior in detect-version-bump.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="${SCRIPT_DIR}/../scripts/detect-version-bump.sh"
TEST_ROOT="${SCRIPT_DIR}/.scratch/test_planned_release_outputs"

test_count=0
passed_count=0
failed_count=0

cleanup() {
    rm -rf "${TEST_ROOT}"
}

trap cleanup EXIT

create_repo() {
    local repo_dir="$1"
    local commit_subject="$2"

    rm -rf "${repo_dir}"
    mkdir -p "${repo_dir}"

    (
        cd "${repo_dir}"
        git init --quiet
        git config core.autocrlf false
        git config user.name "Test User"
        git config user.email "test@example.com"

        cat > README.md <<'EOF'
# Test Repository
EOF
        git add README.md
        git commit --quiet -m "chore: initial release"
        git tag v1.0.0

        printf '\n%s\n' "${commit_subject}" >> README.md
        git add README.md
        git commit --quiet -m "${commit_subject}"
    )
}

run_detect() {
    local repo_dir="$1"
    shift

    local output_file="${repo_dir}/github-output.txt"
    : > "${output_file}"

    (
        cd "${repo_dir}"
        env GITHUB_OUTPUT="${output_file}" "$@" bash "${DETECT_SCRIPT}" >/dev/null 2>&1
    )
}

assert_output() {
    local test_name="$1"
    local output_file="$2"
    local key="$3"
    local expected="$4"
    local actual

    test_count=$((test_count + 1))
    actual="$(grep -E "^${key}=" "${output_file}" | tail -n 1 | cut -d'=' -f2- || true)"

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

echo "=== Testing planned release outputs ==="
echo ""

planned_repo="${TEST_ROOT}/planned"
create_repo "${planned_repo}" "feat: add release planning mode"
run_detect "${planned_repo}" \
    VERSION_PREFIX=v \
    INITIAL_VERSION=0.1.0 \
    PLANNED_VERSION=2.0.0 \
    PLANNED_VERSION_TAG=v2.0.0 \
    PLANNED_VERSION_BUMP_TYPE=major \
    PLANNED_PREVIOUS_VERSION=1.9.0

assert_output "Planned release uses provided version" "${planned_repo}/github-output.txt" "version" "2.0.0"
assert_output "Planned release uses provided tag" "${planned_repo}/github-output.txt" "version-tag" "v2.0.0"
assert_output "Planned release uses provided previous version" "${planned_repo}/github-output.txt" "previous-version" "1.9.0"
assert_output "Planned release exposes derived previous tag" "${planned_repo}/github-output.txt" "previous-tag" "v1.9.0"
assert_output "Planned release uses provided bump type" "${planned_repo}/github-output.txt" "version-bump-type" "major"

legacy_repo="${TEST_ROOT}/legacy"
create_repo "${legacy_repo}" "fix: resolve release detection bug"
run_detect "${legacy_repo}" \
    VERSION_PREFIX=v \
    INITIAL_VERSION=0.1.0

assert_output "Legacy detection still calculates version" "${legacy_repo}/github-output.txt" "version" "1.0.1"
assert_output "Legacy detection still calculates tag" "${legacy_repo}/github-output.txt" "version-tag" "v1.0.1"
assert_output "Legacy detection still reports previous version" "${legacy_repo}/github-output.txt" "previous-version" "1.0.0"
assert_output "Legacy detection still reports previous tag" "${legacy_repo}/github-output.txt" "previous-tag" "v1.0.0"
assert_output "Legacy detection still reports bump type" "${legacy_repo}/github-output.txt" "version-bump-type" "patch"

echo ""
echo "=== Results: ${passed_count}/${test_count} passed ==="

if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi

echo "All tests passed!"
