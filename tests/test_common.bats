#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    source "$LIB_DIR/common.sh"
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

# --- mb_check_command ---

@test "mb_check_command returns 0 for existing command" {
    run mb_check_command bash
    assert_success
}

@test "mb_check_command returns 1 for missing command" {
    run mb_check_command nonexistent_command_xyz
    assert_failure
}

# --- mb_require_command ---

@test "mb_require_command succeeds for existing command" {
    run mb_require_command bash "should not see this"
    assert_success
}

@test "mb_require_command dies for missing command" {
    run mb_require_command nonexistent_xyz "Install from example.com"
    assert_failure
    assert_output --partial "nonexistent_xyz not found"
    assert_output --partial "Install from example.com"
}

# --- mb_require_file ---

@test "mb_require_file succeeds for existing file" {
    local tmpfile="$MEETBALLS_DIR/testfile.txt"
    touch "$tmpfile"
    run mb_require_file "$tmpfile" "Test file"
    assert_success
}

@test "mb_require_file dies for missing file" {
    run mb_require_file "/nonexistent/path.txt" "Config file"
    assert_failure
    assert_output --partial "Config file not found"
    assert_output --partial "/nonexistent/path.txt"
}

# --- mb_require_whisper_model ---

@test "mb_require_whisper_model echoes path when model exists" {
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run mb_require_whisper_model
    assert_success
    assert_output "$model_dir/ggml-base.en.bin"
}

@test "mb_require_whisper_model dies when model not found" {
    local ORIG_HOME="$HOME"
    export HOME="$MEETBALLS_DIR/fakehome"
    unset WHISPER_CPP_MODEL_DIR

    run mb_require_whisper_model
    export HOME="$ORIG_HOME"
    assert_failure
    assert_output --partial "Whisper model not found"
}

# --- mb_wav_duration ---

@test "mb_wav_duration calculates correct duration" {
    local wav="$MEETBALLS_DIR/test.wav"
    # 10 seconds: 44 + (10 * 16000 * 2) = 320044
    truncate -s 320044 "$wav"
    run mb_wav_duration "$wav"
    assert_success
    assert_output "10"
}

@test "mb_wav_duration returns 0 for header-only file" {
    local wav="$MEETBALLS_DIR/empty.wav"
    truncate -s 44 "$wav"
    run mb_wav_duration "$wav"
    assert_success
    assert_output "0"
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
    # Restrict PATH so real parecord/pw-record aren't found
    local ORIG_PATH="$PATH"
    export PATH="$MOCK_BIN"
    run mb_detect_audio_backend
    export PATH="$ORIG_PATH"
    assert_success
    assert_output "arecord"
}

