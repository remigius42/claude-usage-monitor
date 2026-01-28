# Shared test helpers for bats tests
# Load with: load 'helpers'

setup() {
    # Get the directory containing this test file
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"

    # Source the script functions without executing main
    # SC1091 - path varies by CWD, can't reliably specify for shellcheck
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/claude-usage.sh" --source-only
}
