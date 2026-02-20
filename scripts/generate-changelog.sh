#!/bin/bash
# =============================================================================
# GENERATE CHANGELOG
# =============================================================================
# Generates or updates CHANGELOG.md following Keep a Changelog format
#
# Environment Variables (from action.yml):
#   - CHANGELOG_PATH
#   - VERSION
#   - VERSION_TAG
#   - COMMITS_JSON
#
# Outputs (via GitHub Actions):
#   - updated         : Whether changelog was updated (true/false)
#   - changelog-entry : Generated changelog entry for this version
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

# Check for jq and warn if not available
check_jq() {
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Fallback parsing will be used (less reliable)."
        log_warning "For best results, install jq: https://stedolan.github.io/jq/"
    fi
    # Always return 0 to avoid script termination under set -e
    return 0
}

# =============================================================================
# CONFIGURATION
# =============================================================================

CHANGELOG_PATH="${CHANGELOG_PATH:-./CHANGELOG.md}"
VERSION="${VERSION:-}"
VERSION_TAG="${VERSION_TAG:-}"
COMMITS_JSON="${COMMITS_JSON:-[]}"

# Current date in YYYY-MM-DD format
RELEASE_DATE=$(date +%Y-%m-%d)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Create initial changelog if it doesn't exist
create_initial_changelog() {
    local file="$1"
    
    cat > "${file}" << 'EOF'
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

EOF
    
    log_info "Created initial changelog: ${file}"
}

