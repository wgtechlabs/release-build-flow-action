#!/bin/bash
# Test the Clean Commit [Unreleased] lifecycle in generate-changelog.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_CHANGELOG_SCRIPT="${SCRIPT_DIR}/../scripts/generate-changelog.sh"

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    shift

    test_count=$((test_count + 1))

    if "$@"; then
        echo -e "${GREEN}✓${NC} Test ${test_count}: ${test_name}"
        passed_count=$((passed_count + 1))
    else
        echo -e "${RED}✗${NC} Test ${test_count}: ${test_name}"
        failed_count=$((failed_count + 1))
    fi
}

run_generate() {
    local changelog_path="$1"
    local github_output="$2"
    local version="$3"
    local version_tag="$4"
    local bump_type="$5"
    local commits_json="$6"

    CHANGELOG_PATH="${changelog_path}" \
    GITHUB_OUTPUT="${github_output}" \
    VERSION="${version}" \
    VERSION_TAG="${version_tag}" \
    VERSION_BUMP_TYPE="${bump_type}" \
    COMMITS_JSON="${commits_json}" \
    COMMIT_CONVENTION="clean-commit" \
    bash "${GENERATE_CHANGELOG_SCRIPT}" >/dev/null
}

run_generate_monorepo() {
    local changelog_path="$1"
    local github_output="$2"
    local version="$3"
    local version_tag="$4"
    local bump_type="$5"
    local commits_json="$6"
    local packages_data="$7"
    local per_package_commits="$8"
    local root_changelog="$9"
    local per_package_changelog="${10}"

    CHANGELOG_PATH="${changelog_path}" \
    GITHUB_OUTPUT="${github_output}" \
    VERSION="${version}" \
    VERSION_TAG="${version_tag}" \
    VERSION_BUMP_TYPE="${bump_type}" \
    COMMITS_JSON="${commits_json}" \
    COMMIT_CONVENTION="clean-commit" \
    MONOREPO="true" \
    ROOT_CHANGELOG="${root_changelog}" \
    PER_PACKAGE_CHANGELOG="${per_package_changelog}" \
    PACKAGES_DATA="${packages_data}" \
    PER_PACKAGE_COMMITS="${per_package_commits}" \
    bash "${GENERATE_CHANGELOG_SCRIPT}" >/dev/null
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

changelog_path="${tmp_dir}/CHANGELOG.md"
github_output="${tmp_dir}/github-output.txt"

non_release_commits='[
  {"type":"docs","section":"Changed","description":"document branch guard behavior"},
  {"type":"setup","section":"Changed","description":"tighten workflow defaults"},
  {"type":"test","section":"Changed","description":"cover unreleased changelog flow"}
]'

release_commits='[
  {"type":"docs","section":"Changed","description":"document branch guard behavior"},
  {"type":"setup","section":"Changed","description":"tighten workflow defaults"},
  {"type":"test","section":"Changed","description":"cover unreleased changelog flow"},
  {"type":"new","section":"Added","description":"ship unreleased changelog support"}
]'

monorepo_packages='[
    {"name":"pkg-a","path":"TMP_PACKAGES/pkg-a","oldVersion":"1.2.0","version":"1.3.0","bumpType":"minor","tag":"pkg-a@1.3.0"},
    {"name":"pkg-b","path":"TMP_PACKAGES/pkg-b","oldVersion":"2.0.0","version":"2.0.0","bumpType":"none","tag":""}
]'

monorepo_per_package_no_release='{
    "TMP_PACKAGES/pkg-a": [
        {"type":"docs","section":"Changed","description":"document package a behavior"},
        {"type":"setup","section":"Changed","description":"tighten package a defaults"}
    ],
    "TMP_PACKAGES/pkg-b": [
        {"type":"new","section":"Added","description":"ship feature for package b"}
    ]
}'

monorepo_per_package_release='{
    "TMP_PACKAGES/pkg-a": [
        {"type":"docs","section":"Changed","description":"document package a behavior"},
        {"type":"setup","section":"Changed","description":"tighten package a defaults"},
        {"type":"new","section":"Added","description":"ship package a feature"}
    ],
    "TMP_PACKAGES/pkg-b": [
        {"type":"new","section":"Added","description":"ship feature for package b"}
    ]
}'

echo "=== Testing Clean Commit [Unreleased] lifecycle ==="
echo ""

run_generate "${changelog_path}" "${github_output}" "1.6.2" "v1.6.2" "none" "${non_release_commits}"

run_test "No-release run writes Changed section under [Unreleased]" \
    grep -Fq "### Changed" "${changelog_path}"

run_test "No-release run includes docs entry in [Unreleased]" \
    grep -Fq -- "- document branch guard behavior" "${changelog_path}"

run_test "No-release run reports updated=true" \
    grep -Fq "updated=true" "${github_output}"

