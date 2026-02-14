#!/usr/bin/env bats
# Tests for bin/meetballs CLI dispatcher (task-02)

load test_helper

@test "meetballs --help prints usage and exits 0" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "record"
    assert_output --partial "transcribe"
    assert_output --partial "ask"
    assert_output --partial "hist"
    assert_output --partial "clean"
    assert_output --partial "logs"
    assert_output --partial "doctor"
}

@test "meetballs with no arguments prints help and exits 0" {
    run "$BIN_DIR/meetballs"
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "record"
    assert_output --partial "transcribe"
    assert_output --partial "ask"
    assert_output --partial "hist"
    assert_output --partial "clean"
    assert_output --partial "logs"
    assert_output --partial "doctor"
}

@test "meetballs no-args output matches --help output" {
    run "$BIN_DIR/meetballs"
    local no_args_output="$output"
    run "$BIN_DIR/meetballs" --help
    assert_equal "$no_args_output" "$output"
}

@test "meetballs --version prints version string and exits 0" {
    run "$BIN_DIR/meetballs" --version
    assert_success
    assert_output --partial "meetballs"
    # Version should match semver-like pattern
    assert_output --regexp "^meetballs [0-9]+\.[0-9]+\.[0-9]+"
}

@test "meetballs unknown command prints error to stderr and exits 1" {
    run "$BIN_DIR/meetballs" bogus
    assert_failure
    assert_output --partial "Unknown command: bogus"
    assert_output --partial "--help"
}

@test "meetballs resolves LIB_DIR via symlink" {
    # Create a symlink to bin/meetballs in a temp directory
    local symlink_dir
    symlink_dir="$(mktemp -d)"
    ln -s "$BIN_DIR/meetballs" "$symlink_dir/meetballs"

    run "$symlink_dir/meetballs" --version
    assert_success
    assert_output --partial "meetballs"

    rm -rf "$symlink_dir"
}

@test "meetballs sources common.sh successfully" {
    # If common.sh fails to source, any command would fail
    # --help exercises the sourcing path
    run "$BIN_DIR/meetballs" --help
    assert_success
}

@test "meetballs help lists command descriptions" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    # Each command should have a brief description
    assert_output --partial "live transcription"
    assert_output --partial "Browse session history"
    assert_output --partial "Remove recordings"
    assert_output --partial "Record meeting audio"
    assert_output --partial "Transcribe a recording"
    assert_output --partial "Ask questions"
    assert_output --partial "Check dependencies"
}

@test "meetballs help lists live as first command before record" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    assert_output --partial "live"
    # live should appear before record in output
    local live_pos record_pos
    live_pos=$(echo "$output" | grep -n "live" | head -1 | cut -d: -f1)
    record_pos=$(echo "$output" | grep -n "record" | head -1 | cut -d: -f1)
    [[ "$live_pos" -lt "$record_pos" ]]
}

@test "meetballs help lists hist before record" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    local hist_pos record_pos
    hist_pos=$(echo "$output" | grep -n "hist" | head -1 | cut -d: -f1)
    record_pos=$(echo "$output" | grep -n "record" | head -1 | cut -d: -f1)
    [[ "$hist_pos" -lt "$record_pos" ]]
}

@test "meetballs help lists clean before record" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    local clean_pos record_pos
    clean_pos=$(echo "$output" | grep -n "^  clean" | head -1 | cut -d: -f1)
    record_pos=$(echo "$output" | grep -n "^  record" | head -1 | cut -d: -f1)
    [[ "$clean_pos" -lt "$record_pos" ]]
}

@test "meetballs help does not list deprecated list command" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    refute_output --partial "  list"
}

@test "meetballs list shows deprecation notice" {
    run "$BIN_DIR/meetballs" list
    assert_success
    assert_output --partial "deprecated"
    assert_output --partial "meetballs hist"
}

@test "meetballs hist --help shows usage" {
    run "$BIN_DIR/meetballs" hist --help
    assert_success
    assert_output --partial "hist"
}

@test "meetballs clean --help shows usage" {
    run "$BIN_DIR/meetballs" clean --help
    assert_success
    assert_output --partial "clean"
}
