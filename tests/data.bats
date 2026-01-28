#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Data layer tests: caching, locking, burn rate, error handling
# Run with: bats tests/data.bats

load 'helpers'

# --- Burn Rate & Projection ---
# calculate_slope_averaged_burn_rate, calculate_burn_rate_projection

@test "calculate_slope_averaged_burn_rate succeeds with sufficient data" {
    # Create temporary history file with test data
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,10,5
1000003600,15,6
1000007200,22,7
1000010800,32,9
1000014400,45,11
EOF

    calculate_slope_averaged_burn_rate
    [ -n "$historical_burn_rate" ]
    rm -f "$HISTORY_FILE"
}

@test "calculate_slope_averaged_burn_rate returns reasonable rate" {
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,10,5
1000003600,15,6
1000007200,22,7
1000010800,32,9
1000014400,45,11
EOF

    calculate_slope_averaged_burn_rate
    # Burn rate should be positive and less than 50%/hour
    [ "$(echo "$historical_burn_rate > 0" | bc)" -eq 1 ]
    [ "$(echo "$historical_burn_rate < 50" | bc)" -eq 1 ]
    rm -f "$HISTORY_FILE"
}

@test "calculate_slope_averaged_burn_rate fails with insufficient data" {
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,10,5
EOF

    run ! calculate_slope_averaged_burn_rate
    [ "$status" -ne 0 ]
    rm -f "$HISTORY_FILE"
}

@test "calculate_burn_rate_projection shows exhaustion format and returns warning status" {
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,20,10
1000003600,25,11
1000007200,30,12
1000010800,37,13
1000014400,42,14
EOF

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    # Capture exit code - function returns 1 for exhaustion warning
    calculate_burn_rate_projection "$mock_capture" "42" && exit_code=0 || exit_code=$?
    [ "$exit_code" -eq 1 ]
    [[ "$burn_rate_message" =~ Exhausted\ in ]]
    rm -f "$HISTORY_FILE"
}

@test "calculate_burn_rate_projection no message and returns 0 for zero burn rate" {
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,42,10
1000003600,42,10
1000007200,42,10
1000010800,42,10
1000014400,42,10
EOF

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    calculate_burn_rate_projection "$mock_capture" "42"
    exit_code=$?
    [ "$exit_code" -eq 0 ]
    [ -z "$burn_rate_message" ]
    rm -f "$HISTORY_FILE"
}

@test "calculate_burn_rate_projection no message at 100% usage" {
    mock_capture="Current session: 100% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    calculate_burn_rate_projection "$mock_capture" "100"
    [ -z "$burn_rate_message" ]
}

@test "calculate_burn_rate_projection no message over 100% usage" {
    mock_capture="Current session: 105% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    calculate_burn_rate_projection "$mock_capture" "105"
    [ -z "$burn_rate_message" ]
}

# --- bc unavailability: burn rate & projection ---

@test "calculate_burn_rate_projection returns 0 and no message without bc" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    burn_rate_message="should be cleared"

    calculate_burn_rate_projection "$mock_capture" "42"
    exit_code=$?

    [ "$exit_code" -eq 0 ]
    [ -z "$burn_rate_message" ]
}

@test "session_hours_remaining uses integer fallback without bc" {
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    session_hours_remaining=""
    calculate_burn_rate_projection "$mock_capture" "42"

    # Should have integer.0 format (fallback uses ${hours_until_reset}.0)
    [[ "$session_hours_remaining" =~ ^[0-9]+\.0$ ]]
}

