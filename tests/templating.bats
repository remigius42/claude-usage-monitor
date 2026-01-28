#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Template engine unit tests
# Run with: bats tests/templating.bats

load 'helpers'

# --- Basic Placeholder Substitution ---

@test "format_templated_with_data substitutes session_num" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "%session_num%")
    [ "$result" = "25%" ]
}

@test "format_templated_with_data substitutes week_num" {
    WEEK_NUM="10"
    result=$(format_templated_with_data "%week_num%")
    [ "$result" = "10%" ]
}

@test "format_templated_with_data shows N/A for missing session_num" {
    SESSION_NUM=""
    result=$(format_templated_with_data "%session_num%")
    [ "$result" = "N/A" ]
}

@test "format_templated_with_data shows N/A for missing week_num" {
    WEEK_NUM=""
    result=$(format_templated_with_data "%week_num%")
    [ "$result" = "N/A" ]
}

@test "format_templated_with_data substitutes last_update" {
    # Create a fresh cache file to get "now" for last_update
    echo "" > "$CACHE_FILE"
    result=$(format_templated_with_data "%last_update%")
    [ "$result" = "now" ]
}

@test "format_templated_with_data substitutes projected_expiration" {
    burn_rate_message="Exhausted in 3h"
    result=$(format_templated_with_data "%projected_expiration%")
    [ "$result" = "Exhausted in 3h" ]
}

@test "format_templated_with_data shows empty for missing projected_expiration" {
    burn_rate_message=""
    result=$(format_templated_with_data "%projected_expiration%")
    [ -z "$result" ]
}

@test "format_templated_with_data substitutes session_reset_time" {
    SESSION_RESET="Dec 16, 9pm"
    result=$(format_templated_with_data "%session_reset_time%")
    # Should be reformatted based on 24h setting
    [[ -n "$result" ]]
}

@test "format_templated_with_data substitutes session_reset_duration" {
    SESSION_RESET="Dec 16, 9pm"
    session_hours_remaining="2.5"
    result=$(format_templated_with_data "%session_reset_duration%")
    [ "$result" = "2h 30m" ]
}

@test "format_templated_with_data shows N/A for session_reset_duration when no reset" {
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    SESSION_RESET=""
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    session_hours_remaining="2.5"
    result=$(format_templated_with_data "%session_reset_duration%")
    [ "$result" = "N/A" ]
}

@test "format_templated_with_data substitutes week_reset_duration" {
    WEEK_RESET="Dec 23, 9pm"
    week_hours_remaining="168.0"
    result=$(format_templated_with_data "%week_reset_duration%")
    [ "$result" = "7d" ]
}

@test "format_templated_with_data shows N/A for week_reset_duration when no reset" {
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    WEEK_RESET=""
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    week_hours_remaining="168.0"
    result=$(format_templated_with_data "%week_reset_duration%")
    [ "$result" = "N/A" ]
}

# --- Multiple Placeholders ---

@test "format_templated_with_data handles multiple placeholders" {
    SESSION_NUM="25"
    WEEK_NUM="10"
    result=$(format_templated_with_data "Session: %session_num% | Week: %week_num%")
    [ "$result" = "Session: 25% | Week: 10%" ]
}

@test "format_templated_with_data handles repeated placeholders" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "%session_num% and %session_num%")
    [ "$result" = "25% and 25%" ]
}

# --- Newline Substitution ---

@test "format_templated_with_data substitutes newline" {
    SESSION_NUM="25"
    WEEK_NUM="10"
    result=$(format_templated_with_data "Line1%n%Line2")
    expected=$'Line1\nLine2'
    [ "$result" = "$expected" ]
}

@test "format_templated_with_data handles multiple newlines" {
    result=$(format_templated_with_data "A%n%B%n%C")
    expected=$'A\nB\nC'
    [ "$result" = "$expected" ]
}

@test "format_templated_with_data handles consecutive newlines" {
    result=$(format_templated_with_data "A%n%%n%B")
    expected=$'A\n\nB'
    [ "$result" = "$expected" ]
}

