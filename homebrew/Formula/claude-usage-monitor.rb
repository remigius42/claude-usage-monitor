# Homebrew Formula for Claude Usage Monitor
# Install with: brew install claude-usage-monitor

# spellchecker: ignore opoo

class ClaudeUsageMonitor < Formula
  desc "Monitor Claude API usage in your menu bar (SwiftBar/Polybar)"
  homepage "https://github.com/remigius42/claude-usage-monitor"
  url "https://github.com/remigius42/claude-usage-monitor/archive/v1.0.0.tar.gz"
  sha256 "YOUR_SHA256_HERE"
  license "MIT"

  # Platform-specific dependencies
  on_macos do
    depends_on "swiftbar"
  end

  on_linux do
    depends_on "polybar"
  end

  # Common dependencies
  depends_on "bc"
  depends_on "jq"
  depends_on "tmux"

  def install
    if OS.mac?
      # Install main script to share (will be copied to SwiftBar plugins in post_install)
      # SwiftBar auto-detects and uses correct format via SWIFTBAR=1 env var
      (share/"swiftbar-plugins").install "claude-usage.sh"

      # Install helper scripts
      bin.install "scripts/configure-claude-json.sh"
      bin.install "scripts/setup-swiftbar-autostart-macos.sh"

    elsif OS.linux?
      # Install main script to bin for Polybar to call
      bin.install "claude-usage.sh"

      # Install Polybar config snippet
      (share/"polybar-modules").install "plugins/polybar/config-snippet.ini"

      # Install helper scripts
      bin.install "scripts/configure-claude-json.sh"
    end

    # Install documentation
    doc.install "README.md"
    doc.install "MANUAL_INSTALL.md"
  end

  def post_install
    if OS.mac?
      post_install_macos
    elsif OS.linux?
      post_install_linux
    end
  end

  def prompt_yes_no(question)
    print "#{question} [y/N] "
    response = $stdin.gets.chomp.downcase
    response == 'y' || response == 'yes'
  end

  def post_install_macos
    ohai "Claude Usage Monitor installed!"
    puts

    # Get SwiftBar plugin directory
    plugin_dir = `defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null`.strip

    if plugin_dir.empty?
      opoo "SwiftBar plugin directory not found."
      puts "Please set up SwiftBar first, then manually copy:"
      puts "  #{share}/swiftbar-plugins/claude-usage.sh"
      puts "  to your SwiftBar plugin directory"
    else
      # Copy plugin to SwiftBar directory
      FileUtils.cp "#{share}/swiftbar-plugins/claude-usage.sh", "#{plugin_dir}/"
      FileUtils.chmod 0755, "#{plugin_dir}/claude-usage.sh"
      ohai "✓ Installed SwiftBar plugin to #{plugin_dir}"
    end

    puts
    puts "=" * 70
    puts "CONFIGURATION REQUIRED"
    puts "=" * 70
    puts
    puts "1. Configure ~/.claude.json to suppress trust dialog:"
    puts "   Run: #{bin}/configure-claude-json.sh"
    puts
    puts "2. (Optional) Set up SwiftBar to start automatically at login:"
    puts "   Run: #{bin}/setup-swiftbar-autostart-macos.sh"
    puts
    puts "=" * 70
    puts

    if prompt_yes_no("Would you like to configure ~/.claude.json now?")
      system "#{bin}/configure-claude-json.sh", plugin_dir
    end

    puts
    if prompt_yes_no("Would you like to set up SwiftBar autostart now?")
      system "#{bin}/setup-swiftbar-autostart-macos.sh"
    end
  end

  def post_install_linux
    ohai "Claude Usage Monitor installed!"
    puts
    puts "=" * 70
    puts "POLYBAR CONFIGURATION"
    puts "=" * 70
    puts
    puts "1. Add the following to your ~/.config/polybar/config.ini:"
    puts
    puts File.read("#{share}/polybar-modules/config-snippet.ini")
    puts
    puts "2. Configure ~/.claude.json to suppress trust dialog:"
    puts "   Run: #{bin}/configure-claude-json.sh"
    puts
    puts "=" * 70
    puts

    if prompt_yes_no("Would you like to configure ~/.claude.json now?")
      system "#{bin}/configure-claude-json.sh", ENV['HOME']
    end
  end

  def caveats
    if OS.mac?
      <<~EOS
        SwiftBar plugin installed to your SwiftBar plugins directory.

        The plugin requires:
        1. Claude CLI installed and authenticated
        2. Configuration in ~/.claude.json (run configure-claude-json.sh)
        3. SwiftBar running (optionally set to start at login)

        To refresh the plugin manually, click the menu bar item and select "Refresh".
        The plugin auto-refreshes every 30 seconds.
      EOS
    elsif OS.linux?
      <<~EOS
        Polybar module files installed to #{share}/polybar-modules/

        To use:
        1. Add the config snippet to your ~/.config/polybar/config.ini
        2. Configure ~/.claude.json (run configure-claude-json.sh)
        3. Restart Polybar

        The module auto-updates based on your Polybar configuration.
      EOS
    end
  end

  test do
    # Test that helper scripts are executable
    assert_predicate bin/"configure-claude-json.sh", :executable?

    if OS.mac?
      assert_predicate bin/"setup-swiftbar-autostart-macos.sh", :executable?
      assert_predicate share/"swiftbar-plugins/claude-usage.sh", :exist?
    elsif OS.linux?
      assert_predicate bin/"claude-usage.sh", :executable?
      assert_predicate share/"polybar-modules/config-snippet.ini", :exist?
    end
  end
end
