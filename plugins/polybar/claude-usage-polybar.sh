#!/usr/bin/env bash

# spellchecker: ignore rrggbb

# Polybar wrapper for Claude Usage Monitor
# Displays usage with Nerd Font icons, dynamic colors, and click notifications
#
# Usage: claude-usage-polybar.sh
#
# Click behavior (via Polybar BUTTON env var):
#   Left click (1):  Show summary notification
#   Right click (3): Show summary notification

set -euo pipefail

# --- Configuration ---

# Resolve the path to claude-usage.sh
# Check same directory first (installed layout), then relative path (source repo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/claude-usage.sh" ]]; then
    CLAUDE_USAGE_SH="${SCRIPT_DIR}/claude-usage.sh"
elif [[ -x "${SCRIPT_DIR}/../../claude-usage.sh" ]]; then
    CLAUDE_USAGE_SH="${SCRIPT_DIR}/../../claude-usage.sh"
else
    echo "Error: claude-usage.sh not found"
    exit 1
fi

# Color thresholds (matches SwiftBar behavior)
# Colors are Polybar format: %{F#rrggbb}text%{F-}
COLOR_GREEN="#98c379"
COLOR_ORANGE="#e5c07b"
COLOR_RED="#e06c75"

# Notification settings
NOTIFY_TITLE="Claude Usage"
NOTIFY_TIMEOUT=5000  # milliseconds
NOTIFY_ICON="face-robot"  # freedesktop icon name (fallback: dialog-information)

# --- Functions ---

# Determine color based on percentage (green < 50%, orange < 80%, red >= 80%)
get_color() {
    local pct="$1"
    # Extract number from "45%" or handle non-numeric gracefully
    local num="${pct%\%}"
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        if ((num >= 80)); then
            echo "$COLOR_RED"
        elif ((num >= 50)); then
            echo "$COLOR_ORANGE"
        else
            echo "$COLOR_GREEN"
        fi
    else
        # Non-numeric (loading/error state) - no color
        echo ""
    fi
}

# Wrap text in Polybar color tags
colorize() {
    local text="$1"
    local color="$2"
    if [[ -n "$color" ]]; then
        echo "%{F${color}}${text}%{F-}"
    else
        echo "$text"
    fi
}

show_notification() {
    local summary
    summary=$("$CLAUDE_USAGE_SH" -o summary) || return 0

    if command -v notify-send &>/dev/null; then
        notify-send -i "$NOTIFY_ICON" -t "$NOTIFY_TIMEOUT" "$NOTIFY_TITLE" "$summary" || true
    fi
}

# --- Main ---

# Handle Polybar click events
# BUTTON is set by Polybar: 1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down
case "${BUTTON:-}" in
    1|3)
        show_notification
        ;;
esac

# Get usage values
session=$("$CLAUDE_USAGE_SH" -o format="%session_num%")
week=$("$CLAUDE_USAGE_SH" -o format="%week_num%")

# Handle loading/error states (non-percentage output like ⏳, ?, ⚠️)
if [[ ! "$session" =~ ^[0-9]+%$ ]]; then
    echo "$session"
    exit 0
fi

# Colorize based on percentage
session_color=$(get_color "$session")
week_color=$(get_color "$week")

# Output with icons and colors
echo "🤖 $(colorize "$session" "$session_color") | 📅 $(colorize "$week" "$week_color")"
