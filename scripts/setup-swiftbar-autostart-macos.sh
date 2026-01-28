#!/usr/bin/env bash
set -euo pipefail

# spellchecker: words mdfind osascript

# Set up SwiftBar to launch automatically at login (macOS only)
# Usage: ./setup-swiftbar-autostart.sh

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

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This script is for macOS only"
    exit 1
fi

# Get SwiftBar application path (supports both Homebrew and direct DMG installs)
SWIFTBAR_APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.ameba.SwiftBar'" | head -n 1)

if [ -z "$SWIFTBAR_APP" ]; then
    error "SwiftBar is not installed"
    echo "Install with: brew install swiftbar"
    echo "Or download from: https://github.com/swiftbar/SwiftBar/releases"
    exit 1
fi

info "Found SwiftBar at: $SWIFTBAR_APP"

echo
echo "======================================================================"
echo "SwiftBar Autostart Setup"
echo "======================================================================"
echo

# Check if SwiftBar is already in login items
# Note: This is a simplified check and may not catch all cases
if osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -q "SwiftBar"; then
    info "✓ SwiftBar is already configured to start at login"
    echo
    read -rp "Do you want to remove it from login items? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        info "Removing SwiftBar from login items..."
        osascript <<EOF
tell application "System Events"
    delete login item "SwiftBar"
end tell
EOF
        info "✓ SwiftBar removed from login items"
    fi
    exit 0
fi

echo "This will add SwiftBar to your login items so it starts automatically"
echo "when you log in to macOS."
echo

read -rp "Do you want to add SwiftBar to login items? [y/N] " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Setup cancelled."
    echo
    echo "To add SwiftBar to login items manually:"
    echo "1. Open System Settings"
    echo "2. Go to General → Login Items"
    echo "3. Click the '+' button and select SwiftBar.app"
    exit 0
fi

info "Adding SwiftBar to login items..."

# Add SwiftBar to login items using osascript
if osascript <<EOF
tell application "System Events"
    make new login item at end of login items with properties {path:"$SWIFTBAR_APP", hidden:false}
end tell
EOF
then
    echo
    info "✓ SwiftBar has been added to login items!"
    echo
    info "SwiftBar will now start automatically when you log in."
    echo
    echo "You can manage login items in System Settings → General → Login Items"
else
    error "Failed to add SwiftBar to login items"
    echo
    echo "Please add it manually:"
    echo "1. Open System Settings"
    echo "2. Go to General → Login Items"
    echo "3. Click the '+' button and select SwiftBar.app"
    exit 1
fi
