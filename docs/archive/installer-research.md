# Research Summary: Modern Script Distribution Methods

<!-- spellchecker: words chezmoi distro distros elif justfile -->
<!-- spellchecker: words linuxbrew maclaunch mktemp msys mxcl -->
<!-- spellchecker: words osascript ostype pipefail rustup taskbars -->
<!-- spellchecker: words userland velopack waybar xbar zebar -->

> **Note:** This document contains historical research notes. The
> "Implementation Plan" section describes a single-repo structure that
the project **did not adopt**. The actual project uses a two-repo
structure - see the [Homebrew Tap section in
CONTRIBUTING.md](../CONTRIBUTING.md#homebrew-tap) and
[`homebrew/CONTRIBUTING.md`](../homebrew/CONTRIBUTING.md) for the
current approach.

## Context

The user has a SwiftBar plugin script ([claude-usage.5m.sh](claude-usage.5m.sh)) that requires multiple installation steps:

1. SwiftBar must be installed
2. Script must be placed in SwiftBar's plugin folder
3. Configuration change to `~/.claude.json` to suppress trust dialog
4. Potentially enable SwiftBar as an autostart app

**Question**: How do modern open-source projects handle multi-step script installations in an OS-agnostic, trustworthy way?

---

## Key Findings

### 1. Package Managers - The Gold Standard

**Homebrew** remains the most trusted cross-platform package manager for macOS and Linux in 2025:

- **Custom Taps**: The recommended approach for distributing custom scripts
  - Users run: `brew tap username/tap-name && brew install tool-name`
  - Formula can handle all dependencies, file placement, and configuration
  - Users trust Homebrew's ecosystem and can inspect formulas before installation
  - Works consistently across macOS and Linux

**Advantages**:

- High trust level (users already trust Homebrew)
- Automatic dependency management
- Version management and updates built-in
- Can handle complex post-install steps via formula scripts
- Open source and commercially free

**Limitations**:

- macOS/Linux only (not Windows native, though WSL works)
- Requires users to have Homebrew installed first

### 2. Installation Script Patterns

**The "curl | bash" Pattern**:

- Widely used (Homebrew itself, rustup, nvm, etc.)
- **Trust concerns identified in 2025**:
  - Man-in-the-middle attack vectors
  - Script interruption risks
  - Lack of transparency (users don't know what will execute)
  - No cryptographic verification of script integrity

**Best Practices for Bash Install Scripts (2025)**:

- Use `set -euo pipefail` (strict mode)
- Validate all inputs
- Use absolute paths to avoid PATH injection
- Never hardcode secrets
- Use `mktemp` for temporary files
- Keep scripts under 50 lines (Google style guide)
- Run through ShellCheck before distribution
- Provide script URL for user inspection before piping

**Modern Approach**:

```bash
# Recommended: Two-step process
curl -fsSL https://example.com/install.sh -o install.sh
# User can inspect install.sh
bash install.sh

# Not recommended but common:
curl -fsSL https://example.com/install.sh | bash
```

### 3. Task Runners for Installation Automation

Modern alternatives to raw bash scripts:

**Just** (rising popularity in 2025):

- Rust-based command runner
- Better UX than Make
- Multi-language recipe support
- Automatic .env file loading
- MIT licensed, commercially free
- Can create a `justfile` with installation tasks

**Make** (still relevant in 2025):

- Universal availability on Unix systems
- `make install` is intuitive
- Cross-platform with platform detection possible
- Familiar to developers

**Task** (Go-based):

- YAML-based configuration
- Simpler than Make for modern workflows
- Cross-platform including Windows

### 4. Configuration Management Tools

For managing dotfiles and configuration changes:

**chezmoi** (recommended for complex setups):

- Written in Go, single binary
- Template support for machine-specific configs
- Built-in secret encryption (GPG)
- Cross-platform (macOS, Linux, Windows)
- Can manage `~/.claude.json` modifications safely
- MIT licensed

**GNU Stow** (simple symlink manager):

- Minimal dependencies
- Elegant simplicity
- Best for straightforward symlinking
- No template or secret support

### 5. Cross-Platform Installers

**Open Source Options**:

- **Zero Install**: Cross-platform (Windows, macOS, Linux), fully open source
- **IzPack**: Java-based, works on all platforms
- **Velopack**: Modern, includes auto-update framework

**Limitations**:

- Overkill for simple script distribution
- Better suited for compiled applications

---

## Trust Patterns in 2025

### What Users Trust (in order)

1. **Official package managers** (apt, Homebrew, etc.)
2. **GitHub releases** with checksum verification
3. **Reviewed installation scripts** (two-step: download then execute)
4. **Direct curl | bash** (lowest trust, but widely accepted if from known source)

### Building Trust

- Host on GitHub with transparent history
- Provide checksums (SHA-256)
- Document exactly what the installer does
- Allow dry-run mode (`--dry-run` flag)
- Keep install scripts simple and readable
- Use established tools (Homebrew, Make, Just)

---

## Recommendations for SwiftBar Plugin Distribution

### Recommended Approach: Homebrew Tap + Justfile

#### Option A: Homebrew Formula (Best for macOS users)

1. Create a custom tap: `homebrew-claude-usage`
2. Formula handles:
   - Installing SwiftBar if not present (`depends_on "swiftbar"`)
   - Symlinking script to SwiftBar plugin folder
   - Patching `~/.claude.json` (with user confirmation)
   - Optional: Adding SwiftBar to login items

**User experience**:

```bash
brew tap username/claude-usage
brew install claude-usage-swiftbar
```

**Advantages**:

- Single command installation
- Automatic updates via `brew upgrade`
- Users trust Homebrew ecosystem
- Can declare SwiftBar as dependency
- Post-install scripts for config changes

**Disadvantages**:

- macOS/Linux only
- Requires maintaining a formula

---

#### Option B: Just + Install Script (More Universal)

Create a `justfile` with installation recipes:

```just
# Install SwiftBar plugin
install:
    @echo "Installing claude-usage SwiftBar plugin..."
    just _check-swiftbar
    just _install-plugin
    just _configure-claude
    @echo "✓ Installation complete!"

# Check if SwiftBar is installed
_check-swiftbar:
    @command -v swiftbar >/dev/null || (echo "SwiftBar not found. Install with: brew install swiftbar" && exit 1)

# Install the plugin
_install-plugin:
    @cp claude-usage.5m.sh "$(defaults read com.ameba.SwiftBar PluginDirectory)/claude-usage.5m.sh"
    @chmod +x "$(defaults read com.ameba.SwiftBar PluginDirectory)/claude-usage.5m.sh"

# Configure Claude to trust the directory
_configure-claude:
    @echo "Configuring ~/.claude.json..."
    # Safe JSON patching logic here
```

**User experience**:

```bash
git clone https://github.com/username/claude-usage-swiftbar
cd claude-usage-swiftbar
just install
```

**Advantages**:

- Human-readable installation steps
- Easy to audit before running
- Can support multiple platforms
- Users can run individual steps if needed

**Disadvantages**:

- Requires Just to be installed first
- Not as seamless as Homebrew

---

#### Option C: Simple Makefile (Most Compatible)

Classic approach with universal availability:

```makefile
.PHONY: install check clean

install: check
    @echo "Installing claude-usage SwiftBar plugin..."
    cp claude-usage.5m.sh "$$(defaults read com.ameba.SwiftBar PluginDirectory)/"
    chmod +x "$$(defaults read com.ameba.SwiftBar PluginDirectory)/claude-usage.5m.sh"
    @echo "Plugin installed. Please configure ~/.claude.json manually."

check:
    @command -v swiftbar >/dev/null || (echo "Error: SwiftBar not installed" && exit 1)
```

**User experience**:

```bash
git clone https://github.com/username/claude-usage-swiftbar
cd claude-usage-swiftbar
make install
```

---

### Handling `~/.claude.json` Configuration

**Security considerations**: Automatically modifying JSON config files is risky and can be seen as invasive.

**Recommended approach**:

1. **Ask for explicit permission** during installation
2. **Show exactly what will be added**
3. **Create backup** before modification
4. **Use safe JSON manipulation** (not sed/awk)

**Implementation options**:

1. **jq** (JSON processor - most reliable):

```bash
# Backup first
cp ~/.claude.json ~/.claude.json.backup

# Add entry safely
jq '. + {"/Users/remigius/swiftbar": {"hasTrustDialogAccepted": true}}' \
   ~/.claude.json > ~/.claude.json.tmp &&
   mv ~/.claude.json.tmp ~/.claude.json
```

1. **Manual with clear instructions**:

Add this to your ~/.claude.json:

```json
"/Users/remigius/swiftbar": {
  "hasTrustDialogAccepted": true
}
```

1. **Interactive script**:

```bash
read -p "Configure ~/.claude.json to suppress trust dialog? [y/N] " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Perform config change with jq
fi
```

---

## Answers to Clarifying Questions

### Q1: Is Homebrew available for Linux? Is it a reasonable compromise vs apt/pacman/dnf?

**Yes, Homebrew works on Linux** (merged Linuxbrew in 2019), and **yes, it's a reasonable compromise** with caveats:

**Adoption**: ~9% of Homebrew users are on Linux (as of 2025). ARM support landed in 2025.

**Key advantages on Linux**:

- Works across ALL distros (Debian, Arch, Fedora, etc.) - no need to maintain separate apt/dnf/pacman packages
- Installs userland apps without system package manager
- Can install newer versions than distro packages
- Users can run alongside native package managers (doesn't replace apt/dnf/pacman)

**Reasonable compromise?**: **Yes for developer tools**, especially if
your target audience is developers who likely already have Homebrew
installed. However:

- Requires Homebrew pre-installed (not default on Linux)
- Native package managers (apt/pacman/dnf) have wider reach on Linux
- For maximum Linux reach, would need separate .deb, .rpm, AUR packages

**Recommendation**: Homebrew is excellent for cross-platform macOS/Linux
developer tooling. For broader Linux reach, supplement with distribution
packages.

### Q2: How is the UX better in Just vs Make? What drives choice between them?

**Just UX improvements over Make**:

1. **No `.PHONY` declarations needed** - recipes are commands by default (eliminates common confusion)
2. **Better error messages** - "specific and informative, syntax errors reported with source context"
3. **Earlier error detection** - "unknown recipes and circular dependencies reported before anything runs"
4. **Recipe arguments** - `just deploy staging` passes args directly to recipes
5. **Automatic .env loading** - no need for external tools
6. **Recipe listing** - `just --list` shows all available commands with descriptions
7. **Fuzzy finder** - interactive selection of recipes (uses fzf)
8. **Multi-language recipes** - write recipes in Python, Node.js, Ruby, etc.
9. **Works from subdirectories** - don't need to be in root directory
10. **Cross-platform** - works identically on Linux/macOS/Windows

**What drives the choice?**:

**Choose Make when**:

- **Universal availability** is critical - Make is pre-installed on virtually all Unix systems
- You need maximum compatibility without extra dependencies
- Team/users may not want to install new tools

**Choose Just when**:

- Better UX is worth the extra install step
- Your users are developers comfortable installing tools
- You want modern features (fuzzy finder, .env support, multi-language recipes)
- You value clearer syntax and better error messages

**Current state (2025)**: Just requires separate installation via
package managers (`brew install just`, `apt install just`, `cargo
install just`, `npm install -g rust-just`). It's NOT installed by
default on any OS.

**Verdict**: Make has **availability advantage**. Just has **UX
advantage**. For your SwiftBar plugin, Make is likely the safer choice
since users already need to install dependencies.

### Q3: Can any option support adding SwiftBar to autostart apps on macOS?

**Yes! Homebrew formulas can handle this** via the `service` block (modern) or `plist` method (legacy).

**Modern approach (recommended)**: Use `service do` block in Homebrew formula

```ruby
service do
  run opt_bin/"swiftbar"
  keep_alive true
end
```

Users then run: `brew services start swiftbar`

This generates a LaunchAgent plist at `~/Library/LaunchAgents/homebrew.mxcl.swiftbar.plist`

**Your installer could**:

1. Check if SwiftBar is already in login items
2. Offer to add it via `brew services start swiftbar` (if installed via Homebrew)
3. Or provide instructions to add manually via System Settings → Login Items

**Implementation in your Homebrew formula**:

```ruby
def post_install
  # Install plugin
  plugin_dir = `defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null`.strip
  if !plugin_dir.empty?
    FileUtils.cp "#{prefix}/claude-usage.5m.sh", "#{plugin_dir}/"
    system "chmod", "+x", "#{plugin_dir}/claude-usage.5m.sh"
  end

  # Optionally prompt user about autostart
  ohai "To start SwiftBar automatically at login:"
  ohai "  brew services start swiftbar"
end
```

**Alternative for non-Homebrew SwiftBar**:

- Use `osascript` to add login item programmatically
- Or provide clear manual instructions

**Conclusion**: Yes, Homebrew formulas can manage autostart via LaunchAgents. This is a standard pattern for services.

### Q4: Can any option support cross-platform installer (macOS/Linux/Windows)?

**Short answer**: Not easily for this specific use case, because **SwiftBar is macOS-only**.

**Long answer - Platform-specific alternatives exist**:

| Platform | Tool                   | Plugin Compatible?    |
| -------- | ---------------------- | --------------------- |
| macOS    | SwiftBar, xbar, BitBar | Yes (same format)     |
| Linux    | Polybar, Waybar        | No (different config) |
| Windows  | No direct equivalent   | N/A                   |

**Cross-platform status bar tool found**: **Zebar** - works on Windows/macOS/Linux

- Part of GlazeWM project
- Customizable desktop widgets and taskbars
- Would require rewriting your plugin

#### Realistic cross-platform approach

##### Option A: Platform detection installer

```bash
# install.sh detects OS and installs appropriate tool
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Install SwiftBar version
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Install Polybar/Waybar version (requires rewrite)
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "Windows not supported"
fi
```

##### Option B: Homebrew with platform guards

```ruby
# Formula with platform checks
class ClaudeUsage < Formula
  desc "Claude usage monitor for menu bar"

  on_macos do
    depends_on "swiftbar"
  end

  on_linux do
    depends_on "polybar"  # Would need Linux version
  end

  def install
    if OS.mac?
      # Install SwiftBar plugin
    elsif OS.linux?
      # Install Polybar config
    end
  end
end
```

##### Option C: Web-based alternative

- Create a web dashboard instead
- Truly cross-platform (browser-based)
- No menu bar integration

#### Recommendation for your use case

Since SwiftBar is macOS-specific:

1. **Primary**: macOS-only installer (Homebrew tap) - focus on where the tool actually works
2. **Future**: Linux version using Polybar/Waybar (separate plugin, different implementation)
3. **Don't try to force cross-platform** - better to do macOS well than all platforms poorly

#### If you must have cross-platform from day one

- Use **Homebrew with platform detection** - works on macOS + Linux (not Windows native)
- Document platform limitations clearly
- Provide platform-specific installation instructions in README

**Tools supporting all three (macOS/Linux/Windows)**:

- **Electron-based system tray apps** (heavy, but truly cross-platform)
- **Zebar** (requires complete rewrite)
- Neither uses your existing bash script approach

**Conclusion**: True cross-platform (macOS/Linux/Windows) would require:

1. Rewriting for different status bar tools per platform, OR
2. Building an Electron app (overkill), OR
3. Using Zebar (new framework)

**Best approach**: Focus on macOS (where SwiftBar works), provide
Homebrew formula that works on macOS + Linux (with platform detection),
document that SwiftBar itself is macOS-only.

## Final Recommendation

**For maximum reach and trust**: Create a **Homebrew Tap** with interactive configuration prompts.

**For simplicity and transparency**: Provide both:

1. A **Makefile** with `make install` (widest compatibility)
2. A **detailed README** with manual installation steps
3. An **optional install script** users can inspect before running

**Hybrid approach** (recommended):

```sh
# Quick install for Homebrew users (macOS/Linux)
brew tap username/claude-usage
brew install claude-usage-swiftbar

# Manual install for others
git clone https://github.com/username/claude-usage-swiftbar
cd claude-usage-swiftbar
make install
# Then follow prompts to configure ~/.claude.json
```

This provides:

- Convenience for Homebrew users (macOS + Linux with Homebrew)
- Transparency for security-conscious users (inspect Makefile/scripts)
- Flexibility for users wanting control
- All open source and commercially free
- Can handle autostart via `brew services` or post-install prompts

---

## Implementation Plan (Approved by User)

### Project Details

- **Repository**: GitHub - `claude-usage-monitor`
- **Platforms**: macOS (SwiftBar) + Linux (Polybar)
- **Distribution**: Homebrew tap with formula

### User Requirements

1. **Repository**: GitHub repository named `claude-usage-monitor`

2. **Platform Support**:
   - macOS: SwiftBar plugin
   - Linux: Polybar module (primary Linux support)
   - Both configs included in repository

3. **Plugin Implementation**:
   - Include both SwiftBar script format (existing)
   - Create Polybar config equivalent (new)
   - Support both syntaxes/formats

4. **~/.claude.json Configuration**:
   - Prompt user for confirmation before modifying
   - Use `jq` for safe JSON manipulation (add as dependency)
   - Create backup before modification
   - Show exactly what will be added

5. **SwiftBar Autostart** (macOS only):
   - Check if already in login items
   - If not, ask user if they want to add it
   - Provide instructions or automate via `osascript`

### Files to Create

1. **Homebrew Formula** (`claude-usage-monitor.rb`)
   - Platform detection (macOS vs Linux)
   - Dependencies: `swiftbar` (macOS), `polybar` (Linux), `jq` (both)
   - Installation logic for each platform
   - Post-install script with interactive prompts

2. **SwiftBar Plugin** (`plugins/swiftbar/claude-usage.5m.sh`)
   - Current script (already exists)

3. **Polybar Module** (`plugins/polybar/claude-usage.sh` + config snippet)
   - Port the logic to Polybar format
   - Provide config snippet for `~/.config/polybar/config.ini`

4. **Installation Helper** (`scripts/configure-claude-json.sh`)
   - Interactive prompt
   - Backup creation
   - Safe jq-based JSON modification

5. **Documentation**:
   - `README.md` - Installation instructions, usage
   - `MANUAL_INSTALL.md` - Detailed manual installation steps
   - `docs/HOMEBREW_TAP.md` - How to create and maintain the tap

### Repository Structure

```plain
claude-usage-monitor/
├── README.md
├── MANUAL_INSTALL.md
├── LICENSE
├── Formula/
│   └── claude-usage-monitor.rb
├── plugins/
│   ├── swiftbar/
│   │   └── claude-usage.5m.sh
│   └── polybar/
│       ├── claude-usage.sh
│       └── config-snippet.ini
├── scripts/
│   ├── configure-claude-json.sh
│   └── setup-swiftbar-autostart.sh
└── docs/
    └── HOMEBREW_TAP.md
```

### Homebrew Tap Setup

- Repository: `github.com/username/homebrew-claude-usage`
- Formula location: `Formula/claude-usage-monitor.rb`
- Installation: `brew tap username/claude-usage && brew install claude-usage-monitor`

---

## Sources

### Package Managers & Distribution

- [Homebrew Documentation - Taps](https://docs.brew.sh/Taps)
- [Creating Homebrew Taps - Beginner's Guide](https://casraf.dev/2025/01/distribute-open-source-tools-with-homebrew-taps-a-beginners-guide/)
- [How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Distributing Scripts via Homebrew](https://justin.searls.co/posts/how-to-distribute-your-own-scripts-via-homebrew/)
- [Homebrew on Linux - Discussion 2025](https://github.com/orgs/Homebrew/discussions/5964)
- [Homebrew on Linux Documentation](https://docs.brew.sh/Homebrew-on-Linux)
- [Linux Package Managers Compared](https://linuxblog.io/linux-package-managers-apt-dnf-pacman-zypper/)

### Installation Script Security

- [Bash Scripting Best Practices 2025](https://medium.com/@prasanna.a1.usage/best-practices-we-need-to-follow-in-bash-scripting-in-2025-cebcdf254768)
- [Secure Shell Scripting Practices](https://www.linuxbash.sh/post/secure-shell-scripting-practices)
- [Bash Shell Script Security Best Practices](https://www.linuxbash.sh/post/bash-shell-script-security-best-practices)
- [curl | bash Security Concerns](https://www.sysdig.com/blog/friends-dont-let-friends-curl-bash)
- [curl bash pipe Security Discussion](https://www.kicksecure.com/wiki/Dev/curl_bash_pipe)

### Task Runners

- [Just - Command Runner](https://github.com/casey/just)
- [Justfile - My Favorite Task Runner](https://tduyng.medium.com/justfile-became-my-favorite-task-runner-7a89e3f45d9a)
- [Just Official Site](https://just.systems/)
- [Make in 2025: DevOps Secret Weapon](https://suyashbhawsar.com/make-in-2025-the-devops-secret-weapon-you-already-have)
- [Task - Simpler Make Alternative](https://github.com/go-task/task)

### Configuration Management

- [chezmoi Documentation](https://www.chezmoi.io/)
- [Why Use chezmoi?](https://www.chezmoi.io/why-use-chezmoi/)
- [Managing Dotfiles with chezmoi](https://stoddart.github.io/2024/09/08/managing-dotfiles-with-chezmoi.html)
- [GNU Stow for Dotfiles](https://www.tusharchauhan.com/writing/dotfile-management-using-gnu-stow/)

### macOS Automation

- [Running at Startup - Login Items vs LaunchAgents](https://eclecticlight.co/2018/05/22/running-at-startup-when-to-use-a-login-item-or-a-launchagent-launchdaemon/)
- [Creating Launch Daemons and Agents - Apple Docs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [maclaunch - Manage macOS Startup Items](https://github.com/hazcod/maclaunch)
- [Homebrew Services - Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Starting Services with Homebrew](https://thoughtbot.com/blog/starting-and-stopping-background-services-with-homebrew)

### SwiftBar & Menu Bar Tools

- [SwiftBar GitHub Repository](https://github.com/swiftbar/SwiftBar)
- [SwiftBar Official Site](https://swiftbar.app/)
- [SwiftBar Alternatives](https://alternativeto.net/software/swiftbar/)
- [Waybar - Wayland Status Bar](https://github.com/Alexays/Waybar)
- [Cross-Platform Status Bar Tools](https://github.com/topics/status-bar?o=desc&s=stars)

### Cross-Platform Installers

- [Zero Install](https://0install.net/)
- [IzPack](https://izpack.org/)
- [Open Source Installer Alternatives](https://alternativeto.net/software/installbuilder/?license=opensource)
