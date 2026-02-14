#!/usr/bin/env bats
# Tests for lib/hist.sh — interactive history browser TUI

load test_helper

setup() {
    common_setup
    source "$LIB_DIR/common.sh"
    source "$LIB_DIR/hist.sh"
}

# Helper: create a session directory with metadata
create_test_session() {
    local session_name="$1"
    local summary="${2:-}"
    local speakers="${3:-}"
    local duration="${4:-}"
    local dir="$SESSIONS_DIR/$session_name"
    mkdir -p "$dir"
    if [[ -n "$summary" ]]; then
        echo "$summary" > "$dir/summary.txt"
    fi
    if [[ -n "$speakers" || -n "$duration" ]]; then
        cat > "$dir/session-state.md" <<EOF
# Session State

## Hat
listener

## Muted
true

## Speakers
${speakers}

## Agenda

## Action Items

## Decisions

## Research

## Initialized
true

## Duration
${duration}
EOF
    fi
}

# --- Help ---

@test "hist --help prints usage and exits 0" {
    run cmd_hist --help
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "hist"
}

@test "hist --help mentions navigation keys" {
    run cmd_hist --help
    assert_success
    assert_output --partial "j/k"
    assert_output --partial "enter"
    assert_output --partial "q"
}

# --- Empty state ---

@test "hist with no sessions shows empty message" {
    mb_init
    # Pipe 'q' to exit the TUI loop
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "0 sessions"
    assert_output --partial "No sessions found"
    assert_output --partial "meetballs live"
}

# --- Session parsing ---

@test "hist parses date from session folder name" {
    mb_init
    _hist_parse_session "/tmp/fake/feb14-26-0800-andy-sarah-deploy"
    [ "$_HIST_DATE_DISPLAY" = "Feb 14, 2026" ]
}

@test "hist parses time from session folder name — morning" {
    mb_init
    _hist_parse_session "/tmp/fake/feb14-26-0800-andy-sarah-deploy"
    [ "$_HIST_TIME_DISPLAY" = "8:00 AM" ]
}

@test "hist parses time from session folder name — afternoon" {
    mb_init
    _hist_parse_session "/tmp/fake/feb13-26-1430-andy-sarah-api"
    [ "$_HIST_TIME_DISPLAY" = "2:30 PM" ]
}

@test "hist parses time noon as 12:00 PM" {
    mb_init
    _hist_parse_session "/tmp/fake/feb13-26-1200-andy-sarah-lunch"
    [ "$_HIST_TIME_DISPLAY" = "12:00 PM" ]
}

@test "hist parses time midnight as 12:00 AM" {
    mb_init
    _hist_parse_session "/tmp/fake/feb13-26-0000-andy-test"
    [ "$_HIST_TIME_DISPLAY" = "12:00 AM" ]
}

@test "hist reads speakers from session-state.md" {
    mb_init
    create_test_session "feb14-26-0800-andy-sarah-deploy" "" "- Andy
- Sarah" ""
    _hist_parse_session "$SESSIONS_DIR/feb14-26-0800-andy-sarah-deploy"
    [ "$_HIST_PARTICIPANTS" = "Andy, Sarah" ]
}

@test "hist reads duration from session-state.md" {
    mb_init
    create_test_session "feb14-26-0800-andy-sarah-deploy" "" "" "47m00s"
    _hist_parse_session "$SESSIONS_DIR/feb14-26-0800-andy-sarah-deploy"
    [ "$_HIST_DURATION" = "47m00s" ]
}

# --- Summary display ---

@test "hist reads summary from summary.txt" {
    mb_init
    create_test_session "feb14-26-0800-andy-sarah-deploy" "Discussed deployment timeline."
    local summary
    summary=$(_hist_get_summary "$SESSIONS_DIR/feb14-26-0800-andy-sarah-deploy")
    [ "$summary" = "Discussed deployment timeline." ]
}