@test "calculate_week_hours_remaining leaves value empty without bc" {
    command() {
        if [[ "$1" == "-v" ]] && [[ "$2" == "bc" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    week_hours_remaining="should be cleared"
    calculate_week_hours_remaining "$mock_capture"

    # Without bc, week_hours_remaining should be empty
    [ -z "$week_hours_remaining" ]
}

@test "calculate_slope_averaged_burn_rate fails gracefully without bc" {
    # Create history data that would normally calculate a burn rate
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,10,5
1000003600,15,6
1000007200,22,7
1000010800,32,9
1000014400,45,11
EOF

    # Override bc to produce no output (simulating unavailable/broken bc)
    bc() { :; }

    # Should fail because bc calls return empty results
    run ! calculate_slope_averaged_burn_rate
    [ "$status" -ne 0 ]
    [ -z "$historical_burn_rate" ]

    rm -f "$HISTORY_FILE"
}

# --- revalidate_burn_rate_message ---

@test "revalidate_burn_rate_message clamps past exhaustion to <1m" {
    # Simulate cached data where exhaustion_epoch is in the past
    exhaustion_epoch=$(($(date +%s) - 120))  # 2 minutes ago
    burn_rate_message="⚠️ Exhausted in 3m (14:33)"
    SESSION_NUM="85"

    revalidate_burn_rate_message

    [[ "$burn_rate_message" == *"<1m"* ]]
    # Should NOT contain the old stale time
    [[ "$burn_rate_message" != *"14:33"* ]]
}

@test "revalidate_burn_rate_message re-derives future duration" {
    # Simulate cached data where exhaustion_epoch is 30 minutes in the future
    exhaustion_epoch=$(($(date +%s) + 1800))  # 30 min from now
    burn_rate_message="⚠️ Exhausted in 1h 30m (16:00)"  # Stale duration
    SESSION_NUM="60"

    revalidate_burn_rate_message

    [[ "$burn_rate_message" =~ Exhausted\ in\ 30m ]]
}

@test "revalidate_burn_rate_message no-op when no exhaustion data" {
    exhaustion_epoch=""
    burn_rate_message=""
    SESSION_NUM="50"

    revalidate_burn_rate_message

    [ -z "$burn_rate_message" ]
}

@test "revalidate_burn_rate_message clears message at 100% usage" {
    exhaustion_epoch=$(($(date +%s) - 60))
    burn_rate_message="⚠️ Exhausted in 0m (14:33)"
    SESSION_NUM="100"

    revalidate_burn_rate_message

    [ -z "$burn_rate_message" ]
}

@test "revalidate_burn_rate_message preserves message when epoch is in future" {
    exhaustion_epoch=$(($(date +%s) + 7200))  # 2 hours from now
    burn_rate_message="⚠️ Exhausted in 2h (18:00)"
    SESSION_NUM="40"

    revalidate_burn_rate_message

    [[ "$burn_rate_message" =~ Exhausted\ in ]]
    # Duration should be approximately 2h (re-derived from epoch)
    [[ "$burn_rate_message" =~ 1h\ 5[0-9]m|2h ]]
}

# SC2030 - subshell-local assignment is intentional (bats test)
# shellcheck disable=SC2030
@test "revalidate_burn_rate_message no-op when burn_rate_message is empty" {
    exhaustion_epoch=$(($(date +%s) + 3600))
    burn_rate_message=""
    SESSION_NUM="50"

    revalidate_burn_rate_message

    [ -z "$burn_rate_message" ]
}

@test "calculate_burn_rate_projection sets exhaustion_epoch as global" {
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,20,10
1000003600,25,11
1000007200,30,12
1000010800,37,13
1000014400,42,14
EOF

    mock_capture="Current session: 42% of messages
  Resets 11:59pm (in 8 hours)
Current week: 50% of messages
  Resets Dec 16, 8:59pm (in 24 hours)"

    exhaustion_epoch=""
    calculate_burn_rate_projection "$mock_capture" "42" || true

    # exhaustion_epoch should be set (non-empty, numeric, in the future)
    [ -n "$exhaustion_epoch" ]
    [[ "$exhaustion_epoch" =~ ^[0-9]+$ ]]
    [ "$exhaustion_epoch" -gt "$(date +%s)" ]

    rm -f "$HISTORY_FILE"
}

# --- Cache Path (_RUNTIME_DIR) ---
# Verify CACHE_FILE uses XDG_RUNTIME_DIR, TMPDIR, or /tmp fallback

@test "CACHE_FILE uses XDG_RUNTIME_DIR when set" {
    local result
    result=$(env -i HOME="$HOME" USER="$USER" PATH="$PATH" XDG_RUNTIME_DIR="/run/user/1000" \
        bash -c "source '$PROJECT_DIR/claude-usage.sh' --source-only && echo \"\$CACHE_FILE\"")
    [[ "$result" == "/run/user/1000/claude-usage-monitor-cache-$USER.txt" ]]
}

@test "CACHE_FILE uses TMPDIR when XDG_RUNTIME_DIR unset" {
    local result
    result=$(env -i HOME="$HOME" USER="$USER" PATH="$PATH" TMPDIR="/private/tmp/user" \
        bash -c "source '$PROJECT_DIR/claude-usage.sh' --source-only && echo \"\$CACHE_FILE\"")
    [[ "$result" == "/private/tmp/user/claude-usage-monitor-cache-$USER.txt" ]]
}

@test "CACHE_FILE falls back to /tmp when both unset" {
    local result
    result=$(env -i HOME="$HOME" USER="$USER" PATH="$PATH" \
        bash -c "source '$PROJECT_DIR/claude-usage.sh' --source-only && echo \"\$CACHE_FILE\"")
    [[ "$result" == "/tmp/claude-usage-monitor-cache-$USER.txt" ]]
}

@test "XDG_RUNTIME_DIR takes priority over TMPDIR" {
    local result
    result=$(env -i HOME="$HOME" USER="$USER" PATH="$PATH" \
        XDG_RUNTIME_DIR="/run/user/1000" TMPDIR="/private/tmp/user" \
        bash -c "source '$PROJECT_DIR/claude-usage.sh' --source-only && echo \"\$CACHE_FILE\"")
    [[ "$result" == "/run/user/1000/claude-usage-monitor-cache-$USER.txt" ]]
}

# --- Data Layer ---
# Locking, caching, get_usage_data, try_load_cache, maybe_trigger_background_refresh

@test "acquire_lock succeeds when no lock exists" {
    rm -rf "$LOCK_DIR"
    acquire_lock
    [ -d "$LOCK_DIR" ]
    release_lock
}

@test "acquire_lock fails when lock held by live process" {
    rm -rf "$LOCK_DIR"
    acquire_lock
    # Second attempt should fail (same process, but lock already held)
    run ! acquire_lock
    [ "$status" -ne 0 ]
    release_lock
}

@test "stale lock cleaned up when PID not running" {
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo "99999" > "$LOCK_DIR/pid"  # Non-existent PID
    acquire_lock
    release_lock
}

@test "stale lock cleaned up after timeout" {
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"  # Our PID (live)
    touch -t 202001010000 "$LOCK_DIR"  # Very old timestamp
    acquire_lock
    release_lock
}

@test "acquire_lock fails after max recursion depth" {
    rm -rf "$LOCK_DIR"
    # Mock mkdir to always fail (simulating persistent permission issue)
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    mkdir() { return 1; }

    run ! acquire_lock
    [ "$status" -ne 0 ]

    unset -f mkdir
    rm -rf "$LOCK_DIR"
}

@test "is_refresh_running returns true when lock held" {
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"
    is_refresh_running
    rm -rf "$LOCK_DIR"
}

@test "is_refresh_running returns false when no lock" {
    rm -rf "$LOCK_DIR"
    run ! is_refresh_running
    [ "$status" -ne 0 ]
}

@test "get_usage_data returns cached data and sets data_state ok" {
    rm -rf "$LOCK_DIR"
    rm -f "$CACHE_FILE"

    # Create valid cache
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="10"
SESSION_RESET="in 2 hours"
WEEK_RESET="in 3 days"
EOF
    touch "$CACHE_FILE"

    # Mock background refresh to avoid spawning
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2329
    maybe_trigger_background_refresh() { :; }

    get_usage_data
    # SC2154 - "not assigned" set by tested function
    # shellcheck disable=SC2154
    [ "$data_state" = "ok" ]
    # SC2031 - set by get_usage_data via source (bats test)
    # shellcheck disable=SC2031
    [ "$SESSION_NUM" = "25" ]

    rm -f "$CACHE_FILE"
}

@test "get_usage_data sets data_state loading when no cache and refresh running" {
    rm -rf "$LOCK_DIR"
    rm -f "$CACHE_FILE"

    # Simulate refresh in progress
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    # Mock background refresh to avoid spawning
    maybe_trigger_background_refresh() { :; }

    # Function returns 1 when no cache - capture exit code
    get_usage_data || true
    [ "$data_state" = "loading" ]

    rm -rf "$LOCK_DIR"
}

@test "try_load_cache rejects cache not owned by current user" {
    rm -f "$CACHE_FILE"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="10"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # Mock stat to return a different UID (simulating foreign-owned file)
    # SC2317 - "unreachable" for mock
    # SC2329 - "unused function" for mock
    # shellcheck disable=SC2317,SC2329
    stat() { echo "99999"; }

    run ! try_load_cache
    [ "$status" -ne 0 ]

    unset -f stat
    rm -f "$CACHE_FILE"
}

@test "try_load_cache sets cache_is_fresh true for fresh cache" {
    rm -f "$CACHE_FILE"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
EOF
    touch "$CACHE_FILE"  # Fresh timestamp

    try_load_cache
    # SC2154 - "not assigned" set by tested function
    # shellcheck disable=SC2154
    [ "$cache_is_fresh" = "true" ]

    rm -f "$CACHE_FILE"
}

@test "try_load_cache sets cache_is_fresh false for stale cache" {
    rm -f "$CACHE_FILE"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
EOF
    touch -t 202001010000 "$CACHE_FILE"  # Very old timestamp

    try_load_cache
    [ "$cache_is_fresh" = "false" ]

    rm -f "$CACHE_FILE"
}

@test "maybe_trigger_background_refresh skips when lock held" {
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    # Override nohup to track calls
    spawned=false
    nohup() { spawned=true; }

    maybe_trigger_background_refresh
    [ "$spawned" = "false" ]

    rm -rf "$LOCK_DIR"
}

# --- fetch_usage_data sequence tests ---

@test "fetch_usage_data calls /context before /usage (workaround for stuck /usage)" {
    # This test verifies the /context workaround is in place.
    # /usage can get stuck after session reset; /context resolves this.

    # Check that /context appears before /usage in the fetch_usage_data function
    local func_body
    func_body=$(sed -n '/^fetch_usage_data()/,/^}/p' "$PROJECT_DIR/claude-usage.sh")

    local context_line usage_line
    context_line=$(echo "$func_body" | grep -n '"/context"' | head -1 | cut -d: -f1)
    usage_line=$(echo "$func_body" | grep -n '"/usage"' | head -1 | cut -d: -f1)

    # /context must come before /usage
    [ -n "$context_line" ]  # /context call exists
    [ -n "$usage_line" ]    # /usage call exists
    [ "$context_line" -lt "$usage_line" ]  # /context comes first
}

@test "fetch_usage_data has comment explaining /context workaround" {
    # Ensure the workaround is documented in the code
    grep -q "stuck" "$PROJECT_DIR/claude-usage.sh"
}

@test "fetch_usage_data validates parsed data requires both percentages" {
    # Verify the validation checks for percentage data (not reset times)
    local func_body
    func_body=$(sed -n '/^fetch_usage_data()/,/^}/p' "$PROJECT_DIR/claude-usage.sh")

    # Should check for empty SESSION_NUM or WEEK_NUM (require both)
    echo "$func_body" | grep -q 'SESSION_NUM.*WEEK_NUM'
    echo "$func_body" | grep -q 'FETCH_ERROR='
    echo "$func_body" | grep -q 'return 1'
}

@test "fetch_usage_data sets specific FETCH_ERROR before each return 1" {
    local func_body
    func_body=$(sed -n '/^fetch_usage_data()/,/^}/p' "$PROJECT_DIR/claude-usage.sh")

    # Every return 1 should be preceded by a FETCH_ERROR assignment
    local return_count fetch_error_count
    return_count=$(echo "$func_body" | grep -c 'return 1')
    fetch_error_count=$(echo "$func_body" | grep -c 'FETCH_ERROR=')
    [ "$fetch_error_count" -ge "$return_count" ]
}

@test "refresh-cache handler uses FETCH_ERROR not hardcoded message" {
    # Verify the handler passes FETCH_ERROR variable, not a string literal
    local handler
    handler=$(sed -n '/--refresh-cache/,/^fi$/p' "$PROJECT_DIR/claude-usage.sh")

    echo "$handler" | grep -q 'save_error_cache.*FETCH_ERROR'
    # Should NOT have the old hardcoded message
    local has_old_msg=false
    echo "$handler" | grep -q '"Claude CLI not available"' && has_old_msg=true
    [ "$has_old_msg" = "false" ]
}

# --- Error State Caching ---

@test "save_error_cache creates cache with error message" {
    rm -f "$CACHE_FILE"

    save_error_cache "Test error message"

    [ -f "$CACHE_FILE" ]
    # SC1090 - "non-constant source" file created by test
    # shellcheck disable=SC1090
    source "$CACHE_FILE"
    [ "$FETCH_ERROR" = "Test error message" ]
    # SC2031 - set by source above (bats test)
    # shellcheck disable=SC2031
    [ -z "$SESSION_NUM" ]

    rm -f "$CACHE_FILE"
}

@test "try_load_cache loads FETCH_ERROR from cache" {
    rm -f "$CACHE_FILE"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"

    try_load_cache
    [ "$FETCH_ERROR" = "Claude CLI not available" ]

    rm -f "$CACHE_FILE"
}

@test "format_swiftbar shows warning when FETCH_ERROR set" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
WEEK_NUM=""
SESSION_RESET=""
WEEK_RESET=""
burn_rate_message=""
session_hours_remaining=""
week_hours_remaining=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"

    result=$(format_swiftbar)
    [[ "$result" == *"⚠️"* ]]
    [[ "$result" == *"Claude CLI not available"* ]]

    rm -f "$CACHE_FILE"
}

@test "format_claude shows error when FETCH_ERROR set" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
WEEK_NUM=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"

    result=$(echo '{"model":{"display_name":"Opus"}}' | format_claude)
    [[ "$result" == *"Error"* ]]
    [[ "$result" == *"Claude CLI not available"* ]]

    rm -f "$CACHE_FILE"
}

@test "format_templated shows warning when FETCH_ERROR set" {
    rm -f "$CACHE_FILE"
    rm -rf "$LOCK_DIR"

    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
WEEK_NUM=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"

    result=$(format_templated "test")
    [[ "$result" == *"⚠️"* ]]

    rm -f "$CACHE_FILE"
}

# SC2030 - subshell-local assignment is intentional (bats test)
# SC2034 - "appears unused" for mock
# shellcheck disable=SC2030,SC2034
@test "save_cache clears FETCH_ERROR" {
    FETCH_ERROR="old error"
    SESSION_NUM="50"
    WEEK_NUM="25"
    SESSION_RESET="5pm"
    WEEK_RESET="Dec 20"
    burn_rate_message=""
    session_hours_remaining=""
    week_hours_remaining=""

    save_cache

    # SC1090 - "non-constant source" file created by test
    # shellcheck disable=SC1090
    source "$CACHE_FILE"
    [ -z "$FETCH_ERROR" ]
    [ "$SESSION_NUM" = "50" ]

    rm -f "$CACHE_FILE"
}

# --- has_valid_recent_cache ---

@test "has_valid_recent_cache returns true for fresh cache with data" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="25"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    has_valid_recent_cache

    rm -f "$CACHE_FILE"
}

