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
#   - MONOREPO          Whether monorepo mode is active (true/false)
#   - PACKAGES_DATA     JSON array of package data from detect-version-bump
#   - UNIFIED_VERSION   Whether all packages share a single version (true/false)
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
MONOREPO="${MONOREPO:-false}"
PACKAGES_DATA="${PACKAGES_DATA:-[]}"
UNIFIED_VERSION="${UNIFIED_VERSION:-false}"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Update version in package.json using jq
update_package_json() {
    local file="$1"
    local version="$2"

    if ! command -v jq &> /dev/null; then
        log_warning "jq not found; skipping ${file}"
        return 0
    fi

    local current_version
    current_version="$(jq -r '.version // empty' "${file}" 2>/dev/null || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No .version field found in ${file} (file may be malformed or missing version key); skipping"
        return 0
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    jq --arg v "${version}" '.version = $v' "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
    log_success "Updated ${file}: ${current_version} → ${version}"
}

# Update version in Cargo.toml (version field inside [package] section only)
update_cargo_toml() {
    local file="$1"
    local version="$2"

    # Extract current version from the [package] section only
    local current_version
    current_version="$(awk '
        /^\[package\]/ { in_pkg=1; next }
        /^\[/ { in_pkg=0 }
        in_pkg && /^version[[:space:]]*=/ {
            match($0, /"[^"]*"/)
            print substr($0, RSTART+1, RLENGTH-2)
            exit
        }
    ' "${file}" || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No version field found under [package] in ${file}; skipping"
        return 0
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    # Replace version only inside [package] section
    awk -v ver="${version}" '
        /^\[package\]/ { in_pkg=1 }
        /^\[/ && !/^\[package\]/ { in_pkg=0 }
        in_pkg && !replaced && /^version[[:space:]]*=/ {
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

    # Extract current version from [project] or [tool.poetry] section only
    local current_version
    current_version="$(awk '
        /^\[project\]/ || /^\[tool\.poetry\]/ { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && /^version[[:space:]]*=/ {
            match($0, /"[^"]*"/)
            print substr($0, RSTART+1, RLENGTH-2)
            exit
        }
    ' "${file}" || true)"

    if [[ -z "${current_version}" ]]; then
        log_warning "No version field found under [project] or [tool.poetry] in ${file}; skipping"
        return 0
    fi

    if [[ "${current_version}" == "${version}" ]]; then
        log_info "${file} already at version ${version}"
        return 0
    fi

    # Replace version only inside [project] or [tool.poetry] sections
    awk -v ver="${version}" '
        /^\[project\]/ || /^\[tool\.poetry\]/ { in_section=1 }
        /^\[/ && !/^\[project\]/ && !/^\[tool\.poetry\]/ { in_section=0 }
        in_section && !replaced && /^version[[:space:]]*=/ {
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
        return 0
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

# Auto-detect manifest files in a directory (defaults to current directory)
detect_version_files() {
    local dir="${1:-.}"
    local -a detected=()

    [[ -f "${dir}/package.json" ]]   && detected+=("${dir}/package.json")
    [[ -f "${dir}/Cargo.toml" ]]     && detected+=("${dir}/Cargo.toml")
    [[ -f "${dir}/pyproject.toml" ]] && detected+=("${dir}/pyproject.toml")
    [[ -f "${dir}/pubspec.yaml" ]]   && detected+=("${dir}/pubspec.yaml")

    local IFS=','
    echo "${detected[*]}"
}

# Sync version files for all packages in a monorepo
# Reads PACKAGES_DATA JSON array where each entry has:
#   { name, path, oldVersion, version, bumpType, tag }
sync_monorepo_packages() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for monorepo version sync"
        return 1
    fi

    local pkg_count
    pkg_count="$(echo "${PACKAGES_DATA}" | jq 'length')"

    if [[ "${pkg_count}" -eq 0 ]]; then
        log_info "No packages found in packages-data"
        return 0
    fi

    log_info "Syncing versions for ${pkg_count} workspace packages..."

    local synced=0
    local skipped=0

    for (( i=0; i<pkg_count; i++ )); do
        local pkg_name pkg_path pkg_version bump_type
        pkg_name="$(echo "${PACKAGES_DATA}" | jq -r ".[${i}].name")"
        pkg_path="$(echo "${PACKAGES_DATA}" | jq -r ".[${i}].path")"
        pkg_version="$(echo "${PACKAGES_DATA}" | jq -r ".[${i}].version")"
        bump_type="$(echo "${PACKAGES_DATA}" | jq -r ".[${i}].bumpType")"

        # In unified mode, sync all packages; otherwise only bumped packages
        if [[ "${UNIFIED_VERSION}" != "true" ]] && [[ "${bump_type}" == "none" ]]; then
            log_info "Skipping ${pkg_name} (no version bump)"
            skipped=$((skipped + 1))
            continue
        fi

        if [[ ! -d "${pkg_path}" ]]; then
            log_warning "Package directory not found: ${pkg_path}; skipping ${pkg_name}"
            skipped=$((skipped + 1))
            continue
        fi

        # Detect manifest files in the package directory
        local pkg_files
        pkg_files="$(detect_version_files "${pkg_path}")"

        if [[ -z "${pkg_files}" ]]; then
            log_warning "No manifest files found in ${pkg_path}; skipping ${pkg_name}"
            skipped=$((skipped + 1))
            continue
        fi

        log_info "Syncing ${pkg_name} → ${pkg_version}"

        IFS=',' read -ra file_list <<< "${pkg_files}"
        for file in "${file_list[@]}"; do
            file="${file#"${file%%[! ]*}"}"
            file="${file%"${file##*[! ]}"}"
            [[ -z "${file}" ]] && continue
            update_version_file "${file}" "${pkg_version}"
        done

        synced=$((synced + 1))
    done

    log_success "Monorepo version sync: ${synced} synced, ${skipped} skipped"
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

# =============================================================================
# MONOREPO MODE
# =============================================================================

if [[ "${MONOREPO}" == "true" ]]; then
    log_info "Monorepo version sync mode"

    # Sync per-package manifest files
    sync_monorepo_packages

    # Also sync root manifest files if they exist
    ROOT_FILES="$(detect_version_files ".")"
    if [[ -n "${ROOT_FILES}" ]]; then
        log_info "Syncing root manifest files with version ${VERSION}..."
        IFS=',' read -ra root_file_list <<< "${ROOT_FILES}"
        for raw_file in "${root_file_list[@]}"; do
            file="${raw_file#"${raw_file%%[! ]*}"}"
            file="${file%"${file##*[! ]}"}"
            [[ -z "${file}" ]] && continue
            update_version_file "${file}" "${VERSION}"
        done
    fi

    log_success "Monorepo version file sync complete"
    exit 0
fi

# =============================================================================
# SINGLE REPO MODE
# =============================================================================

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
