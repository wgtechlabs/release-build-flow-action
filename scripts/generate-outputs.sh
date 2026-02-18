#!/bin/bash
# =============================================================================
# GENERATE OUTPUTS
# =============================================================================
# Consolidates all outputs from previous steps
#
# Environment Variables (from action.yml):
#   - VERSION
#   - VERSION_TAG
#   - PREVIOUS_VERSION
#   - VERSION_BUMP_TYPE
#   - CHANGELOG_UPDATED
#   - CHANGELOG_ENTRY
#   - COMMIT_COUNT
#   - ADDED_COUNT
#   - CHANGED_COUNT
#   - DEPRECATED_COUNT
#   - REMOVED_COUNT
#   - FIXED_COUNT
#   - SECURITY_COUNT
#   - RELEASE_ID
#   - RELEASE_URL
#   - RELEASE_UPLOAD_URL
#   - RELEASE_CREATED
#
# Outputs (via GitHub Actions):
#   All variables are passed through as outputs
# =============================================================================

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" >&2
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Generating action outputs..."

# Version outputs
echo "version=${VERSION:-}" >> $GITHUB_OUTPUT
echo "version-tag=${VERSION_TAG:-}" >> $GITHUB_OUTPUT
echo "previous-version=${PREVIOUS_VERSION:-}" >> $GITHUB_OUTPUT
echo "version-bump-type=${VERSION_BUMP_TYPE:-none}" >> $GITHUB_OUTPUT

# Release outputs
echo "release-created=${RELEASE_CREATED:-false}" >> $GITHUB_OUTPUT
echo "release-id=${RELEASE_ID:-}" >> $GITHUB_OUTPUT
echo "release-url=${RELEASE_URL:-}" >> $GITHUB_OUTPUT
echo "release-upload-url=${RELEASE_UPLOAD_URL:-}" >> $GITHUB_OUTPUT

# Changelog outputs
echo "changelog-updated=${CHANGELOG_UPDATED:-false}" >> $GITHUB_OUTPUT
if [[ -n "${CHANGELOG_ENTRY:-}" ]]; then
    {
        echo "changelog-entry<<EOF"
        echo "${CHANGELOG_ENTRY}"
        echo "EOF"
    } >> $GITHUB_OUTPUT
else
    echo "changelog-entry=" >> $GITHUB_OUTPUT
fi

# Commit count outputs
echo "commit-count=${COMMIT_COUNT:-0}" >> $GITHUB_OUTPUT
echo "added-count=${ADDED_COUNT:-0}" >> $GITHUB_OUTPUT
echo "changed-count=${CHANGED_COUNT:-0}" >> $GITHUB_OUTPUT
echo "deprecated-count=${DEPRECATED_COUNT:-0}" >> $GITHUB_OUTPUT
echo "removed-count=${REMOVED_COUNT:-0}" >> $GITHUB_OUTPUT
echo "fixed-count=${FIXED_COUNT:-0}" >> $GITHUB_OUTPUT
echo "security-count=${SECURITY_COUNT:-0}" >> $GITHUB_OUTPUT

log_success "Outputs generated successfully"

# =============================================================================
# MONOREPO OUTPUTS
# =============================================================================

MONOREPO="${MONOREPO:-false}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"

if [[ "${MONOREPO}" == "true" ]] && command -v jq &> /dev/null; then
    # Filter packages that were updated
    PACKAGES_UPDATED=$(echo "${PACKAGES_DATA}" | jq '[.[] | select(.bumpType != "none")]')
    PACKAGES_COUNT=$(echo "${PACKAGES_UPDATED}" | jq 'length')
    
    # Output as compact JSON to avoid newlines in $GITHUB_OUTPUT
    echo "packages-updated=$(echo "${PACKAGES_UPDATED}" | jq -c '.')" >> $GITHUB_OUTPUT
    echo "packages-count=${PACKAGES_COUNT}" >> $GITHUB_OUTPUT
    
    log_info "=== Monorepo Summary ==="
    log_info "Packages Updated: ${PACKAGES_COUNT}"
    
    # List updated packages
    echo "${PACKAGES_UPDATED}" | jq -r '.[] | "  - \(.name) \(.oldVersion) → \(.version) (\(.bumpType))"' | while IFS= read -r line; do
        log_info "${line}"
    done
else
    echo "packages-updated=[]" >> $GITHUB_OUTPUT
    echo "packages-count=0" >> $GITHUB_OUTPUT
fi

# Display summary
log_info "=== Release Summary ==="
log_info "Version: ${VERSION:-none}"
log_info "Tag: ${VERSION_TAG:-none}"
log_info "Bump Type: ${VERSION_BUMP_TYPE:-none}"
log_info "Commits: ${COMMIT_COUNT:-0}"
log_info "Release Created: ${RELEASE_CREATED:-false}"