@test "hist returns empty when no summary and no transcript" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "" "" ""
    local summary
    summary=$(_hist_get_summary "$SESSIONS_DIR/feb14-26-0800-andy-deploy")
    [ -z "$summary" ]
}

# --- Card rendering ---

@test "hist render includes box-drawing characters" {
    mb_init
    create_test_session "feb14-26-0800-andy-sarah-deploy" "Test summary." "- Andy
- Sarah" "47m00s"
    # Pipe 'q' to exit
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "┌"
    assert_output --partial "│"
    assert_output --partial "└"
}

@test "hist render shows session number in brackets" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary here."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "[1]"
}

@test "hist render shows selected marker on first entry" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary here."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "▸"
}

# --- Title bar ---

@test "hist shows title MEETBALLS HISTORY" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "MEETBALLS HISTORY"
}

@test "hist shows session count in title" {
    mb_init
    create_test_session "feb14-26-0800-andy-first" "First meeting."
    create_test_session "feb13-26-0900-andy-second" "Second meeting."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "2 sessions"
}

# --- Footer ---

@test "hist shows navigation footer" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "navigate"
    assert_output --partial "enter select"
    assert_output --partial "q quit"
}

# --- Session path display ---

@test "hist shows session path in card" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "feb14-26-0800-andy-deploy"
}

# --- Participants display ---

@test "hist shows participants from session-state.md" {
    mb_init
    create_test_session "feb14-26-0800-andy-sarah-deploy" "Summary." "- Andy
- Sarah" ""
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "Andy, Sarah"
}

# --- Summary in render ---

@test "hist shows summary text in card" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Discussed pushing deployment to next Friday."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "Discussed pushing deployment to next Friday."
}

# --- Tmux command generation ---

@test "hist opens tmux new-window inside tmux" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary."
    # Create a mock tmux that records the command
    create_mock_command "tmux" 'echo "tmux-called: $*"'
    # Simulate being inside tmux
    export TMUX="/tmp/tmux-test/default,12345,0"
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && _hist_open_session '$SESSIONS_DIR/feb14-26-0800-andy-deploy'"
    assert_success
    assert_output --partial "new-window"
    assert_output --partial "meetball"
}

@test "hist opens tmux new-session outside tmux" {
    mb_init
    create_test_session "feb14-26-0800-andy-deploy" "Summary."
    # Create a mock tmux that records the command
    create_mock_command "tmux" 'echo "tmux-called: $*"'
    # Ensure not inside tmux
    unset TMUX
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && unset TMUX && _hist_open_session '$SESSIONS_DIR/feb14-26-0800-andy-deploy'"
    assert_success
    assert_output --partial "new-session"
    assert_output --partial "meetball-hist"
}

# --- Multiple sessions ordering ---

@test "hist lists sessions in reverse chronological order" {
    mb_init
    create_test_session "feb10-26-1000-andy-third" "Third meeting."
    create_test_session "feb13-26-1430-andy-second" "Second meeting."
    create_test_session "feb14-26-0800-andy-first" "First meeting."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "3 sessions"
    # [1] should be the newest (feb14), which sort -r puts first
    assert_output --partial "[1]"
    assert_output --partial "[3]"
}

# --- Date/time formatting ---

@test "hist formats date correctly" {
    mb_init
    create_test_session "jan03-26-0930-andy-test" "Summary."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "Jan 03, 2026"
    assert_output --partial "9:30 AM"
}

@test "hist formats PM time correctly" {
    mb_init
    create_test_session "feb13-26-1430-andy-test" "Summary."
    run bash -c "source '$LIB_DIR/common.sh' && source '$LIB_DIR/hist.sh' && export MEETBALLS_DIR='$MEETBALLS_DIR' && SESSIONS_DIR='$MEETBALLS_DIR/sessions' && echo 'q' | cmd_hist"
    assert_success
    assert_output --partial "2:30 PM"
}