@test "has_valid_recent_cache returns false for error-only cache" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
WEEK_NUM=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"

    run ! has_valid_recent_cache
    [ "$status" -ne 0 ]

    rm -f "$CACHE_FILE"
}

@test "has_valid_recent_cache returns false for very old cache" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="25"
FETCH_ERROR=""
EOF
    touch -t 202001010000 "$CACHE_FILE"

    run ! has_valid_recent_cache
    [ "$status" -ne 0 ]

    rm -f "$CACHE_FILE"
}

@test "has_valid_recent_cache returns false when no cache exists" {
    rm -f "$CACHE_FILE"

    run ! has_valid_recent_cache
    [ "$status" -ne 0 ]
}

@test "has_valid_recent_cache returns true even when session reset time has passed" {
    rm -f "$CACHE_FILE"
    local past_epoch=$(($(date +%s) - 60))  # 1 minute ago
    cat > "$CACHE_FILE" <<EOF
SESSION_NUM="100"
WEEK_NUM="50"
SESSION_RESET_EPOCH="$past_epoch"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    # Prefers stale data over error states
    has_valid_recent_cache

    rm -f "$CACHE_FILE"
}

@test "has_valid_recent_cache returns true when session reset time is in future" {
    rm -f "$CACHE_FILE"
    local future_epoch=$(($(date +%s) + 3600))  # 1 hour from now
    cat > "$CACHE_FILE" <<EOF
SESSION_NUM="50"
WEEK_NUM="25"
SESSION_RESET_EPOCH="$future_epoch"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    has_valid_recent_cache

    rm -f "$CACHE_FILE"
}

