#!/usr/bin/env bats
# Tests for lib/ask.sh — ask command (task-07)

load test_helper

# Use a restricted PATH so only mocked commands are found.
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

# Helper: create a fixture transcript file with known content
create_fixture_transcript() {
    local name="${1:-test-transcript.txt}"
    local content="${2:-Alice said we need to ship by Friday. Bob agreed to handle the deployment.}"
    echo "$content" > "$MEETBALLS_DIR/transcripts/$name"
    echo "$MEETBALLS_DIR/transcripts/$name"
}

# Helper: create a mock claude that saves args to a file for assertion
create_mock_claude() {
    create_mock_command "claude" "
# Save all arguments to a file for test assertions
printf '%s\n' \"\$@\" > \"$MOCK_BIN/claude_args.txt\"
echo 'Mock response'
exit 0
"
}

# --- Help ---

@test "ask --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" ask --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "ask"
}

# --- Missing transcript argument ---

@test "ask errors on missing transcript argument" {
    create_mock_claude

    run "$BIN_DIR/meetballs" ask
    assert_failure
    assert_output --partial "transcript"
}

# --- Nonexistent transcript file ---

@test "ask errors on nonexistent transcript file" {
    create_mock_claude

    run "$BIN_DIR/meetballs" ask /fake/path/nonexistent.txt
    assert_failure
    assert_output --partial "not found"
}

# --- Missing claude CLI ---

@test "ask errors when claude CLI not available" {
    local transcript_file
    transcript_file=$(create_fixture_transcript)

    # No mock claude on PATH
    run "$BIN_DIR/meetballs" ask "$transcript_file" "What happened?"
    assert_failure
    assert_output --partial "claude"
}

# --- Single-shot mode ---

@test "single-shot mode calls claude with -p flag and question" {
    local transcript_file
    transcript_file=$(create_fixture_transcript)
    create_mock_claude

    run "$BIN_DIR/meetballs" ask "$transcript_file" "What are the action items?"
    assert_success

    # Verify mock claude received -p flag and the question
    local args_file="$MOCK_BIN/claude_args.txt"
    [ -f "$args_file" ]

    run cat "$args_file"
    assert_output --partial "-p"
    assert_output --partial "What are the action items?"
}

# --- Interactive mode ---

@test "interactive mode calls claude with --append-system-prompt" {
    local transcript_file
    transcript_file=$(create_fixture_transcript)
    create_mock_claude

    run "$BIN_DIR/meetballs" ask "$transcript_file"
    assert_success

    # Verify mock claude received --append-system-prompt
    local args_file="$MOCK_BIN/claude_args.txt"
    [ -f "$args_file" ]

    run cat "$args_file"
    assert_output --partial "--append-system-prompt"
}

# --- System prompt contains transcript content ---

@test "system prompt contains transcript content" {
    local transcript_file
    transcript_file=$(create_fixture_transcript "meeting.txt" "Bob will deploy on Friday")
    create_mock_claude

    run "$BIN_DIR/meetballs" ask "$transcript_file" "What will Bob do?"
    assert_success

    # The system prompt passed to claude should contain the transcript text
    local args_file="$MOCK_BIN/claude_args.txt"
    [ -f "$args_file" ]

    run cat "$args_file"
    assert_output --partial "Bob will deploy on Friday"
}
