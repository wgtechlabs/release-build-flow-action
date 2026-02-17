#!/bin/bash
# =============================================================================
# CREATE RELEASE
# =============================================================================
# Creates a GitHub Release with changelog content
#
# Environment Variables (from action.yml):
#   - GITHUB_TOKEN
#   - VERSION
#   - VERSION_TAG
#   - RELEASE_NAME_TEMPLATE
#   - RELEASE_DRAFT
#   - RELEASE_PRERELEASE
#   - CHANGELOG_ENTRY
#
# Outputs (via GitHub Actions):
#   - created          : Whether release was created (true/false)
#   - release-id       : GitHub Release ID
#   - release-url      : GitHub Release URL
#   - release-upload-url : GitHub Release upload URL
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

# =============================================================================
# CONFIGURATION
# =============================================================================

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
VERSION="${VERSION:-}"
VERSION_TAG="${VERSION_TAG:-}"
RELEASE_NAME_TEMPLATE="${RELEASE_NAME_TEMPLATE:-Release {version}}"
RELEASE_DRAFT="${RELEASE_DRAFT:-false}"
RELEASE_PRERELEASE="${RELEASE_PRERELEASE:-false}"
CHANGELOG_ENTRY="${CHANGELOG_ENTRY:-}"

# Get repository information
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Generate release name from template
generate_release_name() {
    local template="$1"
    local version="$2"
    local date=$(date +%Y-%m-%d)
    
    # Replace placeholders
    local name="${template//\{version\}/${version}}"
    name="${name//\{date\}/${date}}"
    
    echo "${name}"
}

# Create GitHub Release using API
create_github_release() {
    local tag="$1"
    local name="$2"
    local body="$3"
    local draft="$4"
    local prerelease="$5"
    
    # Prepare JSON payload
    local payload=$(cat <<EOF
{
  "tag_name": "${tag}",
  "name": "${name}",
  "body": $(echo -n "${body}" | jq -Rs .),
  "draft": ${draft},
  "prerelease": ${prerelease}
}
EOF
)
    
    # Make API request
    local response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases" \
        -d "${payload}")
    
    # Check for errors
    if echo "${response}" | grep -q '"message"'; then
        local error_msg=$(echo "${response}" | jq -r '.message // "Unknown error"')
        log_error "Failed to create release: ${error_msg}"
        return 1
    fi
    
    echo "${response}"
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Creating GitHub Release for ${VERSION_TAG}..."

# Validate required inputs
if [[ -z "${GITHUB_TOKEN}" ]]; then
    log_error "GITHUB_TOKEN is required"
    exit 1
fi

if [[ -z "${GITHUB_REPOSITORY}" ]]; then
    log_error "GITHUB_REPOSITORY is not set"
    exit 1
fi

if [[ -z "${VERSION}" ]] || [[ -z "${VERSION_TAG}" ]]; then
    log_error "VERSION and VERSION_TAG are required"
    exit 1
fi

# Generate release name
RELEASE_NAME=$(generate_release_name "${RELEASE_NAME_TEMPLATE}" "${VERSION}")

# Prepare release body
RELEASE_BODY="${CHANGELOG_ENTRY}"

if [[ -z "${RELEASE_BODY}" ]]; then
    RELEASE_BODY="Release ${VERSION}"
fi

# Create release
log_info "Creating release: ${RELEASE_NAME}"

RESPONSE=$(create_github_release "${VERSION_TAG}" "${RELEASE_NAME}" "${RELEASE_BODY}" "${RELEASE_DRAFT}" "${RELEASE_PRERELEASE}")

if [[ $? -eq 0 ]]; then
    # Extract release information
    RELEASE_ID=$(echo "${RESPONSE}" | jq -r '.id')
    RELEASE_URL=$(echo "${RESPONSE}" | jq -r '.html_url')
    RELEASE_UPLOAD_URL=$(echo "${RESPONSE}" | jq -r '.upload_url')
    
    # Output results
    echo "created=true" >> $GITHUB_OUTPUT
    echo "release-id=${RELEASE_ID}" >> $GITHUB_OUTPUT
    echo "release-url=${RELEASE_URL}" >> $GITHUB_OUTPUT
    echo "release-upload-url=${RELEASE_UPLOAD_URL}" >> $GITHUB_OUTPUT
    
    log_success "Release created: ${RELEASE_URL}"
else
    echo "created=false" >> $GITHUB_OUTPUT
    echo "release-id=" >> $GITHUB_OUTPUT
    echo "release-url=" >> $GITHUB_OUTPUT
    echo "release-upload-url=" >> $GITHUB_OUTPUT
    
    exit 1
fi
