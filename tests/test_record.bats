#!/usr/bin/env bats
# Tests for lib/record.sh — record command (task-05)

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

# Helper: create a mock audio backend that creates a WAV file then exits.
# This simulates a short recording that finishes on its own.
# WAV file size: 44 header + (duration_secs * 16000 * 2)
create_mock_recorder() {
    local cmd_name="${1:-pw-record}"
    local duration_secs="${2:-10}"
    local data_size=$(( duration_secs * 16000 * 2 ))
    local file_size=$(( 44 + data_size ))

    create_mock_command "$cmd_name" "
# Find the output file argument (last arg)
output_file=\"\${@: -1}\"
# Create a WAV file of known size
truncate -s $file_size \"\$output_file\"
# Trap SIGTERM to exit cleanly
trap 'exit 0' TERM
# Brief sleep then exit (simulates short recording)
sleep 0.2
"
}

# Helper: create a mock recorder that waits for SIGTERM (for signal tests)
create_mock_recorder_wait() {
    local cmd_name="${1:-pw-record}"
    local duration_secs="${2:-10}"
    local data_size=$(( duration_secs * 16000 * 2 ))
    local file_size=$(( 44 + data_size ))

    create_mock_command "$cmd_name" "
output_file=\"\${@: -1}\"
truncate -s $file_size \"\$output_file\"
trap 'exit 0' TERM INT
while true; do sleep 0.1; done
"
}

# --- Help ---

@test "record --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" record --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "record"
}

# --- No audio backend ---

@test "record errors when no audio backend available" {
    run "$BIN_DIR/meetballs" record
    assert_failure
    assert_output --partial "audio"
}

# --- Successful recording creates WAV file ---

@test "record creates WAV file in recordings directory" {
    create_mock_recorder "pw-record" 10

    run "$BIN_DIR/meetballs" record
    assert_success

    local wav_count
    wav_count=$(find "$MEETBALLS_DIR/recordings" -name '*.wav' | wc -l)
    [ "$wav_count" -eq 1 ]
}

# --- Timestamp-based filename ---

@test "record output file has timestamp-based name" {
    create_mock_recorder "pw-record" 10

    run "$BIN_DIR/meetballs" record
    assert_success

    local wav_file
    wav_file=$(find "$MEETBALLS_DIR/recordings" -name '*.wav' -printf '%f\n')
    [[ "$wav_file" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}\.wav$ ]]
}

# --- Duration printed ---

@test "record prints duration on completion" {
    create_mock_recorder "pw-record" 10

    run "$BIN_DIR/meetballs" record
    assert_success
    assert_output --partial "10s"
}

# --- Prints "Recording..." message ---

@test "record prints Recording message when started" {
    create_mock_recorder "pw-record" 10

    run "$BIN_DIR/meetballs" record
    assert_success
    assert_output --partial "Recording"
}

# --- Prints Saved message with file path ---

@test "record prints Saved with file path on completion" {
    create_mock_recorder "pw-record" 10

    run "$BIN_DIR/meetballs" record
    assert_success
    assert_output --partial "Saved"
    assert_output --partial ".wav"
}

# --- PulseAudio backend works ---

@test "record uses parecord when pw-record unavailable" {
    create_mock_recorder "parecord" 10

    run "$BIN_DIR/meetballs" record
    assert_success

    local wav_count
    wav_count=$(find "$MEETBALLS_DIR/recordings" -name '*.wav' | wc -l)
    [ "$wav_count" -eq 1 ]
}

# --- Low disk space warning ---

@test "record warns on low disk space but continues" {
    create_mock_recorder "pw-record" 10
    # Mock df to report low disk space (100MB = 102400 KB)
    create_mock_command "df" \
        'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 99900000   102400  99% /"'

    run "$BIN_DIR/meetballs" record
    assert_success
    assert_output --partial "disk space"
}
