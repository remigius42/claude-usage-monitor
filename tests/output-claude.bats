#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Claude CLI output format tests
# Run with: bats tests/output-claude.bats

load 'helpers'

@test "claude format includes context and reset times" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="10"
        SESSION_RESET="in 2 hours"
        WEEK_RESET="in 3 days"
        return 0
    }

    # Provide mock JSON input
    result=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.5}}' | format_claude)
    [[ "$result" == *"[Opus]"* ]]
    [[ "$result" == *"Ctx:"* ]]
    [[ "$result" == *"42%"* ]]
    [[ "$result" == *"Session:"* ]]
    [[ "$result" == *"25%"* ]]
    [[ "$result" == *"(2h)"* ]]
    [[ "$result" == *"Week:"* ]]
    [[ "$result" == *"10%"* ]]
    [[ "$result" == *"(3d)"* ]]
}

@test "claude format includes ANSI color codes when supported" {
    # Mock supports_color to return true
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    supports_color() { return 0; }

    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="85"
        SESSION_RESET="in 2 hours"
        WEEK_RESET="in 3 days"
        return 0
    }

    result=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.5}}' | format_claude)
    # Check that ANSI escape codes are present (green for 25%, red for 85%)
    [[ "$result" == *$'\033[32m'* ]]  # Green for session 25%
    [[ "$result" == *$'\033[31m'* ]]  # Red for week 85%
    [[ "$result" == *$'\033[0m'* ]]   # Reset code
}

@test "claude format has no ANSI codes when colors not supported" {
    # Mock supports_color to return false
    supports_color() { return 1; }

    # SC2034 - "appears unused" for mock
    # shellcheck disable=SC2034
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="85"
        SESSION_RESET="in 2 hours"
        WEEK_RESET="in 3 days"
        return 0
    }

    result=$(echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42.5}}' | format_claude)
    # Check that no ANSI escape codes are present
    [[ "$result" != *$'\033['* ]]
}

@test "format_claude shows hourglass when loading" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    # Simulate refresh in progress
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    # Mock background refresh to avoid spawning
    maybe_trigger_background_refresh() { :; }

    result=$(echo '{"model":{"display_name":"Opus"}}' | format_claude)
    [[ "$result" == *"⏳"* ]]

    rm -rf "$LOCK_DIR"
}
