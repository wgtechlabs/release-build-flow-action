#!/bin/bash
# =============================================================================
# VALIDATE INPUTS
# =============================================================================
# Validates action inputs before processing
#
# Environment Variables (from action.yml):
#   - MAIN_BRANCH
#   - DEV_BRANCH
#   - VERSION_PREFIX
#   - INITIAL_VERSION
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

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

# =============================================================================
# VALIDATION
# =============================================================================

log_info "Validating inputs..."

# Validate branch names
if [[ -z "${MAIN_BRANCH:-}" ]]; then
    log_error "main-branch is required"
    exit 1
fi

if [[ -z "${DEV_BRANCH:-}" ]]; then
    log_error "dev-branch is required"
    exit 1
fi

# Validate initial version format (SemVer)
if [[ -n "${INITIAL_VERSION:-}" ]]; then
    if ! [[ "${INITIAL_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "initial-version must be in SemVer format (e.g., 0.1.0)"
        exit 1
    fi
fi

log_success "All inputs are valid"
