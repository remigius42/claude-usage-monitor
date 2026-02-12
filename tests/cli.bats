#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# CLI interface and debug utility tests
# Run with: bats tests/cli.bats

load 'helpers'

# --- CLI Interface ---
# PATH, usage/help, argument validation, SWIFTBAR auto-detection

@test "PATH includes ~/.local/bin for native installer support" {
    # Check ~/.local/bin is prepended to PATH
    [[ "$PATH" == "$HOME/.local/bin:"* ]]
}

@test "no arguments shows usage and exits with code 1" {
    run "$PROJECT_DIR/claude-usage.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "invalid format shows usage and exits with code 1" {
    run "$PROJECT_DIR/claude-usage.sh" -o invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"swiftbar"* ]]
    [[ "$output" == *"claude"* ]]
    [[ "$output" == *"format="* ]]
}

@test "-h shows usage and exits with code 0" {
    run "$PROJECT_DIR/claude-usage.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "SWIFTBAR=1 auto-detects swiftbar format" {
    run env SWIFTBAR=1 "$PROJECT_DIR/claude-usage.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"🤖"* ]]
}

@test "explicit -o flag overrides SWIFTBAR auto-detection" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    # Create cache to avoid actual fetch
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="10"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # Run with SWIFTBAR=1 but explicit -o format="..."
    run env SWIFTBAR=1 "$PROJECT_DIR/claude-usage.sh" -o format="Claude: %session_num%"
    [ "$status" -eq 0 ]
    # Should use format output (single line with our format)
    [[ "$output" == "Claude: 25%" ]]

    rm -f "$CACHE_FILE"
}

@test "no SWIFTBAR env requires -o flag" {
    # Ensure SWIFTBAR is not set
    run env -u SWIFTBAR "$PROJECT_DIR/claude-usage.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "SWIFTBAR=1 reads cache without -c flag (regression)" {
    # This test verifies the fix for SwiftBar being stuck in "Loading..." state
    # Bug: USE_CACHE defaulted to false, so cache was never read even when present
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    # Create a valid cache file
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="42"
WEEK_NUM="15"
SESSION_RESET="in 3 hours"
WEEK_RESET="in 5 days"
burn_rate_message=""
session_hours_remaining="3.0"
week_hours_remaining="120.0"
EOF
    touch "$CACHE_FILE"  # Fresh timestamp — no background refresh triggered

    # Run the actual script with SWIFTBAR=1 (no -c flag)
    run env SWIFTBAR=1 "$PROJECT_DIR/claude-usage.sh"
    [ "$status" -eq 0 ]

    # Should show actual data, not loading indicator
    [[ "$output" == *"42%"* ]]
    [[ "$output" != *"⏳"* ]]
    [[ "$output" != *"Loading"* ]]

    rm -f "$CACHE_FILE"
}

# --- Debug Utilities ---
# is_debug_enabled, toggle_debug_logging

@test "is_debug_enabled returns false when log does not exist" {
    rm -f "$DEBUG_LOG"
    run ! is_debug_enabled
    [ "$status" -ne 0 ]
}

@test "toggle_debug_logging creates log file" {
    rm -f "$DEBUG_LOG"
    toggle_debug_logging
    [ -f "$DEBUG_LOG" ]
    rm -f "$DEBUG_LOG"
}

@test "is_debug_enabled returns true when log exists" {
    echo "test" > "$DEBUG_LOG"
    is_debug_enabled
    rm -f "$DEBUG_LOG"
}

@test "toggle_debug_logging deletes log file when enabled" {
    echo "test" > "$DEBUG_LOG"
    toggle_debug_logging
    [ ! -f "$DEBUG_LOG" ]
}