# --- Conditional Blocks ---

@test "conditional block renders when content is valid" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "Usage{? is %session_num%?}")
    [ "$result" = "Usage is 25%" ]
}

@test "conditional block removed when content has N/A" {
    SESSION_NUM=""
    result=$(format_templated_with_data "Usage{? is %session_num%?}")
    [ "$result" = "Usage" ]
}

@test "conditional block removed when content is empty" {
    burn_rate_message=""
    result=$(format_templated_with_data "Status{?%projected_expiration%?}")
    [ "$result" = "Status" ]
}

@test "conditional block removed when content is whitespace only" {
    burn_rate_message=""
    result=$(format_templated_with_data "Status{?   %projected_expiration%   ?}")
    [ "$result" = "Status" ]
}

@test "conditional block with newline renders when valid" {
    burn_rate_message="Warning!"
    result=$(format_templated_with_data "Status{?%n%%projected_expiration%?}")
    expected=$'Status\nWarning!'
    [ "$result" = "$expected" ]
}

@test "conditional block with newline removed when empty" {
    burn_rate_message=""
    result=$(format_templated_with_data "Status{?%n%%projected_expiration%?}")
    [ "$result" = "Status" ]
}

@test "multiple conditional blocks handled correctly" {
    SESSION_NUM="25"
    WEEK_NUM=""
    result=$(format_templated_with_data "{?S:%session_num%?}{?W:%week_num%?}")
    [ "$result" = "S:25%" ]
}

@test "nested placeholders inside conditional blocks work" {
    SESSION_NUM="25"
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    WEEK_NUM="10"
    result=$(format_templated_with_data "{?Session: %session_num%, Week: %week_num%?}")
    [ "$result" = "Session: 25%, Week: 10%" ]
}

@test "conditional block at end of string" {
    burn_rate_message="Warning"
    result=$(format_templated_with_data "Status{? - %projected_expiration%?}")
    [ "$result" = "Status - Warning" ]
}

@test "conditional block at start of string" {
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    burn_rate_message="Warning"
    result=$(format_templated_with_data "{?%projected_expiration% - ?}Status")
    [ "$result" = "Warning - Status" ]
}

# --- Literal Text ---

@test "format_templated_with_data handles literal text without placeholders" {
    result=$(format_templated_with_data "Hello World")
    [ "$result" = "Hello World" ]
}

@test "format_templated_with_data handles empty format string" {
    result=$(format_templated_with_data "")
    [ -z "$result" ]
}

@test "format_templated_with_data preserves special characters" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "Usage: %session_num% | Status: OK")
    [ "$result" = "Usage: 25% | Status: OK" ]
}

@test "format_templated_with_data handles ampersand in template" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "Session & Week: %session_num%")
    [ "$result" = "Session & Week: 25%" ]
}

@test "format_templated_with_data handles backslash in template" {
    SESSION_NUM="25"
    result=$(format_templated_with_data "Path\\Value: %session_num%")
    [ "$result" = "Path\\Value: 25%" ]
}

# --- Edge Cases ---

@test "format_templated_with_data handles unknown placeholder literally" {
    result=$(format_templated_with_data "%unknown_placeholder%")
    [ "$result" = "%unknown_placeholder%" ]
}

@test "format_templated_with_data handles partial placeholder syntax" {
    result=$(format_templated_with_data "%incomplete")
    [ "$result" = "%incomplete" ]
}

@test "format_templated_with_data handles unclosed conditional block" {
    # SC2034 - "appears unused" for test
    # shellcheck disable=SC2034
    SESSION_NUM="25"
    result=$(format_templated_with_data "Start{?content")
    [ "$result" = "Start{?content" ]
}

@test "format_templated_with_data handles empty conditional block delimiters" {
    result=$(format_templated_with_data "Before{??}After")
    [ "$result" = "BeforeAfter" ]
}
