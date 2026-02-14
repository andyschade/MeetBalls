#!/usr/bin/env bats
# Tests for meetballs update command

load test_helper

setup() {
    common_setup
    isolate_path

    # Source common.sh and doctor.sh (update needs cmd_doctor)
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/doctor.sh"
    source "$LIB_DIR/update.sh"
}

teardown() {
    common_teardown
}

@test "update --help prints usage and exits 0" {
    run cmd_update --help
    assert_success
    assert_output --partial "Usage: meetballs update"
    assert_output --partial "Pull the latest"
}

@test "meetballs update --help via dispatcher" {
    run "$BIN_DIR/meetballs" update --help
    assert_success
    assert_output --partial "Usage: meetballs update"
}

@test "update listed in meetballs --help" {
    run "$BIN_DIR/meetballs" --help
    assert_success
    assert_output --partial "update"
    assert_output --partial "Pull latest code"
}

@test "update fails gracefully without git repo" {
    # Use MEETBALLS_REPO_DIR to point to a temp dir without .git
    local fake_repo
    fake_repo="$(mktemp -d)"
    export MEETBALLS_REPO_DIR="$fake_repo"

    run cmd_update
    assert_failure
    assert_output --partial "Not a git repository"

    rm -rf "$fake_repo"
    unset MEETBALLS_REPO_DIR
}

@test "update reports already up to date" {
    # Mock git to return same hash for before and after
    create_mock_command "git" '
        case "$1$2" in
            -C*) shift 2 ;;
        esac
        case "$1" in
            rev-parse) echo "abc1234def5678" ;;
            pull) echo "Already up to date." ;;
            *) exit 0 ;;
        esac
    '

    # Need dpkg mock for doctor (libsdl2 check)
    create_mock_command "dpkg" 'exit 1'

    run cmd_update
    assert_success
    assert_output --partial "Already up to date"
}

@test "update reports new commits" {
    # Track call count to return different hashes
    local counter_file
    counter_file="$(mktemp)"
    echo "0" > "$counter_file"

    create_mock_command "git" "
        case \"\$1\$2\" in
            -C*) shift 2 ;;
        esac
        case \"\$1\" in
            rev-parse)
                count=\$(cat \"$counter_file\")
                if (( count == 0 )); then
                    echo \"aaa1111\"
                    echo 1 > \"$counter_file\"
                else
                    echo \"bbb2222\"
                fi
                ;;
            pull) echo \"Updating aaa1111..bbb2222\" ;;
            *) exit 0 ;;
        esac
    "

    create_mock_command "dpkg" 'exit 1'

    run cmd_update
    assert_success
    assert_output --partial "Updated: aaa1111 -> bbb2222"

    rm -f "$counter_file"
}

@test "update shows whisper-stream build commit from state" {
    # Set up state file
    mkdir -p "$MEETBALLS_DIR/.state"
    echo "deadbeef123456" > "$MEETBALLS_DIR/.state/whisper-stream-commit"

    # Mock whisper-stream as available
    create_mock_command "whisper-stream" 'exit 0'

    # Mock git for the pull
    create_mock_command "git" '
        case "$1$2" in
            -C*) shift 2 ;;
        esac
        case "$1" in
            rev-parse) echo "abc1234def5678" ;;
            pull) echo "Already up to date." ;;
            *) exit 0 ;;
        esac
    '

    create_mock_command "dpkg" 'exit 1'

    run cmd_update
    assert_success
    assert_output --partial "whisper-stream built from commit: deadbeef1234"
}

@test "update runs doctor" {
    create_mock_command "git" '
        case "$1$2" in
            -C*) shift 2 ;;
        esac
        case "$1" in
            rev-parse) echo "abc1234def5678" ;;
            pull) echo "Already up to date." ;;
            *) exit 0 ;;
        esac
    '

    create_mock_command "dpkg" 'exit 1'

    run cmd_update
    assert_success
    assert_output --partial "Checking dependencies"
}
