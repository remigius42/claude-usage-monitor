# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-29

### Added

- Unified usage monitoring script (`claude-usage.sh`) supporting SwiftBar, custom
  format strings (for Polybar, Starship, etc.), and Claude CLI statusline
- Custom format strings with `-o format="..."` supporting placeholders
  (`%session_num%`, `%week_num%`, `%session_reset_time%`, `%session_reset_duration%`,
  `%week_reset_time%`, `%week_reset_duration%`, `%last_update%`,
  `%projected_expiration%`, `%n%`) and conditional blocks (`{?content?}`)
- SwiftBar auto-detection via `SWIFTBAR=1` environment variable
- SwiftBar metadata tags for refresh scheduling and menu customization
- Summary output format (`-o summary`) for notifications
- Claude CLI statusline format (`-o claude`) with context window display
- Color-coded usage indicators (green < 50%, orange < 80%, red >= 80%)
- Cache-first architecture with background refresh for high-frequency polling
- Burn rate calculation with slope-averaged history and quota exhaustion projection
- Helper scripts: `configure-claude-json.sh`, `setup-swiftbar-autostart-macos.sh`
- Cross-platform installation instructions (macOS, Debian/Ubuntu, Fedora/RHEL, Arch)
- Pre-commit hooks for code quality (ShellCheck, markdownlint, cspell, gitleaks)
- Bats test suite for unit testing (CLI, formatting, data, and output-specific tests)
