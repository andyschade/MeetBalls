#!/usr/bin/env bats
# Tests for lib/doctor.sh — doctor command (task-03)

load test_helper

# Use a restricted PATH in all tests so only mocked commands are found.
# This prevents real system commands (claude, pw-record, etc.) from
# leaking into "missing dependency" tests.
setup() {
    export MEETBALLS_DIR="$(mktemp -d)"
    mkdir -p "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"

    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:/usr/bin:/bin"
}

teardown() {
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}

# Helper: set up all mocks so doctor passes all core checks
setup_all_deps() {
    create_mock_command "pw-record"
    create_mock_command "whisper-cli"
    create_mock_command "claude"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'

    # Create fake whisper model file
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"
}

# Helper: set up all mocks for both core and live-mode checks
setup_all_deps_with_live() {
    setup_all_deps
    create_mock_command "tmux"
    create_mock_command "whisper-stream"
    create_mock_command "dpkg" \
        'if [[ "$2" == "libsdl2-dev" ]]; then echo "Status: install ok installed"; exit 0; fi; exit 1'
}

# --- Help ---

@test "doctor --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" doctor --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "doctor"
}

# --- All checks pass ---

@test "doctor all deps present shows OK for each and All checks passed" {
    setup_all_deps_with_live

    run "$BIN_DIR/meetballs" doctor
    assert_success
    assert_output --partial "audio"
    assert_output --partial "OK"
    assert_output --partial "whisper-cli"
    assert_output --partial "claude"
    assert_output --partial "disk space"
    assert_output --partial "All checks passed"
}

# --- Missing audio backend ---

@test "doctor missing audio backend shows MISSING and exits 1" {
    create_mock_command "whisper-cli"
    create_mock_command "claude"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "MISSING"
}

# --- Missing whisper-cli ---

@test "doctor missing whisper-cli shows MISSING and exits 1" {
    create_mock_command "pw-record"
    create_mock_command "claude"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "MISSING"
}

# --- Missing whisper model ---

@test "doctor missing whisper model shows MISSING and exits 1" {
    create_mock_command "pw-record"
    create_mock_command "whisper-cli"
    create_mock_command "claude"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'
    # No WHISPER_CPP_MODEL_DIR set, and no model in default locations
    unset WHISPER_CPP_MODEL_DIR 2>/dev/null || true

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "MISSING"
}

# --- Missing claude ---

@test "doctor missing claude shows MISSING and exits 1" {
    create_mock_command "pw-record"
    create_mock_command "whisper-cli"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "MISSING"
}

# --- Disk space reported ---

@test "doctor reports disk space with GB free" {
    setup_all_deps_with_live

    run "$BIN_DIR/meetballs" doctor
    assert_success
    assert_output --partial "GB free"
}

# --- Low disk space ---

@test "doctor low disk space shows LOW and exits 1" {
    create_mock_command "pw-record"
    create_mock_command "whisper-cli"
    create_mock_command "claude"
    # Only 100MB free (102400 KB)
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 99900000   102400  99% /"'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "LOW"
}

# --- Exit code 0 only when all pass ---

@test "doctor exits 0 only when all checks pass" {
    setup_all_deps_with_live

    run "$BIN_DIR/meetballs" doctor
    assert_success
}

# --- Live mode section ---

@test "doctor shows Live mode section when all deps present" {
    setup_all_deps_with_live

    run "$BIN_DIR/meetballs" doctor
    assert_success
    assert_output --partial "Live mode:"
    assert_output --partial "tmux"
    assert_output --partial "whisper-stream"
    assert_output --partial "libsdl2"
    assert_output --partial "All checks passed"
}

@test "doctor core-only failure still exits 1 even with live deps present" {
    # All live deps present, but missing whisper-cli (core dep)
    create_mock_command "pw-record"
    create_mock_command "claude"
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000 10485760  50% /"'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"
    # Live deps present
    create_mock_command "tmux"
    create_mock_command "whisper-stream"
    create_mock_command "dpkg" \
        'if [[ "$2" == "libsdl2-dev" ]]; then echo "Status: install ok installed"; exit 0; fi; exit 1'
    # whisper-cli NOT mocked → core failure

    run "$BIN_DIR/meetballs" doctor
    assert_failure
    assert_output --partial "check(s) failed"
}

@test "doctor live-only failure exits 0 with warning" {
    # Use an isolated PATH that excludes /usr/bin to prevent real tmux/dpkg
    local ISOLATED_BIN="$(mktemp -d)"
    # Link basic utilities needed by doctor into isolated bin
    ln -s /usr/bin/awk "$ISOLATED_BIN/awk"
    ln -s /usr/bin/basename "$ISOLATED_BIN/basename"
    export PATH="$MOCK_BIN:$ISOLATED_BIN:/bin"

    # All core deps present
    setup_all_deps
    # whisper-stream present, but tmux and dpkg NOT present (not mocked, not on PATH)
    create_mock_command "whisper-stream"

    run "$BIN_DIR/meetballs" doctor
    assert_success
    assert_output --partial "Live mode:"
    assert_output --partial "MISSING"
    assert_output --partial "live-mode"

    rm -rf "$ISOLATED_BIN"
}
