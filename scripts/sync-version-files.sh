#!/bin/bash
# =============================================================================
# SYNC VERSION FILES
# =============================================================================
# Updates the version field in manifest files to match the released version.
# Supports: package.json, Cargo.toml, pyproject.toml, pubspec.yaml
#
# Environment Variables:
#   - VERSION           The new version string (e.g., 1.2.3)
#   - SYNC_VERSION_FILES  Whether to sync (true/false)
#   - VERSION_FILE_PATHS  Comma-separated file paths (auto-detected if empty)
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

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

# =============================================================================
# CONFIGURATION
# =============================================================================

SYNC_VERSION_FILES="${SYNC_VERSION_FILES:-false}"
VERSION="${VERSION:-}"
VERSION_FILE_PATHS="${VERSION_FILE_PATHS:-}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Update version in package.json using jq
update_package_json() {
    local file="$1"
    local version="$2"

    if ! command -v jq &> /dev/null; then
        log_warning "jq not found; skipping ${file}"
        return 1
    fi

    local current_version
    current_version="$(jq -r '.version // empty' "${file}" 2>/dev/null || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No .version field found in ${file} (file may be malformed or missing version key); skipping"
        return 1
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    jq --arg v "${version}" '.version = $v' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    log_success "Updated ${file}: ${current_version} → ${version}"
}

# Update version in Cargo.toml (first occurrence in [package] section)
update_cargo_toml() {
    local file="$1"
    local version="$2"

    # Replace the first `version = "..."` line (typically under [package])
    local current_version
    current_version="$(grep -m1 '^version[[:space:]]*=' "${file}" | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/' || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No version field found in ${file}; skipping"
        return 1
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    # Use awk to replace only the first occurrence of version = "..."
    awk -v ver="${version}" '
        !replaced && /^version[[:space:]]*=/ {
            sub(/"[^"]*"/, "\"" ver "\"")
            replaced=1
        }
        { print }
    ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    log_success "Updated ${file}: ${current_version} → ${version}"
}

# Update version in pyproject.toml ([project] or [tool.poetry] version field)
update_pyproject_toml() {
    local file="$1"
    local version="$2"

    local current_version
    current_version="$(grep -m1 '^version[[:space:]]*=' "${file}" | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/' || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No version field found in ${file}; skipping"
        return 1
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    # Use awk to replace only the first occurrence of version = "..."
    awk -v ver="${version}" '
        !replaced && /^version[[:space:]]*=/ {
            sub(/"[^"]*"/, "\"" ver "\"")
            replaced=1
        }
        { print }
    ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    log_success "Updated ${file}: ${current_version} → ${version}"
}

# Update version in pubspec.yaml
update_pubspec_yaml() {
    local file="$1"
    local version="$2"

    local current_version
    current_version="$(grep -m1 '^version:' "${file}" | sed 's/^version:[[:space:]]*//' | tr -d "\"'" || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No version field found in ${file}; skipping"
        return 1
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    # Replace the first `version:` line
    awk -v ver="${version}" '
        !replaced && /^version:/ {
            print "version: " ver
            replaced=1
            next
        }
        { print }
    ' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    log_success "Updated ${file}: ${current_version} → ${version}"
}

# Route file update to the correct handler based on filename
update_version_file() {
    local file="$1"
    local version="$2"

    if [[ ! -f "${file}" ]]; then
        log_warning "File not found: ${file}; skipping"
        return 0
    fi

    local basename
    basename="$(basename "${file}")"

    case "${basename}" in
        package.json)
            update_package_json "${file}" "${version}"
            ;;
        Cargo.toml)
            update_cargo_toml "${file}" "${version}"
            ;;
        pyproject.toml)
            update_pyproject_toml "${file}" "${version}"
            ;;
        pubspec.yaml)
            update_pubspec_yaml "${file}" "${version}"
            ;;
        *)
            log_warning "Unknown manifest type: ${file}; skipping"
            ;;
    esac
}

# Auto-detect manifest files in the repository root
detect_version_files() {
    local -a detected=()

    [[ -f "package.json" ]]   && detected+=("package.json")
    [[ -f "Cargo.toml" ]]     && detected+=("Cargo.toml")
    [[ -f "pyproject.toml" ]] && detected+=("pyproject.toml")
    [[ -f "pubspec.yaml" ]]   && detected+=("pubspec.yaml")

    local IFS=','
    echo "${detected[*]}"
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

if [[ "${SYNC_VERSION_FILES}" != "true" ]]; then
    log_info "Version file sync is disabled; skipping"
    exit 0
fi

if [[ -z "${VERSION}" ]]; then
    log_error "VERSION is required but not set"
    exit 1
fi

# Resolve file list
if [[ -z "${VERSION_FILE_PATHS}" ]]; then
    log_info "Auto-detecting manifest files..."
    VERSION_FILE_PATHS="$(detect_version_files)"
fi

if [[ -z "${VERSION_FILE_PATHS}" ]]; then
    log_info "No manifest files found to sync"
    exit 0
fi

log_info "Syncing version ${VERSION} into manifest files..."

IFS=',' read -ra file_list <<< "${VERSION_FILE_PATHS}"
for raw_file in "${file_list[@]}"; do
    # Trim leading/trailing whitespace
    file="${raw_file#"${raw_file%%[! ]*}"}"
    file="${file%"${file##*[! ]}"}"
    [[ -z "${file}" ]] && continue
    update_version_file "${file}" "${VERSION}"
done

log_success "Version file sync complete"
