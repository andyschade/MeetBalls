#!/usr/bin/env bats
# Tests for lib/clean.sh — clean command

load test_helper

setup() {
    common_setup
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/clean.sh"
}

# Helper: create a session with a recording of given size in bytes
create_session_with_recording() {
    local session_name="$1"
    local size_bytes="$2"
    local dir="$SESSIONS_DIR/$session_name"
    mkdir -p "$dir"
    truncate -s "$size_bytes" "$dir/recording.wav"
    # Add other session artifacts
    echo "transcript" > "$dir/transcript.txt"
    echo "summary" > "$dir/summary.txt"
}

# Helper: create a session without a recording
create_session_without_recording() {
    local session_name="$1"
    local dir="$SESSIONS_DIR/$session_name"
    mkdir -p "$dir"
    echo "transcript" > "$dir/transcript.txt"
    echo "summary" > "$dir/summary.txt"
}

# --- Help ---

@test "clean --help prints usage and exits 0" {
    run cmd_clean --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "clean"
}

@test "clean --help mentions recordings" {
    run cmd_clean --help
    assert_success
    assert_output --partial "recording"
}

# --- Empty state ---

@test "clean with no sessions prints empty message" {
    mb_init
    run cmd_clean
    assert_success
    assert_output --partial "No recordings found in ~/.meetballs/sessions/."
}

@test "clean with sessions but no recordings prints empty message" {
    mb_init
    create_session_without_recording "feb14-26-0800-andy-test"
    run cmd_clean
    assert_success
    assert_output --partial "No recordings found in ~/.meetballs/sessions/."
}

# --- Listing recordings ---

@test "clean lists session names with recordings" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-sarah-deploy" 1048576
    # Answer 'n' to the confirmation prompt
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "feb14-26-0800-andy-sarah-deploy"
}

@test "clean shows file sizes" {
    mb_init
    # 1 MB recording
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "1.0 MB"
}

@test "clean shows total count and size" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test1" 1048576
    create_session_with_recording "feb13-26-0900-andy-test2" 2097152
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "Total: 2 recording(s)"
    assert_output --partial "3.0 MB"
}

@test "clean lists multiple sessions" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-deploy" 1048576
    create_session_with_recording "feb13-26-0900-andy-retro" 2097152
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "feb14-26-0800-andy-deploy"
    assert_output --partial "feb13-26-0900-andy-retro"
}

# --- Confirmation ---

@test "clean aborts when user answers n" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "Aborted"
    # Recording should still exist
    [ -f "$SESSIONS_DIR/feb14-26-0800-andy-test/recording.wav" ]
}

@test "clean aborts on empty input" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo '' | cmd_clean"
    assert_success
    assert_output --partial "Aborted"
    [ -f "$SESSIONS_DIR/feb14-26-0800-andy-test/recording.wav" ]
}

# --- Deletion ---

@test "clean deletes recordings when user confirms y" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'y' | cmd_clean"
    assert_success
    assert_output --partial "Deleted 1 recording(s)"
    # Recording should be gone
    [ ! -f "$SESSIONS_DIR/feb14-26-0800-andy-test/recording.wav" ]
}

@test "clean deletes recordings when user confirms Y (uppercase)" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'Y' | cmd_clean"
    assert_success
    assert_output --partial "Deleted 1 recording(s)"
    [ ! -f "$SESSIONS_DIR/feb14-26-0800-andy-test/recording.wav" ]
}

@test "clean preserves other session artifacts after deletion" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'y' | cmd_clean"
    assert_success
    # Other artifacts should still exist
    [ -f "$SESSIONS_DIR/feb14-26-0800-andy-test/transcript.txt" ]
    [ -f "$SESSIONS_DIR/feb14-26-0800-andy-test/summary.txt" ]
    # Session directory should still exist
    [ -d "$SESSIONS_DIR/feb14-26-0800-andy-test" ]
}

@test "clean deletes multiple recordings" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-deploy" 1048576
    create_session_with_recording "feb13-26-0900-andy-retro" 2097152
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'y' | cmd_clean"
    assert_success
    assert_output --partial "Deleted 2 recording(s)"
    [ ! -f "$SESSIONS_DIR/feb14-26-0800-andy-deploy/recording.wav" ]
    [ ! -f "$SESSIONS_DIR/feb13-26-0900-andy-retro/recording.wav" ]
}

@test "clean output includes preserved message after deletion" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-test" 1048576
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'y' | cmd_clean"
    assert_success
    assert_output --partial "Session artifacts preserved"
}

# --- Size formatting ---

@test "clean shows KB for small recordings" {
    mb_init
    # 50 KB
    create_session_with_recording "feb14-26-0800-andy-test" 51200
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "50.0 KB"
}

@test "clean shows GB for large recordings" {
    mb_init
    # 1.5 GB = 1610612736 bytes — use sparse file (no actual disk space)
    create_session_with_recording "feb14-26-0800-andy-test" 1610612736
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "1.5 GB"
}

# --- Only sessions with recordings count ---

@test "clean ignores sessions without recordings" {
    mb_init
    create_session_with_recording "feb14-26-0800-andy-deploy" 1048576
    create_session_without_recording "feb13-26-0900-andy-retro"
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/clean.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'n' | cmd_clean"
    assert_success
    assert_output --partial "Total: 1 recording(s)"
    # Should not list the session without recording
    refute_output --partial "feb13-26-0900-andy-retro"
}
