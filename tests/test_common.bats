#!/usr/bin/env bats

load test_helper

setup() {
    # Call parent setup for MEETBALLS_DIR and MOCK_BIN isolation
    export MEETBALLS_DIR="$(mktemp -d)"
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"

    # Source common.sh
    source "$LIB_DIR/common.sh"
}

teardown() {
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}

# --- Constants ---

@test "MEETBALLS_DIR respects env override" {
    # It should NOT be $HOME/.meetballs since we set it in setup
    [[ "$MEETBALLS_DIR" != "$HOME/.meetballs" ]]
}

@test "RECORDINGS_DIR is MEETBALLS_DIR/recordings" {
    assert_equal "$RECORDINGS_DIR" "$MEETBALLS_DIR/recordings"
}

@test "TRANSCRIPTS_DIR is MEETBALLS_DIR/transcripts" {
    assert_equal "$TRANSCRIPTS_DIR" "$MEETBALLS_DIR/transcripts"
}

@test "WHISPER_MODEL defaults to base.en" {
    assert_equal "$WHISPER_MODEL" "base.en"
}

@test "MIN_DISK_MB is 500" {
    assert_equal "$MIN_DISK_MB" "500"
}

# --- mb_init ---

@test "mb_init creates recordings and transcripts directories" {
    # Remove dirs created by setup to test mb_init
    rm -rf "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"
    [ ! -d "$MEETBALLS_DIR/recordings" ]
    [ ! -d "$MEETBALLS_DIR/transcripts" ]

    mb_init

    [ -d "$MEETBALLS_DIR/recordings" ]
    [ -d "$MEETBALLS_DIR/transcripts" ]
}

@test "mb_init is idempotent" {
    mb_init
    mb_init
    [ -d "$MEETBALLS_DIR/recordings" ]
    [ -d "$MEETBALLS_DIR/transcripts" ]
}

# --- mb_format_duration ---

@test "mb_format_duration 0 returns 0s" {
    run mb_format_duration 0
    assert_output "0s"
}

@test "mb_format_duration 45 returns 45s" {
    run mb_format_duration 45
    assert_output "45s"
}

@test "mb_format_duration 90 returns 1m30s" {
    run mb_format_duration 90
    assert_output "1m30s"
}

@test "mb_format_duration 2712 returns 45m12s" {
    run mb_format_duration 2712
    assert_output "45m12s"
}

@test "mb_format_duration 3720 returns 1h02m00s" {
    run mb_format_duration 3720
    assert_output "1h02m00s"
}

@test "mb_format_duration 7200 returns 2h00m00s" {
    run mb_format_duration 7200
    assert_output "2h00m00s"
}

# --- mb_timestamp ---

@test "mb_timestamp matches YYYY-MM-DDTHH-MM-SS format" {
    run mb_timestamp
    assert_success
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}$'
}

# --- mb_recording_dir / mb_transcript_dir ---

@test "mb_recording_dir echoes RECORDINGS_DIR" {
    run mb_recording_dir
    assert_output "$MEETBALLS_DIR/recordings"
}

@test "mb_transcript_dir echoes TRANSCRIPTS_DIR" {
    run mb_transcript_dir
    assert_output "$MEETBALLS_DIR/transcripts"
}

# --- mb_check_command ---

@test "mb_check_command returns 0 for existing command" {
    run mb_check_command bash
    assert_success
}

@test "mb_check_command returns 1 for missing command" {
    run mb_check_command nonexistent_command_xyz
    assert_failure
}

# --- mb_detect_audio_backend ---

@test "mb_detect_audio_backend returns pw-record when all available" {
    create_mock_command "pw-record"
    create_mock_command "parecord"
    create_mock_command "arecord"

    run mb_detect_audio_backend
    assert_success
    assert_output "pw-record"
}

@test "mb_detect_audio_backend returns parecord when no pw-record" {
    create_mock_command "parecord"
    create_mock_command "arecord"

    run mb_detect_audio_backend
    assert_success
    assert_output "parecord"
}

@test "mb_detect_audio_backend returns arecord as last fallback" {
    create_mock_command "arecord"

    run mb_detect_audio_backend
    assert_success
    assert_output "arecord"
}

@test "mb_detect_audio_backend returns 1 when none available" {
    run mb_detect_audio_backend
    assert_failure
}

# --- mb_check_disk_space ---

@test "mb_check_disk_space succeeds with sufficient space" {
    # Mock df to report plenty of space (1GB = 1048576 KB)
    create_mock_command "df" 'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 50000000  1048576  50% /"'

    run mb_check_disk_space
    assert_success
}

@test "mb_check_disk_space warns with low space" {
    # Mock df to report only 100MB free (102400 KB)
    create_mock_command "df" 'echo "Filesystem     1K-blocks    Used Available Use% Mounted on"; echo "/dev/sda1      100000000 99900000   102400  99% /"'

    run mb_check_disk_space
    assert_failure
}

# --- Messaging functions ---

@test "mb_info prints message" {
    run mb_info "test message"
    assert_output "test message"
}

@test "mb_success prints message" {
    run mb_success "done"
    assert_output --partial "done"
}

@test "mb_warn prints to stderr" {
    run mb_warn "warning msg"
    assert_output --partial "warning msg"
}

@test "mb_error prints to stderr" {
    run mb_error "error msg"
    assert_output --partial "error msg"
}

@test "mb_die prints error and exits 1" {
    run mb_die "fatal error"
    assert_failure
    assert_output --partial "fatal error"
}
