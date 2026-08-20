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
    local initial_tag="${3-v1.0.0}"

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
        if [[ -n "${initial_tag}" ]]; then
            git tag "${initial_tag}"
        fi

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

assert_detect_failure() {
    local test_name="$1"
    local repo_dir="$2"
    local expected_message="$3"
    shift 3

    local output_file="${repo_dir}/github-output.txt"
    local stderr_file="${repo_dir}/detect-stderr.txt"
    : > "${output_file}"
    : > "${stderr_file}"

    test_count=$((test_count + 1))

    if (
        cd "${repo_dir}"
        env GITHUB_OUTPUT="${output_file}" "$@" bash "${DETECT_SCRIPT}" >/dev/null 2>"${stderr_file}"
    ); then
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected detect-version-bump.sh to fail"
        failed_count=$((failed_count + 1))
        return
    fi

    if grep -Fq "${expected_message}" "${stderr_file}"; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        echo "  Expected error containing: [${expected_message}]"
        echo "  Error output:"
        sed 's/^/    /' "${stderr_file}"
        failed_count=$((failed_count + 1))
    fi
}

get_output_value() {
    local output_file="$1"
    local key="$2"

    grep -E "^${key}=" "${output_file}" | tail -n 1 | cut -d'=' -f2- || true
}

assert_output() {
    local test_name="$1"
    local output_file="$2"
    local key="$3"
    local expected="$4"
    local actual

    test_count=$((test_count + 1))
    actual="$(get_output_value "${output_file}" "${key}")"

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
create_repo "${planned_repo}" "feat: add release planning mode" "v1.9.0"
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

initial_planned_repo="${TEST_ROOT}/initial-planned"
create_repo "${initial_planned_repo}" "feat: finalize initial planned release" ""
run_detect "${initial_planned_repo}" \
    VERSION_PREFIX=v \
    INITIAL_VERSION=0.1.0 \
    PLANNED_VERSION=0.1.0-beta.1+build.7 \
    PLANNED_VERSION_TAG=v0.1.0-beta.1+build.7 \
    PLANNED_VERSION_BUMP_TYPE=patch \
    PLANNED_PREVIOUS_VERSION=

assert_output "Initial planned release uses provided prerelease version" "${initial_planned_repo}/github-output.txt" "version" "0.1.0-beta.1+build.7"
assert_output "Initial planned release has no previous version" "${initial_planned_repo}/github-output.txt" "previous-version" ""
assert_output "Initial planned release has no previous tag" "${initial_planned_repo}/github-output.txt" "previous-tag" ""

missing_tag_repo="${TEST_ROOT}/missing-tag"
create_repo "${missing_tag_repo}" "feat: finalize planned release"
assert_detect_failure "Planned release fails when planned previous tag is unavailable" "${missing_tag_repo}" "Planned previous tag v1.9.0 is unavailable after fetching tags" \
    VERSION_PREFIX=v \
    INITIAL_VERSION=0.1.0 \
    PLANNED_VERSION=2.0.0 \
    PLANNED_VERSION_TAG=v2.0.0 \
    PLANNED_VERSION_BUMP_TYPE=major \
    PLANNED_PREVIOUS_VERSION=1.9.0

prerelease_conflict_repo="${TEST_ROOT}/prerelease-conflict"
create_repo "${prerelease_conflict_repo}" "feat: finalize planned release" "v1.9.0"
assert_detect_failure "Planned release fails when prerelease-prefix is also set" "${prerelease_conflict_repo}" "prerelease-prefix cannot be combined with planned release inputs" \
    VERSION_PREFIX=v \
    INITIAL_VERSION=0.1.0 \
    PRERELEASE_PREFIX=beta \
    PLANNED_VERSION=2.0.0 \
    PLANNED_VERSION_TAG=v2.0.0 \
    PLANNED_VERSION_BUMP_TYPE=major \
    PLANNED_PREVIOUS_VERSION=1.9.0

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
