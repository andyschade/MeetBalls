#!/usr/bin/env bats
# Tests for install.sh

load test_helper

setup() {
    # Create isolated temp directory for MEETBALLS_DIR
    export MEETBALLS_DIR="$(mktemp -d)"
    mkdir -p "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"

    # Create temp directory for mock commands
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"

    # Create a fake HOME to avoid touching real ~/.local/bin
    export REAL_HOME="$HOME"
    export HOME="$(mktemp -d)"

    # Mock git to avoid actual cloning
    create_mock_command "git" 'mkdir -p "$4"'

    # Mock meetballs doctor to avoid real dependency checks
    create_mock_command "meetballs" 'echo "Checking dependencies..."; echo "  audio:       MISSING"; echo "Done."'
}

teardown() {
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
    [[ -d "${HOME:-}" && "$HOME" != "$REAL_HOME" ]] && rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

@test "install.sh exists and is executable" {
    [[ -x "$PROJECT_ROOT/install.sh" ]]
}

@test "install.sh checks bash version" {
    # The script should contain a bash version check
    run grep -q "BASH_VERSINFO\|bash.*version\|bash.*4" "$PROJECT_ROOT/install.sh"
    assert_success
}

@test "install.sh creates ~/.local/bin directory" {
    [[ ! -d "$HOME/.local/bin" ]]
    run "$PROJECT_ROOT/install.sh"
    assert_success
    [[ -d "$HOME/.local/bin" ]]
}

@test "install.sh creates symlink to bin/meetballs" {
    run "$PROJECT_ROOT/install.sh"
    assert_success
    [[ -L "$HOME/.local/bin/meetballs" ]]
    local target
    target=$(readlink -f "$HOME/.local/bin/meetballs")
    [[ "$target" == "$(readlink -f "$PROJECT_ROOT/bin/meetballs")" ]]
}

@test "install.sh updates existing symlink" {
    # Create a stale symlink
    mkdir -p "$HOME/.local/bin"
    ln -s /nonexistent/path "$HOME/.local/bin/meetballs"

    run "$PROJECT_ROOT/install.sh"
    assert_success

    # Symlink should now point to the real bin/meetballs
    local target
    target=$(readlink -f "$HOME/.local/bin/meetballs")
    [[ "$target" == "$(readlink -f "$PROJECT_ROOT/bin/meetballs")" ]]
}

@test "install.sh warns when ~/.local/bin not in PATH" {
    # Remove ~/.local/bin from PATH (it shouldn't be there anyway with fake HOME)
    export PATH="$MOCK_BIN:/usr/bin:/bin"

    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "PATH"
}

@test "install.sh is idempotent" {
    run "$PROJECT_ROOT/install.sh"
    assert_success

    # Run again — should still succeed
    run "$PROJECT_ROOT/install.sh"
    assert_success
}

@test "install.sh runs meetballs doctor" {
    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "Checking dependencies"
}

@test "install.sh skips bats install if already present" {
    # Pre-create bats dirs to simulate already installed
    mkdir -p "$PROJECT_ROOT/tests/libs/bats"
    mkdir -p "$PROJECT_ROOT/tests/libs/bats-support"
    mkdir -p "$PROJECT_ROOT/tests/libs/bats-assert"

    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "already installed"
}
