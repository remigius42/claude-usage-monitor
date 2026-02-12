#!/usr/bin/env bats

# spellchecker: ignore mktemp

bats_require_minimum_version 1.5.0

# Tests for plugins/i3blocks/claude-usage-i3blocks.sh
# Run with: bats tests/i3blocks-wrapper.bats

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    WRAPPER="$PROJECT_DIR/plugins/i3blocks/claude-usage-i3blocks.sh"

    # Set up cache file path (same as main script's _RUNTIME_DIR logic)
    local runtime_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    export CACHE_FILE="$runtime_dir/claude-usage-monitor-cache-$USER.txt"
    export LOCK_DIR="/tmp/claude-usage-monitor-$USER.lock"

    # Clean up before each test
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    # Reset I3BLOCKS_PANGO for each test
    unset I3BLOCKS_PANGO
}

teardown() {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"
}

# Helper to create a cache file with given session and week values
create_cache() {
    local session_num="${1:-50}"
    local week_num="${2:-60}"
    cat > "$CACHE_FILE" <<EOF
SESSION_NUM="$session_num"
WEEK_NUM="$week_num"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"
}

# --- Basic Tests ---

@test "wrapper script exists and is executable" {
    [ -f "$WRAPPER" ]
    [ -x "$WRAPPER" ]
}

@test "wrapper outputs display format with cached data (simple mode)" {
    create_cache 45 67

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # First line should have percentages
    [[ "${lines[0]}" == *"45%"* ]]
    [[ "${lines[0]}" == *"67%"* ]]
    # Second line should have color=
    [[ "${lines[1]}" == "color="* ]]
}

@test "wrapper outputs both session and week values" {
    create_cache 25 80

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"25%"* ]]
    [[ "${lines[0]}" == *"80%"* ]]
    # Check for separator
    [[ "${lines[0]}" == *"|"* ]]
}

# --- Click Event Tests ---

@test "BLOCK_BUTTON=1 (left click) runs without error" {
    create_cache 50 60

    # Override notify-send to avoid actual notification
    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { :; }
    export -f notify-send

    BLOCK_BUTTON=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Should still output display string
    [[ "${lines[0]}" == *"50%"* ]]
}

@test "BLOCK_BUTTON=3 (right click) runs without error" {
    create_cache 50 60

    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { :; }
    export -f notify-send

    BLOCK_BUTTON=3 run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"50%"* ]]
}

@test "BLOCK_BUTTON=2 (middle click) does not trigger notification" {
    create_cache 50 60

    # This should NOT be called for middle click
    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { echo "NOTIFY_CALLED"; }
    export -f notify-send

    BLOCK_BUTTON=2 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # notify-send should not have been called
    [[ "$output" != *"NOTIFY_CALLED"* ]]
}

@test "no BLOCK_BUTTON env runs without notification" {
    create_cache 50 60

    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { echo "NOTIFY_CALLED"; }
    export -f notify-send

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "$output" != *"NOTIFY_CALLED"* ]]
    [[ "${lines[0]}" == *"50%"* ]]
}

# --- Path Resolution Tests ---

@test "exits with error when claude-usage.sh is not found" {
    # Copy wrapper to a temp directory where claude-usage.sh does not exist
    local tmpdir
    tmpdir="$(mktemp -d)"
    cp "$WRAPPER" "$tmpdir/claude-usage-i3blocks.sh"
    chmod +x "$tmpdir/claude-usage-i3blocks.sh"

    run "$tmpdir/claude-usage-i3blocks.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: claude-usage.sh not found"* ]]

    rm -rf "$tmpdir"
}

# --- Simple Mode Color Tests ---

@test "simple mode: green color for usage < 50%" {
    create_cache 25 30

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for green color on second line
    [[ "${lines[1]}" == "color=#98c379" ]]
}

@test "simple mode: orange color for usage 50-79%" {
    create_cache 65 70

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for orange color on second line
    [[ "${lines[1]}" == "color=#e5c07b" ]]
}

@test "simple mode: red color for usage >= 80%" {
    create_cache 85 90

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for red color on second line
    [[ "${lines[1]}" == "color=#e06c75" ]]
}

@test "simple mode: worst color wins (session green, week red)" {
    create_cache 25 85

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Red should win as the worst color
    [[ "${lines[1]}" == "color=#e06c75" ]]
}

@test "simple mode: worst color wins (session red, week green)" {
    create_cache 85 25

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Red should win as the worst color
    [[ "${lines[1]}" == "color=#e06c75" ]]
}

@test "simple mode: worst color wins (session orange, week green)" {
    create_cache 60 30

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Orange should win over green
    [[ "${lines[1]}" == "color=#e5c07b" ]]
}

# --- Pango Mode Tests ---

@test "pango mode: outputs Pango markup" {
    create_cache 45 67

    I3BLOCKS_PANGO=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Should have Pango span tags
    [[ "$output" == *"<span foreground="* ]]
    [[ "$output" == *"</span>"* ]]
    # Should NOT have color= line (single line output)
    [ "${#lines[@]}" -eq 1 ]
}

@test "pango mode: green color for usage < 50%" {
    create_cache 25 30

    I3BLOCKS_PANGO=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for green color in Pango markup
    [[ "$output" == *'<span foreground="#98c379">'* ]]
}

@test "pango mode: mixed colors for different session and week usage" {
    create_cache 25 85

    I3BLOCKS_PANGO=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Should have both green (session) and red (week)
    [[ "$output" == *'<span foreground="#98c379">25%</span>'* ]]
    [[ "$output" == *'<span foreground="#e06c75">85%</span>'* ]]
}

@test "pango mode: red color for usage >= 80%" {
    create_cache 85 90

    I3BLOCKS_PANGO=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for red color in Pango markup
    [[ "$output" == *'<span foreground="#e06c75">'* ]]
}

# --- Loading State Detection Tests ---

@test "0% session usage is displayed, not treated as loading/error" {
    create_cache 0 10

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"0%"* ]]
    [[ "${lines[0]}" == *"10%"* ]]
    [[ "${lines[0]}" == *"|"* ]]
}

@test "5% session usage is displayed, not treated as loading/error" {
    create_cache 5 15

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"5%"* ]]
    [[ "${lines[0]}" == *"15%"* ]]
    [[ "${lines[0]}" == *"|"* ]]
}
