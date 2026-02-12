#!/usr/bin/env bash
set -euo pipefail

# Configure ~/.claude.json to suppress trust dialog
# Usage: ./configure-claude-json.sh [directory_path]

readonly CLAUDE_JSON="$HOME/.claude.json"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_SUFFIX

# Get the directory to trust (defaults to first argument or current swiftbar directory)
TRUST_DIR="${1:-$HOME/swiftbar}"

# Color codes for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    error "jq is required but not installed."
    echo "Install with: brew install jq"
    exit 1
fi

# Check if ~/.claude.json exists
if [ ! -f "$CLAUDE_JSON" ]; then
    error "$HOME/.claude.json not found"
    echo "This file should be created by Claude CLI during first run."
    echo "Please run 'claude' first to initialize the configuration."
    exit 1
fi

echo "======================================================================"
echo "Claude Configuration Helper"
echo "======================================================================"
echo
echo "This script will add the following entry to ~/.claude.json:"
echo
echo -e "${YELLOW}"
cat <<EOF
{
  "$TRUST_DIR": {
    "hasTrustDialogAccepted": true
  }
}
EOF
echo -e "${NC}"
echo
echo "This suppresses the trust dialog when running scripts from this directory."
echo

# Prompt for confirmation
read -rp "Do you want to proceed? [y/N] " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Configuration cancelled."
    exit 0
fi

# Create backup
info "Creating backup: ${CLAUDE_JSON}${BACKUP_SUFFIX}"
cp "$CLAUDE_JSON" "${CLAUDE_JSON}${BACKUP_SUFFIX}"

# Check if the entry already exists
if jq -e --arg dir "$TRUST_DIR" '.[$dir].hasTrustDialogAccepted' "$CLAUDE_JSON" &>/dev/null; then
    warn "Directory $TRUST_DIR already configured in ~/.claude.json"
    current_value=$(jq -r --arg dir "$TRUST_DIR" '.[$dir].hasTrustDialogAccepted' "$CLAUDE_JSON")

    if [ "$current_value" = "true" ]; then
        info "Trust dialog is already suppressed for this directory."
        exit 0
    else
        info "Updating existing entry..."
    fi
fi

# Add or update the entry
info "Updating ~/.claude.json..."
jq --arg dir "$TRUST_DIR" \
   '. * {($dir): {"hasTrustDialogAccepted": true}}' \
   "$CLAUDE_JSON" > "${CLAUDE_JSON}.tmp"

# Validate the JSON is still valid
if jq empty "${CLAUDE_JSON}.tmp" 2>/dev/null; then
    mv "${CLAUDE_JSON}.tmp" "$CLAUDE_JSON"
    info "✓ Configuration updated successfully!"
    echo
    info "Backup saved to: ${CLAUDE_JSON}${BACKUP_SUFFIX}"
    echo
    info "Configuration for $TRUST_DIR is now active."
else
    error "Failed to update JSON (invalid JSON produced)"
    rm -f "${CLAUDE_JSON}.tmp"
    info "Original file unchanged. Backup: ${CLAUDE_JSON}${BACKUP_SUFFIX}"
    exit 1
fi

# Show the updated configuration
echo
echo "Current configuration:"
echo -e "${GREEN}"
jq --arg dir "$TRUST_DIR" '.[$dir]' "$CLAUDE_JSON"
echo -e "${NC}"
