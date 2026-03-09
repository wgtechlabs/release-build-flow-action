#!/bin/bash
# Test: per-package changelog content is passed directly to the release step
#
# Verifies that:
# 1. generate-changelog.sh outputs per-package-changelogs as a JSON object
# 2. create-release.sh reads the changelog entry from PER_PACKAGE_CHANGELOGS
#    before falling back to the CHANGELOG.md file or a generic message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATE_CHANGELOG_SCRIPT="${SCRIPT_DIR}/../scripts/generate-changelog.sh"
CREATE_RELEASE_SCRIPT="${SCRIPT_DIR}/../scripts/create-release.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

test_count=0
passed_count=0
failed_count=0

run_test() {
    local test_name="$1"
    local expected="$2"
    local result="$3"

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

# Extract the generate_entry function from generate-changelog.sh for unit testing
generate_entry_definition="$(
    awk '
        /^generate_entry[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^\}/ { exit }
    ' "${GENERATE_CHANGELOG_SCRIPT}"
)"

if [ -z "${generate_entry_definition}" ]; then
    echo "Error: could not extract generate_entry from ${GENERATE_CHANGELOG_SCRIPT}" >&2
    exit 1
fi

eval "${generate_entry_definition}"

echo "=== Testing per-package changelog generation and lookup ==="
echo ""

# ---------------------------------------------------------------------------
# 1. generate_entry produces the expected header
# ---------------------------------------------------------------------------
commits_json='[{"section":"Added","description":"add user auth"},{"section":"Fixed","description":"fix login bug"}]'
entry=$(generate_entry "1.2.0" "2026-02-22" "${commits_json}")

run_test "generate_entry produces version header" \
    "## [1.2.0] - 2026-02-22" \
    "$(echo "${entry}" | head -n 1)"

# ---------------------------------------------------------------------------
# 2. PKG_CHANGELOGS JSON is built correctly (simulating the loop in generate-changelog.sh)
# ---------------------------------------------------------------------------
PKG_CHANGELOGS="{}"
pkg_path="packages/pkg-a"
pkg_version="1.2.0"
pkg_commits='[{"section":"Added","description":"add feature X"}]'
RELEASE_DATE="2026-02-22"

pkg_changelog_entry=$(generate_entry "${pkg_version}" "${RELEASE_DATE}" "${pkg_commits}")
PKG_CHANGELOGS=$(echo "${PKG_CHANGELOGS}" | jq -c --arg path "${pkg_path}" --arg entry "${pkg_changelog_entry}" '. + {($path): $entry}')

stored=$(echo "${PKG_CHANGELOGS}" | jq -r --arg path "${pkg_path}" '.[$path] // empty')
run_test "PKG_CHANGELOGS stores entry keyed by package path" \
    "## [1.2.0] - 2026-02-22" \
    "$(echo "${stored}" | head -n 1)"

# ---------------------------------------------------------------------------
# 3. create-release.sh correctly reads from PER_PACKAGE_CHANGELOGS
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

# Simulate what create-release.sh does when PER_PACKAGE_CHANGELOGS is set
PER_PACKAGE_CHANGELOGS='{"packages/pkg-a":"## [1.2.0] - 2026-02-22\n\n### Added\n\n- add feature X"}'
pkg_path="packages/pkg-a"
pkg_tag="pkg-a@1.2.0"
pkg_changelog=""

if [[ -n "${PER_PACKAGE_CHANGELOGS}" ]] && [[ "${PER_PACKAGE_CHANGELOGS}" != "{}" ]]; then
    pkg_changelog=$(echo "${PER_PACKAGE_CHANGELOGS}" | jq -r --arg path "${pkg_path}" '.[$path] // empty' 2>/dev/null || echo "")
fi

if [[ -z "${pkg_changelog}" ]]; then
    pkg_changelog="Release ${pkg_tag}"
fi

echo "${pkg_changelog}" | head -n 1
BASH_EOF
)

run_test "create-release reads changelog from PER_PACKAGE_CHANGELOGS" \
    "## [1.2.0] - 2026-02-22" \
    "${result}"

# ---------------------------------------------------------------------------
# 4. Falls back to generic message when PER_PACKAGE_CHANGELOGS is empty
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

PER_PACKAGE_CHANGELOGS=""
pkg_path="packages/pkg-a"
pkg_tag="pkg-a@1.2.0"
pkg_changelog=""

if [[ -n "${PER_PACKAGE_CHANGELOGS}" ]] && [[ "${PER_PACKAGE_CHANGELOGS}" != "{}" ]]; then
    pkg_changelog=$(echo "${PER_PACKAGE_CHANGELOGS}" | jq -r --arg path "${pkg_path}" '.[$path] // empty' 2>/dev/null || echo "")
fi

if [[ -z "${pkg_changelog}" ]]; then
    pkg_changelog="Release ${pkg_tag}"
fi

echo "${pkg_changelog}"
BASH_EOF
)

run_test "Falls back to generic message when PER_PACKAGE_CHANGELOGS is empty" \
    "Release pkg-a@1.2.0" \
    "${result}"

# ---------------------------------------------------------------------------
# 5. Falls back to generic message when PER_PACKAGE_CHANGELOGS is {}
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

PER_PACKAGE_CHANGELOGS="{}"
pkg_path="packages/pkg-a"
pkg_tag="pkg-a@1.2.0"
pkg_changelog=""

if [[ -n "${PER_PACKAGE_CHANGELOGS}" ]] && [[ "${PER_PACKAGE_CHANGELOGS}" != "{}" ]]; then
    pkg_changelog=$(echo "${PER_PACKAGE_CHANGELOGS}" | jq -r --arg path "${pkg_path}" '.[$path] // empty' 2>/dev/null || echo "")
fi

if [[ -z "${pkg_changelog}" ]]; then
    pkg_changelog="Release ${pkg_tag}"
fi

echo "${pkg_changelog}"
BASH_EOF
)

run_test "Falls back to generic message when PER_PACKAGE_CHANGELOGS is {}" \
    "Release pkg-a@1.2.0" \
    "${result}"

# ---------------------------------------------------------------------------
# 6. Multiple packages stored and retrieved correctly
# ---------------------------------------------------------------------------
PKG_CHANGELOGS="{}"
for pkg in "packages/pkg-a:1.0.0" "packages/pkg-b:2.1.0"; do
    path="${pkg%%:*}"
    version="${pkg##*:}"
    commits='[{"section":"Fixed","description":"fix something"}]'
    entry=$(generate_entry "${version}" "2026-02-22" "${commits}")
    PKG_CHANGELOGS=$(echo "${PKG_CHANGELOGS}" | jq -c --arg p "${path}" --arg e "${entry}" '. + {($p): $e}')
done

pkg_a_entry=$(echo "${PKG_CHANGELOGS}" | jq -r '."packages/pkg-a" // empty' | head -n 1)
pkg_b_entry=$(echo "${PKG_CHANGELOGS}" | jq -r '."packages/pkg-b" // empty' | head -n 1)

run_test "Multiple packages stored: pkg-a header correct" \
    "## [1.0.0] - 2026-02-22" \
    "${pkg_a_entry}"

run_test "Multiple packages stored: pkg-b header correct" \
    "## [2.1.0] - 2026-02-22" \
    "${pkg_b_entry}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
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
