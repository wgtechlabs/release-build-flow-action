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
echo "=== Results: ${passed_count}/${test_count} passed ==="

if [[ ${failed_count} -gt 0 ]]; then
    exit 1
fi

echo "All tests passed!"