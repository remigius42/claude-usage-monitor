#!/usr/bin/env bats

# spellchecker: ignore mktemp

bats_require_minimum_version 1.5.0

# Tests for plugins/polybar/claude-usage-polybar.sh
# Run with: bats tests/polybar-wrapper.bats

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    WRAPPER="$PROJECT_DIR/plugins/polybar/claude-usage-polybar.sh"

    # Set up cache file path (same as main script's _RUNTIME_DIR logic)
    local runtime_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    export CACHE_FILE="$runtime_dir/claude-usage-monitor-cache-$USER.txt"
    export LOCK_DIR="/tmp/claude-usage-monitor-$USER.lock"

    # Clean up before each test
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"
}

teardown() {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"
}

# --- Basic Tests ---

@test "wrapper script exists and is executable" {
    [ -f "$WRAPPER" ]
    [ -x "$WRAPPER" ]
}

@test "wrapper outputs display format with cached data" {
    # Create cache with test data
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="45"
WEEK_NUM="67"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for percentages in output (icons may vary by font)
    [[ "$output" == *"45%"* ]]
    [[ "$output" == *"67%"* ]]
}

@test "wrapper outputs both session and week values" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="80"
SESSION_RESET="in 1 hour"
WEEK_RESET="in 2 days"
session_hours_remaining="1.0"
week_hours_remaining="48.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"25%"* ]]
    [[ "$output" == *"80%"* ]]
    # Check for separator
    [[ "$output" == *"|"* ]]
}

# --- Click Event Tests ---

@test "BUTTON=1 (left click) runs without error" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="60"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # Override notify-send to avoid actual notification
    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { :; }
    export -f notify-send

    BUTTON=1 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Should still output display string
    [[ "$output" == *"50%"* ]]
}

@test "BUTTON=3 (right click) runs without error" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="60"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { :; }
    export -f notify-send

    BUTTON=3 run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"50%"* ]]
}

@test "BUTTON=2 (middle click) does not trigger notification" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="60"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # This should NOT be called for middle click
    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { echo "NOTIFY_CALLED"; }
    export -f notify-send

    BUTTON=2 run "$WRAPPER"
    [ "$status" -eq 0 ]
    # notify-send should not have been called
    [[ "$output" != *"NOTIFY_CALLED"* ]]
}

@test "no BUTTON env runs without notification" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="60"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # SC2329 - "unused function" for mock (invoked indirectly via subshell)
    # shellcheck disable=SC2329
    notify-send() { echo "NOTIFY_CALLED"; }
    export -f notify-send

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    [[ "$output" != *"NOTIFY_CALLED"* ]]
    [[ "$output" == *"50%"* ]]
}

# --- Path Resolution Tests ---

@test "exits with error when claude-usage.sh is not found" {
    # Copy wrapper to a temp directory where claude-usage.sh does not exist
    local tmpdir
    tmpdir="$(mktemp -d)"
    cp "$WRAPPER" "$tmpdir/claude-usage-polybar.sh"
    chmod +x "$tmpdir/claude-usage-polybar.sh"

    run "$tmpdir/claude-usage-polybar.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: claude-usage.sh not found"* ]]

    rm -rf "$tmpdir"
}

# --- Color Tests ---

@test "green color for usage < 50%" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="30"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for green color code
    [[ "$output" == *"#98c379"* ]]
}

@test "orange color for usage 50-79%" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="65"
WEEK_NUM="70"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for orange color code
    [[ "$output" == *"#e5c07b"* ]]
}

@test "red color for usage >= 80%" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="85"
WEEK_NUM="90"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Check for red color code
    [[ "$output" == *"#e06c75"* ]]
}

@test "mixed colors for different session and week usage" {
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="85"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
session_hours_remaining="2.0"
week_hours_remaining="72.0"
burn_rate_message=""
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    run "$WRAPPER"
    [ "$status" -eq 0 ]
    # Should have both green (session) and red (week)
    [[ "$output" == *"#98c379"* ]]
    [[ "$output" == *"#e06c75"* ]]
}
