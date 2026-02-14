#!/usr/bin/env bats
# Tests for lib/logs.sh — logs command

load test_helper

setup() {
    common_setup
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/logs.sh"
    mb_init
}

# Helper: create a fake session log
create_test_log() {
    local ts="${1:-2026-02-12T14-30-00}"
    local content="${2:-[2026-02-12 14:30:00] session started}"
    mkdir -p "$LOGS_DIR"
    echo "$content" > "$LOGS_DIR/$ts.log"
}

# --- Help ---

@test "logs --help prints usage and exits 0" {
    run cmd_logs --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "logs"
}

# --- No sessions ---

@test "logs with no sessions prints message" {
    run cmd_logs
    assert_success
    assert_output --partial "No session logs found"
}

# --- --last ---

@test "logs --last shows most recent log" {
    create_test_log "2026-02-12T14-30-00" "first session"
    sleep 0.1
    create_test_log "2026-02-12T15-00-00" "second session"

    run cmd_logs --last
    assert_success
    assert_output --partial "second session"
}

@test "logs --last with no sessions prints message" {
    run cmd_logs --last
    assert_success
    assert_output --partial "No session logs found"
}

# --- Listing ---

@test "logs listing shows column headers" {
    create_test_log

    run cmd_logs
    assert_success
    assert_output --partial "SESSION"
    assert_output --partial "LOG"
    assert_output --partial "STDERR"
    assert_output --partial "DUMP"
}

@test "logs listing shows session timestamp" {
    create_test_log "2026-02-12T14-30-00"

    run cmd_logs
    assert_success
    assert_output --partial "2026-02-12T14-30-00"
}

# --- Specific session ---

@test "logs shows specific session by timestamp" {
    create_test_log "2026-02-12T14-30-00" "specific session content"

    run cmd_logs "2026-02-12T14-30-00"
    assert_success
    assert_output --partial "specific session content"
}

@test "logs errors on nonexistent session" {
    run cmd_logs "1999-01-01T00-00-00"
    assert_failure
    assert_output --partial "No log found"
}

# --- --dump ---

@test "logs --dump shows diagnostic dump sections" {
    local content="[2026-02-12 14:30:00] session started
=== DIAGNOSTIC DUMP ===
error: whisper-stream failed
exit_code: 1
=== END DIAGNOSTIC DUMP ==="
    create_test_log "2026-02-12T14-30-00" "$content"

    run cmd_logs --dump
    assert_success
    assert_output --partial "DIAGNOSTIC DUMP"
    assert_output --partial "whisper-stream failed"
}

@test "logs --dump with no dumps prints message" {
    create_test_log "2026-02-12T14-30-00" "clean session"

    run cmd_logs --dump
    assert_success
    assert_output --partial "No diagnostic dumps"
}
