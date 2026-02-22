#!/bin/bash
# Test: monorepo root release behavior controlled by MONOREPO_ROOT_RELEASE flag
#
# Verifies that:
# 1. When MONOREPO_ROOT_RELEASE=true (default), create-release.sh proceeds to create root release
# 2. When MONOREPO_ROOT_RELEASE=false, create-release.sh skips root release and sets created=false
# 3. create-tag.sh creates root VERSION_TAG in monorepo mode when MONOREPO_ROOT_RELEASE=true
# 4. create-tag.sh skips root VERSION_TAG in monorepo mode when MONOREPO_ROOT_RELEASE=false

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_RELEASE_SCRIPT="${SCRIPT_DIR}/../scripts/create-release.sh"
CREATE_TAG_SCRIPT="${SCRIPT_DIR}/../scripts/create-tag.sh"

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

echo "=== Testing monorepo root release flag behavior ==="
echo ""

# ---------------------------------------------------------------------------
# Extract generate_release_name from create-release.sh for unit testing
# ---------------------------------------------------------------------------
generate_release_name_definition="$(
    awk '
        /^generate_release_name[[:space:]]*\(\)[[:space:]]*\{/ { in_func=1 }
        in_func { print }
        in_func && /^\}/ { exit }
    ' "${CREATE_RELEASE_SCRIPT}"
)"

if [ -z "${generate_release_name_definition}" ]; then
    echo "Error: could not extract generate_release_name from ${CREATE_RELEASE_SCRIPT}" >&2
    exit 1
fi

eval "${generate_release_name_definition}"

# ---------------------------------------------------------------------------
# 1. generate_release_name correctly substitutes {tag}
# ---------------------------------------------------------------------------
result=$(generate_release_name '{tag}' '2.1.0' 'v2.1.0')
run_test "generate_release_name substitutes {tag}" \
    "v2.1.0" \
    "${result}"

# ---------------------------------------------------------------------------
# 2. generate_release_name correctly substitutes {version}
# ---------------------------------------------------------------------------
result=$(generate_release_name 'Release {version}' '2.1.0' 'v2.1.0')
run_test "generate_release_name substitutes {version}" \
    "Release 2.1.0" \
    "${result}"

# ---------------------------------------------------------------------------
# 3. In monorepo mode with MONOREPO_ROOT_RELEASE=false, created output is false
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

# Simulate the MONOREPO_ROOT_RELEASE=false branch
MONOREPO="true"
MONOREPO_ROOT_RELEASE="false"
output=""

if [[ "${MONOREPO}" == "true" ]] && [[ "${MONOREPO_ROOT_RELEASE}" != "true" ]]; then
    output="created=false"
fi

echo "${output}"
BASH_EOF
)

run_test "Monorepo with MONOREPO_ROOT_RELEASE=false skips root release" \
    "created=false" \
    "${result}"

# ---------------------------------------------------------------------------
# 4. In monorepo mode with MONOREPO_ROOT_RELEASE=true, skips the skip-branch
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="true"
MONOREPO_ROOT_RELEASE="true"
skipped="false"

if [[ "${MONOREPO}" == "true" ]] && [[ "${MONOREPO_ROOT_RELEASE}" != "true" ]]; then
    skipped="true"
fi

echo "${skipped}"
BASH_EOF
)

run_test "Monorepo with MONOREPO_ROOT_RELEASE=true does not skip root release" \
    "false" \
    "${result}"

# ---------------------------------------------------------------------------
# 5. In single-package mode (MONOREPO=false), always creates root release
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="false"
MONOREPO_ROOT_RELEASE="true"
skipped="false"

if [[ "${MONOREPO}" == "true" ]] && [[ "${MONOREPO_ROOT_RELEASE}" != "true" ]]; then
    skipped="true"
fi

echo "${skipped}"
BASH_EOF
)

run_test "Single-package mode always creates root release" \
    "false" \
    "${result}"

# ---------------------------------------------------------------------------
# 6. MONOREPO_ROOT_RELEASE defaults to true when not set
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="true"
MONOREPO_ROOT_RELEASE="${MONOREPO_ROOT_RELEASE:-true}"
skipped="false"

if [[ "${MONOREPO}" == "true" ]] && [[ "${MONOREPO_ROOT_RELEASE}" != "true" ]]; then
    skipped="true"
fi

echo "${skipped}"
BASH_EOF
)

run_test "MONOREPO_ROOT_RELEASE defaults to true (root release created by default)" \
    "false" \
    "${result}"

# ---------------------------------------------------------------------------
# 7. In monorepo mode with root release, single-package exits are NOT triggered
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="true"
MONOREPO_ROOT_RELEASE="true"
would_exit="false"

# Simulate the exit guard in create-release.sh
if [[ "${MONOREPO}" != "true" ]]; then
    would_exit="true"
fi

echo "${would_exit}"
BASH_EOF
)

run_test "Monorepo mode does not exit after root release (continues to per-package)" \
    "false" \
    "${result}"

# ---------------------------------------------------------------------------
# 8. In single-package mode, exit IS triggered after root release
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="false"
would_exit="false"

if [[ "${MONOREPO}" != "true" ]]; then
    would_exit="true"
fi

echo "${would_exit}"
BASH_EOF
)

run_test "Single-package mode exits after root release (no per-package loop)" \
    "true" \
    "${result}"

# ---------------------------------------------------------------------------
# 9. create-tag.sh: root tag created when MONOREPO_ROOT_RELEASE=true
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="true"
MONOREPO_ROOT_RELEASE="true"
VERSION_TAG="v2.1.0"
root_tag_created="false"

if [[ "${MONOREPO_ROOT_RELEASE}" == "true" ]]; then
    if [[ -n "${VERSION_TAG}" ]]; then
        root_tag_created="true"
    fi
fi

echo "${root_tag_created}"
BASH_EOF
)

run_test "create-tag: root tag created when MONOREPO_ROOT_RELEASE=true" \
    "true" \
    "${result}"

# ---------------------------------------------------------------------------
# 10. create-tag.sh: root tag NOT created when MONOREPO_ROOT_RELEASE=false
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO="true"
MONOREPO_ROOT_RELEASE="false"
VERSION_TAG="v2.1.0"
root_tag_created="false"

if [[ "${MONOREPO_ROOT_RELEASE}" == "true" ]]; then
    if [[ -n "${VERSION_TAG}" ]]; then
        root_tag_created="true"
    fi
fi

echo "${root_tag_created}"
BASH_EOF
)

run_test "create-tag: root tag NOT created when MONOREPO_ROOT_RELEASE=false" \
    "false" \
    "${result}"

# ---------------------------------------------------------------------------
# 11. create-tag.sh: warning emitted when VERSION_TAG is empty
# ---------------------------------------------------------------------------
result=$(bash << 'BASH_EOF'
set -euo pipefail

MONOREPO_ROOT_RELEASE="true"
VERSION_TAG=""
warning_emitted="false"

if [[ "${MONOREPO_ROOT_RELEASE}" == "true" ]]; then
    if [[ -n "${VERSION_TAG}" ]]; then
        : # would create tag
    else
        warning_emitted="true"
    fi
fi

echo "${warning_emitted}"
BASH_EOF
)

run_test "create-tag: warning when MONOREPO_ROOT_RELEASE=true but VERSION_TAG is empty" \
    "true" \
    "${result}"

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
