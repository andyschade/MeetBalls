#!/usr/bin/env bash
# Shared test setup for MeetBalls bats tests

# Resolve project root relative to this file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
BIN_DIR="$PROJECT_ROOT/bin"

# Load bats libraries
load "$TEST_DIR/libs/bats-support/load"
load "$TEST_DIR/libs/bats-assert/load"

setup() {
    # Create isolated temp directory for MEETBALLS_DIR
    export MEETBALLS_DIR="$(mktemp -d)"
    mkdir -p "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"

    # Create temp directory for mock commands
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    # Clean up temp directories
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}

# Helper: create a mock command in MOCK_BIN
# Usage: create_mock_command "command_name" "script_body"
create_mock_command() {
    local name="$1"
    local body="${2:-exit 0}"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$MOCK_BIN/$name"
}