@test "mb_detect_audio_backend returns 1 when none available" {
    # Restrict PATH so no real audio backends are found
    local ORIG_PATH="$PATH"
    export PATH="$MOCK_BIN"
    run mb_detect_audio_backend
    export PATH="$ORIG_PATH"
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

# --- LIVE_DIR constant ---

@test "LIVE_DIR is MEETBALLS_DIR/live" {
    assert_equal "$LIVE_DIR" "$MEETBALLS_DIR/live"
}

# --- mb_init creates live directory ---

@test "mb_init creates live directory" {
    rm -rf "$MEETBALLS_DIR/live"
    [ ! -d "$MEETBALLS_DIR/live" ]

    mb_init

    [ -d "$MEETBALLS_DIR/live" ]
}

# --- mb_find_whisper_model ---

@test "mb_find_whisper_model returns path when found via WHISPER_CPP_MODEL_DIR" {
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"

    run mb_find_whisper_model
    assert_success
    assert_output "$model_dir/ggml-base.en.bin"
}

@test "mb_find_whisper_model returns path from default dir" {
    # Use isolated HOME so real ~/whisper.cpp/models doesn't interfere
    local ORIG_HOME="$HOME"
    export HOME="$MEETBALLS_DIR/fakehome"
    local default_dir="$HOME/whisper.cpp/models"
    mkdir -p "$default_dir"
    touch "$default_dir/ggml-base.en.bin"
    unset WHISPER_CPP_MODEL_DIR

    run mb_find_whisper_model
    export HOME="$ORIG_HOME"
    assert_success
    assert_output "$default_dir/ggml-base.en.bin"
}

@test "mb_find_whisper_model returns 1 when model not found" {
    # Use isolated HOME so real ~/whisper.cpp/models doesn't interfere
    local ORIG_HOME="$HOME"
    export HOME="$MEETBALLS_DIR/fakehome"
    unset WHISPER_CPP_MODEL_DIR

    run mb_find_whisper_model
    export HOME="$ORIG_HOME"
    assert_failure
    assert_output ""
}

# --- LOGS_DIR constant ---

@test "LOGS_DIR is MEETBALLS_DIR/logs" {
    assert_equal "$LOGS_DIR" "$MEETBALLS_DIR/logs"
}

# --- mb_init creates logs directory ---

@test "mb_init creates logs directory" {
    rm -rf "$MEETBALLS_DIR/logs"
    [ ! -d "$MEETBALLS_DIR/logs" ]

    mb_init

    [ -d "$MEETBALLS_DIR/logs" ]
}

# --- mb_log ---

@test "mb_log is no-op when MB_LOG_FILE unset" {
    unset MB_LOG_FILE
    run mb_log "should not appear"
    assert_success
    assert_output ""
}

@test "mb_log writes timestamped line to log file" {
    export MB_LOG_FILE="$MEETBALLS_DIR/test.log"
    mb_log "hello world"
    [ -f "$MB_LOG_FILE" ]
    run cat "$MB_LOG_FILE"
    assert_output --regexp '^\[.+\] hello world$'
}

# --- mb_collect_system_state ---

@test "mb_collect_system_state outputs key=value pairs" {
    run mb_collect_system_state
    assert_success
    assert_output --partial "audio_backend="
    assert_output --partial "whisper_model_path="
    assert_output --partial "disk_free_mb="
    assert_output --partial "pulseaudio_status="
    assert_output --partial "timestamp="
}

# --- mb_gather_context ---

@test "mb_gather_context wraps file contents in XML tags" {
    local testfile="$MEETBALLS_DIR/hello.txt"
    echo "hello world" > "$testfile"

    run mb_gather_context "$testfile"
    assert_success
    assert_output --partial "<file path=\"$testfile\">"
    assert_output --partial "hello world"
    assert_output --partial "</file>"
}

@test "mb_gather_context includes directory tree and key files" {
    local testdir="$MEETBALLS_DIR/project"
    mkdir -p "$testdir"
    echo '{"name": "test"}' > "$testdir/package.json"
    mkdir -p "$testdir/src"
    touch "$testdir/src/index.js"

    run mb_gather_context "$testdir"
    assert_success
    assert_output --partial "<directory path=\"$testdir\">"
    assert_output --partial "<tree>"
    assert_output --partial "package.json"
    assert_output --partial "</directory>"
}

@test "mb_gather_context warns on nonexistent path" {
    run mb_gather_context "/nonexistent/path"
    assert_success
    assert_output --partial "Context path not found"
}

@test "mb_gather_context enforces size limit" {
    local testfile="$MEETBALLS_DIR/big.txt"
    # Create a file larger than 100KB
    dd if=/dev/zero bs=1024 count=110 of="$testfile" 2>/dev/null
    export MAX_CONTEXT_BYTES=1024

    run mb_gather_context "$testfile"
    assert_success
    assert_output --partial "would exceed"
}

@test "mb_gather_context handles multiple paths" {
    local file1="$MEETBALLS_DIR/a.txt"
    local file2="$MEETBALLS_DIR/b.txt"
    echo "alpha" > "$file1"
    echo "beta" > "$file2"

    run mb_gather_context "$file1" "$file2"
    assert_success
    assert_output --partial "alpha"
    assert_output --partial "beta"
}