# --- try_load_cache: session reset invalidation ---

@test "try_load_cache marks cache stale when session reset time has passed" {
    rm -f "$CACHE_FILE"
    local past_epoch=$(($(date +%s) - 60))  # 1 minute ago
    cat > "$CACHE_FILE" <<EOF
SESSION_NUM="100"
WEEK_NUM="50"
SESSION_RESET="8pm"
WEEK_RESET="Feb 2 at 6pm"
SESSION_RESET_EPOCH="$past_epoch"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    try_load_cache
    # SC2031 - set by try_load_cache via source (bats subshell is expected)
    # shellcheck disable=SC2031
    [ "$SESSION_NUM" = "100" ]       # Data still loaded
    # SC2154 - set by tested function
    # shellcheck disable=SC2154
    [ "$cache_is_fresh" = "false" ]  # But marked stale

    rm -f "$CACHE_FILE"
}

@test "try_load_cache accepts cache when session reset time is in future" {
    rm -f "$CACHE_FILE"
    local future_epoch=$(($(date +%s) + 3600))  # 1 hour from now
    cat > "$CACHE_FILE" <<EOF
SESSION_NUM="50"
WEEK_NUM="25"
SESSION_RESET="8pm"
WEEK_RESET="Feb 2 at 6pm"
SESSION_RESET_EPOCH="$future_epoch"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    try_load_cache
    # SC2031 - set by try_load_cache via source (bats test)
    # shellcheck disable=SC2031
    [ "$SESSION_NUM" = "50" ]

    rm -f "$CACHE_FILE"
}

