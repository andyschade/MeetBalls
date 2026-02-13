# Existing Patterns — MeetBalls Codebase

## 1. Module Structure

Every command lives in `lib/<name>.sh` and exports a single entry function `cmd_<name>()`.

**Pattern** (`lib/ask.sh:1-2`, `lib/record.sh:1-2`, `lib/transcribe.sh:1-2`, `lib/doctor.sh:1-3`):
```bash
# MeetBalls — <Name> command: <description>

cmd_<name>() {
```

**Key:** No `set -euo pipefail` in library files — only in `bin/meetballs:2`. Library files are sourced into the main script's context.

## 2. CLI Dispatcher Pattern

`bin/meetballs:40-77` uses a `case` statement to route subcommands:
```bash
case "${1:-}" in
    --help|"")
        show_help
        ;;
    <command>)
        shift
        source "$LIB_DIR/<command>.sh"
        cmd_<command> "$@"
        ;;
    *)
        mb_error "Unknown command: $1"
        ...
esac
```

Each command is lazy-loaded via `source` only when invoked.

## 3. Help Pattern

Every `cmd_<name>` starts with `--help` check (`lib/ask.sh:4-19`, `lib/record.sh:33-47`, etc.):
```bash
if [[ "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: meetballs <command> [args...]

<description>

Options:
  --help    Show this help message

Examples:
  meetballs <command> <example>
EOF
    return 0
fi
```

Uses heredoc with `'EOF'` (single-quoted to prevent expansion).

## 4. Initialization Pattern

Commands that touch the filesystem call `mb_init` early (`lib/record.sh:50`, `lib/transcribe.sh:57`, `lib/doctor.sh:19`, `lib/list.sh:19`):
```bash
mb_init
```

This creates `$RECORDINGS_DIR` and `$TRANSCRIPTS_DIR` via `mkdir -p` (`lib/common.sh:25-27`).

## 5. Dependency Check Pattern

Commands check dependencies with `mb_check_command` + `mb_die` (`lib/transcribe.sh:33-35`, `lib/ask.sh:34-36`):
```bash
if ! mb_check_command <tool>; then
    mb_die "<tool> not found. Install instructions..."
fi
```

`mb_die` prints error in red and exits 1 (`lib/common.sh:46-49`).

## 6. Error Messaging Pattern

- `mb_info` — neutral messages (stdout)
- `mb_success` — green, success messages (stdout)
- `mb_warn` — yellow, warnings (stderr)
- `mb_error` — red, errors (stderr)
- `mb_die` — red error + `exit 1`

All defined in `lib/common.sh:30-49`.

## 7. Whisper Model Search (Duplicated)

**doctor.sh:48-61:**
```bash
local model_file="ggml-${WHISPER_MODEL}.bin"
local model_found=false
local search_dirs=(
    "${WHISPER_CPP_MODEL_DIR:-}"
    "$HOME/.local/share/whisper.cpp/models"
    "/usr/local/share/whisper.cpp/models"
)
for dir in "${search_dirs[@]}"; do
    [[ -z "$dir" ]] && continue
    if [[ -f "$dir/$model_file" ]]; then
        model_found=true
        break
    fi
done
```

**transcribe.sh:38-51:**
```bash
local model_file="ggml-${WHISPER_MODEL}.bin"
local model_path=""
local search_dirs=(
    "${WHISPER_CPP_MODEL_DIR:-}"
    "$HOME/.local/share/whisper.cpp/models"
    "/usr/local/share/whisper.cpp/models"
)
for dir in "${search_dirs[@]}"; do
    [[ -z "$dir" ]] && continue
    if [[ -f "$dir/$model_file" ]]; then
        model_path="$dir/$model_file"
        break
    fi
done
```

**Difference:** doctor.sh sets a boolean `model_found`, transcribe.sh captures the full path. The shared `mb_find_whisper_model()` should return the path (empty string = not found).

## 8. Disk Space Check Pattern

`lib/common.sh:58-67` — `mb_check_disk_space()`:
- Returns 0 if >= 500MB free
- Returns 1 with warning if below
- Used as `mb_check_disk_space || true` (warn but don't abort) in `lib/record.sh:53`

## 9. Signal Handling Pattern

`lib/record.sh:7-17` uses module-level variables + trap:
```bash
_RECORDER_PID=""
_OUTPUT_FILE=""

_mb_stop_recording() {
    if [[ -n "$_RECORDER_PID" ]]; then
        kill "$_RECORDER_PID" 2>/dev/null || true
        wait "$_RECORDER_PID" 2>/dev/null || true
    fi
    _mb_print_summary
    trap - INT TERM
    exit 0
}
```

Trap set with: `trap '_mb_stop_recording' INT TERM` (`lib/record.sh:79`).

## 10. Testing Patterns

### Test File Structure
- Named `tests/test_<feature>.bats`
- Load test helper: `load test_helper` (line 1-3 of each .bats file)
- Custom setup/teardown per file

### Setup Pattern (most common — `test_doctor.bats:9-20`, `test_record.bats:7-18`):
```bash
setup() {
    export MEETBALLS_DIR="$(mktemp -d)"
    mkdir -p "$MEETBALLS_DIR/recordings" "$MEETBALLS_DIR/transcripts"
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:/usr/bin:/bin"  # Restricted PATH
}
teardown() {
    [[ -d "${MEETBALLS_DIR:-}" ]] && rm -rf "$MEETBALLS_DIR"
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}
```

**Restricted PATH:** Tests that check dependencies use `$MOCK_BIN:/usr/bin:/bin` to prevent real commands from leaking in.

### Mocking Pattern (`tests/test_helper.bash:30-40`):
```bash
create_mock_command() {
    local name="$1"
    local body="${2:-exit 0}"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
    chmod +x "$MOCK_BIN/$name"
}
```

### All-Dependencies Setup (`test_doctor.bats:22-35`):
```bash
setup_all_deps() {
    create_mock_command "pw-record"
    create_mock_command "whisper-cli"
    create_mock_command "claude"
    create_mock_command "df" 'echo "Filesystem ..."; echo "/dev/sda1 ... 10485760 ..."'
    local model_dir="$MEETBALLS_DIR/whisper-models"
    mkdir -p "$model_dir"
    touch "$model_dir/ggml-base.en.bin"
    export WHISPER_CPP_MODEL_DIR="$model_dir"
}
```

### Test Assertion Pattern:
```bash
@test "description" {
    run "$BIN_DIR/meetballs" <args>
    assert_success          # or assert_failure
    assert_output --partial "expected substring"
}
```

## 11. Timestamp Convention

`lib/common.sh:111-113` — `mb_timestamp()`:
```bash
mb_timestamp() {
    date +"%Y-%m-%dT%H-%M-%S"
}
```

Format: `2026-02-13T10-00-00` — used for recording filenames and transcript filenames.

## 12. Constants

All defined at top of `lib/common.sh:5-9`:
```bash
MEETBALLS_DIR="${MEETBALLS_DIR:-$HOME/.meetballs}"
RECORDINGS_DIR="$MEETBALLS_DIR/recordings"
TRANSCRIPTS_DIR="$MEETBALLS_DIR/transcripts"
WHISPER_MODEL="${WHISPER_MODEL:-base.en}"
MIN_DISK_MB=500
```

All use the `MEETBALLS_DIR` base path. New `LIVE_DIR` should follow the same pattern.
