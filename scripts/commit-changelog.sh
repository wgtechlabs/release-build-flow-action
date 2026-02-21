#!/bin/bash
# =============================================================================
# COMMIT CHANGELOG
# =============================================================================
# Commits changelog changes to the repository
# Supports both single-package and monorepo modes
#
# Environment Variables:
#   - GITHUB_TOKEN
#   - GIT_USER_NAME
#   - GIT_USER_EMAIL
#   - VERSION_TAG
#   - CHANGELOG_PATH
#   - MONOREPO
#   - WORKSPACE_PACKAGES
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

# =============================================================================
# CONFIGURATION
# =============================================================================

MONOREPO="${MONOREPO:-false}"
CHANGELOG_PATH="${CHANGELOG_PATH:-./CHANGELOG.md}"
VERSION_TAG="${VERSION_TAG:-}"
WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"
# Load from shared file if available (avoids env var size/encoding issues with large monorepos)
# shellcheck source=scripts/lib-workspace.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-workspace.sh"
load_workspace_packages
COMMIT_CONVENTION="${COMMIT_CONVENTION:-clean-commit}"
SYNC_VERSION_FILES="${SYNC_VERSION_FILES:-false}"
VERSION_FILE_PATHS="${VERSION_FILE_PATHS:-}"

# Validate WORKSPACE_PACKAGES format
if [[ "${MONOREPO}" == "true" ]] && command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
    WP_FIRST_TYPE=$(echo "${WORKSPACE_PACKAGES}" | jq -r '.[0] | type' 2>/dev/null || echo "invalid")
    if [[ "${WP_FIRST_TYPE}" != "object" ]]; then
        log_warning "WORKSPACE_PACKAGES has '${WP_FIRST_TYPE}' elements instead of objects - treating as empty"
        WORKSPACE_PACKAGES="[]"
    fi
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Format commit message based on chosen convention
format_commit_message() {
    local type="$1"
    local description="$2"
    
    if [[ "${COMMIT_CONVENTION}" == "clean-commit" ]]; then
        # Clean Commit: <emoji> <type>: <description>
        local emoji=""
        case "${type}" in
            chore) emoji="☕" ;;
            new)   emoji="📦" ;;
            update) emoji="🔧" ;;
            remove) emoji="🗑️" ;;
            security) emoji="🔒" ;;
            setup) emoji="⚙️" ;;
            test)  emoji="🧪" ;;
            docs)  emoji="📖" ;;
            release) emoji="🚀" ;;
            *) emoji="☕" ;;
        esac
        echo "${emoji} ${type}: ${description}"
    else
        # Conventional Commits: <type>: <description>
        echo "${type}: ${description}"
    fi
}

# Stage synced manifest files (package.json, Cargo.toml, etc.) if sync is enabled
stage_version_files() {
    if [[ "${SYNC_VERSION_FILES}" != "true" ]]; then
        return 0
    fi

    local file_paths="${VERSION_FILE_PATHS}"

    # Auto-detect if no paths provided
    if [[ -z "${file_paths}" ]]; then
        local -a detected=()
        [[ -f "package.json" ]]   && detected+=("package.json")
        [[ -f "Cargo.toml" ]]     && detected+=("Cargo.toml")
        [[ -f "pyproject.toml" ]] && detected+=("pyproject.toml")
        [[ -f "pubspec.yaml" ]]   && detected+=("pubspec.yaml")
        local IFS=','
        file_paths="${detected[*]}"
    fi

    if [[ -z "${file_paths}" ]]; then
        return 0
    fi

    IFS=',' read -ra file_list <<< "${file_paths}"
    for raw_file in "${file_list[@]}"; do
        local file="${raw_file#"${raw_file%%[! ]*}"}"
        file="${file%"${file##*[! ]}"}"
        [[ -z "${file}" ]] && continue
        if [[ -f "${file}" ]]; then
            git add "${file}"
            log_info "Staged version file: ${file}"
        fi
    done

    # In monorepo mode, also stage per-package manifest files that were modified
    if [[ "${MONOREPO}" == "true" ]] && command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
        local manifest_names=("package.json" "Cargo.toml" "pyproject.toml" "pubspec.yaml")
        while IFS= read -r pkg_path; do
            for manifest in "${manifest_names[@]}"; do
                if [[ -f "${pkg_path}/${manifest}" ]] && ! git diff --quiet "${pkg_path}/${manifest}" 2>/dev/null; then
                    git add "${pkg_path}/${manifest}"
                    log_info "Staged version file: ${pkg_path}/${manifest}"
                fi
            done
        done < <(echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path')
    fi
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

if [[ -z "$(git status --porcelain)" ]]; then
    log_info "No changelog changes to commit"
    exit 0
fi

log_info "Using ${COMMIT_CONVENTION} commit convention"

# Add changelog files
if [[ "${MONOREPO}" == "true" ]]; then
    log_info "Committing monorepo changelogs..."
    
    # Add root changelog if exists
    if [[ -f "${CHANGELOG_PATH}" ]]; then
        git add "${CHANGELOG_PATH}"
    fi
    
    # Add per-package changelogs
    if command -v jq &> /dev/null && [[ "${WORKSPACE_PACKAGES}" != "[]" ]]; then
        while IFS= read -r pkg_path; do
            if [[ -f "${pkg_path}/CHANGELOG.md" ]]; then
                git add "${pkg_path}/CHANGELOG.md"
            fi
        done < <(echo "${WORKSPACE_PACKAGES}" | jq -r '.[].path')
    fi
    
    COMMIT_MSG=$(format_commit_message "chore" "update changelogs for ${VERSION_TAG}")
    stage_version_files
    git commit -m "${COMMIT_MSG}"
else
    log_info "Committing changelog..."
    git add "${CHANGELOG_PATH}"
    COMMIT_MSG=$(format_commit_message "chore" "update CHANGELOG.md for ${VERSION_TAG}")
    stage_version_files
    git commit -m "${COMMIT_MSG}"
fi

git push

log_success "Changelog committed successfully"
