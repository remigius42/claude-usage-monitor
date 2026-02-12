#!/usr/bin/env bash

# Claude usage monitor
# Usage: claude-usage.sh -o swiftbar|claude|summary|format="..."
#
# Displays Claude API usage quotas in various status bar formats.
# Requires: claude CLI, tmux, jq (for -o claude)
# Optional: bc (for burn rate calculations)

# <xbar.title>Claude Usage Monitor</xbar.title>
# <xbar.version>v0.1.0</xbar.version>
# <xbar.author>Andreas Remigius Schmidt</xbar.author>
# <swiftbar.schedule>*/1 * * * *</swiftbar.schedule>
#
# SwiftBar v2.0+ specific tags to hide default menu items
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

# Add Claude native installer path (menu bar plugins don't source shell profiles)
export PATH="$HOME/.local/bin:$PATH"

set -euo pipefail

# --- Configuration ---
readonly SESSION_NAME="claude-usage-monitor"
readonly _RUNTIME_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
readonly CACHE_FILE="$_RUNTIME_DIR/claude-usage-monitor-cache-$USER.txt"
readonly CACHE_DURATION=30  # 30 seconds
readonly HISTORY_FILE="/tmp/claude-usage-monitor-history-$USER.csv"
readonly DEBUG_LOG="/tmp/claude-usage-monitor-debug-$USER.log"
readonly BURN_RATE_SAMPLES=10  # Number of recent samples for burn rate calculation
readonly MAX_HISTORY_ENTRIES=120  # Max history rows to retain (~1 hour at 30s)

# Time format preference (modifiable by sed in-place for SwiftBar)
readonly USE_24H_FORMAT=true

# --- Global State ---
OUTPUT_FORMAT=""
OUTPUT_FORMAT_STRING=""

# Parsed usage data (populated by get_usage_data)
SESSION_NUM=""
WEEK_NUM=""
SESSION_RESET=""
WEEK_RESET=""
SESSION_RESET_EPOCH=""

# Color codes (initialized by init_colors)
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_RESET=""

# Burn rate calculation results
historical_burn_rate=""
burn_rate_message=""
exhaustion_epoch=""
session_hours_remaining=""
week_hours_remaining=""
reset_epoch=""

# Cache state
cache_is_fresh=false
data_state=""  # "ok", "loading", or "error"
FETCH_ERROR=""  # Error message if fetch failed

# --- Platform Detection ---
IS_BSD_DATE=false
if date -j -f "%s" 0 +%s >/dev/null 2>&1; then
    IS_BSD_DATE=true
fi

