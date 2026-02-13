#!/usr/bin/env bats
# Verification tests for project scaffolding (task-00)

load test_helper

@test "MEETBALLS_DIR is an isolated temp directory" {
    [[ -d "$MEETBALLS_DIR" ]]
    [[ "$MEETBALLS_DIR" == /tmp/* ]]
}

@test "MEETBALLS_DIR has recordings and transcripts subdirs" {
    [[ -d "$MEETBALLS_DIR/recordings" ]]
    [[ -d "$MEETBALLS_DIR/transcripts" ]]
}

@test "MOCK_BIN is on PATH" {
    [[ "$PATH" == "$MOCK_BIN:"* ]]
}

@test "create_mock_command creates executable mock" {
    create_mock_command "fake-tool" 'echo "mocked"'
    run fake-tool
    assert_success
    assert_output "mocked"
}

@test "bin/meetballs is executable" {
    run "$BIN_DIR/meetballs"
    assert_success
    assert_output --partial "Usage:"
}

@test "lib/common.sh is sourceable" {
    run bash -c "source '$LIB_DIR/common.sh'"
    assert_success
}

@test "LIB_DIR points to lib directory" {
    [[ -d "$LIB_DIR" ]]
    [[ -f "$LIB_DIR/common.sh" ]]
}