@test "try_load_cache marks error cache as stale (never fresh)" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM=""
WEEK_NUM=""
SESSION_RESET=""
WEEK_RESET=""
SESSION_RESET_EPOCH=""
FETCH_ERROR="Claude CLI not available"
EOF
    touch "$CACHE_FILE"  # Just written = within TTL

    try_load_cache
    # Error caches are never fresh - always trigger retry
    [ "$cache_is_fresh" = "false" ]

    rm -f "$CACHE_FILE"
}

@test "try_load_cache accepts cache without SESSION_RESET_EPOCH (backward compat)" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="10"
SESSION_RESET="8pm"
WEEK_RESET="Feb 2 at 6pm"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    try_load_cache
    # SC2031 - set by try_load_cache via source (bats test)
    # shellcheck disable=SC2031
    [ "$SESSION_NUM" = "25" ]

    rm -f "$CACHE_FILE"
}

# --- save_cache includes SESSION_RESET_EPOCH ---

# SC2034 - "appears unused" for mock (variables consumed by save_cache)
# shellcheck disable=SC2034
@test "save_cache includes SESSION_RESET_EPOCH" {
    SESSION_NUM="50"
    WEEK_NUM="25"
    SESSION_RESET="8pm"
    WEEK_RESET="Feb 2 at 6pm"
    SESSION_RESET_EPOCH="1769700000"
    burn_rate_message=""
    session_hours_remaining=""
    week_hours_remaining=""

    save_cache

    grep -q 'SESSION_RESET_EPOCH="1769700000"' "$CACHE_FILE"

    rm -f "$CACHE_FILE"
}

