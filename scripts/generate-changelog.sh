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
        return 1
    fi
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
    local unreleased_line=$(grep -n "## \[Unreleased\]" "${file}" | cut -d: -f1 | head -n 1)
    
    if [[ -z "${unreleased_line}" ]]; then
        log_error "Could not find [Unreleased] section in ${file}"
        exit 1
    fi
    
    # Calculate insertion line (after [Unreleased] and any blank lines)
    local insert_line=$((unreleased_line + 1))
    
    # Skip blank lines after [Unreleased]
    local total_lines=$(wc -l < "${file}")
    while [[ ${insert_line} -le ${total_lines} ]]; do
        local line=$(sed -n "${insert_line}p" "${file}")
        if [[ -n "${line}" ]]; then
            break
        fi
        insert_line=$((insert_line + 1))
    done
    
    # Create temporary file with entry inserted
    local temp_file=$(mktemp)
    
    # Copy everything before insertion point
    head -n "$((unreleased_line))" "${file}" > "${temp_file}"
    
    # Add blank line and entry
    echo "" >> "${temp_file}"
    echo -e "${entry}" >> "${temp_file}"
    echo "" >> "${temp_file}"
    
    # Copy rest of file
    tail -n "+${insert_line}" "${file}" >> "${temp_file}"
    
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
