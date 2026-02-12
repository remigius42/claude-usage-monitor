#!/usr/bin/env bash

# spellchecker: ignore rrggbb

# i3blocks wrapper for Claude Usage Monitor
# Displays usage with icons, dynamic colors, and click notifications
#
# Usage: claude-usage-i3blocks.sh
#
# Click behavior (via i3blocks BLOCK_BUTTON env var):
#   Left click (1):  Show summary notification
#   Right click (3): Show summary notification
#
# Environment variables:
#   I3BLOCKS_PANGO=1  Enable Pango markup for per-value colors
#                     (requires markup=pango in i3blocks config)

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

# Returns the "worst" (highest severity) color for simple mode
get_worst_color() {
    local color1="$1"
    local color2="$2"
    # Priority: red > orange > green > empty
    if [[ "$color1" == "$COLOR_RED" || "$color2" == "$COLOR_RED" ]]; then
        echo "$COLOR_RED"
    elif [[ "$color1" == "$COLOR_ORANGE" || "$color2" == "$COLOR_ORANGE" ]]; then
        echo "$COLOR_ORANGE"
    elif [[ -n "$color1" || -n "$color2" ]]; then
        echo "$COLOR_GREEN"
    else
        echo ""
    fi
}

# Wrap text in Pango span tags (for I3BLOCKS_PANGO=1 mode)
colorize_pango() {
    local text="$1"
    local color="$2"
    if [[ -n "$color" ]]; then
        echo "<span foreground=\"${color}\">${text}</span>"
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

# Handle i3blocks click events
# BLOCK_BUTTON is set by i3blocks: 1=left, 2=middle, 3=right, 4=scroll up, 5=scroll down
case "${BLOCK_BUTTON:-}" in
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

# Get colors based on percentage
session_color=$(get_color "$session")
week_color=$(get_color "$week")

# Output based on mode
if [[ "${I3BLOCKS_PANGO:-}" == "1" ]]; then
    # Pango mode: inline colors per value
    echo "🤖 $(colorize_pango "$session" "$session_color") | 📅 $(colorize_pango "$week" "$week_color")"
else
    # Simple mode: plain text + color= line for worst color
    echo "🤖 $session | 📅 $week"
    worst_color=$(get_worst_color "$session_color" "$week_color")
    if [[ -n "$worst_color" ]]; then
        echo "color=$worst_color"
    fi
fi
