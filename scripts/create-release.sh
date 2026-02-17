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

# Escape JSON string manually
escape_json_string() {
    local str="$1"
    # Replace backslash, double quote, newline, tab, carriage return
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    echo "${str}"
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
    
    # Build JSON payload
    local payload
    if command -v jq &> /dev/null; then
        # Use jq to build JSON payload safely
        payload=$(jq -n \
            --arg tag "$tag" \
            --arg name "$name" \
            --arg body "$body" \
            --argjson draft "$draft" \
            --argjson prerelease "$prerelease" \
            '{tag_name: $tag, name: $name, body: $body, draft: $draft, prerelease: $prerelease}')
    else
        # Fallback: manual escaping for all string fields
        local encoded_tag="\"$(escape_json_string "${tag}")\""
        local encoded_name="\"$(escape_json_string "${name}")\""
        local encoded_body="\"$(escape_json_string "${body}")\""
        
        # Prepare JSON payload
        payload=$(cat <<EOF
{
  "tag_name": ${encoded_tag},
  "name": ${encoded_name},
  "body": ${encoded_body},
  "draft": ${draft},
  "prerelease": ${prerelease}
}
EOF
)
    fi
    
    # Make API request
    local response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases" \
        -d "${payload}")
    
    # Check for errors
    if echo "${response}" | grep -q '"message"'; then
        local error_msg
        if command -v jq &> /dev/null; then
            error_msg=$(echo "${response}" | jq -r '.message // "Unknown error"')
        else
            # Fallback: try to extract "message" field without jq; otherwise use raw response
            error_msg=$(echo "${response}" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            if [[ -z "${error_msg}" ]]; then
                error_msg="${response}"
            fi
        fi
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

if RESPONSE=$(create_github_release "${VERSION_TAG}" "${RELEASE_NAME}" "${RELEASE_BODY}" "${RELEASE_DRAFT}" "${RELEASE_PRERELEASE}"); then
    # Extract release information
    if command -v jq &> /dev/null; then
        RELEASE_ID=$(echo "${RESPONSE}" | jq -r '.id')
        RELEASE_URL=$(echo "${RESPONSE}" | jq -r '.html_url')
        RELEASE_UPLOAD_URL=$(echo "${RESPONSE}" | jq -r '.upload_url')
    else
        # Fallback: extract fields without jq
        RELEASE_ID=$(echo "${RESPONSE}" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -n 1)
        RELEASE_URL=$(echo "${RESPONSE}" | sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
        RELEASE_UPLOAD_URL=$(echo "${RESPONSE}" | sed -n 's/.*"upload_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    fi
    
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

# =============================================================================
# MONOREPO MODE - Create per-package releases
# =============================================================================

MONOREPO="${MONOREPO:-false}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"

if [[ "${MONOREPO}" != "true" ]]; then
    exit 0
fi

log_info "Creating monorepo package releases..."

# Track created releases
RELEASES_CREATED="[]"

if command -v jq &> /dev/null && [[ "${PACKAGES_DATA}" != "[]" ]]; then
    echo "${PACKAGES_DATA}" | jq -c '.[]' | while IFS= read -r package; do
        local pkg_name=$(echo "${package}" | jq -r '.name')
        local pkg_path=$(echo "${package}" | jq -r '.path')
        local pkg_version=$(echo "${package}" | jq -r '.version')
        local pkg_tag=$(echo "${package}" | jq -r '.tag')
        local bump_type=$(echo "${package}" | jq -r '.bumpType')
        
        # Skip if no version bump
        if [[ "${bump_type}" == "none" ]] || [[ -z "${pkg_tag}" ]] || [[ "${pkg_tag}" == "null" ]]; then
            log_info "Skipping ${pkg_name} (no version bump)"
            continue
        fi
        
        # Get package changelog entry
        local pkg_changelog=""
        if [[ -f "${pkg_path}/CHANGELOG.md" ]]; then
            # Extract the latest entry from package changelog
            pkg_changelog=$(awk '/^## \[/{if(p)exit;p=1;next}p' "${pkg_path}/CHANGELOG.md" || echo "")
        fi
        
        if [[ -z "${pkg_changelog}" ]]; then
            pkg_changelog="Release ${pkg_tag}"
        fi
        
        # Generate release name for package
        local pkg_release_name=$(generate_release_name "${RELEASE_NAME_TEMPLATE}" "${pkg_tag}")
        
        # Create release for package
        log_info "Creating release for ${pkg_name}: ${pkg_tag}"
        
        if RESPONSE=$(create_github_release "${pkg_tag}" "${pkg_release_name}" "${pkg_changelog}" "${RELEASE_DRAFT}" "${RELEASE_PRERELEASE}"); then
            local release_id=$(echo "${RESPONSE}" | jq -r '.id')
            local release_url=$(echo "${RESPONSE}" | jq -r '.html_url')
            
            log_success "Release created for ${pkg_name}: ${release_url}"
            
            # Track this release
            local release_info=$(jq -n \
                --arg name "${pkg_name}" \
                --arg tag "${pkg_tag}" \
                --arg url "${release_url}" \
                --arg id "${release_id}" \
                '{name: $name, tag: $tag, url: $url, id: $id}')
            
            RELEASES_CREATED=$(echo "${RELEASES_CREATED}" | jq --argjson release "${release_info}" '. += [$release]')
        else
            log_error "Failed to create release for ${pkg_name}"
        fi
    done
    
    # Output monorepo releases information
    echo "monorepo-releases=${RELEASES_CREATED}" >> $GITHUB_OUTPUT
    
    local release_count=$(echo "${RELEASES_CREATED}" | jq 'length')
    log_success "Created ${release_count} package releases"
fi

log_success "Monorepo releases created successfully"
