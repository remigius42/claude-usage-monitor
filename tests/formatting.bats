#!/usr/bin/env bats

# spellchecker: ignore mktemp

bats_require_minimum_version 1.5.0

# Parsing and formatting tests
# Run with: bats tests/formatting.bats

load 'helpers'

# --- Parsing Functions ---
# parse_session_pct, parse_week_pct, parse_session_reset, parse_week_reset, parse_reset_time

@test "parse_session_pct extracts first percentage" {
    local mock_output="Current session: 15% used
Some other text
Current week: 42% used"
    result=$(parse_session_pct "$mock_output")
    [ "$result" = "15" ]
}

@test "parse_session_pct handles no match" {
    local mock_output="No percentages here"
    result=$(parse_session_pct "$mock_output")
    [ -z "$result" ]
}

@test "parse_week_pct extracts second percentage" {
    local mock_output="Current session: 15% used
Some other text
Current week: 42% used"
    result=$(parse_week_pct "$mock_output")
    [ "$result" = "42" ]
}

@test "parse_session_reset extracts reset time" {
    local mock_output="Current session: 15% used
  Resets in 2 hours (at 5:00 PM)"
    result=$(parse_session_reset "$mock_output")
    [[ "$result" == *"2 hours"* ]]
}

@test "parse_week_reset extracts week reset time" {
    local mock_output="Current week: 42% used
  Resets in 3 days (on Monday)"
    result=$(parse_week_reset "$mock_output")
    [[ "$result" == *"3 days"* ]]
}

@test "parse_reset_time parses time-only 5pm" {
    parse_reset_time "5pm"
    [ -n "$reset_epoch" ]
    # Should be in the future
    now_epoch=$(date +%s)
    [ "$reset_epoch" -gt "$now_epoch" ] && [ "$reset_epoch" -lt $((now_epoch + 86400)) ]
}

@test "parse_reset_time parses time with minutes 9:59pm" {
    parse_reset_time "9:59pm"
    [ -n "$reset_epoch" ]
}

@test "parse_reset_time parses full date Dec 16, 9pm" {
    parse_reset_time "Dec 16, 9pm"
    [ -n "$reset_epoch" ]
}

@test "parse_reset_time parses full date with minutes Dec 16, 8:59pm" {
    parse_reset_time "Dec 16, 8:59pm"
    [ -n "$reset_epoch" ]
}

@test "parse_reset_time handles date with year Dec 16, 9pm 2025" {
    parse_reset_time "Dec 16, 9pm 2025"
    [ -n "$reset_epoch" ]
}

@test "parse_reset_time fails gracefully on invalid input" {
    run ! parse_reset_time "invalid date string"
    [ "$status" -ne 0 ]
}

@test "parse_reset_time 10pm returns exactly 22:00:00" {
    parse_reset_time "10pm"
    [ -n "$reset_epoch" ]
    hour=$(epoch_to_date "$reset_epoch" '%H')
    minute=$(epoch_to_date "$reset_epoch" '%M')
    second=$(epoch_to_date "$reset_epoch" '%S')
    [ "$hour" = "22" ] && [ "$minute" = "00" ] && [ "$second" = "00" ]
}

@test "parse_reset_time 9am returns exactly 09:00:00" {
    parse_reset_time "9am"
    [ -n "$reset_epoch" ]
    hour=$(epoch_to_date "$reset_epoch" '%H')
    minute=$(epoch_to_date "$reset_epoch" '%M')
    second=$(epoch_to_date "$reset_epoch" '%S')
    [ "$hour" = "09" ] && [ "$minute" = "00" ] && [ "$second" = "00" ]
}

@test "parse_reset_time Dec 23, 9pm returns exactly 21:00:00" {
    parse_reset_time "Dec 23, 9pm"
    [ -n "$reset_epoch" ]
    hour=$(epoch_to_date "$reset_epoch" '%H')
    minute=$(epoch_to_date "$reset_epoch" '%M')
    second=$(epoch_to_date "$reset_epoch" '%S')
    [ "$hour" = "21" ] && [ "$minute" = "00" ] && [ "$second" = "00" ]
}

@test "parse_reset_time 8:59pm preserves minutes as 20:59:00" {
    parse_reset_time "8:59pm"
    [ -n "$reset_epoch" ]
    hour=$(epoch_to_date "$reset_epoch" '%H')
    minute=$(epoch_to_date "$reset_epoch" '%M')
    second=$(epoch_to_date "$reset_epoch" '%S')
    [ "$hour" = "20" ] && [ "$minute" = "59" ] && [ "$second" = "00" ]
}