# --- save_cache / try_load_cache: exhaustion_epoch ---

# SC2030 - subshell-local assignment is intentional (bats test)
# SC2034 - "appears unused" for mock (variables consumed by save_cache)
# shellcheck disable=SC2030,SC2034
@test "save_cache includes exhaustion_epoch" {
    SESSION_NUM="50"
    WEEK_NUM="25"
    SESSION_RESET="8pm"
    WEEK_RESET="Feb 2 at 6pm"
    SESSION_RESET_EPOCH="9999999999"
    burn_rate_message="⚠️ Exhausted in 3h (21:00)"
    exhaustion_epoch="1769710800"
    session_hours_remaining="5.0"
    week_hours_remaining="48.0"

    save_cache

    grep -q 'exhaustion_epoch="1769710800"' "$CACHE_FILE"

    rm -f "$CACHE_FILE"
}

@test "try_load_cache loads exhaustion_epoch" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="50"
WEEK_NUM="25"
SESSION_RESET="8pm"
WEEK_RESET="Feb 2 at 6pm"
SESSION_RESET_EPOCH="9999999999"
burn_rate_message="⚠️ Exhausted in 3h (21:00)"
exhaustion_epoch="1769710800"
session_hours_remaining="5.0"
week_hours_remaining="48.0"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    try_load_cache
    # SC2031 - set by try_load_cache via source (bats test)
    # shellcheck disable=SC2031
    [ "$exhaustion_epoch" = "1769710800" ]

    rm -f "$CACHE_FILE"
}

