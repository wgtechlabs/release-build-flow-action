#!/bin/bash
# =============================================================================
# DETECT VERSION BUMP
# =============================================================================
# Analyzes commits since last tag to determine version bump type
# and calculate new version number following SemVer
#
# Environment Variables (from action.yml):
#   - GITHUB_TOKEN
#   - VERSION_PREFIX (e.g., 'v')
#   - INITIAL_VERSION (e.g., '0.1.0')
#   - PRERELEASE_PREFIX (e.g., 'beta', 'alpha', 'rc')
#   - MAJOR_KEYWORDS (comma-separated)
#   - MINOR_KEYWORDS (comma-separated)
#   - PATCH_KEYWORDS (comma-separated)
#   - FETCH_DEPTH
#   - INCLUDE_ALL_COMMITS
#
# Outputs (via GitHub Actions):
#   - version           : New version number (e.g., '1.2.3')
#   - version-tag       : Full version tag with prefix (e.g., 'v1.2.3')
#   - previous-version  : Previous version number
#   - previous-tag      : Previous version tag
#   - version-bump-type : Type of bump (major, minor, patch, none)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_debug() {
    echo -e "${CYAN}🔍 $1${NC}" >&2
}

# =============================================================================
# CONFIGURATION
# =============================================================================

VERSION_PREFIX="${VERSION_PREFIX:-v}"
INITIAL_VERSION="${INITIAL_VERSION:-0.1.0}"
PRERELEASE_PREFIX="${PRERELEASE_PREFIX:-}"
MAJOR_KEYWORDS="${MAJOR_KEYWORDS:-BREAKING CHANGE,BREAKING-CHANGE,breaking}"
MINOR_KEYWORDS="${MINOR_KEYWORDS:-feat,new,add}"
PATCH_KEYWORDS="${PATCH_KEYWORDS:-fix,bugfix,security,perf}"
FETCH_DEPTH="${FETCH_DEPTH:-0}"
INCLUDE_ALL_COMMITS="${INCLUDE_ALL_COMMITS:-false}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get latest version tag
get_latest_tag() {
    local prefix="${VERSION_PREFIX}"
    
    # Fetch tags if needed
    if [[ "${FETCH_DEPTH}" == "0" ]]; then
        git fetch --tags --quiet 2>/dev/null || true
    fi
    
    # Get all tags matching version pattern
    local tags=$(git tag -l "${prefix}*" 2>/dev/null | grep -E "^${prefix}[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -n 1)
    
    if [[ -z "${tags}" ]]; then
        echo ""
    else
        echo "${tags}"
    fi
}

# Extract version from tag
extract_version() {
    local tag="$1"
    local prefix="${VERSION_PREFIX}"
    
    # Remove prefix
    echo "${tag#${prefix}}"
}

# Parse SemVer version
parse_version() {
    local version="$1"
    
    if [[ "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    else
        echo "0 0 0"
    fi
}

# Bump version based on type
bump_version() {
    local version="$1"
    local bump_type="$2"
    
    read -r major minor patch <<< $(parse_version "${version}")
    
    case "${bump_type}" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            ;;
    esac
    
    echo "${major}.${minor}.${patch}"
}

# Get commits since tag
get_commits_since_tag() {
    local tag="$1"
    
    # Use null byte as delimiter (more reliable than pipe)
    if [[ -z "${tag}" ]] || [[ "${INCLUDE_ALL_COMMITS}" == "true" ]]; then
        # Get all commits
        git log --format="%H%x00%s%x00%b%x00" --no-merges
    else
        # Get commits since tag
        git log "${tag}..HEAD" --format="%H%x00%s%x00%b%x00" --no-merges
    fi
}

# Determine bump type from commits
determine_bump_type() {
    local commits="$1"
    
    # Convert comma-separated keywords to arrays
    IFS=',' read -ra MAJOR_KEYS <<< "${MAJOR_KEYWORDS}"
    IFS=',' read -ra MINOR_KEYS <<< "${MINOR_KEYWORDS}"
    IFS=',' read -ra PATCH_KEYS <<< "${PATCH_KEYWORDS}"
    
    local has_major=false
    local has_minor=false
    local has_patch=false
    
    while IFS= read -r -d $'\0' sha && IFS= read -r -d $'\0' subject && IFS= read -r -d $'\0' body; do
        # Combine subject and body for searching
        local full_message="${subject}${body:+ }${body}"
        
        # Check for major keywords
        for keyword in "${MAJOR_KEYS[@]}"; do
            if [[ "${full_message}" =~ ${keyword} ]]; then
                has_major=true
                break 2
            fi
        done
        
        # Extract commit type from conventional commit format
        local pattern='^([a-z]+)(\([^)]+\))?(!)?: '
        if [[ "${subject}" =~ $pattern ]]; then
            local commit_type="${BASH_REMATCH[1]}"
            local breaking="${BASH_REMATCH[3]}"
            
            # Check for breaking change marker
            if [[ "${breaking}" == "!" ]]; then
                has_major=true
                break
            fi
            
            # Check for minor keywords
            for keyword in "${MINOR_KEYS[@]}"; do
                if [[ "${commit_type}" == "${keyword}" ]]; then
                    has_minor=true
                fi
            done
            
            # Check for patch keywords
            for keyword in "${PATCH_KEYS[@]}"; do
                if [[ "${commit_type}" == "${keyword}" ]]; then
                    has_patch=true
                fi
            done
        fi
    done <<< "${commits}"
    
    # Return highest priority bump type
    if [[ "${has_major}" == "true" ]]; then
        echo "major"
    elif [[ "${has_minor}" == "true" ]]; then
        echo "minor"
    elif [[ "${has_patch}" == "true" ]]; then
        echo "patch"
    else
        echo "none"
    fi
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Detecting version bump type..."

# Get latest tag
LATEST_TAG=$(get_latest_tag)

if [[ -z "${LATEST_TAG}" ]]; then
    log_warning "No previous version tag found"
    PREVIOUS_VERSION=""
    PREVIOUS_TAG=""
    CURRENT_VERSION="${INITIAL_VERSION}"
    
    # Check if we have any commits to release
    COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    if [[ "${COMMIT_COUNT}" == "0" ]]; then
        log_warning "No commits to release"
        BUMP_TYPE="none"
    else
        log_info "Using initial version: ${INITIAL_VERSION}"
        BUMP_TYPE="patch"
    fi
else
    log_info "Latest tag: ${LATEST_TAG}"
    PREVIOUS_TAG="${LATEST_TAG}"
    PREVIOUS_VERSION=$(extract_version "${LATEST_TAG}")
    
    # Get commits since last tag
    COMMITS=$(get_commits_since_tag "${LATEST_TAG}")
    
    if [[ -z "${COMMITS}" ]]; then
        log_warning "No new commits since ${LATEST_TAG}"
        CURRENT_VERSION="${PREVIOUS_VERSION}"
        BUMP_TYPE="none"
    else
        # Determine bump type
        BUMP_TYPE=$(determine_bump_type "${COMMITS}")
        
        if [[ "${BUMP_TYPE}" == "none" ]]; then
            log_warning "No version-bumping commits found"
            CURRENT_VERSION="${PREVIOUS_VERSION}"
        else
            # Bump version
            CURRENT_VERSION=$(bump_version "${PREVIOUS_VERSION}" "${BUMP_TYPE}")
            log_success "Version bump: ${PREVIOUS_VERSION} -> ${CURRENT_VERSION} (${BUMP_TYPE})"
        fi
    fi
fi

# Add prerelease prefix if configured
if [[ -n "${PRERELEASE_PREFIX}" ]] && [[ "${BUMP_TYPE}" != "none" ]]; then
    CURRENT_VERSION="${CURRENT_VERSION}-${PRERELEASE_PREFIX}"
fi

# Generate full tag
CURRENT_TAG="${VERSION_PREFIX}${CURRENT_VERSION}"

# Output results
echo "version=${CURRENT_VERSION}" >> $GITHUB_OUTPUT
echo "version-tag=${CURRENT_TAG}" >> $GITHUB_OUTPUT
echo "previous-version=${PREVIOUS_VERSION}" >> $GITHUB_OUTPUT
echo "previous-tag=${PREVIOUS_TAG}" >> $GITHUB_OUTPUT
echo "version-bump-type=${BUMP_TYPE}" >> $GITHUB_OUTPUT

log_info "Version: ${CURRENT_VERSION}"
log_info "Tag: ${CURRENT_TAG}"
log_info "Bump Type: ${BUMP_TYPE}"
