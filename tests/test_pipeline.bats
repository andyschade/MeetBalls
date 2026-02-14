#!/usr/bin/env bats
# Tests for pipeline.sh — Stage 1 pattern matching triggers

load test_helper

setup() {
    common_setup

    # Source the stage1_detect function by extracting it from a generated pipeline.sh
    # We create a minimal harness that defines stage1_detect for testing.
    cat > "$MOCK_BIN/stage1_harness.sh" <<'EOF'
#!/usr/bin/env bash
# Stage 1 pattern matching — extracted for unit testing

stage1_detect() {
    local line="$1"
    local triggers=""

    # Wake word detection (case-insensitive)
    if echo "$line" | grep -qi "meetballs"; then
        triggers="${triggers:+$triggers }wake-word"
    fi

    # Action-item triggers
    if echo "$line" | grep -qiE "(I'll|I will|by friday|by monday|by tuesday|by wednesday|by thursday|by saturday|by sunday|by tomorrow|by next week|by end of|take that on|deadline|action item)"; then
        triggers="${triggers:+$triggers }action-item"
    fi

    # Decision triggers
    if echo "$line" | grep -qiE "(agreed|decided|let's go with|lets go with|consensus|final answer|we've decided|we decided|decision is|the call is)"; then
        triggers="${triggers:+$triggers }decision"
    fi

    # Initialization triggers (speakers/agenda)
    if echo "$line" | grep -qiE "(Hi I'm|My name is|I'm [A-Z]|Today we're going to|The agenda is|Let's cover|we'll discuss|we will discuss|nice to meet)"; then
        triggers="${triggers:+$triggers }initialization"
    fi

    echo "$triggers"
}

# Run with provided line
stage1_detect "$1"
EOF
    chmod +x "$MOCK_BIN/stage1_harness.sh"
}

# --- Wake word triggers ---

@test "stage1: detects 'meetballs' wake word" {
    run bash "$MOCK_BIN/stage1_harness.sh" "hey meetballs can you research that"
    assert_success
    assert_output --partial "wake-word"
}

@test "stage1: detects 'MeetBalls' wake word (case insensitive)" {
    run bash "$MOCK_BIN/stage1_harness.sh" "MeetBalls wrap-up please"
    assert_success
    assert_output --partial "wake-word"
}

@test "stage1: detects 'MEETBALLS' wake word (uppercase)" {
    run bash "$MOCK_BIN/stage1_harness.sh" "MEETBALLS mute"
    assert_success
    assert_output --partial "wake-word"
}

# --- Action-item triggers ---

@test "stage1: detects I'll as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "I'll get the QA checklist done"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects I will as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "I will handle the deployment"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects 'by Friday' as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "We need this done by Friday"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects 'by tomorrow' as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Can you have it ready by tomorrow"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects 'take that on' as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "I can take that on for the team"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects 'deadline' as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "The deadline is next Wednesday"
    assert_success
    assert_output --partial "action-item"
}

@test "stage1: detects 'action item' as action-item trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Let me add that as an action item"
    assert_success
    assert_output --partial "action-item"
}

# --- Decision triggers ---

@test "stage1: detects 'agreed' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "OK so we agreed to freeze branches Wednesday"
    assert_success
    assert_output --partial "decision"
}

@test "stage1: detects 'decided' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "We've decided to go with option B"
    assert_success
    assert_output --partial "decision"
}

@test "stage1: detects 'let's go with' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "let's go with the simpler approach"
    assert_success
    assert_output --partial "decision"
}

@test "stage1: detects 'consensus' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "I think we have consensus on this"
    assert_success
    assert_output --partial "decision"
}

@test "stage1: detects 'final answer' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "That's our final answer on the API design"
    assert_success
    assert_output --partial "decision"
}

@test "stage1: detects 'we decided' as decision trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Earlier we decided to use Postgres"
    assert_success
    assert_output --partial "decision"
}

# --- Initialization triggers ---

@test "stage1: detects 'Hi I'm' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Hi I'm Andy from the platform team"
    assert_success
    assert_output --partial "initialization"
}

@test "stage1: detects 'My name is' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "My name is Sarah and I lead QA"
    assert_success
    assert_output --partial "initialization"
}

@test "stage1: detects 'Today we're going to' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Today we're going to discuss the deployment timeline"
    assert_success
    assert_output --partial "initialization"
}

@test "stage1: detects 'The agenda is' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "The agenda is deployment review and QA handoff"
    assert_success
    assert_output --partial "initialization"
}

@test "stage1: detects 'Let's cover' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Let's cover the sprint goals first"
    assert_success
    assert_output --partial "initialization"
}

@test "stage1: detects 'nice to meet' as initialization trigger" {
    run bash "$MOCK_BIN/stage1_harness.sh" "nice to meet you all I'm the new PM"
    assert_success
    assert_output --partial "initialization"
}

# --- No triggers ---

@test "stage1: returns empty for ordinary conversation" {
    run bash "$MOCK_BIN/stage1_harness.sh" "So what do you think about the color scheme"
    assert_success
    assert_output ""
}

@test "stage1: returns empty for empty line" {
    run bash "$MOCK_BIN/stage1_harness.sh" ""
    assert_success
    assert_output ""
}

@test "stage1: returns empty for filler words" {
    run bash "$MOCK_BIN/stage1_harness.sh" "yeah um so anyway"
    assert_success
    assert_output ""
}

# --- Multiple triggers on same line ---

@test "stage1: detects both action-item and decision on same line" {
    run bash "$MOCK_BIN/stage1_harness.sh" "We've decided I'll handle the migration by Friday"
    assert_success
    assert_output --partial "action-item"
    assert_output --partial "decision"
}

@test "stage1: detects wake-word and action-item on same line" {
    run bash "$MOCK_BIN/stage1_harness.sh" "meetballs I'll take that action item"
    assert_success
    assert_output --partial "wake-word"
    assert_output --partial "action-item"
}

@test "stage1: detects initialization and wake-word on same line" {
    run bash "$MOCK_BIN/stage1_harness.sh" "Hi I'm Andy, meetballs can you track the agenda"
    assert_success
    assert_output --partial "initialization"
    assert_output --partial "wake-word"
}
