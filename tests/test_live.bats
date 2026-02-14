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

# --- Speaker diarization ---

@test "live stores diarize-tier.txt in session directory" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/diarize-tier.txt" ]]
}

@test "live logs diarization tier" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/session.log"
    assert_output --partial "diarization tier:"
}

@test "transcriber.sh includes --tinydiarize when tier is tinydiarize" {
    setup_live_deps
    # Override whisper-stream mock to report tinydiarize support
    create_mock_command "whisper-stream" 'echo "  --tinydiarize     [false  ] enable tinydiarize"'

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/transcriber.sh"
    assert_output --partial "--tinydiarize"
}

@test "transcriber.sh omits --tinydiarize when tier is llm-fallback" {
    setup_live_deps
    # Default whisper-stream mock doesn't report tinydiarize support

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/transcriber.sh"
    refute_output --partial "--tinydiarize"
}

# --- Q&A logging ---

# --- Session end: duration ---

@test "live calculates duration and caches in session-state.md" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    local session_dir="${session_dirs[0]}"
    [[ -f "$session_dir/session-state.md" ]]
    # Duration section should have a value (not empty)
    run grep -A1 "## Duration" "$session_dir/session-state.md"
    assert_success
    # Should contain a formatted duration (e.g., "0s", "1m00s", etc.)
    assert_output --partial "s"
}

@test "live logs session duration" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    run cat "${session_dirs[0]}/session.log"
    assert_output --partial "session duration:"
}

# --- Session end: summary generation ---

@test "live generates summary.txt when transcript exists" {
    setup_live_deps
    create_mock_command "claude" 'echo "Meeting summary: test discussion."'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Hello this is a test meeting" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -f "${session_dirs[0]}/summary.txt" ]]
}

@test "live skips summary generation if summary.txt already exists" {
    setup_live_deps
    create_mock_command "claude" 'echo "LLM output"'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test transcript" > "${_live_dirs[0]}/transcript.txt"
            echo "Existing summary from wrap-up" > "${_live_dirs[0]}/summary.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    # Summary should be the one from wrap-up, not regenerated
    run cat "${session_dirs[0]}/summary.txt"
    assert_output --partial "Existing summary from wrap-up"
}

# --- Session end: LLM naming ---

@test "live renames session folder with descriptive name from LLM" {
    setup_live_deps
    create_mock_command "claude" 'echo "andy-sarah-deployment-planning"'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test meeting transcript" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    # Session folder should have a descriptive name, not just a timestamp
    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    local session_name
    session_name=$(basename "${session_dirs[0]}")
    # Should contain the LLM-generated slug
    [[ "$session_name" == *"andy-sarah-deployment-planning"* ]]
}

@test "live session name contains date prefix" {
    setup_live_deps
    create_mock_command "claude" 'echo "andy-sarah-sprint-retro"'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test transcript content" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    local session_name
    session_name=$(basename "${session_dirs[0]}")
    # Should start with date prefix pattern: mon<d>-yy-HHMM
    # e.g., feb14-26-1530-andy-sarah-sprint-retro
    [[ "$session_name" =~ ^[a-z]{3}[0-9]+-[0-9]{2}-[0-9]{4}- ]]
}

@test "live falls back to timestamp name on LLM failure" {
    setup_live_deps
    create_mock_command "claude" 'exit 1'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test transcript content" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    # Session folder should still exist (timestamp-based name)
    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -d "${session_dirs[0]}" ]]
    # Name should be a timestamp pattern (YYYY-MM-DDTHH-MM-SS)
    local session_name
    session_name=$(basename "${session_dirs[0]}")
    [[ "$session_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

@test "live --save-here uses descriptive session name" {
    setup_live_deps
    create_mock_command "claude" 'echo "andy-sarah-api-review"'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test transcript" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    local save_dir
    save_dir=$(mktemp -d)
    cd "$save_dir"

    run "$BIN_DIR/meetballs" live --save-here
    assert_success

    # The CWD copy should use the descriptive name
    local copy_dirs=("$save_dir/meetballs"/*)
    local copy_name
    copy_name=$(basename "${copy_dirs[0]}")
    [[ "$copy_name" == *"andy-sarah-api-review"* ]]
}

@test "live prints descriptive session path on save" {
    setup_live_deps
    create_mock_command "claude" 'echo "andy-sarah-standup"'
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test transcript" > "${_live_dirs[0]}/transcript.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    # Output should show the descriptive name, not just a timestamp
    assert_output --partial "andy-sarah-standup"
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

# --- Q&A pane notifications ---

@test "pipeline.sh contains NOTIFY_FILE variable" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "NOTIFY_FILE"
    assert_output --partial "qa-notifications.txt"
}

@test "pipeline.sh contains notify function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "notify()"
}

@test "pipeline.sh contains stage2_notify function" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "stage2_notify"
}

@test "pipeline.sh generates action item notifications" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Action Item:"
}

@test "pipeline.sh generates decision notifications" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Decision:"
}

@test "pipeline.sh generates speaker notifications" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Speakers:"
}

@test "pipeline.sh generates agenda notifications" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Agenda:"
}

@test "pipeline.sh generates wrap-up notification" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Wrap-up summary generated"
}

@test "pipeline.sh generates clarification for missing speakers" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Could you reintroduce the speakers?"
}

@test "pipeline.sh generates clarification for missing agenda" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "Could you restate the agenda?"
}

@test "pipeline.sh generates unknown wake word clarification" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/pipeline.sh"
    assert_output --partial "What hat would you like me to wear"
}

@test "asker.sh contains notification watcher" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/asker.sh"
    assert_output --partial "NOTIFY_FILE"
    assert_output --partial "qa-notifications.txt"
}

@test "asker.sh starts background tail -f on notifications file" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/asker.sh"
    assert_output --partial "tail -f"
    assert_output --partial "NOTIFY_FILE"
}

@test "asker.sh cleans up notification watcher on exit" {
    setup_live_deps

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/live"/*)
    local session_dir="${session_dirs[0]}"
    run cat "$session_dir/asker.sh"
    assert_output --partial "_NOTIFY_PID"
    assert_output --partial "trap"
}

@test "live copies qa-notifications.txt to session folder" {
    setup_live_deps
    create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session)
        _live_dirs=("$MEETBALLS_DIR/live"/*)
        if [[ -d "${_live_dirs[0]}" ]]; then
            echo "Test notification" > "${_live_dirs[0]}/qa-notifications.txt"
        fi
        exit 0
        ;;
    *) exit 0 ;;
esac'

    run "$BIN_DIR/meetballs" live
    assert_success

    local session_dirs=("$MEETBALLS_DIR/sessions"/*)
    [[ -f "${session_dirs[0]}/qa-notifications.txt" ]]
}
