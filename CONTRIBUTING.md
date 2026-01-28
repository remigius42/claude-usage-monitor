# Contributing to Claude Usage Monitor

Thank you for your interest in contributing! This guide covers the
development environment setup.

## Prerequisites

Install these tools before developing:

| Tool | Purpose | Install |
| ---- | ------- | ------- |
| pre-commit | Code quality hooks | `brew install pre-commit` |
| bats-core | Unit testing | `brew install bats-core` |
| tmux | Runtime dependency | `brew install tmux` |
| jq | JSON parsing | `brew install jq` |
| Claude CLI | Manual testing | [claude.ai/download](https://claude.ai/download) |

**macOS or Linux (Homebrew):**

```bash
brew install pre-commit bats-core tmux jq
```

**Debian/Ubuntu:**

```bash
sudo apt update && sudo apt install -y tmux jq npm
pip install pre-commit
npm install -g bats
```

**Fedora/RHEL:**

```bash
sudo dnf install -y tmux jq npm
pip install pre-commit
npm install -g bats
```

**Arch Linux:**

```bash
sudo pacman -S tmux jq python-pre-commit bash-bats
```

> **Note:** ShellCheck is installed via pre-commit, but having it locally
> helps with IDE integration (`apt install shellcheck`, `dnf install ShellCheck`,
> or `pacman -S shellcheck`).

## Development Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/remigius42/claude-usage-monitor.git
   cd claude-usage-monitor
   ```

2. Install pre-commit hooks:

   ```bash
   pre-commit install
   ```

3. Verify setup:

   ```bash
   pre-commit run --all-files
   bats tests/
   ```

## Pre-commit Hooks

Hooks run automatically on each commit. See
[.pre-commit-config.yaml](.pre-commit-config.yaml) for the full list.

**Run hooks manually:**

```bash
pre-commit run --all-files
```

## Testing

### Unit Tests

Run the bats test suite:

```bash
bats tests/
```

### Manual Testing

Test output formats directly:

```bash
./claude-usage.sh -o swiftbar
./claude-usage.sh -o format="Session: %session_num% | Week: %week_num%"
./claude-usage.sh -o summary
echo '{"model":{"display_name":"Opus"}}' | ./claude-usage.sh -o claude
```

Debug the tmux session:

```bash
tmux list-sessions
tmux attach -t claude-usage-monitor
```

## Project Architecture

See [AGENTS.md](AGENTS.md) for the full architecture overview.

**Quick summary:**

- `claude-usage.sh` - Unified script with parsing, formatting, and platform detection
  - Auto-detects SwiftBar via `SWIFTBAR=1` environment variable
  - Uses `-o format="..."` for custom output (Polybar, Starship, etc.)
  - Uses `-o claude` for Claude CLI statusline
  - Uses `-o summary` for notifications
- `scripts/configure-claude-json.sh` - Helper to configure trust settings
- `scripts/setup-swiftbar-autostart-macos.sh` - Helper for macOS autostart

## Code Style & Conventions

- **ShellCheck compliance** - All shell scripts must pass ShellCheck
  (enforced by pre-commit)
- **Function naming** - Use snake_case (e.g., `parse_session_pct`, `format_swiftbar`)
- **Variables** - UPPER_CASE for globals, lower_case for locals
- **Comments** - Explain *why*, not *what*

## Release Process

1. Update [CHANGELOG.md](CHANGELOG.md) (move Unreleased items to new version)
2. Tag version: `git tag -a v1.x.x -m "Release v1.x.x" && git push origin v1.x.x`
3. Create GitHub release
4. Update the Homebrew formula and push to tap (see below)

### Homebrew Tap

The Homebrew formula lives in `homebrew/` and is published to
`remigius42/homebrew-claude-usage-monitor` via git subtree. This keeps all
code in one repository, ensuring the formula stays in sync with the
application and giving AI assistants full context when making changes.

See [homebrew/CONTRIBUTING.md](homebrew/CONTRIBUTING.md) for the release
workflow and subtree commands.

## Questions?

Open an issue or check [README.md](README.md) for user documentation.
