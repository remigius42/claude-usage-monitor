# [Claude Usage Monitor](https://github.com/remigius42/claude-usage-monitor)

<!-- spellchecker: words pango untap xbar -->
<!-- spellchecker: ignore deje -->

Copyright 2026 [Andreas Remigius Schmidt](https://github.com/remigius42)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)
[![CI](https://github.com/remigius42/claude-usage-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/remigius42/claude-usage-monitor/actions/workflows/ci.yml)
[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/remigius42/claude-usage-monitor?utm_source=oss&utm_medium=github&utm_campaign=remigius42%2Fclaude-usage-monitor&labelColor=171717&color=FF570A&label=CodeRabbit+Reviews)](https://coderabbit.ai)

> **Disclaimer:** This is an unofficial tool, not affiliated with or
> endorsed by Anthropic. Claude is a trademark of Anthropic, PBC.

---

## What It Does

Claude Usage Monitor displays your Claude API usage in your menu bar
(macOS), status bar (Linux), or [Claude Code CLI](https://code.claude.com/docs/en/setup) status line. It shows
session and weekly usage percentages with color-coded indicators and
reset countdowns.

> **Note:** Context window usage (Ctx: %) is only available in the Claude
> Code CLI statusline (`-o claude`), where the CLI provides its own
> session data.

### Why This Approach

The Claude CLI doesn't expose usage data via API for subscription plans,
only through its interactive `/usage` command. This
script works around that by managing a detached
[tmux](https://github.com/tmux/tmux/wiki) session that runs Claude CLI
non-interactively:

1. Sends `/context` to prevent `/usage` from getting stuck
2. Sends `/clear` to ensure clean terminal state
3. Sends `/usage` and captures the pane output
4. Parses percentages and reset times with grep/sed
5. Sends `/clear` to clean up

This approach enables integration with menu bars and status lines that
need to poll for data periodically. Since the tmux session runs an
isolated Claude instance, its context window usage reflects its own
conversation — not the user's active session(s). The Claude Code CLI
statusline receives context data directly from the running session via
stdin, which is why it's the only format that can display it.

### Output Examples

**Claude Code CLI** (`-o claude`):

```text
[Opus] Ctx: 42% | Session: 45% (2h) | Week: 67% (3d)
```

**macOS SwiftBar** (`-o swiftbar`):

```text
🤖 45% ▼
---
Session: 45% - resets in 2h 15m
Week: 67% - resets in 3d 5h
---
Refresh
```

**Custom format** (`-o format="..."`):

```bash
claude-usage.sh -o format="Claude: %session_num% | %week_num%"
# Output: Claude: 45% | 67%
```

### License

MIT License - see [LICENSE](LICENSE) for details.

---

## Usage

### Prerequisites

- [Claude CLI](https://code.claude.com/docs/en/setup) via **native
  installer** (not npm)
- [tmux](https://github.com/tmux/tmux/wiki) (`brew install tmux`)
- [jq](https://github.com/jqlang/jq) (`brew install jq`) - required for `-o claude` format
- [bc](https://www.gnu.org/software/bc/) (optional, for burn rate projections)
- [SwiftBar](https://swiftbar.app/) for macOS menu bar (`brew install
  swiftbar`)

> **Note:** Menu bar plugins run without shell profiles, so
> npm/nvm-installed binaries won't be found. Use the native installer.

### Quick Start: macOS with SwiftBar

```bash
# 1. Install
brew tap remigius42/claude-usage-monitor
brew install claude-usage-monitor

# 2. Configure Claude CLI trust (suppresses permission dialogs)
configure-claude-json.sh

# 3. (Optional) Set SwiftBar to launch at login
setup-swiftbar-autostart-macos.sh

# 4. Verify - the plugin appears in your menu bar
```

The plugin auto-refreshes every 30 seconds. Click the menu bar icon to see
details and manual refresh option.

### Other Platforms

**Claude Code CLI statusline** - Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/claude-usage.sh -o claude"
  }
}
```

**Linux Polybar** - Add to `~/.config/polybar/config.ini` (see
[config-snippet.ini](plugins/polybar/config-snippet.ini) for full example):

```ini
[module/claude-usage]
type = custom/script
exec = /path/to/plugins/polybar/claude-usage-polybar.sh
interval = 30
label = %output%
```

Left/right click shows a summary notification via `notify-send`. For direct
usage without click support:

```ini
exec = /path/to/claude-usage.sh -o format=" %session_num% |  %week_num%"
```

**Linux i3blocks** - Add to `~/.config/i3blocks/config` (see
[config-snippet.ini](plugins/i3blocks/config-snippet.ini) for full example):

```ini
[claude-usage]
command=/path/to/plugins/i3blocks/claude-usage-i3blocks.sh
interval=30
```

Left/right click shows a summary notification. For per-value colors like
Polybar, set `I3BLOCKS_PANGO=1` and add `markup=pango` to your config.

**Starship prompt** - Add to `starship.toml`:

```toml
[custom.claude]
command = "claude-usage.sh -o format='%session_num%'"
when = "command -v claude-usage.sh"
symbol = "🤖 "
```

Multiple clients (SwiftBar, Starship, Claude CLI) can safely poll the
script simultaneously. A shared cache and file-based locking ensure only
one background fetch runs at a time.

### Format String Reference

| Placeholder | Description | Example |
| ----------- | ----------- | ------- |
| `%session_num%` | Session usage percentage | `45%` |
| `%week_num%` | Week usage percentage | `67%` |
| `%session_reset_time%` | Session reset time | `21:00` |
| `%session_reset_duration%` | Time until session reset | `2h 30m` |
| `%week_reset_time%` | Week reset time | `Dec 23, 21:00` |
| `%week_reset_duration%` | Time until week reset | `3d 5h` |
| `%last_update%` | Time since last refresh | `5m ago` |
| `%projected_expiration%` | Burn rate warning | `Exhausted in 3h` |
| `%n%` | Newline character | |

**Conditional blocks** - Use `{?content?}` to hide content when it
contains `N/A`:

```bash
claude-usage.sh -o format="Usage: %session_num%{? - %projected_expiration%?}"
# With warning:    "Usage: 45% - Exhausted in 3h"
# Without warning: "Usage: 45%"
```

### Customization

**SwiftBar refresh interval** - Edit the cron expression in the script
(minimum 1 minute due to cron granularity):

```bash
# <swiftbar.schedule>*/1 * * * *</swiftbar.schedule>
# Change to */5 * * * * for 5-minute intervals
```

**Polybar interval** - Edit `interval` in your config (seconds, default 30).

**Color thresholds** - Green < 50%, orange < 80%, red >= 80%.

### Troubleshooting

**Shows "N/A" or doesn't update:**

```bash
claude --version        # CLI installed?
claude auth status      # Authenticated?
which tmux              # tmux installed?
cat ~/.claude.json      # Trust configured?
```

**SwiftBar not showing plugin:** Check plugin directory with `defaults
read com.ameba.SwiftBar PluginDirectory`, ensure script is executable.

**Polybar not showing module:** Check script path, ensure executable,
check logs with `polybar example 2>&1 | grep claude`.

### Uninstallation

```bash
brew uninstall claude-usage-monitor
brew untap remigius42/claude-usage-monitor
```

---

## Documentation & Support

| Resource | Description |
| -------- | ----------- |
| [MANUAL_INSTALL.md](MANUAL_INSTALL.md) | Step-by-step manual installation |
| [CHANGELOG.md](CHANGELOG.md) | Version history and changes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup and guidelines |
| [GitHub Issues](https://github.com/remigius42/claude-usage-monitor/issues) | Bug reports and feature requests |
| [Claude CLI docs](https://code.claude.com/docs/en/setup) | Official Claude documentation |

Contributions welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) to get started.

### Acknowledgments

- Built for [SwiftBar](https://github.com/swiftbar/SwiftBar) by @p0deje
- [Polybar](https://github.com/polybar/polybar) support
- Inspired by [BitBar/xbar](https://github.com/matryer/xbar) plugin ecosystem
