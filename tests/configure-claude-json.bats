#!/usr/bin/env bats

# spellchecker: ignore mktemp

bats_require_minimum_version 1.5.0

# Tests for scripts/configure-claude-json.sh jq merge logic
# Run with: bats tests/configure-claude-json.bats

setup() {
    TEST_JSON="$(mktemp)"
}

teardown() {
    rm -f "$TEST_JSON"
}

# --- jq recursive merge preserves existing properties ---

@test "jq merge preserves existing properties in directory object" {
    cat > "$TEST_JSON" <<'EOF'
{
  "/home/user/swiftbar": {
    "hasTrustDialogAccepted": true,
    "customSetting": "keep-me"
  }
}
EOF

    result=$(jq --arg dir "/home/user/swiftbar" \
       '. * {($dir): {"hasTrustDialogAccepted": true}}' \
       "$TEST_JSON")

    # customSetting must survive the merge
    echo "$result" | jq -e '.["/home/user/swiftbar"].customSetting == "keep-me"'
    echo "$result" | jq -e '.["/home/user/swiftbar"].hasTrustDialogAccepted == true'
}

@test "jq merge adds new directory without affecting existing entries" {
    cat > "$TEST_JSON" <<'EOF'
{
  "/home/user/existing": {
    "hasTrustDialogAccepted": true
  }
}
EOF

    result=$(jq --arg dir "/home/user/new-dir" \
       '. * {($dir): {"hasTrustDialogAccepted": true}}' \
       "$TEST_JSON")

    echo "$result" | jq -e '.["/home/user/existing"].hasTrustDialogAccepted == true'
    echo "$result" | jq -e '.["/home/user/new-dir"].hasTrustDialogAccepted == true'
}

@test "jq merge updates hasTrustDialogAccepted from false to true" {
    cat > "$TEST_JSON" <<'EOF'
{
  "/home/user/swiftbar": {
    "hasTrustDialogAccepted": false
  }
}
EOF

    result=$(jq --arg dir "/home/user/swiftbar" \
       '. * {($dir): {"hasTrustDialogAccepted": true}}' \
       "$TEST_JSON")

    echo "$result" | jq -e '.["/home/user/swiftbar"].hasTrustDialogAccepted == true'
}