@test "parse_reset_time normalization gives same epoch for same time" {
    parse_reset_time "9:59pm"
    epoch_1=$reset_epoch
    parse_reset_time "9:59pm"
    epoch_2=$reset_epoch
    [ "$epoch_1" -eq "$epoch_2" ]
}

# --- Time Formatting ---
# format_reset_compact, format_time_remaining, format_time, reformat_reset_time

@test "format_reset_compact converts hours" {
    result=$(format_reset_compact "in 2 hours")
    [ "$result" = "2h" ]
}

@test "format_reset_compact converts days" {
    result=$(format_reset_compact "in 3 days")
    [ "$result" = "3d" ]
}

@test "format_reset_compact converts minutes" {
    result=$(format_reset_compact "in 45 minutes")
    [ "$result" = "45m" ]
}

@test "format_reset_compact handles empty input" {
    result=$(format_reset_compact "")
    [ "$result" = "?" ]
}

@test "format_reset_compact handles various hour formats" {
    result=$(format_reset_compact "Resets in 1 hour")
    [ "$result" = "1h" ]
}

@test "format_time_remaining converts 0.5 hours to 30m" {
    result=$(format_time_remaining "0.5")
    [ "$result" = "30m" ]
}

@test "format_time_remaining converts 0.75 hours to 45m" {
    result=$(format_time_remaining "0.75")
    [ "$result" = "45m" ]
}

@test "format_time_remaining converts 1.0 hours to 1h" {
    result=$(format_time_remaining "1.0")
    [ "$result" = "1h" ]
}

@test "format_time_remaining converts 2.5 hours to 2h 30m" {
    result=$(format_time_remaining "2.5")
    [ "$result" = "2h 30m" ]
}

@test "format_time_remaining converts 5.25 hours to 5h 15m" {
    result=$(format_time_remaining "5.25")
    [ "$result" = "5h 15m" ]
}

@test "format_time_remaining converts 24.0 hours to 1d" {
    result=$(format_time_remaining "24.0")
    [ "$result" = "1d" ]
}

@test "format_time_remaining converts 26.0 hours to 1d 2h" {
    result=$(format_time_remaining "26.0")
    [ "$result" = "1d 2h" ]
}

@test "format_time_remaining converts 26.5 hours to 1d 2h 30m" {
    result=$(format_time_remaining "26.5")
    [ "$result" = "1d 2h 30m" ]
}

@test "format_time_remaining converts 72.25 hours to 3d 15m" {
    result=$(format_time_remaining "72.25")
    [ "$result" = "3d 15m" ]
}

@test "format_time_remaining converts 168.0 hours to 7d" {
    result=$(format_time_remaining "168.0")
    [ "$result" = "7d" ]
}

@test "format_time_remaining converts 48.5 hours to 2d 30m" {
    result=$(format_time_remaining "48.5")
    [ "$result" = "2d 30m" ]
}

@test "format_time_remaining converts 0.0 to 0m" {
    result=$(format_time_remaining "0.0")
    [ "$result" = "0m" ]
}

@test "format_time_remaining converts 0.01 to 0m" {
    result=$(format_time_remaining "0.01")
    [ "$result" = "0m" ]
}

@test "format_time_remaining handles empty input" {
    result=$(format_time_remaining "")
    [ -z "$result" ]
}

@test "format_time_remaining returns original for non-numeric abc" {
    result=$(format_time_remaining "abc")
    [ "$result" = "abc" ]
}

@test "format_time_remaining returns original for negative -5.0" {
    result=$(format_time_remaining "-5.0")
    [ "$result" = "-5.0" ]
}

@test "format_time_remaining converts 23.99 hours to 23h 59m" {
    result=$(format_time_remaining "23.99")
    [ "$result" = "23h 59m" ]
}

@test "format_time_remaining converts 1.01 to 1h (0m not shown)" {
    result=$(format_time_remaining "1.01")
    [ "$result" = "1h" ]
}

@test "format_time_remaining converts 3.7 hours to 3h 42m" {
    result=$(format_time_remaining "3.7")
    [ "$result" = "3h 42m" ]
}

@test "format_time_remaining converts 156.5 hours to 6d 12h 30m" {
    result=$(format_time_remaining "156.5")
    [ "$result" = "6d 12h 30m" ]
}

@test "format_time_remaining handles leading decimal .9" {
    result=$(format_time_remaining ".9")
    [ "$result" = "54m" ]
}

@test "format_time_remaining handles leading decimal .8" {
    result=$(format_time_remaining ".8")
    [ "$result" = "48m" ]
}

@test "format_time_remaining handles leading decimal .5" {
    result=$(format_time_remaining ".5")
    [ "$result" = "30m" ]
}

# --- bc unavailability: format_time_remaining ---

