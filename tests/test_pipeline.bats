#!/usr/bin/env bats
# Tests for pipeline.sh — Stage 1 pattern matching triggers and hat system

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

    # Harness for parse_wake_command
    cat > "$MOCK_BIN/wake_cmd_harness.sh" <<'EOF'
#!/usr/bin/env bash
# Wake word command parsing — extracted for unit testing

parse_wake_command() {
    local line="$1"
    local after
    after=$(echo "$line" | sed -n 's/.*[Mm][Ee][Ee][Tt][Bb][Aa][Ll][Ll][Ss]\s*//Ip')
    local cmd
    cmd=$(echo "$after" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | cut -d' ' -f1)

    case "$cmd" in
        research)    echo "research" ;;
        fact-check|factcheck|fact)  echo "fact-check" ;;
        timekeeper|timer|time)      echo "timekeeper" ;;
        wrap-up|wrapup|wrap)        echo "wrap-up" ;;
        mute)        echo "mute" ;;
        unmute)      echo "unmute" ;;
        *)           echo "" ;;
    esac
}

parse_wake_command "$1"
EOF
    chmod +x "$MOCK_BIN/wake_cmd_harness.sh"

    # Harness for read_state_section / read_initialized / section_has_content
    cat > "$MOCK_BIN/state_harness.sh" <<'EOF'
#!/usr/bin/env bash
# Session state helpers — extracted for unit testing

SESSION_STATE="$1"
FUNC="$2"
ARG="$3"

read_state_section() {
    local section="$1"
    if [[ ! -f "$SESSION_STATE" ]]; then
        echo ""
        return
    fi
    local in_section=false
    while IFS= read -r line; do
        if [[ "$line" == "## $section" ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == true ]]; then
            if [[ "$line" == "## "* ]]; then
                break
            fi
            if [[ -n "$line" ]]; then
                echo "$line"
                return
            fi
        fi
    done < "$SESSION_STATE"
    echo ""
}

read_hat() {
    read_state_section "Hat"
}

read_initialized() {
    read_state_section "Initialized"
}

section_has_content() {
    local section="$1"
    if [[ ! -f "$SESSION_STATE" ]]; then
        return 1
    fi
    local in_section=false
    while IFS= read -r line; do
        if [[ "$line" == "## $section" ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == true ]]; then
            if [[ "$line" == "## "* ]]; then
                return 1
            fi
            if [[ -n "$line" ]] && [[ "$line" != "(none)" ]]; then
                return 0
            fi
        fi
    done < "$SESSION_STATE"
    return 1
}

case "$FUNC" in
    read_hat) read_hat ;;
    read_initialized) read_initialized ;;
    section_has_content) section_has_content "$ARG" ;;
esac
EOF
    chmod +x "$MOCK_BIN/state_harness.sh"
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

# --- Wake word command parsing ---

@test "parse_wake_command: detects 'research' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs research what's the latest API status"
    assert_success
    assert_output "research"
}

@test "parse_wake_command: detects 'fact-check' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs fact-check that claim about performance"
    assert_success
    assert_output "fact-check"
}

@test "parse_wake_command: detects 'timekeeper' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs timekeeper"
    assert_success
    assert_output "timekeeper"
}

@test "parse_wake_command: detects 'wrap-up' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs wrap-up"
    assert_success
    assert_output "wrap-up"
}

@test "parse_wake_command: detects 'mute' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs mute"
    assert_success
    assert_output "mute"
}

@test "parse_wake_command: detects 'unmute' command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs unmute"
    assert_success
    assert_output "unmute"
}

@test "parse_wake_command: returns empty for unknown command" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs do something random"
    assert_success
    assert_output ""
}

@test "parse_wake_command: handles case insensitive wake word" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "MeetBalls Research the topic"
    assert_success
    assert_output "research"
}

@test "parse_wake_command: detects 'wrapup' variant" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs wrapup"
    assert_success
    assert_output "wrap-up"
}

@test "parse_wake_command: detects 'timer' as timekeeper" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs timer"
    assert_success
    assert_output "timekeeper"
}

# --- Session state helpers ---

@test "read_hat: returns listener from default state" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Hat
listener

## Muted
true

## Speakers

## Initialized
false
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "read_hat"
    assert_success
    assert_output "listener"
}

@test "read_hat: returns research when hat changed" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Hat
research

## Muted
true
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "read_hat"
    assert_success
    assert_output "research"
}

@test "read_initialized: returns false from default state" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Hat
listener

## Initialized
false

## Duration
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "read_initialized"
    assert_success
    assert_output "false"
}

@test "read_initialized: returns true when set" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Hat
listener

## Initialized
true

## Duration
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "read_initialized"
    assert_success
    assert_output "true"
}

@test "section_has_content: returns 1 for empty Speakers" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Speakers

## Agenda
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "section_has_content" "Speakers"
    assert_failure
}

@test "section_has_content: returns 0 for populated Speakers" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Speakers
- Andy
- Sarah

## Agenda
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "section_has_content" "Speakers"
    assert_success
}

@test "section_has_content: returns 1 for (none) content" {
    local state_file="$MOCK_BIN/test-state.md"
    cat > "$state_file" <<'STATE'
# Session State

## Research
(none)

## Duration
STATE
    run bash "$MOCK_BIN/state_harness.sh" "$state_file" "section_has_content" "Research"
    assert_failure
}

# --- Hat transition mutual exclusivity ---

@test "parse_wake_command: active hats are distinct commands" {
    # Verify each active hat returns a unique value
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs research topic"
    assert_output "research"

    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs fact-check claim"
    assert_output "fact-check"

    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs timekeeper"
    assert_output "timekeeper"
}

@test "parse_wake_command: wrap-up is distinct from active hats" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs wrap-up"
    assert_output "wrap-up"
    # wrap-up is NOT an active hat — it's a special trigger
}

@test "parse_wake_command: mute/unmute are not hat transitions" {
    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs mute"
    assert_output "mute"

    run bash "$MOCK_BIN/wake_cmd_harness.sh" "meetballs unmute"
    assert_output "unmute"
    # These are state changes, not hat transitions
}
