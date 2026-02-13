#!/usr/bin/env bats
# Tests for lib/list.sh — list command (task-04)

load test_helper

# Helper: create a minimal WAV file with known duration
# WAV 16kHz mono 16-bit: data_size = duration_secs * 16000 * 2
# Total file size = 44 (header) + data_size
create_wav_fixture() {
    local filename="$1"
    local duration_secs="$2"
    local data_size=$(( duration_secs * 16000 * 2 ))
    local file_size=$(( 44 + data_size ))

    # Use truncate for instant file creation at the correct size
    truncate -s "$file_size" "$MEETBALLS_DIR/recordings/$filename"
}

# --- Help ---

@test "list --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" list --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "list"
}

# --- No recordings ---

@test "list with no recordings prints no recordings message" {
    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "No recordings"
}

# --- Recordings listed with filenames ---

@test "list shows recording filenames in output" {
    create_wav_fixture "2026-02-10T09-00-00.wav" 60
    create_wav_fixture "2026-02-11T14-30-00.wav" 120

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "2026-02-10T09-00-00.wav"
    assert_output --partial "2026-02-11T14-30-00.wav"
}

# --- Table header ---

@test "list output contains table header columns" {
    create_wav_fixture "2026-02-10T09-00-00.wav" 10

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "RECORDING"
    assert_output --partial "DURATION"
    assert_output --partial "TRANSCRIPT"
}

# --- Transcript status yes ---

@test "list shows yes for recording with transcript" {
    create_wav_fixture "2026-02-10T09-00-00.wav" 60
    echo "some transcript text" > "$MEETBALLS_DIR/transcripts/2026-02-10T09-00-00.txt"

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "yes"
}

# --- Transcript status no ---

@test "list shows no for recording without transcript" {
    create_wav_fixture "2026-02-10T09-00-00.wav" 60

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "no"
}

# --- Duration displayed ---

@test "list shows correct duration for known-size WAV" {
    # 2712 seconds = 45m12s
    create_wav_fixture "2026-02-12T14-30-00.wav" 2712

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "45m12s"
}

# --- Duration for longer recording ---

@test "list shows hour-format duration for long recording" {
    # 3720 seconds = 1h02m00s
    create_wav_fixture "2026-02-11T09-00-00.wav" 3720

    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "1h02m00s"
}

# --- Sorted order ---

@test "list shows recordings sorted chronologically" {
    create_wav_fixture "2026-02-11T14-30-00.wav" 60
    create_wav_fixture "2026-02-10T09-00-00.wav" 60

    run "$BIN_DIR/meetballs" list
    assert_success
    # First filename should appear before the second in output
    local first_pos second_pos
    first_pos=$(echo "$output" | grep -n "2026-02-10" | head -1 | cut -d: -f1)
    second_pos=$(echo "$output" | grep -n "2026-02-11" | head -1 | cut -d: -f1)
    [ "$first_pos" -lt "$second_pos" ]
}
