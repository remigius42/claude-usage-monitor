#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Integration tests for -o format="..." CLI option
# Run with: bats tests/output-format.bats

load 'helpers'

# --- CLI Format Option ---

@test "-o format option is recognized" {
    # Mock get_usage_data to return success with test data
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="10"
        SESSION_RESET="Dec 16, 9pm"
        WEEK_RESET="Dec 23, 9pm"
        session_hours_remaining="2.5"
        week_hours_remaining="168.0"
        burn_rate_message=""
        data_state="ok"
        return 0
    }

    result=$(format_templated "Session: %session_num%")
    [ "$result" = "Session: 25%" ]
}

@test "-o format handles loading state" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        data_state="loading"
        return 1
    }

    result=$(format_templated "Session: %session_num%")
    [ "$result" = "⏳" ]
}

@test "-o format handles error state" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        data_state="error"
        return 1
    }

    result=$(format_templated "Session: %session_num%")
    [ "$result" = "?" ]
}

@test "-o format handles fetch error with cached data" {
    # SC2034 - "appears unused" for mock
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2034,SC2317,SC2329
    get_usage_data() {
        FETCH_ERROR="Connection failed"
        data_state="ok"
        return 0
    }

    result=$(format_templated "Session: %session_num%")
    [ "$result" = "⚠️" ]
}

# --- Summary Output ---

@test "-o summary produces multi-line output" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="10"
        SESSION_RESET="Dec 16, 9pm"
        WEEK_RESET="Dec 23, 9pm"
        session_hours_remaining="2.5"
        week_hours_remaining="168.0"
        burn_rate_message=""
        data_state="ok"
        return 0
    }

    result=$(format_summary)
    # Should contain session and week info on separate lines
    [[ "$result" == *"Session:"* ]]
    [[ "$result" == *"Week:"* ]]
    [[ "$result" == *"Updated:"* ]]
}

@test "-o summary includes burn rate warning when present" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    get_usage_data() {
        SESSION_NUM="75"
        WEEK_NUM="30"
        SESSION_RESET="Dec 16, 9pm"
        WEEK_RESET="Dec 23, 9pm"
        session_hours_remaining="2.5"
        week_hours_remaining="168.0"
        burn_rate_message="Exhausted in 3h (21:00)"
        data_state="ok"
        return 0
    }

    result=$(format_summary)
    [[ "$result" == *"Exhausted"* ]]
}

@test "-o summary excludes burn rate warning when empty" {
    # SC2034 - "appears unused" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2034,SC2329
    get_usage_data() {
        SESSION_NUM="25"
        WEEK_NUM="10"
        SESSION_RESET="Dec 16, 9pm"
        WEEK_RESET="Dec 23, 9pm"
        session_hours_remaining="2.5"
        week_hours_remaining="168.0"
        burn_rate_message=""
        data_state="ok"
        return 0
    }

    result=$(format_summary)
    [[ "$result" != *"Exhausted"* ]]
}

@test "-o summary handles loading state" {
    # SC2034 - "appears unused" for mock
    # shellcheck disable=SC2034
    get_usage_data() {
        data_state="loading"
        return 1
    }

    result=$(format_summary)
    [ "$result" = "⏳" ]
}
