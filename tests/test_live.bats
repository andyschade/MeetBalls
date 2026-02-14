#!/usr/bin/env bats
# Tests for lib/live.sh — live transcription command (task-04)

load test_helper

setup() {
    common_setup
    isolate_path
}

# Helper: set up all deps so cmd_live can run to completion
setup_live_deps() {
    create_mock_command "whisper-stream"
    create_mock_command "claude"
    create_mock_command "pactl"
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session) exit 0 ;;
    *) exit 0 ;;
esac'

    # Create fake whisper model file
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"
}

# --- Help ---

@test "live --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" live --help
    assert_success
    assert_output --partial "Usage:"
}

# --- Dependency validation ---

@test "live missing tmux exits 1 with error" {
    # No tmux mock → missing
    create_mock_command "whisper-stream"
    create_mock_command "claude"

    run "$BIN_DIR/meetballs" live
    assert_failure
    assert_output --partial "tmux"
}

@test "live missing whisper-stream exits 1 with error" {
    create_mock_command "tmux"
    # No whisper-stream mock → missing

    run "$BIN_DIR/meetballs" live
    assert_failure
    assert_output --partial "whisper-stream"
}

@test "live missing claude exits 1 with error" {
    create_mock_command "tmux"
    create_mock_command "whisper-stream"
    # No claude mock → missing

    run "$BIN_DIR/meetballs" live
    assert_failure
    assert_output --partial "claude"
}

@test "live missing model exits 1 with error" {
    create_mock_command "tmux"
    create_mock_command "whisper-stream"
    create_mock_command "claude"
    # No model file, no WHISPER_CPP_MODEL_DIR
    # Set HOME to temp dir to prevent finding the real model on disk
    unset WHISPER_CPP_MODEL_DIR 2>/dev/null || true

    HOME="$MEETBALLS_DIR" run "$BIN_DIR/meetballs" live
    assert_failure
    assert_output --partial "model"
}

# --- Session setup ---

@test "live creates session directory under LIVE_DIR" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    # There should be exactly one timestamped dir under LIVE_DIR
    local session_dirs=("$MEETBALLS_DIR/live"/*)
    [[ -d "${session_dirs[0]}" ]]
}

@test "live generates helper scripts in session directory" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    # Find the session dir
    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"

    [[ -f "$session_dir/transcriber.sh" ]]
    [[ -f "$session_dir/asker.sh" ]]
    [[ -x "$session_dir/transcriber.sh" ]]
    [[ -x "$session_dir/asker.sh" ]]
}

@test "live kills stale session before creating new one" {
    setup_live_deps
    export TMUX_HAS_SESSION_EXIT=0  # Simulate existing session

    run "$BIN_DIR/meetballs" live
    assert_success

    # Verify kill-session was called before new-session
    local calls
    calls=$(<"$MEETBALLS_DIR/.tmux-calls")
    # kill-session should appear before new-session
    local kill_line new_line
    kill_line=$(grep -n "kill-session" <<< "$calls" | head -1 | cut -d: -f1)
    new_line=$(grep -n "new-session" <<< "$calls" | head -1 | cut -d: -f1)
    [[ "$kill_line" -lt "$new_line" ]]
}
