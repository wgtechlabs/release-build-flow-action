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
PATCH_KEYWORDS="${PATCH_KEYWORDS:-fix,bugfix,security,perf,update,change,chore,setup,remove,delete,deprecate}"
FETCH_DEPTH="${FETCH_DEPTH:-0}"
INCLUDE_ALL_COMMITS="${INCLUDE_ALL_COMMITS:-false}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get latest version tag
get_latest_tag() {
    local prefix="${VERSION_PREFIX}"
    
    # Always fetch tags to ensure version detection sees all tags,
    # regardless of FETCH_DEPTH / clone depth.
    git fetch --tags --quiet 2>/dev/null || true
    
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
        
        # Strip leading emoji and whitespace before parsing
        # Use bash parameter expansion instead of sed to avoid binary-file detection
        # issues with 4-byte UTF-8 emoji sequences (e.g., 📦, 🔧, 🚀)
        local prefix="${subject%%[a-zA-Z]*}"
        local cleaned_subject="${subject#"$prefix"}"
        
        # Extract commit type from conventional commit format
        # Allow optional whitespace before scope parentheses to support Clean Commit format
        local pattern='^([a-z]+)[[:space:]]*(\([^)]+\))?(!)?: '
        if [[ "${cleaned_subject}" =~ $pattern ]]; then
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
    done
    
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
    
    # Check if there are commits since last tag
    COMMIT_COUNT=$(git rev-list --count "${LATEST_TAG}..HEAD" 2>/dev/null || echo "0")
    
    if [[ "${COMMIT_COUNT}" == "0" ]]; then
        log_warning "No new commits since ${LATEST_TAG}"
        CURRENT_VERSION="${PREVIOUS_VERSION}"
        BUMP_TYPE="none"
    else
        # Determine bump type from commits streamed as NUL-delimited data
        BUMP_TYPE=$(get_commits_since_tag "${LATEST_TAG}" | determine_bump_type)
        
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

# =============================================================================
# MONOREPO MODE
# =============================================================================

MONOREPO="${MONOREPO:-false}"
WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"
CHANGE_DETECTION="${CHANGE_DETECTION:-both}"
SCOPE_PACKAGE_MAPPING="${SCOPE_PACKAGE_MAPPING:-}"
UNIFIED_VERSION="${UNIFIED_VERSION:-false}"
CASCADE_BUMPS="${CASCADE_BUMPS:-false}"

if [[ "${MONOREPO}" != "true" ]]; then
    exit 0
fi

log_info "Processing monorepo packages..."

# Helper function to detect package from commit scope
get_package_from_scope() {
    local scope="$1"
    
    if [[ -z "${scope}" ]]; then
        echo ""
        return
    fi
    
    # Try scope package mapping first
    if command -v jq &> /dev/null && [[ -n "${SCOPE_PACKAGE_MAPPING}" ]]; then
        local pkg_path=$(echo "${SCOPE_PACKAGE_MAPPING}" | jq -r --arg scope "${scope}" '.[$scope] // empty')
        if [[ -n "${pkg_path}" ]]; then
            echo "${pkg_path}"
            return
        fi
    fi
    
    # Try to match scope with package scope from workspace packages
    if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
        local pkg_path=$(echo "${WORKSPACE_PACKAGES}" | jq -r --arg scope "${scope}" '.[] | select(.scope == $scope) | .path' | head -1)
        if [[ -n "${pkg_path}" ]]; then
            echo "${pkg_path}"
            return
        fi
    fi
    
    echo ""
}

# Helper function to detect packages from file paths
get_packages_from_files() {
    local sha="$1"
    local packages=()
    
    if ! command -v jq &> /dev/null || [[ "${WORKSPACE_PACKAGES}" == "[]" ]]; then
        echo ""
        return
    fi
    
    # Get files changed in commit
    local files=$(git diff-tree --no-commit-id --name-only -r "${sha}" 2>/dev/null || echo "")
    
    # Match files to packages
    while IFS= read -r file; do
        [[ -z "${file}" ]] && continue
        
        # Find which package this file belongs to
        local pkg_path=$(echo "${WORKSPACE_PACKAGES}" | jq -r --arg file "${file}" '.[] | select(($file == .path) or ($file | startswith(.path + "/"))) | .path' | head -1)
        if [[ -n "${pkg_path}" ]]; then
            packages+=("${pkg_path}")
        fi
    done <<< "${files}"
    
    # Return unique packages
    if [[ ${#packages[@]} -eq 0 ]]; then
        echo ""
        return
    fi
    printf '%s\n' "${packages[@]}" | sort -u | tr '\n' ' '
}

# Determine affected packages and their version bumps
declare -A PACKAGE_BUMPS

# Initialize keyword arrays in main shell
IFS=',' read -ra MINOR_KEYS <<< "${MINOR_KEYWORDS}"
IFS=',' read -ra PATCH_KEYS <<< "${PATCH_KEYWORDS}"

if [[ "${UNIFIED_VERSION}" == "true" ]]; then
    # All packages get the same version
    log_info "Unified version mode: all packages will use version ${CURRENT_VERSION}"
    
    if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
        while IFS= read -r pkg_path; do
            PACKAGE_BUMPS["${pkg_path}"]="${BUMP_TYPE}"
        done < <(echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path')
    fi
else
    # Determine per-package version bumps
    log_info "Per-package version mode: analyzing commits..."
    
    while IFS= read -r -d $'\0' sha && IFS= read -r -d $'\0' subject && IFS= read -r -d $'\0' body; do
        full_message="${subject}${body:+ }${body}"
        affected_packages=()
        
        # Strip leading emoji and whitespace before parsing
        # Use bash parameter expansion instead of sed to avoid binary-file detection
        # issues with 4-byte UTF-8 emoji sequences
        local _prefix="${subject%%[a-zA-Z]*}"
        cleaned_subject="${subject#"$_prefix"}"
        
        # Extract scope from conventional commit
        # Allow optional whitespace before scope parentheses to support Clean Commit format
        pattern='^([a-z]+)[[:space:]]*(\(([^)]+)\))?(!)?: '
        if [[ "${cleaned_subject}" =~ $pattern ]]; then
            commit_type="${BASH_REMATCH[1]}"
            scope="${BASH_REMATCH[3]}"
            breaking="${BASH_REMATCH[4]}"
            
            # Determine bump type for this commit
            commit_bump="none"
            
            # Check for breaking change
            if [[ "${breaking}" == "!" ]] || [[ "${full_message}" =~ BREAKING\ CHANGE ]] || [[ "${full_message}" =~ BREAKING-CHANGE ]]; then
                commit_bump="major"
            else
                # Check commit type
                for keyword in "${MINOR_KEYS[@]}"; do
                    if [[ "${commit_type}" == "${keyword}" ]]; then
                        commit_bump="minor"
                        break
                    fi
                done
                
                if [[ "${commit_bump}" == "none" ]]; then
                    for keyword in "${PATCH_KEYS[@]}"; do
                        if [[ "${commit_type}" == "${keyword}" ]]; then
                            commit_bump="patch"
                            break
                        fi
                    done
                fi
            fi
            
            # Determine affected packages
            if [[ "${CHANGE_DETECTION}" == "scope" ]] || [[ "${CHANGE_DETECTION}" == "both" ]]; then
                if [[ -n "${scope}" ]]; then
                    pkg_path=$(get_package_from_scope "${scope}")
                    if [[ -n "${pkg_path}" ]]; then
                        affected_packages+=("${pkg_path}")
                    fi
                fi
            fi
            
            if [[ "${CHANGE_DETECTION}" == "path" ]] || [[ "${CHANGE_DETECTION}" == "both" ]]; then
                file_packages=$(get_packages_from_files "${sha}")
                if [[ -n "${file_packages}" ]]; then
                    # get_packages_from_files returns a space-separated list of package paths;
                    # read into array to safely handle paths without executing shell metacharacters
                    read -ra file_packages_array <<< "${file_packages}"
                    for pkg_path in "${file_packages_array[@]}"; do
                        affected_packages+=("${pkg_path}")
                    done
                fi
            fi
            
            # If no scope and no file-based detection, affect all packages
            if [[ ${#affected_packages[@]} -eq 0 ]]; then
                if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
                    while IFS= read -r pkg_path; do
                        affected_packages+=("${pkg_path}")
                    done < <(echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path')
                fi
            fi
            
            # Update package bumps with highest priority
            for pkg_path in "${affected_packages[@]}"; do
                current_bump="${PACKAGE_BUMPS[${pkg_path}]:-none}"
                
                # Determine highest priority bump
                if [[ "${commit_bump}" == "major" ]]; then
                    PACKAGE_BUMPS["${pkg_path}"]="major"
                elif [[ "${commit_bump}" == "minor" ]] && [[ "${current_bump}" != "major" ]]; then
                    PACKAGE_BUMPS["${pkg_path}"]="minor"
                elif [[ "${commit_bump}" == "patch" ]] && [[ "${current_bump}" == "none" ]]; then
                    PACKAGE_BUMPS["${pkg_path}"]="patch"
                fi
            done
        fi
    done < <(get_commits_since_tag "${LATEST_TAG}")
fi

# Build packages data JSON with versions and tags
PACKAGES_DATA="["
FIRST=true

if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
    while IFS= read -r pkg_path; do
        pkg_info=$(echo "${WORKSPACE_PACKAGES}" | jq --arg path "${pkg_path}" '.[] | select(.path == $path)')
        pkg_name=$(echo "${pkg_info}" | jq -r '.name')
        pkg_version=$(echo "${pkg_info}" | jq -r '.version')
        bump_type="${PACKAGE_BUMPS[${pkg_path}]:-none}"
        
        new_version="${pkg_version}"
        if [[ "${UNIFIED_VERSION}" == "true" ]]; then
            new_version="${CURRENT_VERSION}"
        elif [[ "${bump_type}" != "none" ]]; then
            new_version=$(bump_version "${pkg_version}" "${bump_type}")
        fi
        
        pkg_tag=""
        if [[ "${bump_type}" != "none" ]]; then
            pkg_tag="${pkg_name}@${new_version}"
        fi
        
        if [[ "${FIRST}" == "true" ]]; then
            FIRST=false
        else
            PACKAGES_DATA="${PACKAGES_DATA},"
        fi
        
        PACKAGES_DATA="${PACKAGES_DATA}"$(jq -n \
            --arg name "${pkg_name}" \
            --arg path "${pkg_path}" \
            --arg version "${pkg_version}" \
            --arg newVersion "${new_version}" \
            --arg bumpType "${bump_type}" \
            --arg tag "${pkg_tag}" \
            '{name: $name, path: $path, oldVersion: $version, version: $newVersion, bumpType: $bumpType, tag: $tag}')
    done < <(echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path')
fi

PACKAGES_DATA="${PACKAGES_DATA}]"

# Output as compact JSON to avoid newlines in $GITHUB_OUTPUT
echo "packages-data=$(echo "${PACKAGES_DATA}" | jq -c '.')" >> $GITHUB_OUTPUT

log_success "Monorepo version detection complete"
if command -v jq &> /dev/null; then
    updated_count=$(echo "${PACKAGES_DATA}" | jq '[.[] | select(.bumpType != "none")] | length')
    log_info "Packages to update: ${updated_count}"
fi
