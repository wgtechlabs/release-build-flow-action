#!/bin/bash
# =============================================================================
# PARSE COMMITS
# =============================================================================
# Parses commit messages and categorizes them according to Clean Commit
# convention, mapping to Keep a Changelog sections
#
# Environment Variables (from action.yml):
#   - COMMIT_TYPE_MAPPING (JSON)
#   - EXCLUDE_TYPES (comma-separated)
#   - EXCLUDE_SCOPES (comma-separated)
#   - PREVIOUS_TAG
#
# Outputs (via GitHub Actions):
#   - commits-json      : JSON array of categorized commits
#   - commit-count      : Total number of commits
#   - added-count       : Number of Added changes
#   - changed-count     : Number of Changed items
#   - deprecated-count  : Number of Deprecated items
#   - removed-count     : Number of Removed items
#   - fixed-count       : Number of Fixed items
#   - security-count    : Number of Security fixes
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

log_debug() {
    echo -e "${CYAN}🔍 $1${NC}" >&2
}

# Escape JSON string manually (fallback if jq not available)
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

COMMIT_TYPE_MAPPING="${COMMIT_TYPE_MAPPING:-}"
EXCLUDE_TYPES="${EXCLUDE_TYPES:-docs,style,test,ci,build}"
EXCLUDE_SCOPES="${EXCLUDE_SCOPES:-}"
PREVIOUS_TAG="${PREVIOUS_TAG:-}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get mapping for commit type using jq if available, otherwise use basic parsing
get_changelog_section() {
    local commit_type="$1"
    
    # Try using jq if available
    if command -v jq &> /dev/null; then
        local section=$(echo "${COMMIT_TYPE_MAPPING}" | jq -r --arg type "${commit_type}" '.[$type] // empty')
        if [[ -n "${section}" ]]; then
            echo "${section}"
            return
        fi
    fi
    
    # Fallback to basic parsing
    case "${commit_type}" in
        feat|new|add)
            echo "Added"
            ;;
        fix|bugfix)
            echo "Fixed"
            ;;
        security)
            echo "Security"
            ;;
        perf|refactor|update|change|chore)
            echo "Changed"
            ;;
        deprecate)
            echo "Deprecated"
            ;;
        remove|delete)
            echo "Removed"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if type should be excluded
