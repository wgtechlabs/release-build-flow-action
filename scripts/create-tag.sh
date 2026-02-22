#!/bin/bash
# =============================================================================
# CREATE TAG
# =============================================================================
# Creates git tags for releases
# Supports both single-package and monorepo modes (per-package tags)
# Optionally updates the major version tag (e.g., v1) to point to the release
#
# Environment Variables:
#   - GITHUB_TOKEN
#   - GIT_USER_NAME
#   - GIT_USER_EMAIL
#   - VERSION_TAG
#   - MONOREPO
#   - PACKAGES_DATA (JSON array of package data with tags)
#   - UPDATE_MAJOR_TAG (true/false - update major version tag)
#   - VERSION_PREFIX (version prefix, e.g., v)
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

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

# =============================================================================
# CONFIGURATION
# =============================================================================

MONOREPO="${MONOREPO:-false}"
VERSION_TAG="${VERSION_TAG:-}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"
COMMIT_CONVENTION="${COMMIT_CONVENTION:-clean-commit}"
UPDATE_MAJOR_TAG="${UPDATE_MAJOR_TAG:-false}"
VERSION_PREFIX="${VERSION_PREFIX:-v}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Format tag message based on chosen convention
format_tag_message() {
    local tag="$1"
    
    if [[ "${COMMIT_CONVENTION}" == "clean-commit" ]]; then
        echo "🚀 release: ${tag}"
    else
        echo "Release ${tag}"
    fi
}

# Extract major version tag from a semver tag
# e.g., v1.2.3 -> v1, release-2.3.4 -> release-2
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

# =============================================================================
# MAIN LOGIC
# =============================================================================

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

if [[ "${MONOREPO}" == "true" && "${PACKAGES_DATA}" != "[]" ]]; then
    log_info "Creating tags for monorepo packages..."
    
    if command -v jq &> /dev/null; then
        # Create tags for each package (filter by bumpType to exclude packages without version bumps)
        echo "${PACKAGES_DATA}" | jq -r '.[] | select(.bumpType != "none") | "\(.tag)|\(.name)"' | while IFS='|' read -r tag name; do
            [[ -z "${tag}" ]] && continue
            
            log_info "Creating tag: ${tag} for ${name}"
            TAG_MSG=$(format_tag_message "${tag}")
            git tag -a "${tag}" -m "${TAG_MSG}"
            git push origin "${tag}"
        done
        
        log_success "Created tags for all updated packages"
    else
        log_info "jq not available, creating unified tag"
        TAG_MSG=$(format_tag_message "${VERSION_TAG}")
        git tag -a "${VERSION_TAG}" -m "${TAG_MSG}"
        git push origin "${VERSION_TAG}"
    fi
else
    log_info "Creating tag: ${VERSION_TAG}"
    TAG_MSG=$(format_tag_message "${VERSION_TAG}")
    git tag -a "${VERSION_TAG}" -m "${TAG_MSG}"
    git push origin "${VERSION_TAG}"
    log_success "Tag created successfully"
fi

# =============================================================================
# UPDATE MAJOR VERSION TAG
# =============================================================================
# Standard practice for GitHub Actions: maintain a floating major version tag
# (e.g., v1) that points to the latest release within that major version.
# This allows consumers to use @v1 to automatically get bug fixes and
# non-breaking updates without changing their workflow files.
# =============================================================================

MAJOR_TAG=""

if [[ "${UPDATE_MAJOR_TAG}" == "true" ]]; then
    log_info "Updating major version tag..."
    
    MAJOR_TAG=$(extract_major_tag "${VERSION_TAG}")
    
    if [[ -n "${MAJOR_TAG}" ]]; then
        log_info "Updating ${MAJOR_TAG} to point to ${VERSION_TAG}"
        git tag -f "${MAJOR_TAG}" "${VERSION_TAG}"
        git push -f origin "${MAJOR_TAG}"
        log_success "Major version tag ${MAJOR_TAG} updated to ${VERSION_TAG}"
    else
        log_warning "Cannot extract major version from tag: ${VERSION_TAG}"
        log_warning "Expected format: <prefix>X.Y.Z (e.g., v1.2.3)"
    fi
fi

# Output the major tag for downstream steps
echo "major-tag=${MAJOR_TAG}" >> "$GITHUB_OUTPUT"
