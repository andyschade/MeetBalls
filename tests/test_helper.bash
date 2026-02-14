#!/usr/bin/env bash
# Shared test setup for MeetBalls bats tests

# Resolve project root relative to this file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"
BIN_DIR="$PROJECT_ROOT/bin"

# Load bats libraries
load "$TEST_DIR/libs/bats-support/load"
load "$TEST_DIR/libs/bats-assert/load"

common_setup() {
    # Create isolated temp directory for MEETBALLS_DIR
    export MEETBALLS_DIR="$(mktemp -d)"
    mkdir -p "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"

    # Create temp directory for mock commands
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"
}

# Helper: restrict PATH to MOCK_BIN + only essential system utilities.
# On modern Linux /bin -> /usr/bin, so we can't use /bin directly without
# leaking real commands like parecord, tmux, dpkg into tests.
# Call this in individual tests or setup() when command isolation is needed.
isolate_path() {
    ORIG_PATH="$PATH"
    ISOLATED_BIN="$(mktemp -d)"
    local cmds=(bash dirname readlink basename mkdir cat awk wc env
                sed grep chmod rm mktemp touch sort date id stat
                find sleep truncate ls head tail tr cut tee ln pwd
                cp mv df printf)
    for cmd in "${cmds[@]}"; do
        local p
        p="$(command -v "$cmd" 2>/dev/null)" && ln -sf "$p" "$ISOLATED_BIN/$cmd"
    done
    export PATH="$MOCK_BIN:$ISOLATED_BIN"
}

common_teardown() {
    # Restore original PATH if isolate_path was used
    if [[ -n "${ORIG_PATH:-}" ]]; then export PATH="$ORIG_PATH"; fi
    # Clean up temp directories
    if [[ -d "${MEETBALLS_DIR:-}" ]]; then rm -rf "$MEETBALLS_DIR"; fi
    if [[ -d "${MOCK_BIN:-}" ]]; then rm -rf "$MOCK_BIN"; fi
    if [[ -d "${ISOLATED_BIN:-}" ]]; then rm -rf "$ISOLATED_BIN"; fi
}

# Default setup/teardown — files that don't override get these
setup() {
    common_setup
}

teardown() {
    common_teardown
}

# Helper: create a mock command in MOCK_BIN
# Usage: create_mock_command "command_name" "script_body"
create_mock_command() {
    local name="$1"
    local body="${2:-exit 0}"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$MOCK_BIN/$name"
}
