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

# --- Stderr redirect & loading indicator ---

@test "transcriber.sh redirects whisper-stream stderr to file" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"

    run cat "$session_dir/transcriber.sh"
    assert_output --partial "whisper-stream.stderr"
}

@test "transcriber.sh contains loading model text" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"

    run cat "$session_dir/transcriber.sh"
    assert_output --partial "Loading model"
}

@test "transcriber.sh sources common.sh" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"

    run cat "$session_dir/transcriber.sh"
    assert_output --partial "source"
    assert_output --partial "common.sh"
}

# --- Session logging ---

@test "live creates session log file" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/session.log" ]]
}

@test "live saves session to sessions directory" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    # Should have a session folder under sessions/
    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -d "${session_dirs[0]}" ]]
}

@test "live creates session-state.md in session folder" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -f "${session_dirs[0]}/session-state.md" ]]
}

@test "live copies session log to session folder" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -f "${session_dirs[0]}/session.log" ]]
}

# --- --context flag ---

@test "live --context creates project-context.txt in session dir" {
    setup_live_deps

    local context_file="$MEETBALLS_DIR/README.md"
    echo "# Test Project" > "$context_file"

    run "$BIN_DIR/meetballs" live --context "$context_file"
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/project-context.txt" ]]
    run cat "$session_dir/project-context.txt"
    assert_output --partial "Test Project"
}

@test "live --context asker.sh references project-context.txt" {
    setup_live_deps

    local context_file="$MEETBALLS_DIR/README.md"
    echo "# Test" > "$context_file"

    run "$BIN_DIR/meetballs" live --context "$context_file"
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/asker.sh"
    assert_output --partial "project-context"
}

# --- --save-here flag ---

@test "live --save-here copies session folder to ./meetballs/<session-name>/" {
    setup_live_deps

    local save_dir
    save_dir=$(mktemp -d)
    cd "$save_dir"

    run "$BIN_DIR/meetballs" live --save-here
    assert_success

    # Should have a session subfolder under ./meetballs/
    [[ -d "$save_dir/meetballs" ]]
    local session_subdirs=("$save_dir/meetballs"/*)
    [[ -d "${session_subdirs[0]}" ]]
    # The copied session should contain session-state.md
    [[ -f "${session_subdirs[0]}/session-state.md" ]]
}

# --- Q&A logging ---

# --- Pipeline generation ---

@test "live generates pipeline.sh in session directory" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/pipeline.sh" ]]
    [[ -x "$session_dir/pipeline.sh" ]]
}

@test "pipeline.sh contains stage1_detect function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "stage1_detect"
}

@test "pipeline.sh contains stage2_refine function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "stage2_refine"
}

@test "pipeline.sh has session dir path substituted" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    # Should NOT contain the placeholder
    refute_output --partial "__SESSION_DIR__"
    # Should contain the actual live dir path
    assert_output --partial "$MEETBALLS_DIR/live/"
}

@test "live initializes session-state.md in live dir" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/session-state.md" ]]
}

@test "pipeline.sh contains parse_wake_command function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "parse_wake_command"
}

@test "pipeline.sh contains handle_wake_word function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "handle_wake_word"
}

@test "pipeline.sh contains stage2_wrapup function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "stage2_wrapup"
}

@test "pipeline.sh contains read_initialized function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "read_initialized"
}

@test "session-state.md contains Initialized section" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/session-state.md"
    assert_output --partial "## Initialized"
    assert_output --partial "false"
}

# --- Q&A logging ---

@test "asker.sh contains QA_LOG variable" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/asker.sh"
    assert_output --partial "QA_LOG"
    assert_output --partial "qa.log"
}
