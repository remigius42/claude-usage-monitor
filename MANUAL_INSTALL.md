# Manual Installation Guide

<!-- spellchecker: words elif killall pgrep yourname -->

This guide provides detailed step-by-step instructions for installing Claude Usage Monitor without Homebrew.

## Table of Contents

- [macOS Installation (SwiftBar)](#macos-installation-swiftbar)
- [Linux Installation (Polybar)](#linux-installation-polybar)
- [Configuration](#configuration)
- [Testing](#testing)

---

## macOS Installation (SwiftBar)

### macOS Prerequisites

1. **Install SwiftBar**:

   ```bash
   brew install swiftbar
   # OR download from https://github.com/swiftbar/SwiftBar/releases
   ```

2. **Install dependencies**:

   ```bash
   brew install tmux jq
   ```

3. **Install and authenticate Claude CLI**:

   ```bash
   # Download from https://claude.com/download
   claude auth login
   ```

### macOS Installation Steps

1. **Download the repository**:

   ```bash
   git clone https://github.com/remigius42/claude-usage-monitor.git
   cd claude-usage-monitor
   ```

2. **Get your SwiftBar plugin directory**:

   ```bash
   defaults read com.ameba.SwiftBar PluginDirectory
   ```

   This will output something like: `/Users/yourname/Library/Application Support/SwiftBar`

3. **Copy the plugin to SwiftBar**:

   ```bash
   PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory)
   cp claude-usage.sh "$PLUGIN_DIR/"
   chmod +x "$PLUGIN_DIR/claude-usage.sh"
   ```

   The script auto-detects when running in SwiftBar and uses the correct output format.
   The refresh interval is configured via metadata tags in the script.

4. **Install helper scripts** (optional but recommended):

   ```bash
   sudo cp scripts/configure-claude-json.sh /usr/local/bin/
   sudo cp scripts/setup-swiftbar-autostart-macos.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/configure-claude-json.sh
   sudo chmod +x /usr/local/bin/setup-swiftbar-autostart-macos.sh
   ```

5. **Configure ~/.claude.json**:

   ```bash
   configure-claude-json.sh "$PLUGIN_DIR"
   # OR manually add to ~/.claude.json:
   ```

   Add this entry:

   ```json
   {
     "/Users/yourname/Library/Application Support/SwiftBar": {
       "hasTrustDialogAccepted": true
     }
   }
   ```

6. **Restart SwiftBar**:
   - Quit SwiftBar from the menu bar
   - Relaunch SwiftBar
   - The plugin should appear in your menu bar

7. **(Optional) Set up autostart**:

   ```bash
   setup-swiftbar-autostart-macos.sh
   ```

---

## Linux Installation (Polybar)

### Linux Prerequisites

1. **Install Polybar**:

   ```bash
   # Arch Linux
   sudo pacman -S polybar

   # Ubuntu/Debian
   sudo apt install polybar

   # Fedora
   sudo dnf install polybar

   # Or build from source: https://github.com/polybar/polybar
   ```

2. **Install dependencies**:

   ```bash
   # Arch
   sudo pacman -S tmux jq

   # Ubuntu/Debian
   sudo apt install tmux jq

   # Fedora
   sudo dnf install tmux jq
   ```

3. **Install and authenticate Claude CLI**:

   ```bash
   # Download from https://claude.com/download
   claude auth login
   ```

### Linux Installation Steps

1. **Download the repository**:

   ```bash
   git clone https://github.com/remigius42/claude-usage-monitor.git
   cd claude-usage-monitor
   ```

2. **Create scripts directory**:

   ```bash
   mkdir -p ~/.config/polybar/scripts
   ```

3. **Copy the scripts**:

   ```bash
   cp claude-usage.sh ~/.config/polybar/scripts/
   cp plugins/polybar/claude-usage-polybar.sh ~/.config/polybar/scripts/
   chmod +x ~/.config/polybar/scripts/claude-usage.sh
   chmod +x ~/.config/polybar/scripts/claude-usage-polybar.sh
   ```

4. **Install helper script** (optional):

   ```bash
   sudo cp scripts/configure-claude-json.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/configure-claude-json.sh
   ```

5. **Configure Polybar**:

   Add to `~/.config/polybar/config.ini`:

   ```ini
   [module/claude-usage]
   type = custom/script
   exec = ~/.config/polybar/scripts/claude-usage-polybar.sh
   interval = 30
   label = %output%
   ```

   This uses the wrapper script with click notification support (left/right
   click shows a summary via `notify-send`).

   For direct usage without click support:

   ```ini
   exec = ~/.config/polybar/scripts/claude-usage.sh -o format=" %session_num% |  %week_num%"
   ```

   Then add `claude-usage` to your bar's modules:

   ```ini
   [bar/example]
   modules-right = ... claude-usage
   ```

6. **Configure ~/.claude.json**:

   ```bash
   configure-claude-json.sh ~/.config/polybar/scripts
   # OR manually add to ~/.claude.json:
   ```

   Add this entry:

   ```json
   {
     "/home/yourname/.config/polybar/scripts": {
       "hasTrustDialogAccepted": true
     }
   }
   ```

7. **Restart Polybar**:

   ```bash
   # Kill existing Polybar instances
   killall -q polybar

   # Wait for processes to shut down
   while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

   # Launch Polybar
   polybar example &
   ```

---

## Configuration

### Manual ~/.claude.json Configuration

If you prefer to manually edit `~/.claude.json`:

1. **Backup the file**:

   ```bash
   cp ~/.claude.json ~/.claude.json.backup
   ```

2. **Edit with your favorite editor**:

   ```bash
   nano ~/.claude.json
   # or
   vim ~/.claude.json
   ```

3. **Add the trust entry**:

   For macOS:

   ```json
   {
     "/Users/yourname/Library/Application Support/SwiftBar": {
       "hasTrustDialogAccepted": true
     }
   }
   ```

   For Linux:

   ```json
   {
     "/home/yourname/.config/polybar/scripts": {
       "hasTrustDialogAccepted": true
     }
   }
   ```

4. **Validate JSON syntax**:

   ```bash
   jq empty ~/.claude.json && echo "Valid JSON" || echo "Invalid JSON"
   ```

### Customizing the Script

#### Change Refresh Interval (macOS)

Edit the metadata tag in the script header:

```bash
# <swiftbar.schedule>*/1 * * * *</swiftbar.schedule>
```

Change the cron expression (e.g., `*/5 * * * *` for 5 minutes, `0 * * * *` for hourly).

Restart SwiftBar.

#### Change Refresh Interval (Linux)

Edit `~/.config/polybar/config.ini`:

```ini
[module/claude-usage]
interval = 600  ; 10 minutes instead of default 30s
```

Restart Polybar.

#### Modify Color Thresholds

Edit the main script (`claude-usage.sh`) and adjust these values in the `determine_color` function:

```bash
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory)
vim "$PLUGIN_DIR/claude-usage.sh"  # macOS (SwiftBar plugin directory)
# or
vim ~/.config/polybar/scripts/claude-usage.sh  # Linux (Polybar scripts directory)

# Find the determine_color function:
determine_color() {
    local usage_num="$1"

    if [[ "$usage_num" -lt 50 ]]; then
        echo "#00AA00,#00FF00"  # Green
    elif [[ "$usage_num" -lt 80 ]]; then
        echo "#CC6600,#FF9933"  # Orange
    else
        echo "#CC0000,#FF3333"  # Red
    fi
}
```

---

## Testing

### Test Claude CLI Access

```bash
# Check Claude is installed
claude --version

# Check authentication
claude auth status

# Test usage command manually
claude
# Then type: /usage
```

### Test the Script Directly

**macOS:**

```bash
# Test from the SwiftBar plugins directory
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory)
"$PLUGIN_DIR/claude-usage.sh" -o swiftbar
```

**Linux:**

```bash
~/.config/polybar/scripts/claude-usage.sh -o format="Claude: %session_num% | %week_num%"
```

You should see output like:

- macOS: `🤖 45% | color=green` (followed by menu items)
- Linux: `Claude: 45%`

### Test ~/.claude.json Configuration

```bash
# Check the file exists
ls -la ~/.claude.json

# Validate it's proper JSON
jq . ~/.claude.json

# Check your directory is trusted
jq 'keys' ~/.claude.json
```

### Verify tmux Session

```bash
# List tmux sessions
tmux list-sessions

# You should see: claude-usage-monitor
```

---

## Troubleshooting

### Script Returns Empty Output

1. **Check Claude CLI**:

   ```bash
   which claude
   claude auth status
   ```

2. **Check tmux**:

   ```bash
   which tmux
   tmux -V
   ```

3. **Run script with debug output**:

   ```bash
   bash -x /path/to/claude-usage.sh
   ```

### Permission Denied Errors

```bash
# Make script executable
chmod +x /path/to/claude-usage.sh

# Check file permissions
ls -la /path/to/claude-usage.sh
```

### ~/.claude.json Not Found

```bash
# Run Claude CLI first to create it
claude

# Exit and check if file was created
ls -la ~/.claude.json
```

### macOS: SwiftBar Doesn't Show Plugin

1. **Check plugin directory**:

   ```bash
   defaults read com.ameba.SwiftBar PluginDirectory
   ls -la "$(defaults read com.ameba.SwiftBar PluginDirectory)"
   ```

2. **Check the script contains SwiftBar metadata tags**:

   ```bash
   head -20 "$PLUGIN_DIR/claude-usage.sh" | grep swiftbar
   # Should show: <swiftbar.schedule>*/1 * * * *</swiftbar.schedule>
   ```

3. **Restart SwiftBar**

### Linux: Polybar Module Not Showing

1. **Check Polybar logs**:

   ```bash
   polybar example 2>&1 | grep -i claude
   ```

2. **Test script directly**:

   ```bash
   ~/.config/polybar/scripts/claude-usage.sh
   ```

3. **Check config syntax**:

   ```bash
   polybar --config=~/.config/polybar/config.ini --dry-run example
   ```

---

## Uninstallation

### Uninstall on macOS

```bash
# Remove SwiftBar plugin
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory)
rm "$PLUGIN_DIR/claude-usage.sh"

# Remove helper scripts (if installed globally)
sudo rm /usr/local/bin/configure-claude-json.sh
sudo rm /usr/local/bin/setup-swiftbar-autostart-macos.sh

# Restart SwiftBar
```

### Uninstall on Linux

```bash
# Remove Polybar module
rm ~/.config/polybar/scripts/claude-usage.sh

# Remove from Polybar config
vim ~/.config/polybar/config.ini
# Delete the [module/claude-usage] section
# Remove 'claude-usage' from your bar's modules

# Restart Polybar
killall -q polybar
polybar example &
```

### Clean up ~/.claude.json

```bash
# Backup first
cp ~/.claude.json ~/.claude.json.backup

# Remove the trust entry with jq
jq 'del(."YOUR_PLUGIN_DIRECTORY")' ~/.claude.json > ~/.claude.json.tmp
mv ~/.claude.json.tmp ~/.claude.json
```

---

## Next Steps

- Customize refresh intervals
- Adjust color thresholds
- Create additional modules for other metrics
- Contribute improvements back to the project

For additional help, see [README.md](README.md) or file an issue on GitHub.