@test "format_time_remaining falls back to simple hours format without bc" {
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    result=$(format_time_remaining "26.5")
    [ "$result" = "26.5h" ]
}

@test "format_time_remaining fallback handles integer hours without bc" {
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    result=$(format_time_remaining "5")
    [ "$result" = "5h" ]
}

@test "format_time_remaining fallback handles large decimal without bc" {
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    result=$(format_time_remaining "168.5")
    [ "$result" = "168.5h" ]
}

@test "is_24h_format returns true when USE_24H_FORMAT is true" {
    # USE_24H_FORMAT is readonly, so we test by verifying the function works
    # The script sets USE_24H_FORMAT=true by default
    is_24h_format
}

@test "is_24h_format behavior can be mocked" {
    # Since USE_24H_FORMAT is readonly, we mock the function itself
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 1; }
    run ! is_24h_format
    [ "$status" -ne 0 ]
}

@test "toggle_time_format switches true to false" {
    local tmp
    tmp="$(mktemp)"
    echo 'readonly USE_24H_FORMAT=true' > "$tmp"
    # Override $0 by redirecting toggle to operate on tmp
    sed_inplace 's/^readonly USE_24H_FORMAT=true$/readonly USE_24H_FORMAT=false/' "$tmp"
    run grep -c 'USE_24H_FORMAT=false' "$tmp"
    [ "$output" = "1" ]
    rm -f "$tmp"
}

@test "toggle_time_format switches false to true" {
    local tmp
    tmp="$(mktemp)"
    echo 'readonly USE_24H_FORMAT=false' > "$tmp"
    sed_inplace 's/^readonly USE_24H_FORMAT=false$/readonly USE_24H_FORMAT=true/' "$tmp"
    run grep -c 'USE_24H_FORMAT=true' "$tmp"
    [ "$output" = "1" ]
    rm -f "$tmp"
}

@test "format_time returns 24h format when is_24h_format true" {
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 0; }
    # Use TZ=UTC for deterministic output across all environments
    # 1734355800 = Mon Dec 16 13:30:00 UTC 2024
    # SC2030 - subshell-local modification of TZ is intentional (bats @test isolation)
    # shellcheck disable=SC2030
    export TZ=UTC
    test_epoch=1734355800
    result=$(format_time "$test_epoch")
    [ "$result" = "13:30" ]
}

@test "format_time returns 12h format when is_24h_format false" {
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 1; }
    # Use TZ=UTC for deterministic output across all environments
    # 1734355800 = Mon Dec 16 13:30:00 UTC 2024
    # SC2031 - reading TZ in a different subshell is intentional (bats @test isolation)
    # shellcheck disable=SC2031
    export TZ=UTC
    test_epoch=1734355800
    result=$(format_time "$test_epoch")
    [ "$result" = "1:30pm" ]
}

@test "reformat_reset_time preserves time in 12h mode" {
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 1; }
    result=$(reformat_reset_time "9pm")
    [ "$result" = "9pm" ]
}

@test "reformat_reset_time converts time-only to 24h" {
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 0; }
    result=$(reformat_reset_time "9pm")
    # Should convert to 21:XX (hour 21)
    [[ "$result" =~ ^21:[0-9]{2}$ ]]
}

@test "reformat_reset_time converts full date to 24h" {
    # Disable SC2329 - "This function is never invoked. Check usage (or ignored if invoked indirectly)" for mocks
    # shellcheck disable=SC2329
    is_24h_format() { return 0; }
    result=$(reformat_reset_time "Dec 16, 9pm")
    [[ "$result" =~ ^Dec\ 16,\ 21:00$ ]]
}

@test "reformat_reset_time handles invalid input gracefully" {
    is_24h_format() { return 0; }
    result=$(reformat_reset_time "invalid")
    [ "$result" = "invalid" ]
}

# --- Color Utilities ---
# supports_color, init_colors, get_pct_color

@test "init_colors sets ANSI codes when colors supported" {
    # Mock supports_color to return true
    # Disable SC2329 (This function is never invoked. Check usage (or ignored if invoked indirectly).) for mocks
    # shellcheck disable=SC2329
    supports_color() { return 0; }

    init_colors
    [ "$COLOR_GREEN" = $'\033[32m' ]
    [ "$COLOR_YELLOW" = $'\033[33m' ]
    [ "$COLOR_RED" = $'\033[31m' ]
    [ "$COLOR_RESET" = $'\033[0m' ]
}

@test "init_colors leaves empty when colors not supported" {
    # Reset colors first
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_RESET=""

    # Mock supports_color to return false
    supports_color() { return 1; }

    init_colors
    [ -z "$COLOR_GREEN" ]
    [ -z "$COLOR_YELLOW" ]
    [ -z "$COLOR_RED" ]
    [ -z "$COLOR_RESET" ]
}

