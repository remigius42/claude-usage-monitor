# Contributing to the Homebrew Tap

This tap is maintained via git subtree from the
[main repository](https://github.com/remigius42/claude-usage-monitor).

## Repository Structure

This tap is published from the `homebrew/` folder of the main repository using
git subtree. Do not edit this repository directly—make changes in the main
repository instead.

```text
Main repo: claude-usage-monitor/homebrew/  →  This repo: homebrew-claude-usage-monitor/
```

## Updating the Tap (Maintainers)

From the main repository:

```bash
# One-time setup: add tap repo as remote
git remote add homebrew-tap git@github.com:remigius42/homebrew-claude-usage-monitor.git

# Push changes to tap repo
git subtree push --prefix=homebrew homebrew-tap main
```

## Publishing a New Release

### 1. Tag a Release in Main Repository

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### 2. Create GitHub Release

1. Go to the main repository releases page
2. Choose the tag
3. Add release notes
4. Publish release

This creates a tarball at:
`https://github.com/remigius42/claude-usage-monitor/archive/v1.0.0.tar.gz`

### 3. Calculate SHA256

```bash
curl -fsSL https://github.com/remigius42/claude-usage-monitor/archive/v1.0.0.tar.gz \
  | shasum -a 256
```

### 4. Update Formula

Edit `homebrew/Formula/claude-usage-monitor.rb` in the main repository:

```ruby
url "https://github.com/remigius42/claude-usage-monitor/archive/v1.0.0.tar.gz"
sha256 "calculated_sha256_here"
```

### 5. Push to Tap

```bash
git commit -am "Update claude-usage-monitor to v1.0.0"
git push origin main
git subtree push --prefix=homebrew homebrew-tap main
```

## Testing the Formula

Before pushing updates:

```bash
# Audit formula
brew audit --strict homebrew/Formula/claude-usage-monitor.rb

# Test installation locally
brew install --build-from-source homebrew/Formula/claude-usage-monitor.rb

# Test uninstall
brew uninstall claude-usage-monitor
```

## Common Issues

### SHA256 Mismatch

Recalculate the hash:

```bash
curl -fsSL <tarball-url> | shasum -a 256
```

### Formula Install Fails

Verify paths in the tarball match the formula's `install` method:

```bash
curl -fsSL <tarball-url> | tar -tz
```

## Resources

- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Formula Ruby API](https://rubydoc.brew.sh/Formula)