@test "try_load_cache backward compat: no exhaustion_epoch in old cache" {
    rm -f "$CACHE_FILE"
    cat > "$CACHE_FILE" <<'EOF'
SESSION_NUM="25"
WEEK_NUM="10"
SESSION_RESET="8pm"
WEEK_RESET="Feb 2 at 6pm"
SESSION_RESET_EPOCH="9999999999"
burn_rate_message="⚠️ Exhausted in 3h"
session_hours_remaining="5.0"
week_hours_remaining="48.0"
FETCH_ERROR=""
EOF
    touch "$CACHE_FILE"

    try_load_cache
    # SC2031 - set by try_load_cache via source (bats test)
    # shellcheck disable=SC2031
    [ -z "$exhaustion_epoch" ]

    rm -f "$CACHE_FILE"
}

# --- save_usage_history: session reset preservation ---

@test "save_usage_history does not truncate on session reset" {
    rm -f "$HISTORY_FILE"
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,80,40
1000003600,90,41
1000007200,100,42
EOF

    # Session resets: 100% -> 5%
    save_usage_history "1000010800" "5" "43"

    # Should have 4 data rows (not truncated to 1)
    local data_lines
    data_lines=$(($(wc -l < "$HISTORY_FILE") - 1))
    [ "$data_lines" -eq 4 ]

    # Last entry should be the new one
    local last_line
    last_line=$(tail -n 1 "$HISTORY_FILE")
    [[ "$last_line" == "1000010800,5,43" ]]

    rm -f "$HISTORY_FILE"
}

@test "save_usage_history caps at MAX_HISTORY_ENTRIES" {
    rm -f "$HISTORY_FILE"

    # Create history at the cap
    echo "timestamp,session_pct,week_pct" > "$HISTORY_FILE"
    for i in $(seq 1 "$MAX_HISTORY_ENTRIES"); do
        echo "$((1000000000 + i * 60)),$((i % 100)),10" >> "$HISTORY_FILE"
    done

    # Add one more entry (should trigger trim)
    save_usage_history "$((1000000000 + (MAX_HISTORY_ENTRIES + 1) * 60))" "50" "10"

    local after_lines
    after_lines=$(wc -l < "$HISTORY_FILE")
    [ "$after_lines" -le "$((MAX_HISTORY_ENTRIES + 1))" ]

    rm -f "$HISTORY_FILE"
}

# --- calculate_slope_averaged_burn_rate: session-aware ---

@test "calculate_slope_averaged_burn_rate uses only current session data" {
    rm -f "$HISTORY_FILE"

    # History with a reset boundary: old session (80->90->100), then new session (0->5->10)
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,80,40
1000003600,90,41
1000007200,100,42
1000010800,0,43
1000014400,5,44
1000018000,10,45
EOF

    calculate_slope_averaged_burn_rate

    # Burn rate should reflect new session (5%/hour), not old session
    [ -n "$historical_burn_rate" ]
    [ "$(echo "$historical_burn_rate > 0" | bc)" -eq 1 ]
    [ "$(echo "$historical_burn_rate < 15" | bc)" -eq 1 ]

    rm -f "$HISTORY_FILE"
}

@test "calculate_slope_averaged_burn_rate works with no reset in history" {
    rm -f "$HISTORY_FILE"

    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,10,5
1000003600,15,6
1000007200,22,7
1000010800,32,9
1000014400,45,11
EOF

    calculate_slope_averaged_burn_rate
    [ -n "$historical_burn_rate" ]
    [ "$(echo "$historical_burn_rate > 0" | bc)" -eq 1 ]

    rm -f "$HISTORY_FILE"
}

@test "calculate_slope_averaged_burn_rate fails with only 1 entry in current session" {
    rm -f "$HISTORY_FILE"

    # History has old session data + 1 new session entry
    cat > "$HISTORY_FILE" <<'EOF'
timestamp,session_pct,week_pct
1000000000,80,40
1000003600,90,41
1000007200,0,42
EOF

    # Only 1 entry in current session -> insufficient
    run ! calculate_slope_averaged_burn_rate
    [ "$status" -ne 0 ]

    rm -f "$HISTORY_FILE"
}