# Cross-platform sed in-place edit (BSD sed requires '' argument, GNU sed does not)
# Usage: sed_inplace 's/pattern/replacement/' FILE
sed_inplace() {
    if [[ "$IS_BSD_DATE" == true ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Convert epoch to formatted date string (cross-platform)
# Usage: epoch_to_date EPOCH FORMAT
epoch_to_date() {
    local epoch="$1"
    local format="$2"
    if [[ "$IS_BSD_DATE" == true ]]; then
        date -r "$epoch" "+$format"
    else
        date -d "@$epoch" "+$format"
    fi
}

# Parse date string to epoch (cross-platform)
# Usage: parse_date_to_epoch FORMAT DATE_STRING
# Returns epoch via stdout, returns 1 on failure
parse_date_to_epoch() {
    local format="$1"
    local date_str="$2"
    if [[ "$IS_BSD_DATE" == true ]]; then
        date -j -f "$format" "$date_str" +%s 2>/dev/null || return 1
    else
        # GNU date -d ignores format parameter; normalize for its parser:
        # - Separate concatenated am/pm: "9pm" -> "9 pm", "8:59pm" -> "8:59 pm"
        # - Remove comma after day number: "Dec 16," -> "Dec 16"
        local gnu_str="$date_str"
        gnu_str=$(echo "$gnu_str" | sed -E 's/([0-9])(am|pm)/\1 \2/g; s/([0-9]+),/\1/')
        date -d "$gnu_str" +%s 2>/dev/null || return 1
    fi
}

# Get file modification time as epoch (cross-platform)
# Usage: file_mtime PATH
file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# --- Locking ---
readonly LOCK_DIR="/tmp/claude-usage-monitor-$USER.lock"
readonly LOCK_TIMEOUT=120  # seconds

# Acquire lock (non-blocking)
# Returns: 0 if lock acquired, 1 if already locked
acquire_lock() {
    local depth="${1:-0}"
    if [[ "$depth" -gt 2 ]]; then
        return 1  # Prevent infinite recursion
    fi

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/pid"
        trap 'release_lock' EXIT INT TERM
        return 0
    fi

    # Check for stale lock
    local lock_pid lock_age
    if [[ -f "$LOCK_DIR/pid" ]]; then
        lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            # Process dead, remove stale lock
            rm -rf "$LOCK_DIR"
            acquire_lock $((depth + 1))
            return $?
        fi

        # Check age-based timeout
        lock_age=$(( $(date +%s) - $(file_mtime "$LOCK_DIR" || echo 0) ))
        if [[ "$lock_age" -gt "$LOCK_TIMEOUT" ]]; then
            rm -rf "$LOCK_DIR"
            acquire_lock $((depth + 1))
            return $?
        fi
    fi

    return 1
}

# Release the lock
release_lock() {
    rm -rf "$LOCK_DIR" 2>/dev/null || true
}

# Check if a background refresh is currently running
is_refresh_running() {
    if [[ -d "$LOCK_DIR" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null
    else
        return 1
    fi
}

# --- Usage / Help ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [-o FORMAT]

Display Claude API usage quotas for various status bars.

Options:
  -o FORMAT   Output format: swiftbar, claude, summary, or format="<string>".
              (auto-detected when running as SwiftBar plugin)
  -h          Show this help message

Format String Placeholders:
  %session_num%            - Session usage percentage (e.g., "25%")
  %week_num%               - Week usage percentage (e.g., "10%")
  %session_reset_time%     - Formatted time of session reset (e.g., "Dec 16, 21:00")
  %session_reset_duration% - Duration until session reset (e.g., "2h 30m")
  %week_reset_time%        - Formatted time of week reset
  %week_reset_duration%    - Duration until week reset
  %last_update%            - Time since last data refresh (e.g., "5m ago")
  %projected_expiration%   - Burn rate projection message (or empty)
  %n%                      - Newline character

Conditional Blocks:
  {?content?}              - Renders content only if it contains no "N/A"
                             and has non-whitespace content

Examples:
  $(basename "$0") -o format="Claude: %session_num% | %week_num%"
  $(basename "$0") -o format="Session: %session_num%%n%Week: %week_num%"
  $(basename "$0") -o format="Usage: %session_num%{? (%projected_expiration%)?}"
EOF
}

usage_and_exit() {
    usage >&2
    exit "${1:-1}"
}

# --- Debug Logging ---

# Check if debug logging is enabled (based on file existence)
is_debug_enabled() {
    [[ -f "$DEBUG_LOG" ]]
}

# Toggle debug logging on/off
toggle_debug_logging() {
    if is_debug_enabled; then
        rm -f "$DEBUG_LOG"
    else
        echo "=== Claude Usage Monitor Debug Log ===" > "$DEBUG_LOG"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$DEBUG_LOG"
        echo "" >> "$DEBUG_LOG"
    fi
}

# Debug logging function
debug_log() {
    if is_debug_enabled; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
    fi
}

# --- Time Format Functions ---

# Check if 24-hour time format is enabled
is_24h_format() {
    [[ "$USE_24H_FORMAT" == "true" ]]
}

# Toggle between 24-hour and 12-hour time format (e.g. for SwiftBar menu)
toggle_time_format() {
    if is_24h_format; then
        sed_inplace 's/^readonly USE_24H_FORMAT=true$/readonly USE_24H_FORMAT=false/' "$0"
    else
        sed_inplace 's/^readonly USE_24H_FORMAT=false$/readonly USE_24H_FORMAT=true/' "$0"
    fi
}

# Format epoch time based on current time format preference
format_time() {
    local epoch="$1"

    if is_24h_format; then
        epoch_to_date "$epoch" '%H:%M'
    elif [[ "$IS_BSD_DATE" == true ]]; then
        # LC_TIME=C: am/pm requires English locale
        LC_TIME=C epoch_to_date "$epoch" '%-I:%M%p' | tr '[:upper:]' '[:lower:]'
    else
        # LC_TIME=C: am/pm requires English locale
        # %P: GNU coreutils >=9.9 errors on %p; %P gives lowercase am/pm
        LC_TIME=C epoch_to_date "$epoch" '%-I:%M%P'
    fi
}

# Reformat reset time string based on time format preference
reformat_reset_time() {
    local reset_str="$1"

    if ! is_24h_format; then
        echo "$reset_str"
        return 0
    fi

    if ! parse_reset_time "$reset_str"; then
        echo "$reset_str"
        return 0
    fi

    if [[ "$reset_str" =~ ^[A-Z][a-z]+[[:space:]][0-9]+ ]]; then
        # LC_TIME=C: month abbreviation must be English to match Claude CLI output
        echo "$(LC_TIME=C epoch_to_date "$reset_epoch" '%b %d'), $(epoch_to_date "$reset_epoch" '%H:%M')"
    else
        epoch_to_date "$reset_epoch" '%H:%M'
    fi
}

# Format time remaining in human-readable format (Xd Yh Zm)
format_time_remaining() {
    local hours_remaining="$1"

    # Validate input - must be a number (handles both "1.5" and ".5" formats)
    if [[ -z "$hours_remaining" ]] || ! echo "$hours_remaining" | grep -qE '^[0-9]*\.?[0-9]+$'; then
        echo "$hours_remaining"
        return 0
    fi

    if ! command -v bc >/dev/null 2>&1; then
        echo "${hours_remaining}h"
        return 0
    fi

    local total_minutes
    total_minutes=$(echo "scale=0; $hours_remaining * 60 / 1" | bc)

    local days=$((total_minutes / 1440))
    local hours=$(((total_minutes % 1440) / 60))
    local minutes=$((total_minutes % 60))

    local result=""

    if [[ "$days" -gt 0 ]]; then
        result="${days}d"
    fi

    if [[ "$hours" -gt 0 ]]; then
        if [[ -n "$result" ]]; then
            result="$result ${hours}h"
        else
            result="${hours}h"
        fi
    fi

    if [[ "$minutes" -gt 0 ]]; then
        if [[ -n "$result" ]]; then
            result="$result ${minutes}m"
        else
            result="${minutes}m"
        fi
    fi

    if [[ -z "$result" ]]; then
        result="0m"
    fi

    echo "$result"
}

# --- Color Support ---

# Check if terminal supports colors
supports_color() {
    command -v tput &>/dev/null && [[ "$(tput colors 2>/dev/null)" -ge 8 ]]
}

# Initialize color codes (empty strings if not supported)
init_colors() {
    if supports_color; then
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_RED=$'\033[31m'
        COLOR_RESET=$'\033[0m'
    fi
}

# Get color based on percentage value (for ANSI output)
get_pct_color() {
    local pct="$1"
    if [[ -z "$pct" ]] || ! [[ "$pct" =~ ^[0-9]+$ ]]; then
        echo ""
    elif [[ "$pct" -lt 50 ]]; then
        echo "$COLOR_GREEN"
    elif [[ "$pct" -lt 80 ]]; then
        echo "$COLOR_YELLOW"
    else
        echo "$COLOR_RED"
    fi
}

# Determine color for SwiftBar (light,dark format)
determine_color() {
    local usage_num="$1"

    if ! [[ "$usage_num" =~ ^[0-9]+$ ]]; then
        echo "#CC0000,#FF3333"
        return
    fi

    if [[ "$usage_num" -lt 50 ]]; then
        echo "#00AA00,#00FF00"
    elif [[ "$usage_num" -lt 80 ]]; then
        echo "#CC6600,#FF9933"
    else
        echo "#CC0000,#FF3333"
    fi
}

# --- Time Parsing ---

# Parse reset time string and convert to epoch seconds
# Sets global variable: reset_epoch
parse_reset_time() {
    local reset_str="$1"
    local now_epoch

    reset_epoch=""
    now_epoch=$(date +%s)

    local has_year=false
    if [[ "$reset_str" =~ [0-9]{4} ]]; then
        has_year=true
    fi

    if [[ "$reset_str" =~ ^[A-Z][a-z]+[[:space:]][0-9]+ ]]; then
        # Full date format: "Dec 16, 9pm" or "Dec 16, 8:59pm"
        if [[ "$has_year" == false ]]; then
            local current_year
            current_year=$(date +%Y)
            reset_str="$reset_str $current_year"
        fi

        reset_epoch=$(parse_date_to_epoch "%b %d, %l:%M%p %Y" "$reset_str") || true
        if [[ -z "$reset_epoch" ]]; then
            local normalized_date="${reset_str}"
            if [[ "$reset_str" =~ [0-9]+pm ]] || [[ "$reset_str" =~ [0-9]+am ]]; then
                normalized_date=$(echo "$reset_str" | sed -E 's/([0-9]+)(pm|am)/\1:00\2/')
            fi
            reset_epoch=$(parse_date_to_epoch "%b %d, %l:%M%p %Y" "$normalized_date") || true
        fi

        if [[ "$has_year" == false ]] && { [[ -z "$reset_epoch" ]] || [[ "$reset_epoch" -lt "$now_epoch" ]]; }; then
            local next_year
            next_year=$((current_year + 1))
            local next_year_str="${reset_str% *} $next_year"

            reset_epoch=$(parse_date_to_epoch "%b %d, %l:%M%p %Y" "$next_year_str") || true
            if [[ -z "$reset_epoch" ]]; then
                local normalized_next_year="${next_year_str}"
                if [[ "$next_year_str" =~ [0-9]+pm ]] || [[ "$next_year_str" =~ [0-9]+am ]]; then
                    normalized_next_year=$(echo "$next_year_str" | sed -E 's/([0-9]+)(pm|am)/\1:00\2/')
                fi
                reset_epoch=$(parse_date_to_epoch "%b %d, %l:%M%p %Y" "$normalized_next_year") || true
            fi
        fi
    else
        # Time-only format: "5pm" or "9:59pm"
        local time_today

        time_today=$(parse_date_to_epoch "%l:%M%p" "$reset_str") || true
        if [[ -z "$time_today" ]]; then
            local normalized_time="${reset_str}"
            if [[ "$reset_str" =~ ^[0-9]+pm$ ]]; then
                normalized_time="${reset_str%pm}:00pm"
            elif [[ "$reset_str" =~ ^[0-9]+am$ ]]; then
                normalized_time="${reset_str%am}:00am"
            fi
            time_today=$(parse_date_to_epoch "%l:%M%p" "$normalized_time") || true
        fi

        if [[ -n "$time_today" ]]; then
            if [[ "$time_today" -gt "$now_epoch" ]]; then
                reset_epoch=$time_today
            else
                reset_epoch=$((time_today + 86400))
            fi
        fi
    fi

    if [[ -z "$reset_epoch" ]]; then
        return 1
    fi

    # Normalize to nearest minute
    reset_epoch=$(( (reset_epoch / 60) * 60 ))
    return 0
}

# --- History & Burn Rate ---

# Save current usage to history file with rolling window (atomic writes)
save_usage_history() {
    local timestamp="$1"
    local session_pct="$2"
    local week_pct="$3"
    local tmp_history="${HISTORY_FILE}.tmp.$$"

    # If no history file exists, create it atomically
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "timestamp,session_pct,week_pct" > "$tmp_history"
        echo "$timestamp,$session_pct,$week_pct" >> "$tmp_history"
        mv "$tmp_history" "$HISTORY_FILE"
        return 0
    fi

    # Check for session reset or too-frequent sampling
    local last_line last_timestamp last_pct
    last_line=$(tail -n 1 "$HISTORY_FILE")
    last_timestamp=$(echo "$last_line" | cut -d',' -f1)
    last_pct=$(echo "$last_line" | cut -d',' -f2)

    if [[ -n "$last_pct" ]] && [[ "$session_pct" -lt "$last_pct" ]]; then
        debug_log "Session reset detected ($last_pct% → $session_pct%)"
    fi

    if [[ -n "$last_timestamp" ]] && [[ "$last_timestamp" =~ ^[0-9]+$ ]]; then
        local time_diff=$((timestamp - last_timestamp))
        if [[ "$time_diff" -lt 30 ]]; then
            debug_log "Skipping save: too soon since last sample (${time_diff}s ago)"
            return 0
        fi
    fi

    # Atomic append via copy + append + mv
    cp "$HISTORY_FILE" "$tmp_history"
    echo "$timestamp,$session_pct,$week_pct" >> "$tmp_history"

    # Trim to max history entries if needed
    local total_lines max_total
    total_lines=$(wc -l < "$tmp_history")
    max_total=$((MAX_HISTORY_ENTRIES + 1))

    if [[ "$total_lines" -gt "$max_total" ]]; then
        local trim_file="${tmp_history}.trim"
        (head -1 "$tmp_history"; tail -n "$MAX_HISTORY_ENTRIES" "$tmp_history") > "$trim_file"
        mv "$trim_file" "$tmp_history"
    fi

    mv "$tmp_history" "$HISTORY_FILE"
}

# Calculate burn rate from historical data using consecutive slope averaging
calculate_slope_averaged_burn_rate() {
    historical_burn_rate=""
    debug_log "--- calculate_slope_averaged_burn_rate START ---"

    if [[ ! -f "$HISTORY_FILE" ]]; then
        debug_log "ERROR: History file not found"
        return 1
    fi

    local total_lines
    total_lines=$(($(wc -l < "$HISTORY_FILE") - 1))
    debug_log "total_lines=$total_lines"

    # Find current session boundary: walk forward, detect where session_pct decreases
    local all_data current_session_start prev_pct_val line_num
    all_data=$(tail -n +2 "$HISTORY_FILE")
    current_session_start=1
    prev_pct_val=""
    line_num=0
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        line_num=$((line_num + 1))
        local this_pct
        this_pct=$(echo "$line" | cut -d',' -f2)
        if [[ -n "$prev_pct_val" ]] && [[ "$this_pct" -lt "$prev_pct_val" ]]; then
            current_session_start=$line_num
        fi
        prev_pct_val=$this_pct
    done <<< "$all_data"

    # Use only current session data
    local session_data session_lines
    session_data=$(echo "$all_data" | tail -n "+$current_session_start")
    session_lines=$(echo "$session_data" | wc -l | tr -d ' ')
    debug_log "current_session_start=$current_session_start, session_lines=$session_lines"

    if [[ "$session_lines" -lt 2 ]]; then
        debug_log "ERROR: Insufficient data in current session (need at least 2 points)"
        return 1
    fi

    local samples_to_use=$BURN_RATE_SAMPLES
    if [[ "$session_lines" -lt "$samples_to_use" ]]; then
        samples_to_use=$session_lines
    fi
    debug_log "Using last $samples_to_use samples for burn rate"

    local samples
    samples=$(echo "$session_data" | tail -n "$samples_to_use" | grep -v '^#')
    debug_log "samples='$samples'"

    local slopes="" prev_line="" slope_count=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^# ]]; then
            continue
        fi

        if [[ -z "$prev_line" ]]; then
            prev_line="$line"
            continue
        fi

        local prev_time prev_pct curr_time curr_pct
        prev_time=$(echo "$prev_line" | cut -d',' -f1)
        prev_pct=$(echo "$prev_line" | cut -d',' -f2)
        curr_time=$(echo "$line" | cut -d',' -f1)
        curr_pct=$(echo "$line" | cut -d',' -f2)

        if [[ -z "$prev_pct" ]] || [[ -z "$curr_pct" ]]; then
            prev_line="$line"
            continue
        fi

        local time_diff=$((curr_time - prev_time))
        if [[ "$time_diff" -le 0 ]]; then
            prev_line="$line"
            continue
        fi

        local hours_diff
        hours_diff=$(echo "scale=4; $time_diff / 3600" | bc 2>/dev/null)
        if [[ -z "$hours_diff" ]]; then
            prev_line="$line"
            continue
        fi

        local pct_diff=$((curr_pct - prev_pct))
        local slope
        slope=$(echo "scale=4; $pct_diff / $hours_diff" | bc 2>/dev/null)

        if [[ -n "$slope" ]]; then
            if [[ -z "$slopes" ]]; then
                slopes="$slope"
            else
                slopes="$slopes $slope"
            fi
            slope_count=$((slope_count + 1))
            debug_log "slope[$slope_count]=$slope (${prev_pct}% → ${curr_pct}% over ${hours_diff}h)"
        fi

        prev_line="$line"
    done <<< "$samples"

    if [[ "$slope_count" -eq 0 ]]; then
        debug_log "ERROR: No valid slopes calculated"
        return 1
    fi

    local sum="0"
    for slope in $slopes; do
        sum=$(echo "scale=4; $sum + $slope" | bc 2>/dev/null)
    done

    historical_burn_rate=$(echo "scale=2; $sum / $slope_count" | bc 2>/dev/null)
    debug_log "historical_burn_rate=$historical_burn_rate (avg of $slope_count slopes)"

    if [[ -z "$historical_burn_rate" ]]; then
        debug_log "ERROR: historical_burn_rate calculation failed"
        return 1
    fi

    debug_log "SUCCESS: historical_burn_rate=$historical_burn_rate %/hour"
    return 0
}

# Calculate burn rate projection
calculate_burn_rate_projection() {
    local capture="$1"
    local current_pct="$2"

    debug_log "=== calculate_burn_rate_projection START ==="
    debug_log "current_pct=$current_pct"

    burn_rate_message=""
    exhaustion_epoch=""
    session_hours_remaining=""

    if [[ "$current_pct" -eq 0 ]]; then
        debug_log "Skipping: current_pct is 0"
        return 0
    fi

    local reset_str
    reset_str=$(echo "$capture" | grep "Current session" -A 2 | grep "Resets" | sed -E 's/.*Resets[: ]+([^(]+).*/\1/' | xargs)
    debug_log "reset_str='$reset_str'"

    if ! parse_reset_time "$reset_str"; then
        debug_log "ERROR: Failed to parse reset time '$reset_str'"
        return 0
    fi
    debug_log "reset_epoch=$reset_epoch"

    local now_epoch seconds_until_reset
    now_epoch=$(date +%s)
    seconds_until_reset=$((reset_epoch - now_epoch))
    debug_log "seconds_until_reset=$seconds_until_reset"

    if [[ "$seconds_until_reset" -le 0 ]]; then
        debug_log "ERROR: seconds_until_reset <= 0"
        return 0
    fi

    local hours_until_reset=$((seconds_until_reset / 3600))
    debug_log "hours_until_reset=$hours_until_reset"

    if command -v bc >/dev/null 2>&1 && [[ -n "$seconds_until_reset" ]] && [[ "$seconds_until_reset" -gt 0 ]]; then
        session_hours_remaining=$(echo "scale=3; $seconds_until_reset / 3600" | bc)
        debug_log "session_hours_remaining (bc)=$session_hours_remaining"
        if [[ -z "$session_hours_remaining" ]]; then
            session_hours_remaining="${hours_until_reset}.0"
            debug_log "session_hours_remaining (fallback)=$session_hours_remaining"
        fi
    else
        session_hours_remaining="${hours_until_reset}.0"
        debug_log "session_hours_remaining (no bc)=$session_hours_remaining"
    fi

    local session_duration=$((24 * 3600))
    local elapsed_seconds=$((session_duration - seconds_until_reset))
    debug_log "elapsed_seconds=$elapsed_seconds"

    if [[ "$elapsed_seconds" -le 0 ]]; then
        debug_log "ERROR: elapsed_seconds <= 0"
        return 0
    fi

    local elapsed_hours=$((elapsed_seconds / 3600))
    debug_log "elapsed_hours=$elapsed_hours"

    if ! command -v bc >/dev/null 2>&1; then
        debug_log "ERROR: bc not found"
        return 0
    fi

    local burn_rate

    if calculate_slope_averaged_burn_rate; then
        burn_rate="$historical_burn_rate"
        debug_log "Using slope-averaged burn_rate=$burn_rate"
    elif [[ "$elapsed_hours" -gt 0 ]]; then
        burn_rate=$(echo "scale=2; $current_pct / $elapsed_hours" | bc 2>/dev/null)
        debug_log "Using linear burn_rate=$burn_rate"
    fi

    if [[ -z "$burn_rate" ]]; then
        debug_log "ERROR: burn_rate is empty"
        return 0
    fi

    if [[ "$(echo "$burn_rate <= 0" | bc)" -eq 1 ]]; then
        debug_log "Skipping projection: burn_rate=$burn_rate (zero or negative)"
        burn_rate_message=""
        exhaustion_epoch=""
        return 0
    fi

    if [[ "$(echo "$current_pct >= 100" | bc)" -eq 1 ]]; then
        debug_log "Skipping projection: current_pct=$current_pct (already at/over limit)"
        burn_rate_message=""
        exhaustion_epoch=""
        return 0
    fi

    local pct_remaining hours_to_exhaustion
    pct_remaining=$(echo "scale=2; 100 - $current_pct" | bc)
    debug_log "pct_remaining=$pct_remaining"

    hours_to_exhaustion=$(echo "scale=1; $pct_remaining / $burn_rate" | bc)
    debug_log "hours_to_exhaustion=$hours_to_exhaustion"

    local seconds_to_exhaustion
    seconds_to_exhaustion=$(echo "$hours_to_exhaustion * 3600" | bc | cut -d. -f1)
    debug_log "seconds_to_exhaustion=$seconds_to_exhaustion"

    exhaustion_epoch=$((now_epoch + seconds_to_exhaustion))

    # Guard: ensure exhaustion is at least 1 minute in the future
    # (prevents rounding to now with bc scale=1)
    if [[ "$exhaustion_epoch" -le "$now_epoch" ]]; then
        exhaustion_epoch=$((now_epoch + 60))
    fi
    debug_log "exhaustion_epoch=$exhaustion_epoch"

    local exhaustion_time formatted_time
    exhaustion_time=$(format_time "$exhaustion_epoch")
    debug_log "exhaustion_time=$exhaustion_time"

    formatted_time=$(format_time_remaining "$hours_to_exhaustion")
    debug_log "formatted_time=$formatted_time"

    burn_rate_message="⚠️ Exhausted in $formatted_time ($exhaustion_time)"
    debug_log "burn_rate_message='$burn_rate_message'"
    return 1
}

# Revalidate burn_rate_message against current time.
# When displaying cached data, the pre-formatted message may reference a time
# that has already passed. This function re-derives the message from the cached
# exhaustion_epoch so the displayed duration and clock time are always accurate.
revalidate_burn_rate_message() {
    # Nothing to revalidate if no exhaustion projection
    if [[ -z "$exhaustion_epoch" ]] || [[ -z "$burn_rate_message" ]]; then
        return 0
    fi

    # If usage hit 100%, the message is irrelevant
    if [[ -n "$SESSION_NUM" ]] && [[ "$SESSION_NUM" -ge 100 ]]; then
        burn_rate_message=""
        return 0
    fi

    local now_epoch
    now_epoch=$(date +%s)

    if [[ "$exhaustion_epoch" -le "$now_epoch" ]]; then
        # Projected exhaustion is in the past, but usage < 100%.
        # Clamp: show "<1m" with the current time.
        local current_time
        current_time=$(format_time "$now_epoch")
        burn_rate_message="⚠️ Exhausted in <1m ($current_time)"
    else
        # Still in the future — re-derive the message from the epoch
        # to get an accurate relative duration.
        local seconds_remaining hours_remaining
        seconds_remaining=$((exhaustion_epoch - now_epoch))

        if command -v bc >/dev/null 2>&1; then
            hours_remaining=$(echo "scale=3; $seconds_remaining / 3600" | bc 2>/dev/null)
        fi
        if [[ -z "$hours_remaining" ]]; then
            hours_remaining="$((seconds_remaining / 3600)).0"
        fi

        local exhaustion_time formatted_time
        exhaustion_time=$(format_time "$exhaustion_epoch")
        formatted_time=$(format_time_remaining "$hours_remaining")
        burn_rate_message="⚠️ Exhausted in $formatted_time ($exhaustion_time)"
    fi
}

# Calculate time remaining until week reset
calculate_week_hours_remaining() {
    local capture="$1"

    debug_log "=== calculate_week_hours_remaining START ==="
    week_hours_remaining=""

    local reset_str
    reset_str=$(echo "$capture" | grep "Current week" -A 2 | grep "Resets" | sed -E 's/.*Resets[: ]+([^(]+).*/\1/' | xargs)
    debug_log "week_reset_str='$reset_str'"

    if ! parse_reset_time "$reset_str"; then
        debug_log "ERROR: Failed to parse week reset time '$reset_str'"
        return 0
    fi
    debug_log "reset_epoch=$reset_epoch"

    local now_epoch seconds_until_reset
    now_epoch=$(date +%s)
    seconds_until_reset=$((reset_epoch - now_epoch))
    debug_log "seconds_until_reset=$seconds_until_reset"

    if [[ "$seconds_until_reset" -le 0 ]]; then
        debug_log "ERROR: seconds_until_reset <= 0"
        return 0
    fi

    if command -v bc >/dev/null 2>&1 && [[ -n "$seconds_until_reset" ]] && [[ "$seconds_until_reset" -gt 0 ]]; then
        week_hours_remaining=$(echo "scale=3; $seconds_until_reset / 3600" | bc)
        debug_log "week_hours_remaining (bc)=$week_hours_remaining"
        if [[ -z "$week_hours_remaining" ]]; then
            debug_log "ERROR: bc failed for week_hours_remaining"
            week_hours_remaining=""
        fi
    else
        debug_log "ERROR: bc not available or invalid seconds_until_reset"
    fi

    debug_log "=== calculate_week_hours_remaining END ==="
    return 0
}

# --- Core Functions ---

clear_session() {
    tmux send-keys -t "$SESSION_NAME" "/clear" Escape 2>/dev/null || true
    sleep 1
    tmux send-keys -t "$SESSION_NAME" Enter 2>/dev/null || true
}

handle_stale_state() {
    local capture
    capture=$(tmux capture-pane -t "$SESSION_NAME" -p -S -20 2>/dev/null) || return 0

    if echo "$capture" | grep -q "How is Claude doing this session"; then
        tmux send-keys -t "$SESSION_NAME" "0" 2>/dev/null
        sleep 0.5
        tmux send-keys -t "$SESSION_NAME" Enter 2>/dev/null
        sleep 2
    fi

    if echo "$capture" | grep -q "Context Usage"; then
        clear_session
        sleep 2
    fi
}

# Parse session percentage from captured output
parse_session_pct() {
    local output="$1"
    echo "$output" | grep -oE '[0-9]+%' | sed -n '1p' | grep -oE '[0-9]+' || true
}

# Parse week percentage from captured output
parse_week_pct() {
    local output="$1"
    echo "$output" | grep -oE '[0-9]+%' | sed -n '2p' | grep -oE '[0-9]+' || true
}

# Parse session reset time from captured output
parse_session_reset() {
    local output="$1"
    echo "$output" | grep "Current session" -A 2 | grep "Resets" | sed -E 's/.*Resets[: ]+([^(]+).*/\1/' | xargs || true
}

# Parse week reset time from captured output
parse_week_reset() {
    local output="$1"
    echo "$output" | grep "Current week" -A 2 | grep "Resets" | sed -E 's/.*Resets[: ]+([^(]+).*/\1/' | xargs || true
}

# Format reset time to compact form (e.g., "in 2 hours" -> "2h")
format_reset_compact() {
    local reset="$1"
    if [[ -z "$reset" ]]; then
        echo "?"
        return
    fi
    local num
    num=$(echo "$reset" | grep -oE '[0-9]+' | head -1)
    if echo "$reset" | grep -qi "hour"; then
        echo "${num}h"
    elif echo "$reset" | grep -qi "day"; then
        echo "${num}d"
    elif echo "$reset" | grep -qi "minute"; then
        echo "${num}m"
    else
        echo "$reset"
    fi
}

# Fetch usage data from Claude CLI via tmux
fetch_usage_data() {
    if ! command -v claude &>/dev/null; then
        FETCH_ERROR="claude command not found"
        return 1
    fi

    if tmux new-session -d -s "$SESSION_NAME" "claude" 2>/dev/null; then
        sleep 10
    fi

    handle_stale_state

    # Workaround: /usage can get stuck after session reset.
    # /context seems to be among the commands which resolves this stuck state.
    if ! tmux send-keys -t "$SESSION_NAME" "/context" Escape 2>/dev/null; then
        FETCH_ERROR="tmux session unavailable"
        return 1
    fi
    sleep 1
    tmux send-keys -t "$SESSION_NAME" Enter 2>/dev/null
    sleep 3  # Wait for /context to register (unstick workaround)
    tmux send-keys -t "$SESSION_NAME" Escape 2>/dev/null  # Dismiss /context
    sleep 1

    # Clear conversation to get clean capture for /usage
    clear_session
    sleep 2  # Wait for /clear to complete

    if ! tmux send-keys -t "$SESSION_NAME" "/usage" Escape 2>/dev/null; then
        FETCH_ERROR="tmux send-keys failed"
        return 1
    fi
    sleep 1
    tmux send-keys -t "$SESSION_NAME" Enter 2>/dev/null
    sleep 8  # Wait for /usage data to load

    local capture
    capture=$(tmux capture-pane -t "$SESSION_NAME" -p -S -100 2>/dev/null)

    tmux send-keys -t "$SESSION_NAME" Escape 2>/dev/null
    sleep 1

    clear_session

    SESSION_NUM=$(parse_session_pct "$capture")
    WEEK_NUM=$(parse_week_pct "$capture")
    SESSION_RESET=$(parse_session_reset "$capture")
    WEEK_RESET=$(parse_week_reset "$capture")

    # Compute session reset epoch for cache invalidation
    SESSION_RESET_EPOCH=""
    if [[ -n "$SESSION_RESET" ]]; then
        if parse_reset_time "$SESSION_RESET"; then
            SESSION_RESET_EPOCH="$reset_epoch"
        fi
    fi

    # Validate that we got both percentages.
    # Reset times may be absent at 0% usage after a session reset — that's valid.
    if [[ -z "$SESSION_NUM" ]] || [[ -z "$WEEK_NUM" ]]; then
        FETCH_ERROR="No usage data in output"
        debug_log "ERROR: $FETCH_ERROR"
        return 1
    fi

    # Save to history for burn rate calculation
    if [[ -n "$SESSION_NUM" ]] && [[ -n "$WEEK_NUM" ]]; then
        if [[ "$SESSION_NUM" -gt 0 ]] || [[ "$WEEK_NUM" -gt 0 ]]; then
            save_usage_history "$(date +%s)" "$SESSION_NUM" "$WEEK_NUM"
        fi
    fi

    # Calculate projections
    calculate_burn_rate_projection "$capture" "${SESSION_NUM:-0}"
    calculate_week_hours_remaining "$capture"
}

# --- Cache Functions ---

# Try to load cache file
# Sets: cache_is_fresh (true if cache is within TTL, not past reset, and not an error)
# Returns: 0 if cache loaded, 1 if no cache or load failed
try_load_cache() {
    cache_is_fresh=false
    FETCH_ERROR=""  # Reset before loading

    [[ -f "$CACHE_FILE" ]] || return 1

    local cache_mtime cache_age
    cache_mtime=$(file_mtime "$CACHE_FILE") || return 1
    cache_age=$(($(date +%s) - cache_mtime))

    if [[ "$cache_age" -lt "$CACHE_DURATION" ]]; then
        cache_is_fresh=true
    fi

    # Security: verify file is owned by current user before sourcing
    local file_owner
    file_owner=$(stat -c %u "$CACHE_FILE" 2>/dev/null || stat -f %u "$CACHE_FILE" 2>/dev/null) || return 1
    if [[ "$file_owner" != "$(id -u)" ]]; then
        return 1
    fi

    # shellcheck source=/dev/null
    source "$CACHE_FILE" 2>/dev/null || return 1
    FETCH_ERROR="${FETCH_ERROR:-}"  # Ensure defined for old cache files
    SESSION_RESET_EPOCH="${SESSION_RESET_EPOCH:-}"  # Ensure defined for old cache files
    exhaustion_epoch="${exhaustion_epoch:-}"  # Ensure defined for old cache files

    # Force stale if session reset time has passed (triggers immediate refresh)
    if [[ -n "$SESSION_RESET_EPOCH" ]] && [[ "$SESSION_RESET_EPOCH" =~ ^[0-9]+$ ]]; then
        if [[ "$(date +%s)" -ge "$SESSION_RESET_EPOCH" ]]; then
            debug_log "Cache stale: session reset time has passed"
            cache_is_fresh=false
        fi
    fi

    # Error caches are never fresh (always retry on next cycle)
    if [[ -n "$FETCH_ERROR" ]]; then
        debug_log "Cache stale: contains fetch error"
        cache_is_fresh=false
    fi

    return 0
}

# Atomically save cache file
save_cache() {
    local tmp_cache="${CACHE_FILE}.tmp.$$"
    cat > "$tmp_cache" <<EOF
SESSION_NUM="$SESSION_NUM"
WEEK_NUM="$WEEK_NUM"
SESSION_RESET="$SESSION_RESET"
WEEK_RESET="$WEEK_RESET"
SESSION_RESET_EPOCH="$SESSION_RESET_EPOCH"
burn_rate_message="$burn_rate_message"
exhaustion_epoch="$exhaustion_epoch"
session_hours_remaining="$session_hours_remaining"
week_hours_remaining="$week_hours_remaining"
FETCH_ERROR=""
EOF
    mv "$tmp_cache" "$CACHE_FILE"
}

# Save error state to cache (when fetch fails)
save_error_cache() {
    local error_msg="$1"
    local tmp_cache="${CACHE_FILE}.tmp.$$"
    cat > "$tmp_cache" <<EOF
SESSION_NUM=""
WEEK_NUM=""
SESSION_RESET=""
WEEK_RESET=""
SESSION_RESET_EPOCH=""
burn_rate_message=""
exhaustion_epoch=""
session_hours_remaining=""
week_hours_remaining=""
FETCH_ERROR="$error_msg"
EOF
    mv "$tmp_cache" "$CACHE_FILE"
}

# Check if cache has valid usage data and is not excessively stale.
# Used to decide whether to preserve old data on fetch failure.
# Prefers stale data over error states.
has_valid_recent_cache() {
    [[ -f "$CACHE_FILE" ]] || return 1
    grep -q 'SESSION_NUM="[0-9]' "$CACHE_FILE" 2>/dev/null || return 1
    local cache_mtime cache_age
    cache_mtime=$(file_mtime "$CACHE_FILE") || return 1
    cache_age=$(($(date +%s) - cache_mtime))
    [[ "$cache_age" -lt $((CACHE_DURATION * 3)) ]]  # Grace period: 3x cache TTL
}

# Trigger background cache refresh if not already running
maybe_trigger_background_refresh() {
    # Check if background refresh is already running (lock held by live process)
    if is_refresh_running; then
        return 0  # Already refreshing
    fi

    # Spawn background refresh (detached from terminal)
    nohup "$0" --refresh-cache >/dev/null 2>&1 &
}

# Get usage data (cache-first, non-blocking)
# Sets: data_state to "ok", "loading", or "error"
get_usage_data() {
    data_state="error"  # Default to error

    # Always try cache first (never blocks)
    if try_load_cache; then
        data_state="ok"
        # Re-derive burn rate message from cached epoch so duration is accurate
        revalidate_burn_rate_message
        # Have cached data - trigger background refresh if stale
        if [[ "$cache_is_fresh" != true ]]; then
            maybe_trigger_background_refresh
        fi
        return 0
    fi

    # No cache - check if refresh is already running
    if is_refresh_running; then
        data_state="loading"
    else
        # Start a refresh
        maybe_trigger_background_refresh
        data_state="loading"
    fi
    return 1
}

# --- Output Formatters ---

# Applies placeholder substitution to a format string. Assumes data is already loaded.
# Supports:
#   %placeholder% - simple substitution
#   %n% - newline
#   {?content?} - conditional block (renders only if no "N/A" and non-empty)
format_templated_with_data() {
    local format_string="$1"

    # Calculate last_update
    local last_update="N/A"
    local cache_mtime
    cache_mtime=$(file_mtime "$CACHE_FILE" || true)
    if [[ -n "$cache_mtime" ]]; then
        local cache_age=$(( $(date +%s) - cache_mtime ))
        if (( cache_age < 2 )); then last_update="now";
        elif (( cache_age < 60 )); then last_update="${cache_age}s ago";
        elif (( cache_age < 3600 )); then last_update="$((cache_age / 60))m ago";
        else last_update="$((cache_age / 3600))h ago"; fi
    fi

    # Build display values
    local session_display="${SESSION_NUM:-N/A}"
    if [[ "$session_display" != "N/A" ]]; then session_display="${session_display}%"; fi

    local week_display="${WEEK_NUM:-N/A}"
    if [[ "$week_display" != "N/A" ]]; then week_display="${week_display}%"; fi

    # Formatted reset times
    local session_reset_time_val
    session_reset_time_val=$(reformat_reset_time "${SESSION_RESET:-N/A}")

    local week_reset_time_val
    week_reset_time_val=$(reformat_reset_time "${WEEK_RESET:-N/A}")

    # Formatted durations (N/A if reset time unavailable)
    local session_reset_duration_val
    if [[ -z "$SESSION_RESET" ]] || [[ "$SESSION_RESET" == "N/A" ]]; then
        session_reset_duration_val="N/A"
    else
        session_reset_duration_val=$(format_time_remaining "${session_hours_remaining:-0}")
    fi

    local week_reset_duration_val
    if [[ -z "$WEEK_RESET" ]] || [[ "$WEEK_RESET" == "N/A" ]]; then
        week_reset_duration_val="N/A"
    else
        week_reset_duration_val=$(format_time_remaining "${week_hours_remaining:-0}")
    fi

    # Substitute placeholders using bash parameter expansion
    local result="$format_string"
    result="${result//%session_num%/$session_display}"
    result="${result//%week_num%/$week_display}"
    result="${result//%session_reset_time%/$session_reset_time_val}"
    result="${result//%session_reset_duration%/$session_reset_duration_val}"
    result="${result//%week_reset_time%/$week_reset_time_val}"
    result="${result//%week_reset_duration%/$week_reset_duration_val}"
    result="${result//%last_update%/$last_update}"
    result="${result//%projected_expiration%/${burn_rate_message:-}}"

    # Substitute newlines
    local NL=$'\n'
    result="${result//%n%/$NL}"

    # Process conditional blocks: {?content?}
    # Remove block if it contains "N/A" or is empty/whitespace-only
    local temp_result=""
    local remaining="$result"
    while [[ "$remaining" == *'{'*'?'*'?}'* ]]; do
        # Find the first {? ... ?} block
        local before="${remaining%%\{\?*}"
        local rest="${remaining#*\{\?}"
        local block="${rest%%\?\}*}"
        local after="${rest#*\?\}}"

        temp_result+="$before"
        # Keep block only if no N/A and has non-whitespace content
        if [[ "$block" != *"N/A"* ]] && [[ "$block" =~ [^[:space:]] ]]; then
            temp_result+="$block"
        fi
        remaining="$after"
    done
    result="${temp_result}${remaining}"

    echo "$result"
}

# Generic formatter for -o format="..."
format_templated() {
    local format_string="$1"
    if ! get_usage_data; then
        if [[ "$data_state" == "loading" ]]; then echo "⏳"; else echo "?"; fi
        return
    fi
    if [[ -n "$FETCH_ERROR" ]]; then echo "⚠️"; return; fi

    format_templated_with_data "$format_string"
}

# Format menu output for SwiftBar
format_menu_output() {
    local session_num="$1"
    local week_num="$2"
    local session_reset="$3"
    local week_reset="$4"
    local session_hours_rem="$5"
    local week_hours_rem="$6"
    local burn_msg="$7"

    # Format display strings: "N%" if set, "N/A" if empty
    local session_display="${session_num:-N/A}${session_num:+%}"
    local week_display="${week_num:-N/A}${week_num:+%}"

    if [[ "$week_num" == "100" ]]; then
        echo "🤖 Week: 100% | color=#CC0000,#FF3333"
    else
        local color
        color=$(determine_color "${session_num:-0}")
        echo "🤖 ${session_display} | color=$color"
    fi

    echo "---"

    if [[ -n "$session_hours_rem" ]]; then
        local formatted_session_time formatted_session_reset
        formatted_session_time=$(format_time_remaining "$session_hours_rem")
        formatted_session_reset=$(reformat_reset_time "${session_reset:-N/A}")
        echo "Session: ${session_display} - resets $formatted_session_reset - $formatted_session_time"
    else
        local formatted_session_reset
        formatted_session_reset=$(reformat_reset_time "${session_reset:-N/A}")
        echo "Session: ${session_display} - resets $formatted_session_reset"
    fi

    if [[ -n "$burn_msg" ]] && [[ "$week_num" != "100" ]]; then
        echo "$burn_msg"
    fi

    if [[ -n "$week_hours_rem" ]]; then
        local formatted_week_time formatted_week_reset
        formatted_week_time=$(format_time_remaining "$week_hours_rem")
        formatted_week_reset=$(reformat_reset_time "${week_reset:-N/A}")
        echo "Week: ${week_display} - resets $formatted_week_reset - $formatted_week_time"
    else
        local formatted_week_reset
        formatted_week_reset=$(reformat_reset_time "${week_reset:-N/A}")
        echo "Week: ${week_display} - resets $formatted_week_reset"
    fi

    echo "---"
    echo "Refresh | refresh=true"

    if is_24h_format; then
        echo "✓ 24-Hour Time Format | bash='$0' terminal=false refresh=true param0='toggle-time-format'"
    else
        echo "12-Hour Time Format | bash='$0' terminal=false refresh=true param0='toggle-time-format'"
    fi

    if is_debug_enabled; then
        echo "✓ Enable Debug Logging | bash='$0' terminal=false refresh=true param0='toggle-debug'"
        echo "View Debug Log | bash='open' param0='$DEBUG_LOG' terminal=false"
    else
        echo "Enable Debug Logging | bash='$0' terminal=false refresh=true param0='toggle-debug'"
    fi
}

format_swiftbar() {
    # Handle menu commands for SwiftBar
    if [[ "${1:-}" == "toggle-debug" ]]; then
        toggle_debug_logging
        exit 0
    fi

    if [[ "${1:-}" == "toggle-time-format" ]]; then
        toggle_time_format
        exit 0
    fi

    if ! get_usage_data; then
        if [[ "$data_state" == "loading" ]]; then
            echo "🤖 ⏳ | color=gray"
            echo "---"
            echo "Loading usage data..."
        else
            echo "🤖 ? | color=gray"
            echo "---"
            echo "Claude CLI not installed"
        fi
        return
    fi

    # Check for error state from failed fetch
    if [[ -n "$FETCH_ERROR" ]]; then
        echo "🤖 ⚠️ | color=gray"
        echo "---"
        echo "$FETCH_ERROR"
        echo "---"
        echo "Refresh | refresh=true"
        return
    fi

    format_menu_output "${SESSION_NUM:-}" "${WEEK_NUM:-}" \
        "$SESSION_RESET" "$WEEK_RESET" "$session_hours_remaining" "$week_hours_remaining" \
        "$burn_rate_message"
}

# Summary format template
readonly SUMMARY_FORMAT="Session: %session_num% (resets %session_reset_duration%)%n%Week: %week_num% (resets %week_reset_duration%)%n%%n%Updated: %last_update%{?%n%%projected_expiration%?}"

format_summary() {
    format_templated "$SUMMARY_FORMAT"
}

format_claude() {
    init_colors

    local input model_display ctx_pct
    input=$(cat)

    if [[ -n "$input" ]]; then
        model_display=$(echo "$input" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
        ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
        ctx_pct=$(printf "%.0f" "$ctx_pct" 2>/dev/null || echo "0")
    else
        model_display="Claude"
        ctx_pct="?"
    fi

    if ! get_usage_data; then
        local indicator="?"
        if [[ "$data_state" == "loading" ]]; then
            indicator="⏳"
        fi
        echo "[$model_display] Ctx: ${ctx_pct}% | Session: $indicator | Week: $indicator"
        return
    fi

    # Check for error state from failed fetch
    if [[ -n "$FETCH_ERROR" ]]; then
        echo "[$model_display] Ctx: ${ctx_pct}% | Error: $FETCH_ERROR"
        return
    fi

    local session_reset_compact week_reset_compact
    session_reset_compact=$(format_reset_compact "$SESSION_RESET")
    week_reset_compact=$(format_reset_compact "$WEEK_RESET")

    local ctx_color session_color week_color
    ctx_color=$(get_pct_color "$ctx_pct")
    session_color=$(get_pct_color "$SESSION_NUM")
    week_color=$(get_pct_color "$WEEK_NUM")

    echo "[$model_display] Ctx: ${ctx_color}${ctx_pct}%${COLOR_RESET} | Session: ${session_color}${SESSION_NUM:-?}${SESSION_NUM:+%}${COLOR_RESET} ($session_reset_compact) | Week: ${week_color}${WEEK_NUM:-?}${WEEK_NUM:+%}${COLOR_RESET} ($week_reset_compact)"
}

# --- Argument Parsing ---

parse_args() {
    while getopts "o:h" opt; do
        case "$opt" in
            o)
                if [[ "$OPTARG" == format=* ]]; then
                    OUTPUT_FORMAT="format"
                    OUTPUT_FORMAT_STRING="${OPTARG#*=}"
                else
                    OUTPUT_FORMAT="$OPTARG"
                fi
                ;;
            h) usage; exit 0 ;;
            *) usage_and_exit 1 ;;
        esac
    done
}

# --- Main ---

# Support --source-only for bats testing
# shellcheck disable=SC2317
if [[ "${1:-}" == "--source-only" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Change to the script's directory. This is crucial for background execution
# (like from SwiftBar or nohup) to ensure that the `claude` CLI, when it
# prompts for trust, sees the script's actual directory, not `/`.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null

# Background cache refresh mode (spawned by maybe_trigger_background_refresh)
if [[ "${1:-}" == "--refresh-cache" ]]; then
    if acquire_lock; then
        if ! fetch_usage_data; then
            if has_valid_recent_cache; then
                debug_log "Fetch failed but valid recent cache exists - preserving"
            else
                save_error_cache "${FETCH_ERROR:-Unknown fetch error}"
            fi
        else
            save_cache
        fi
        release_lock
    fi
    exit 0
fi

parse_args "$@"

# Auto-detect SwiftBar environment (SWIFTBAR=1 is set by SwiftBar when running plugins)
if [[ -z "$OUTPUT_FORMAT" ]] && [[ "${SWIFTBAR:-}" == "1" ]]; then
    OUTPUT_FORMAT="swiftbar"
fi

case "$OUTPUT_FORMAT" in
    swiftbar) format_swiftbar "${@:$OPTIND}" ;;
    claude)   format_claude ;;
    summary)  format_summary ;;
    format)   format_templated "$OUTPUT_FORMAT_STRING" ;;
    *)        usage_and_exit 1 ;;
esac