: > "${github_output}"
run_generate "${changelog_path}" "${github_output}" "1.6.2" "v1.6.2" "none" "${non_release_commits}"

run_test "Repeated no-release run is idempotent" \
    grep -Fq "updated=false" "${github_output}"

entry_count="$(grep -Fc -- "- document branch guard behavior" "${changelog_path}" | tr -d '\r')"
run_test "Repeated no-release run does not duplicate [Unreleased] entries" \
    test "${entry_count}" = "1"

: > "${github_output}"
run_generate "${changelog_path}" "${github_output}" "1.6.2" "v1.6.2" "minor" "${release_commits}"

run_test "Release run creates the versioned entry" \
    grep -Fq "## [1.6.2] - " "${changelog_path}"

run_test "Release run carries maintenance commits into the release entry" \
    grep -Fq -- "- document branch guard behavior" "${changelog_path}"

run_test "Release run carries release-triggering commits into the release entry" \
    grep -Fq -- "- ship unreleased changelog support" "${changelog_path}"

run_test "Release run clears [Unreleased] content" \
    bash -c 'awk "BEGIN{capture=0} /^## \[Unreleased\]/{capture=1; next} capture && /^## \[/{exit} capture{print}" "$1" | grep -q "^[[:space:]]*$" && ! awk "BEGIN{capture=0} /^## \[Unreleased\]/{capture=1; next} capture && /^## \[/{exit} capture{print}" "$1" | grep -Fq "document branch guard behavior"' _ "${changelog_path}"

echo ""
echo "=== Testing monorepo Clean Commit [Unreleased] lifecycle ==="
echo ""

monorepo_dir="${tmp_dir}/packages"
mkdir -p "${monorepo_dir}/pkg-a" "${monorepo_dir}/pkg-b"
monorepo_root_changelog="${tmp_dir}/MONOREPO_CHANGELOG.md"
monorepo_pkg_a_changelog="${monorepo_dir}/pkg-a/CHANGELOG.md"
monorepo_pkg_b_changelog="${monorepo_dir}/pkg-b/CHANGELOG.md"
monorepo_output="${tmp_dir}/monorepo-output.txt"

monorepo_packages_resolved="${monorepo_packages//TMP_PACKAGES/${monorepo_dir}}"
monorepo_per_package_no_release_resolved="${monorepo_per_package_no_release//TMP_PACKAGES/${monorepo_dir}}"
monorepo_per_package_release_resolved="${monorepo_per_package_release//TMP_PACKAGES/${monorepo_dir}}"

run_generate_monorepo \
    "${monorepo_root_changelog}" \
    "${monorepo_output}" \
    "1.3.0" \
    "v1.3.0" \
    "none" \
    "${non_release_commits}" \
    "${monorepo_packages_resolved}" \
    "${monorepo_per_package_no_release_resolved}" \
    "false" \
    "true"

run_test "Monorepo no-release run respects root-changelog=false" \
    test ! -f "${monorepo_root_changelog}"

run_test "Monorepo no-release run writes package [Unreleased] when enabled" \
    grep -Fq -- "- document package a behavior" "${monorepo_pkg_a_changelog}"

run_test "Monorepo no-release run skips package without non-release-trigger commits" \
    test ! -f "${monorepo_pkg_b_changelog}"

run_test "Monorepo no-release run still reports updated=true from package changelog changes" \
    grep -Fq "updated=true" "${monorepo_output}"

: > "${monorepo_output}"
run_generate_monorepo \
    "${monorepo_root_changelog}" \
    "${monorepo_output}" \
    "1.3.0" \
    "v1.3.0" \
    "minor" \
    "${release_commits}" \
    "${monorepo_packages_resolved}" \
    "${monorepo_per_package_release_resolved}" \
    "false" \
    "true"

run_test "Monorepo release run still respects root-changelog=false" \
    test ! -f "${monorepo_root_changelog}"

run_test "Monorepo release run creates package version entry" \
    grep -Fq "## [1.3.0] - " "${monorepo_pkg_a_changelog}"

run_test "Monorepo release run carries package maintenance commits into version entry" \
    grep -Fq -- "- document package a behavior" "${monorepo_pkg_a_changelog}"

run_test "Monorepo release run clears package [Unreleased] content" \
    bash -c 'awk "BEGIN{capture=0} /^## \[Unreleased\]/{capture=1; next} capture && /^## \[/{exit} capture{print}" "$1" | grep -q "^[[:space:]]*$" && ! awk "BEGIN{capture=0} /^## \[Unreleased\]/{capture=1; next} capture && /^## \[/{exit} capture{print}" "$1" | grep -Fq "document package a behavior"' _ "${monorepo_pkg_a_changelog}"

echo ""
echo "=== Results: ${passed_count}/${test_count} passed ==="

if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi

echo "All tests passed!"