is_excluded_type() {
    local type="$1"
    IFS=',' read -ra EXCLUDED <<< "${EXCLUDE_TYPES}"
    
    for excluded in "${EXCLUDED[@]}"; do
        if [[ "${type}" == "${excluded}" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Check if scope should be excluded
is_excluded_scope() {
    local scope="$1"
    
    if [[ -z "${EXCLUDE_SCOPES}" ]] || [[ -z "${scope}" ]]; then
        return 1
    fi
    
    IFS=',' read -ra EXCLUDED <<< "${EXCLUDE_SCOPES}"
    
    for excluded in "${EXCLUDED[@]}"; do
        if [[ "${scope}" == "${excluded}" ]]; then
            return 0
        fi
    done
    
    return 1
}

# Parse conventional commit message
parse_commit() {
    local subject="$1"
    local body="$2"
    
    local type=""
    local scope=""
    local breaking=""
    local description=""
    
    # Parse conventional commit format: type(scope)!: description
    local pattern='^([a-z]+)(\(([^)]+)\))?(!)?: '
    if [[ "${subject}" =~ $pattern ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[3]}"
        breaking="${BASH_REMATCH[4]}"
        description="${subject#*: }"
    else
        # Not a conventional commit, use as-is
        type="other"
        description="${subject}"
    fi
    
    # Check for breaking changes in body
    local breaking_pattern='BREAKING[- ]CHANGE'
    if [[ "${body}" =~ $breaking_pattern ]]; then
        breaking="!"
    fi
    
    # Output using NUL delimiters
    printf "%s\0%s\0%s\0%s\0" "${type}" "${scope}" "${breaking}" "${description}"
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

log_info "Parsing commits..."

# Initialize counters
ADDED_COUNT=0
CHANGED_COUNT=0
DEPRECATED_COUNT=0
REMOVED_COUNT=0
FIXED_COUNT=0
SECURITY_COUNT=0
TOTAL_COUNT=0

# Initialize JSON array
COMMITS_JSON="[]"

# Process each commit - stream git log directly into loop
while IFS= read -r -d $'\0' sha && IFS= read -r -d $'\0' subject && IFS= read -r -d $'\0' body; do
    # Parse commit - now returns NUL-delimited output
    IFS= read -r -d $'\0' type && IFS= read -r -d $'\0' scope && IFS= read -r -d $'\0' breaking && IFS= read -r -d $'\0' description < <(parse_commit "${subject}" "${body}")
    
    # Skip excluded types
    if is_excluded_type "${type}"; then
        log_debug "Excluding commit ${sha:0:7} (type: ${type})"
        continue
    fi
    
    # Skip excluded scopes
    if is_excluded_scope "${scope}"; then
        log_debug "Excluding commit ${sha:0:7} (scope: ${scope})"
        continue
    fi
    
    # Get changelog section
    SECTION=$(get_changelog_section "${type}")
    
    # Mark as breaking change if detected
    if [[ "${breaking}" == "!" ]]; then
        SECTION="Changed"
        description="**BREAKING:** ${description}"
    fi
    
    # Skip if no section mapping found
    if [[ -z "${SECTION}" ]]; then
        log_debug "No section mapping for type: ${type}"
        continue
    fi
    
    # Increment counters
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    case "${SECTION}" in
        Added)
            ADDED_COUNT=$((ADDED_COUNT + 1))
            ;;
        Changed)
            CHANGED_COUNT=$((CHANGED_COUNT + 1))
            ;;
        Deprecated)
            DEPRECATED_COUNT=$((DEPRECATED_COUNT + 1))
            ;;
        Removed)
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            ;;
        Fixed)
            FIXED_COUNT=$((FIXED_COUNT + 1))
            ;;
        Security)
            SECURITY_COUNT=$((SECURITY_COUNT + 1))
            ;;
    esac
    
    # Build JSON entry
    if command -v jq &> /dev/null; then
        COMMITS_JSON=$(echo "${COMMITS_JSON}" | jq --arg sha "${sha}" \
            --arg type "${type}" \
            --arg scope "${scope}" \
            --arg section "${SECTION}" \
            --arg desc "${description}" \
            '. += [{
                "sha": $sha,
                "type": $type,
                "scope": $scope,
                "section": $section,
                "description": $desc
            }]')
    else
        # Fallback: build JSON manually with proper escaping
        escaped_sha=$(escape_json_string "${sha}")
        escaped_type=$(escape_json_string "${type}")
        escaped_scope=$(escape_json_string "${scope}")
        escaped_section=$(escape_json_string "${SECTION}")
        escaped_desc=$(escape_json_string "${description}")
        
        if [[ "${COMMITS_JSON}" == "[]" ]]; then
            COMMITS_JSON="[{\"sha\":\"${escaped_sha}\",\"type\":\"${escaped_type}\",\"scope\":\"${escaped_scope}\",\"section\":\"${escaped_section}\",\"description\":\"${escaped_desc}\"}]"
        else
            COMMITS_JSON="${COMMITS_JSON%]},{\"sha\":\"${escaped_sha}\",\"type\":\"${escaped_type}\",\"scope\":\"${escaped_scope}\",\"section\":\"${escaped_section}\",\"description\":\"${escaped_desc}\"}]"
        fi
    fi
    
    log_debug "Parsed: ${sha:0:7} -> ${SECTION}: ${description}"
done < <(if [[ -z "${PREVIOUS_TAG}" ]]; then
    git log --format="%H%x00%s%x00%b%x00" --no-merges
else
    git log "${PREVIOUS_TAG}..HEAD" --format="%H%x00%s%x00%b%x00" --no-merges
fi)

# Output results
echo "commits-json=${COMMITS_JSON}" >> $GITHUB_OUTPUT
echo "commit-count=${TOTAL_COUNT}" >> $GITHUB_OUTPUT
echo "added-count=${ADDED_COUNT}" >> $GITHUB_OUTPUT
echo "changed-count=${CHANGED_COUNT}" >> $GITHUB_OUTPUT
echo "deprecated-count=${DEPRECATED_COUNT}" >> $GITHUB_OUTPUT
echo "removed-count=${REMOVED_COUNT}" >> $GITHUB_OUTPUT
echo "fixed-count=${FIXED_COUNT}" >> $GITHUB_OUTPUT
echo "security-count=${SECURITY_COUNT}" >> $GITHUB_OUTPUT

log_success "Parsed ${TOTAL_COUNT} commits"
log_info "  Added: ${ADDED_COUNT}"
log_info "  Changed: ${CHANGED_COUNT}"
log_info "  Deprecated: ${DEPRECATED_COUNT}"
log_info "  Removed: ${REMOVED_COUNT}"
log_info "  Fixed: ${FIXED_COUNT}"
log_info "  Security: ${SECURITY_COUNT}"
