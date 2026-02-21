#!/bin/bash
# =============================================================================
# WORKSPACE PACKAGES LOADER - Shared Library
# =============================================================================
# Provides a helper function for loading WORKSPACE_PACKAGES from a shared
# temp file, avoiding env var size/encoding issues when passing large JSON
# blobs through GitHub Actions outputs and YAML expressions.
#
# Expected environment variables (read):
#   - WORKSPACE_PACKAGES_FILE : path to shared JSON file (optional)
#   - WORKSPACE_PACKAGES      : fallback JSON string (optional, defaults to [])
#
# Expected functions (must be defined in the sourcing script):
#   - log_warning
#
# Sets:
#   - WORKSPACE_PACKAGES : JSON array of package objects
# =============================================================================

# load_workspace_packages: Loads WORKSPACE_PACKAGES from the shared file when
# WORKSPACE_PACKAGES_FILE is set and valid, falling back to the env var.
load_workspace_packages() {
    WORKSPACE_PACKAGES="${WORKSPACE_PACKAGES:-[]}"
    if [[ -n "${WORKSPACE_PACKAGES_FILE:-}" && -f "${WORKSPACE_PACKAGES_FILE}" ]]; then
        local file_content
        file_content=$(cat "${WORKSPACE_PACKAGES_FILE}")
        if echo "${file_content}" | jq empty 2>/dev/null; then
            WORKSPACE_PACKAGES="${file_content}"
        else
            log_warning "Shared packages file contains invalid JSON, falling back to env var"
        fi
    fi
}
