#!/bin/bash
# =============================================================================
# CREATE TAG
# =============================================================================
# Creates git tags for releases
# Supports both single-package and monorepo modes (per-package tags)
#
# Environment Variables:
#   - GITHUB_TOKEN
#   - GIT_USER_NAME
#   - GIT_USER_EMAIL
#   - VERSION_TAG
#   - MONOREPO
#   - PACKAGES_DATA (JSON array of package data with tags)
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

# =============================================================================
# CONFIGURATION
# =============================================================================

MONOREPO="${MONOREPO:-false}"
VERSION_TAG="${VERSION_TAG:-}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"

# =============================================================================
# MAIN LOGIC
# =============================================================================

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

if [[ "${MONOREPO}" == "true" && "${PACKAGES_DATA}" != "[]" ]]; then
    log_info "Creating tags for monorepo packages..."
    
    if command -v jq &> /dev/null; then
        # Create tags for each package
        echo "${PACKAGES_DATA}" | jq -r '.[] | select(.tag != null) | "\(.tag)|\(.name)"' | while IFS='|' read -r tag name; do
            [[ -z "${tag}" ]] && continue
            
            log_info "Creating tag: ${tag} for ${name}"
            git tag -a "${tag}" -m "Release ${tag}"
            git push origin "${tag}"
        done
        
        log_success "Created tags for all updated packages"
    else
        log_info "jq not available, creating unified tag"
        git tag -a "${VERSION_TAG}" -m "Release ${VERSION_TAG}"
        git push origin "${VERSION_TAG}"
    fi
else
    log_info "Creating tag: ${VERSION_TAG}"
    git tag -a "${VERSION_TAG}" -m "Release ${VERSION_TAG}"
    git push origin "${VERSION_TAG}"
    log_success "Tag created successfully"
fi
