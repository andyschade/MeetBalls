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
    create_mock_command "git" 'mkdir -p "$4" 2>/dev/null; exit 0'

    # Mock meetballs doctor to avoid real dependency checks
    create_mock_command "meetballs" 'echo "Checking dependencies..."; echo "  audio:       MISSING"; echo "Done."'
}

teardown() {
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
    [[ -d "${HOME:-}" && "$HOME" != "$REAL_HOME" ]] && rm -rf "$HOME"
    export HOME="$REAL_HOME"
}

# --- Existing tests ---

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

# --- New: --help flag ---

@test "install.sh --help prints usage and exits 0" {
    run "$PROJECT_ROOT/install.sh" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--uninstall"
    assert_output --partial "WHISPER_CPP_DIR"
}

@test "install.sh -h prints usage and exits 0" {
    run "$PROJECT_ROOT/install.sh" -h
    assert_success
    assert_output --partial "Usage:"
}

# --- New: unknown flag ---

@test "install.sh rejects unknown flags" {
    run "$PROJECT_ROOT/install.sh" --bogus
    assert_failure
    assert_output --partial "Unknown option"
}

# --- New: --uninstall flag ---

@test "install.sh --uninstall removes symlink" {
    # First install
    mkdir -p "$HOME/.local/bin"
    ln -s "$PROJECT_ROOT/bin/meetballs" "$HOME/.local/bin/meetballs"

    run "$PROJECT_ROOT/install.sh" --uninstall
    assert_success
    assert_output --partial "Removed symlink"
    [[ ! -L "$HOME/.local/bin/meetballs" ]]
}

@test "install.sh --uninstall handles missing symlink gracefully" {
    run "$PROJECT_ROOT/install.sh" --uninstall
    assert_success
    assert_output --partial "No symlink found"
}

@test "install.sh --uninstall removes state directory" {
    mkdir -p "$MEETBALLS_DIR/.state"
    echo "some-commit-hash" > "$MEETBALLS_DIR/.state/whisper-stream-commit"

    run "$PROJECT_ROOT/install.sh" --uninstall
    assert_success
    assert_output --partial "Removed state"
    [[ ! -d "$MEETBALLS_DIR/.state" ]]
}

@test "install.sh --uninstall prints system packages note" {
    run "$PROJECT_ROOT/install.sh" --uninstall
    assert_success
    assert_output --partial "whisper-stream, tmux, and other system packages were not removed"
}

# --- New: symlink idempotency ---

@test "install.sh skips symlink when already correct" {
    # First install creates the symlink
    run "$PROJECT_ROOT/install.sh"
    assert_success

    # Second install should detect symlink is already correct
    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "already correct"
}

# --- New: state recording ---

@test "install.sh creates state directory with repo path" {
    run "$PROJECT_ROOT/install.sh"
    assert_success
    [[ -d "$MEETBALLS_DIR/.state" ]]
    [[ -f "$MEETBALLS_DIR/.state/repo-path" ]]
    [[ -f "$MEETBALLS_DIR/.state/installed-at" ]]
}

# --- New: model verification ---

@test "install.sh reports model not found gracefully" {
    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "model:"
}

@test "install.sh detects corrupt model file" {
    # Create a model file that's too small (< 1MB)
    mkdir -p "$HOME/whisper.cpp/models"
    echo "corrupt" > "$HOME/whisper.cpp/models/ggml-base.en.bin"

    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "CORRUPT"
}

@test "install.sh verifies valid model file" {
    # Create a model file that's > 1MB
    mkdir -p "$HOME/whisper.cpp/models"
    truncate -s 142M "$HOME/whisper.cpp/models/ggml-base.en.bin"

    run "$PROJECT_ROOT/install.sh"
    assert_success
    assert_output --partial "model:    OK"
    assert_output --partial "142MB"
}

@test "install.sh records model checksum in state" {
    # Create a valid-sized model file
    mkdir -p "$HOME/whisper.cpp/models"
    truncate -s 2M "$HOME/whisper.cpp/models/ggml-base.en.bin"

    run "$PROJECT_ROOT/install.sh"
    assert_success
    [[ -f "$MEETBALLS_DIR/.state/model-base.en.sha256" ]]
}
