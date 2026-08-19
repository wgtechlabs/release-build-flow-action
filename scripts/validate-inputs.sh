#!/bin/bash
# =============================================================================
# VALIDATE INPUTS
# =============================================================================
# Validates action inputs before processing
#
# Environment Variables (from action.yml):
#   - MAIN_BRANCH
#   - VERSION_PREFIX
#   - INITIAL_VERSION
#   - PLANNED_VERSION
#   - PLANNED_VERSION_TAG
#   - PLANNED_VERSION_BUMP_TYPE
#   - PLANNED_PREVIOUS_VERSION
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

SEMVER_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

validate_semver() {
    local value="$1"
    local name="$2"

    if ! [[ "${value}" =~ ${SEMVER_PATTERN} ]]; then
        log_error "${name} must be plain X.Y.Z (e.g., 0.1.0 or 1.2.3)"
        exit 1
    fi
}

# =============================================================================
# VALIDATION
# =============================================================================

log_info "Validating inputs..."

# Validate branch names
if [[ -z "${MAIN_BRANCH:-}" ]]; then
    log_error "main-branch is required"
    exit 1
fi

CURRENT_BRANCH="${CURRENT_BRANCH:-${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}}"

if [[ -z "${CURRENT_BRANCH}" ]]; then
    log_warning "Current branch could not be detected; skipping production branch guard"
elif [[ "${CURRENT_BRANCH}" != "${MAIN_BRANCH}" ]]; then
    log_error "This action only runs on the configured production branch (${MAIN_BRANCH}). Current branch: ${CURRENT_BRANCH}"
    exit 1
fi

# Validate initial version format (SemVer)
if [[ -n "${INITIAL_VERSION:-}" ]]; then
    validate_semver "${INITIAL_VERSION}" "initial-version"
fi

planned_input_count=0
for planned_value in \
    "${PLANNED_VERSION:-}" \
    "${PLANNED_VERSION_TAG:-}" \
    "${PLANNED_VERSION_BUMP_TYPE:-}" \
    "${PLANNED_PREVIOUS_VERSION:-}"; do
    if [[ -n "${planned_value}" ]]; then
        planned_input_count=$((planned_input_count + 1))
    fi
done

if [[ "${planned_input_count}" -ne 0 ]] && [[ "${planned_input_count}" -ne 4 ]]; then
    log_error "planned-version, planned-version-tag, planned-version-bump-type, and planned-previous-version must all be provided together"
    exit 1
fi

if [[ "${planned_input_count}" -eq 4 ]]; then
    validate_semver "${PLANNED_VERSION}" "planned-version"
    validate_semver "${PLANNED_PREVIOUS_VERSION}" "planned-previous-version"

    case "${PLANNED_VERSION_BUMP_TYPE}" in
        major|minor|patch)
            ;;
        *)
            log_error "planned-version-bump-type must be one of: major, minor, patch"
            exit 1
            ;;
    esac

    expected_planned_tag="${VERSION_PREFIX:-}${PLANNED_VERSION}"
    if [[ "${PLANNED_VERSION_TAG}" != "${expected_planned_tag}" ]]; then
        log_error "planned-version-tag must match ${expected_planned_tag}"
        exit 1
    fi
fi

log_success "All inputs are valid"
