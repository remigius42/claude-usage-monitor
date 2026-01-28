# AGENTS.md

<!-- spellchecker: ignore noqa xfail -->

This file provides guidance to AI assistants when working with code in
this repository.

## Project Overview

Bash script that displays Claude API usage in system status bars. Uses
tmux to run a persistent Claude CLI session and scrapes the `/usage`
command output.

## Architecture

```text
┌─────────────────────────────────────────┐
│         claude-usage.sh                 │
│  • tmux session management              │
│  • /usage command + parsing             │
│  • Auto-detects SwiftBar via SWIFTBAR=1 │
│  • Output format via -o flag            │
└─────────────────────────────────────────┘
              │
    ┌─────────┼────────────────┬────────────────┐
    ▼         ▼                ▼                ▼
 SwiftBar   Custom Format   Claude CLI      Summary
 (macOS)    -o format="…"   -o claude       -o summary
 auto-detect (Polybar, etc)  statusline      (notifications)
```

**Core mechanism** (`claude-usage.sh`):

1. Create/reuse a detached tmux session running `claude`
2. Send `/context` to prevent `/usage` from getting stuck (workaround)
3. Send `/clear` to ensure clean state for parsing
4. Send `/usage` command via `tmux send-keys`
5. Capture pane output with `tmux capture-pane`
6. Parse percentages and reset times with grep/sed
7. Send `/clear` to clean up session
8. Format output based on `-o` flag or auto-detection

**SwiftBar integration**:

The script includes xbar/SwiftBar metadata tags for configuration:

- `<swiftbar.schedule>*/1 * * * *</swiftbar.schedule>` - Refresh every minute (cron minimum; cache TTL is 30s)
- `<swiftbar.hideAbout>`, `<swiftbar.hideRunInTerminal>`, etc. - Menu customization

When SwiftBar runs the script, it sets `SWIFTBAR=1` environment variable.
The script auto-detects this and uses SwiftBar output format without requiring
the `-o` flag.

**Other integrations** invoke the script with explicit flags:

```bash
./claude-usage.sh -o format="Claude: %session_num%"  # Polybar, Starship, etc.
./claude-usage.sh -o claude                          # Claude CLI statusline
./claude-usage.sh -o summary                         # Notifications
```

**Core functions** (in `claude-usage.sh`):

- `fetch_usage_data()` - Executes `/usage` via tmux, parses output
- `get_usage_data()` - Cache-first data retrieval with background refresh
- `clear_session()` - Sends `/clear` command to reset Claude session
- `handle_stale_state()` - Recovers from feedback prompts or leftover conversations
- `calculate_slope_averaged_burn_rate()` - Calculates usage rate from history
- `calculate_burn_rate_projection()` - Projects quota exhaustion time
- `format_swiftbar()` - Emoji + dropdown menu format with toggles
- `format_templated()` - Custom format string with placeholders and conditionals
- `format_claude()` - Statusline with context window + API quotas
- `format_summary()` - Plain text for notifications

## Concurrency Model

The script uses a **cache-first, non-blocking** approach to handle concurrent
invocations (especially important for Claude CLI which polls every 300ms):

1. **Always return cached data** - Never blocks waiting for fresh data
2. **Background refresh** - Spawns `--refresh-cache` subprocess if cache is stale
3. **File-based locking** - Uses `mkdir` for atomic lock acquisition
4. **Atomic file writes** - Cache and history use temp file + `mv` pattern

**Display states**:

| State | Display | Meaning |
| ----- | ------- | ------- |
| First run (no cache) | `⏳` | Loading in progress |
| Error (fetch failed) | `?` | Something went wrong |
| Have cache | Actual data | Normal operation |

**Recommended refresh intervals**:

| Mode | Interval | Notes |
| ---- | -------- | ----- |
| SwiftBar | 1 minute | Cron minimum; cache TTL is 30s |
| Polybar | 30 seconds | Matches cache TTL |
| Claude CLI | 300ms (built-in) | Caching is always enabled |

## Testing

**Run tests after every significant change** to catch regressions early.

Run unit tests (requires `bats-core`):

```bash
brew install bats-core  # macOS
bats tests/
```

**Test structure:**

```text
tests/
├── helpers.bash          # Shared setup
├── cli.bats              # CLI interface + debug
├── formatting.bats       # Parsing, time, colors
├── data.bats             # Caching, locking, burn rate
├── templating.bats       # Template engine + placeholders
├── output-swiftbar.bats  # SwiftBar output
├── output-format.bats    # Custom format output
└── output-claude.bats    # Claude CLI output
```

Test output formats directly:

```bash
./claude-usage.sh -o swiftbar
./claude-usage.sh -o format="Session: %session_num% | Week: %week_num%"
./claude-usage.sh -o summary
echo '{"model":{"display_name":"Opus"}}' | ./claude-usage.sh -o claude
```

Check tmux session state:

```bash
tmux list-sessions
tmux attach -t claude-usage-monitor  # to debug interactively
```

### Shellcheck disables in test files

Mock functions in BATS tests trigger false positives. Use inline disables
with this format:

```bash
# SC2034 - "appears unused" for mock
# SC2317 - "unreachable" for mock
# SC2329 - "unused function" for mock
# shellcheck disable=SC2034,SC2317,SC2329
get_usage_data() { ... }
```

| Code | Message | Why it's a false positive |
| ---- | ------- | ------------------------- |
| SC1090 | Can't follow non-constant source | Test sources dynamically created files |
| SC1091 | Source not specified as input | Path varies by CWD, can't reliably specify |
| SC2034 | Variable appears unused | Mock sets vars used in assertions |
| SC2154 | Variable not assigned | Set by tested function, not visible to shellcheck |
| SC2317 | Command appears unreachable | Mock called by code under test |
| SC2329 | Function appears unused | Mock called by code under test |

## Key Configuration

Scripts require `~/.claude.json` to have the plugin directory trusted:

```json
{
  "/path/to/plugin/directory": {
    "hasTrustDialogAccepted": true
  }
}
```

Use `scripts/configure-claude-json.sh <directory>` to configure this.

For SwiftBar auto-start on macOS, use `scripts/setup-swiftbar-autostart-macos.sh`.

For Claude CLI statusline, add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-usage.sh -o claude"
  }
}
```

## Code Quality

**Before adding any linter disables, test skips, or ignore directives**
(e.g., `# shellcheck disable`, `# noqa`, `skip()`, `.gitignore` entries for
generated files), you **must get explicit user confirmation**. This includes:

- Shellcheck/linter disable comments
- Test skip annotations or xfail markers
- Adding paths to ignore files
- Suppressing warnings in any form

This prevents silent degradation of code quality. Always fix the underlying
issue rather than suppressing the warning, unless the user explicitly approves
the suppression with a clear rationale. When a suppression is approved, always
precede the disable directive with a comment explaining *why* it is safe to
suppress (e.g., `# SC2030 - subshell-local TZ is intentional (bats test
isolation)`).

## Distribution

Distributed via Homebrew tap (separate repository). The formula and tap
documentation live in `homebrew/` and are published via git subtree.

**Why git subtree?** Keeping the Homebrew formula in this repository (rather
than a separate tap repo) ensures AI assistants have full context when making
changes. The formula references specific file paths, dependencies, and install
logic that must stay in sync with the application. Git subtree lets us maintain
a single source of truth while still publishing to the standard tap structure.

See [homebrew/CONTRIBUTING.md](homebrew/CONTRIBUTING.md) for maintenance.