# Generate changelog entry for a version
generate_entry() {
    local version="$1"
    local date="$2"
    local commits_json="$3"
    
    # Start entry
    local entry="## [${version}] - ${date}"
    
    # Group commits by section
    local sections=("Added" "Changed" "Deprecated" "Removed" "Fixed" "Security")
    
    for section in "${sections[@]}"; do
        local items=""
        
        # Extract items for this section
        if command -v jq &> /dev/null; then
            items=$(echo "${commits_json}" | jq -r --arg sec "${section}" '
                .[] | select(.section == $sec) | "- \(.description)"
            ' 2>/dev/null || echo "")
        else
            # Fallback: Try to parse JSON manually (warning already issued)
            # This is a best-effort approach and may not handle all edge cases
            items=$(echo "${commits_json}" | grep -o "\"section\":\"${section}\"" | wc -l)
            if [[ "${items}" -gt 0 ]]; then
                log_warning "Found ${items} ${section} item(s) but jq is required for proper parsing"
                items=""  # Skip if jq not available to avoid corrupted output
            else
                items=""
            fi
        fi
        
        # Add section if it has items
        if [[ -n "${items}" ]]; then
            entry="${entry}\n\n### ${section}\n\n${items}"
        fi
    done
    
    echo -e "${entry}"
}

# Insert entry into changelog
insert_entry() {
    local file="$1"
    local entry="$2"
    
    # Check if file exists
    if [[ ! -f "${file}" ]]; then
        create_initial_changelog "${file}"
    fi
    
    # Find the line number of [Unreleased]
    local unreleased_line
    unreleased_line=$(grep -n "## \[Unreleased\]" "${file}" | cut -d: -f1 | head -n 1)
    
    if [[ -z "${unreleased_line}" ]]; then
        log_error "Could not find [Unreleased] section in ${file}"
        exit 1
    fi
    
    # Determine insertion line: end of Unreleased section, i.e., right before next "## [" header
    local total_lines
    total_lines=$(wc -l < "${file}")
    local insert_line=$((total_lines + 1))
    
    local line_num=$((unreleased_line + 1))
    while [[ ${line_num} -le ${total_lines} ]]; do
        local line
        line=$(sed -n "${line_num}p" "${file}")
        if [[ "${line}" =~ ^##\ \[.*\] ]]; then
            insert_line=${line_num}
            break
        fi
        line_num=$((line_num + 1))
    done
    
    # Create temporary file with entry inserted
    local temp_file
    temp_file=$(mktemp)
    
    # Copy everything before insertion point
    if [[ ${insert_line} -gt 1 ]]; then
        head -n "$((insert_line - 1))" "${file}" > "${temp_file}"
    else
        : > "${temp_file}"
    fi
    
    # Add blank line and entry
    echo "" >> "${temp_file}"
    echo -e "${entry}" >> "${temp_file}"
    echo "" >> "${temp_file}"
    
    # Copy rest of file (from insertion point to end), if any
    if [[ ${insert_line} -le ${total_lines} ]]; then
        tail -n "+${insert_line}" "${file}" >> "${temp_file}"
    fi
    
    # Replace original file
    mv "${temp_file}" "${file}"
    
    log_success "Updated ${file} with version ${VERSION}"
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Generating changelog entry for ${VERSION}..."

# Check jq availability
check_jq

# Check if we have commits
if [[ "${COMMITS_JSON}" == "[]" ]] || [[ -z "${COMMITS_JSON}" ]]; then
    log_warning "No commits to add to changelog"
    echo "updated=false" >> $GITHUB_OUTPUT
    echo "changelog-entry=" >> $GITHUB_OUTPUT
    exit 0
fi

# Generate entry
CHANGELOG_ENTRY=$(generate_entry "${VERSION}" "${RELEASE_DATE}" "${COMMITS_JSON}")

# Insert into changelog
insert_entry "${CHANGELOG_PATH}" "${CHANGELOG_ENTRY}"

# Output results - use proper multiline output format
{
    echo "updated=true"
    echo "changelog-entry<<EOF"
    echo -e "${CHANGELOG_ENTRY}"
    echo "EOF"
} >> $GITHUB_OUTPUT

log_success "Changelog entry generated successfully"

# =============================================================================
# MONOREPO MODE - Generate per-package changelogs
# =============================================================================

MONOREPO="${MONOREPO:-false}"
WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"
# Load from shared file if available (avoids env var size/encoding issues with large monorepos)
if [[ -n "${WORKSPACE_PACKAGES_FILE:-}" && -f "${WORKSPACE_PACKAGES_FILE}" ]]; then
    WORKSPACE_PACKAGES=$(cat "${WORKSPACE_PACKAGES_FILE}")
    if ! echo "${WORKSPACE_PACKAGES}" | jq empty 2>/dev/null; then
        log_warning "Shared packages file contains invalid JSON, falling back to env var"
        WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"
    fi
fi
PER_PACKAGE_CHANGELOG="${PER_PACKAGE_CHANGELOG:-true}"
ROOT_CHANGELOG="${ROOT_CHANGELOG:-true}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"
PER_PACKAGE_COMMITS="${PER_PACKAGE_COMMITS:-}"

if [[ "${MONOREPO}" != "true" ]]; then
    exit 0
fi

log_info "Generating monorepo changelogs..."

# Generate per-package changelogs
if [[ "${PER_PACKAGE_CHANGELOG}" == "true" ]] && command -v jq &> /dev/null; then
    if [[ "${PACKAGES_DATA}" != "[]" ]]; then
        while IFS= read -r package; do
            pkg_name=$(echo "${package}" | jq -r '.name')
            pkg_path=$(echo "${package}" | jq -r '.path')
            pkg_version=$(echo "${package}" | jq -r '.version')
            bump_type=$(echo "${package}" | jq -r '.bumpType')
            
            # Skip if no version bump
            if [[ "${bump_type}" == "none" ]]; then
                log_info "Skipping ${pkg_name} (no version bump)"
                continue
            fi
            
            # Get commits for this package
            pkg_commits="[]"
            if [[ -n "${PER_PACKAGE_COMMITS}" ]] && [[ "${PER_PACKAGE_COMMITS}" != "{}" ]]; then
                pkg_commits=$(echo "${PER_PACKAGE_COMMITS}" | jq --arg path "${pkg_path}" '.[$path] // []')
            fi
            
            if [[ "${pkg_commits}" == "[]" ]]; then
                log_warning "No commits for ${pkg_name}"
                continue
            fi
            
            # Generate changelog entry for package
            pkg_changelog_entry=$(generate_entry "${pkg_version}" "${RELEASE_DATE}" "${pkg_commits}")
            
            # Insert into package changelog
            pkg_changelog_path="${pkg_path}/CHANGELOG.md"
            insert_entry "${pkg_changelog_path}" "${pkg_changelog_entry}"
            
            log_success "Generated changelog for ${pkg_name}"
        done < <(echo "${PACKAGES_DATA}" | jq -c '.[]')
    fi
fi

# Generate root aggregated changelog
if [[ "${ROOT_CHANGELOG}" == "true" ]] && [[ "${MONOREPO}" == "true" ]]; then
    log_info "Root changelog already updated with all commits"
    # The root changelog was already updated in the main logic above
fi

log_success "Monorepo changelogs generated successfully"
