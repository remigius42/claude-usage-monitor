#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# SwiftBar output format tests
# Run with: bats tests/output-swiftbar.bats

load 'helpers'

@test "swiftbar format includes menu bar output" {
    # Mock the get_usage_data function
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

    result=$(format_swiftbar)
    [[ "$result" == *"🤖 25%"* ]]
    [[ "$result" == *"color=#00AA00,#00FF00"* ]]
    [[ "$result" == *"Session: 25%"* ]]
    [[ "$result" == *"Week: 10%"* ]]
}

@test "swiftbar uses orange for 50-80% usage" {
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    get_usage_data() {
        SESSION_NUM="65"
        WEEK_NUM="10"
        SESSION_RESET="in 2 hours"
        WEEK_RESET="in 3 days"
        return 0
    }

    result=$(format_swiftbar)
    [[ "$result" == *"color=#CC6600,#FF9933"* ]]
}

@test "swiftbar uses red for 80%+ usage" {
    # SC2034 - "appears unused" for mock
    # shellcheck disable=SC2034
    get_usage_data() {
        SESSION_NUM="85"
        WEEK_NUM="10"
        SESSION_RESET="in 2 hours"
        WEEK_RESET="in 3 days"
        return 0
    }

    result=$(format_swiftbar)
    [[ "$result" == *"color=#CC0000,#FF3333"* ]]
}

@test "format_swiftbar shows hourglass when loading" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    # Simulate refresh in progress
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    maybe_trigger_background_refresh() { :; }

    result=$(format_swiftbar)
    [[ "$result" == *"⏳"* ]]
    [[ "$result" == *"Loading"* ]]

    rm -rf "$LOCK_DIR"
}

@test "format_menu_output shows Week 100% in red when week at 100%" {
    output=$(format_menu_output "75" "100" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 5h (10:30pm)")
    echo "$output" | head -n 1 | grep -q "🤖 Week: 100% | color=#CC0000,#FF3333"
}

@test "format_menu_output hides burn rate when week at 100%" {
    output=$(format_menu_output "75" "100" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 5h (10:30pm)")
    run grep -q "Exhausted in" <<< "$output"
    [ "$status" -ne 0 ]
}

@test "format_menu_output shows session percentage when week below 100%" {
    output=$(format_menu_output "75" "50" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 5h (10:30pm)")
    echo "$output" | head -n 1 | grep -q "🤖 75%"
}

@test "format_menu_output shows burn rate when week below 100%" {
    output=$(format_menu_output "75" "50" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 5h (10:30pm)")
    echo "$output" | grep -q "⚠️ Exhausted in 5h"
}

@test "format_menu_output shows week when both at 100%" {
    output=$(format_menu_output "100" "100" "5pm" "Dec 16, 9pm" "3.5" "24.0" "")
    echo "$output" | head -n 1 | grep -q "🤖 Week: 100%"
}

@test "format_menu_output falls back to session with invalid week" {
    output=$(format_menu_output "75" "" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 5h (10:30pm)")
    echo "$output" | head -n 1 | grep -q "🤖 75%"
}

@test "format_menu_output normal display at 99% week" {
    output=$(format_menu_output "90" "99" "5pm" "Dec 16, 9pm" "3.5" "24.0" "⚠️ Exhausted in 2h (8:00pm)")
    echo "$output" | head -n 1 | grep -q "🤖 90%"
    echo "$output" | grep -q "Exhausted in"
}

@test "format_menu_output uses orange for medium usage" {
    output=$(format_menu_output "65" "50" "5pm" "Dec 16, 9pm" "3.5" "24.0" "")
    echo "$output" | head -n 1 | grep -q "color=#CC6600,#FF9933"
}