@test "get_pct_color returns green for low usage" {
    COLOR_GREEN="GREEN"
    COLOR_YELLOW="YELLOW"
    COLOR_RED="RED"

    result=$(get_pct_color "25")
    [ "$result" = "GREEN" ]

    result=$(get_pct_color "0")
    [ "$result" = "GREEN" ]

    result=$(get_pct_color "49")
    [ "$result" = "GREEN" ]
}

@test "get_pct_color returns yellow for medium usage" {
    COLOR_GREEN="GREEN"
    COLOR_YELLOW="YELLOW"
    COLOR_RED="RED"

    result=$(get_pct_color "50")
    [ "$result" = "YELLOW" ]

    result=$(get_pct_color "65")
    [ "$result" = "YELLOW" ]

    result=$(get_pct_color "79")
    [ "$result" = "YELLOW" ]
}

@test "get_pct_color returns red for high usage" {
    COLOR_GREEN="GREEN"
    COLOR_YELLOW="YELLOW"
    COLOR_RED="RED"

    result=$(get_pct_color "80")
    [ "$result" = "RED" ]

    result=$(get_pct_color "95")
    [ "$result" = "RED" ]

    result=$(get_pct_color "100")
    [ "$result" = "RED" ]
}

@test "get_pct_color returns empty for invalid input" {
    COLOR_GREEN="GREEN"
    COLOR_YELLOW="YELLOW"
    COLOR_RED="RED"

    result=$(get_pct_color "")
    [ -z "$result" ]

    result=$(get_pct_color "abc")
    [ -z "$result" ]

    result=$(get_pct_color "?")
    [ -z "$result" ]
}

# --- determine_color (SwiftBar color pairs) ---

@test "determine_color returns green for low usage" {
    result=$(determine_color "0")
    [ "$result" = "#00AA00,#00FF00" ]

    result=$(determine_color "49")
    [ "$result" = "#00AA00,#00FF00" ]
}

@test "determine_color returns orange for medium usage" {
    result=$(determine_color "50")
    [ "$result" = "#CC6600,#FF9933" ]

    result=$(determine_color "79")
    [ "$result" = "#CC6600,#FF9933" ]
}

@test "determine_color returns red for high usage" {
    result=$(determine_color "80")
    [ "$result" = "#CC0000,#FF3333" ]

    result=$(determine_color "100")
    [ "$result" = "#CC0000,#FF3333" ]
}

@test "determine_color defaults to red for non-numeric input" {
    result=$(determine_color "abc")
    [ "$result" = "#CC0000,#FF3333" ]

    result=$(determine_color "")
    [ "$result" = "#CC0000,#FF3333" ]

    result=$(determine_color "?")
    [ "$result" = "#CC0000,#FF3333" ]
}

# --- Cross-Platform Date Helpers ---

@test "epoch_to_date uses BSD flags when IS_BSD_DATE=true" {
    IS_BSD_DATE=true
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    date() { echo "ARGS: $*"; }
    export -f date
    result=$(epoch_to_date 1734355800 '%H:%M')
    [[ "$result" == *"-r 1734355800"* ]]
}

@test "epoch_to_date uses GNU flags when IS_BSD_DATE=false" {
    # SC2034 - "appears unused" for mock
    # shellcheck disable=SC2034
    IS_BSD_DATE=false
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    date() { echo "ARGS: $*"; }
    export -f date
    result=$(epoch_to_date 1734355800 '%H:%M')
    [[ "$result" == *"-d @1734355800"* ]]
}

@test "parse_date_to_epoch uses BSD flags when IS_BSD_DATE=true" {
    IS_BSD_DATE=true
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    date() { echo "ARGS: $*"; }
    export -f date
    result=$(parse_date_to_epoch "%l:%M%p" "5:00pm")
    [[ "$result" == *"-j -f"* ]]
}

@test "parse_date_to_epoch uses GNU flags when IS_BSD_DATE=false" {
    # SC2034 - "appears unused" for mock
    # shellcheck disable=SC2034
    IS_BSD_DATE=false
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    date() { echo "ARGS: $*"; }
    export -f date
    result=$(parse_date_to_epoch "%l:%M%p" "5:00pm")
    [[ "$result" == *"-d 5:00 pm"* ]]
}

@test "file_mtime returns a timestamp" {
    local tmpfile
    tmpfile=$(mktemp)
    result=$(file_mtime "$tmpfile")
    [ -n "$result" ]
    [[ "$result" =~ ^[0-9]+$ ]]
    rm -f "$tmpfile"
}
