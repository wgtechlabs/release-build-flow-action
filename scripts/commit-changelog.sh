#!/bin/bash
# =============================================================================
# COMMIT CHANGELOG
# =============================================================================
# Commits changelog changes to the repository
# Supports both single-package and monorepo modes
#
# Environment Variables:
#   - GITHUB_TOKEN
#   - GIT_USER_NAME
#   - GIT_USER_EMAIL
#   - VERSION_TAG
#   - CHANGELOG_PATH
#   - MONOREPO
#   - WORKSPACE_PACKAGES
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

# =============================================================================
# CONFIGURATION
# =============================================================================

MONOREPO="${MONOREPO:-false}"
CHANGELOG_PATH="${CHANGELOG_PATH:-./CHANGELOG.md}"
VERSION_TAG="${VERSION_TAG:-}"
WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"

# =============================================================================
# MAIN LOGIC
# =============================================================================

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

if [[ -z "$(git status --porcelain)" ]]; then
    log_info "No changelog changes to commit"
    exit 0
fi

# Add changelog files
if [[ "${MONOREPO}" == "true" ]]; then
    log_info "Committing monorepo changelogs..."
    
    # Add root changelog if exists
    if [[ -f "${CHANGELOG_PATH}" ]]; then
        git add "${CHANGELOG_PATH}"
    fi
    
    # Add per-package changelogs
    if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
        echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path' | while IFS= read -r pkg_path; do
            if [[ -f "${pkg_path}/CHANGELOG.md" ]]; then
                git add "${pkg_path}/CHANGELOG.md"
            fi
        done
    fi
    
    git commit -m "chore: update changelogs for ${VERSION_TAG}"
else
    log_info "Committing changelog..."
    git add "${CHANGELOG_PATH}"
    git commit -m "chore: update CHANGELOG.md for ${VERSION_TAG}"
fi

git push

log_success "Changelog committed successfully"
