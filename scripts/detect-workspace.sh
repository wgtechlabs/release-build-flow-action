#!/bin/bash
# =============================================================================
# DETECT WORKSPACE PACKAGES
# =============================================================================
# Detects workspace packages in a monorepo from various package manager configs
#
# Environment Variables:
#   - WORKSPACE_DETECTION (true/false)
#   - PACKAGE_MANAGER (npm/bun/pnpm/yarn or auto-detect)
#   - SCOPE_PACKAGE_MAPPING (JSON mapping of scopes to package paths)
#
# Outputs (via GitHub Actions):
#   - packages: JSON array of package information
#   - package-count: Number of packages detected
#   - package-manager: Detected package manager
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

WORKSPACE_DETECTION="${WORKSPACE_DETECTION:-true}"
PACKAGE_MANAGER="${PACKAGE_MANAGER:-}"
SCOPE_PACKAGE_MAPPING="${SCOPE_PACKAGE_MAPPING:-}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Detect package manager
detect_package_manager() {
    if [[ -n "${PACKAGE_MANAGER}" ]]; then
        echo "${PACKAGE_MANAGER}"
        return
    fi
    
    if [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
        echo "bun"
    elif [[ -f "pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "package-lock.json" ]]; then
        echo "npm"
    else
        echo "npm"  # default
    fi
}

# Get workspace patterns from package.json
get_npm_workspaces() {
    if [[ ! -f "package.json" ]]; then
        echo "[]"
        return
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.workspaces // [] | if type == "array" then . else .packages // [] end | .[]' package.json 2>/dev/null || echo ""
    else
        log_warning "jq not available, falling back to basic parsing"
        grep -A 10 '"workspaces"' package.json 2>/dev/null | grep -oP '"\K[^"]+(?=")' | grep -v workspaces || echo ""
    fi
}

# Get workspace patterns from pnpm-workspace.yaml
get_pnpm_workspaces() {
    if [[ ! -f "pnpm-workspace.yaml" ]]; then
        echo ""
        return
    fi
    
    # Parse YAML packages list
    grep -A 100 "^packages:" pnpm-workspace.yaml 2>/dev/null | grep "^  - " | sed 's/^  - //' | tr -d "'" | tr -d '"' || echo ""
}

# Get workspace patterns from lerna.json
get_lerna_workspaces() {
    if [[ ! -f "lerna.json" ]]; then
        echo ""
        return
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.packages // [] | .[]' lerna.json 2>/dev/null || echo ""
    else
        log_warning "jq not available for lerna.json parsing"
        echo ""
    fi
}

# Expand glob patterns to actual directories
expand_workspace_patterns() {
    local patterns="$1"
    local dirs=()
    
    while IFS= read -r pattern; do
        [[ -z "${pattern}" ]] && continue
        
        # Handle glob patterns - enable nullglob to handle non-matching patterns
        shopt -s nullglob
        for dir in ${pattern}; do
            if [[ -d "${dir}" && -f "${dir}/package.json" ]]; then
                dirs+=("${dir}")
            fi
        done
        shopt -u nullglob
    done <<< "${patterns}"
    
    # Return unique directories
    [[ ${#dirs[@]} -eq 0 ]] && return
    printf '%s\n' "${dirs[@]}" | sort -u
}

# Get package info from package.json
get_package_info() {
    local pkg_dir="$1"
    local pkg_json="${pkg_dir}/package.json"
    
    if [[ ! -f "${pkg_json}" ]]; then
        return
    fi
    
    if command -v jq &> /dev/null; then
        local name=$(jq -r '.name // ""' "${pkg_json}")
        local version=$(jq -r '.version // "0.0.0"' "${pkg_json}")
        local private=$(jq -r '.private // false' "${pkg_json}")
        
        # Determine scope from package name
        local scope=""
        if [[ "${name}" =~ ^@[^/]+/(.+)$ ]]; then
            # For scoped packages like @org/pkg, use the package part as scope
            scope="${BASH_REMATCH[1]}"
        elif [[ "${name}" =~ ^([^/]+)$ ]]; then
            # For unscoped packages, use the package name
            scope="${name}"
        fi
        
        # If scope is still empty, try to infer from directory name
        if [[ -z "${scope}" ]]; then
            scope=$(basename "${pkg_dir}")
        fi
        
        # Build JSON object (compact output to avoid multi-line concatenation issues)
        jq -c -n \
            --arg name "${name}" \
            --arg version "${version}" \
            --arg path "${pkg_dir}" \
            --arg scope "${scope}" \
            --argjson private "${private}" \
            '{name: $name, version: $version, path: $path, scope: $scope, private: $private}'
    else
        log_warning "jq not available, using basic package info extraction"
        local name=$(grep -m1 '"name"' "${pkg_json}" | grep -oP '"\K[^"]+(?="\s*$)' || echo "")
        local version=$(grep -m1 '"version"' "${pkg_json}" | grep -oP '"\K[^"]+(?="\s*$)' || echo "0.0.0")
        echo "{\"name\":\"${name}\",\"version\":\"${version}\",\"path\":\"${pkg_dir}\",\"scope\":\"\",\"private\":false}"
    fi
}

# Build scope to package mapping
build_scope_mapping() {
    local packages="$1"
    
    if command -v jq &> /dev/null; then
        echo "${packages}" | jq -r 'map({(.scope): .path}) | add // {}'
    else
        echo "{}"
    fi
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Detecting workspace packages..."

if [[ "${WORKSPACE_DETECTION}" != "true" ]]; then
    log_info "Workspace detection disabled"
    echo "packages=[]" >> "${GITHUB_OUTPUT}"
    echo "package-count=0" >> "${GITHUB_OUTPUT}"
    exit 0
fi

# Detect package manager
PKG_MGR=$(detect_package_manager)
log_info "Detected package manager: ${PKG_MGR}"

# Get workspace patterns based on package manager
WORKSPACE_PATTERNS=""
case "${PKG_MGR}" in
    pnpm)
        WORKSPACE_PATTERNS=$(get_pnpm_workspaces)
        # Fall back to package.json if pnpm-workspace.yaml not found
        if [[ -z "${WORKSPACE_PATTERNS}" ]]; then
            WORKSPACE_PATTERNS=$(get_npm_workspaces)
        fi
        ;;
    bun|npm|yarn)
        WORKSPACE_PATTERNS=$(get_npm_workspaces)
        ;;
esac

# Also check for lerna
LERNA_PATTERNS=$(get_lerna_workspaces)
if [[ -n "${LERNA_PATTERNS}" ]]; then
    WORKSPACE_PATTERNS="${WORKSPACE_PATTERNS}"$'\n'"${LERNA_PATTERNS}"
fi

if [[ -z "${WORKSPACE_PATTERNS}" ]]; then
    log_warning "No workspace patterns found"
    echo "packages=[]" >> "${GITHUB_OUTPUT}"
    echo "package-count=0" >> "${GITHUB_OUTPUT}"
    echo "package-manager=${PKG_MGR}" >> "${GITHUB_OUTPUT}"
    exit 0
fi

log_info "Found workspace patterns:"
echo "${WORKSPACE_PATTERNS}" | while IFS= read -r pattern; do
    [[ -n "${pattern}" ]] && log_debug "  - ${pattern}"
done

# Expand patterns to directories
PACKAGE_DIRS=$(expand_workspace_patterns "${WORKSPACE_PATTERNS}")

if [[ -z "${PACKAGE_DIRS}" ]]; then
    log_warning "No workspace packages found"
    echo "packages=[]" >> "${GITHUB_OUTPUT}"
    echo "package-count=0" >> "${GITHUB_OUTPUT}"
    echo "package-manager=${PKG_MGR}" >> "${GITHUB_OUTPUT}"
    exit 0
fi

# Collect package information using jq to build the array properly
PACKAGES_JSON="[]"
COUNT=0

while IFS= read -r pkg_dir; do
    [[ -z "${pkg_dir}" ]] && continue
    
    PKG_INFO=$(get_package_info "${pkg_dir}")
    if [[ -n "${PKG_INFO}" ]]; then
        PACKAGES_JSON=$(echo "${PACKAGES_JSON}" | jq -c --argjson pkg "${PKG_INFO}" '. += [$pkg]')
        COUNT=$((COUNT + 1))
    fi
done <<< "${PACKAGE_DIRS}"

log_success "Detected ${COUNT} workspace packages"

# Log package names
if command -v jq &> /dev/null; then
    echo "${PACKAGES_JSON}" | jq -r '.[] | "  - \(.name) (\(.path))"' | while IFS= read -r line; do
        log_debug "${line}"
    done
fi

# Build scope mapping if not provided
if [[ -z "${SCOPE_PACKAGE_MAPPING}" ]]; then
    SCOPE_PACKAGE_MAPPING=$(build_scope_mapping "${PACKAGES_JSON}")
    log_debug "Auto-generated scope mapping: ${SCOPE_PACKAGE_MAPPING}"
fi

# Validate PACKAGES_JSON contains objects, not just strings
if command -v jq &> /dev/null && [[ "${PACKAGES_JSON}" != "[]" ]]; then
    FIRST_TYPE=$(echo "${PACKAGES_JSON}" | jq -r '.[0] | type')
    if [[ "${FIRST_TYPE}" != "object" ]]; then
        log_error "PACKAGES_JSON elements are '${FIRST_TYPE}' instead of 'object' - this is a bug"
        log_debug "PACKAGES_JSON value: ${PACKAGES_JSON:0:500}"
        exit 1
    fi
fi

# Write packages JSON to a shared file to avoid env var size/encoding issues
# when passing large JSON blobs through GitHub Actions outputs and YAML expressions
WORKSPACE_FILE="${RUNNER_TEMP}/workspace-packages.json"
if echo "${PACKAGES_JSON}" | jq '.' > "${WORKSPACE_FILE}"; then
    log_debug "Packages JSON written to ${WORKSPACE_FILE}"
else
    log_warning "Failed to write packages JSON to ${WORKSPACE_FILE}"
    WORKSPACE_FILE=""
fi

# Output results - use compact JSON for safety
log_debug "Packages JSON (first 200 chars): ${PACKAGES_JSON:0:200}"
echo "packages=$(echo "${PACKAGES_JSON}" | jq -c '.')" >> "${GITHUB_OUTPUT}"
echo "packages-file=${WORKSPACE_FILE}" >> "${GITHUB_OUTPUT}"
echo "package-count=${COUNT}" >> "${GITHUB_OUTPUT}"
echo "package-manager=${PKG_MGR}" >> "${GITHUB_OUTPUT}"
echo "scope-mapping=$(echo "${SCOPE_PACKAGE_MAPPING}" | jq -c '.')" >> "${GITHUB_OUTPUT}"

log_success "Workspace detection complete"
