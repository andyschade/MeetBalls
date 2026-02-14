#!/usr/bin/env bash
# MeetBalls — Shared utilities sourced by all modules

# Constants
MEETBALLS_DIR="${MEETBALLS_DIR:-$HOME/.meetballs}"
RECORDINGS_DIR="$MEETBALLS_DIR/recordings"
TRANSCRIPTS_DIR="$MEETBALLS_DIR/transcripts"
LIVE_DIR="$MEETBALLS_DIR/live"
SESSIONS_DIR="$MEETBALLS_DIR/sessions"
LOGS_DIR="$MEETBALLS_DIR/logs"
WHISPER_MODEL="${WHISPER_MODEL:-base.en}"
MIN_DISK_MB=500

# Colors — disabled when stdout is not a terminal
if [[ -t 1 ]]; then
    _CLR_GREEN=$'\033[0;32m'
    _CLR_YELLOW=$'\033[0;33m'
    _CLR_RED=$'\033[0;31m'
    _CLR_RESET=$'\033[0m'
else
    _CLR_GREEN=""
    _CLR_YELLOW=""
    _CLR_RED=""
    _CLR_RESET=""
fi

# Create recordings and transcripts directories
mb_init() {
    mkdir -p "$RECORDINGS_DIR" "$TRANSCRIPTS_DIR" "$LIVE_DIR" "$SESSIONS_DIR" "$LOGS_DIR"
}

# Messaging functions
mb_info() {
    echo "$*"
}

mb_success() {
    echo "${_CLR_GREEN}$*${_CLR_RESET}"
}

mb_warn() {
    echo "${_CLR_YELLOW}$*${_CLR_RESET}" >&2
}

mb_error() {
    echo "${_CLR_RED}$*${_CLR_RESET}" >&2
}

mb_die() {
    mb_error "$@"
    exit 1
}

# Append timestamped line to session log (no-op if MB_LOG_FILE unset)
mb_log() {
    [[ -n "${MB_LOG_FILE:-}" ]] || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$MB_LOG_FILE"
}

# Print key=value system state for diagnostics
mb_collect_system_state() {
    local audio_backend disk_free_mb pulse_status model_path
    audio_backend=$(mb_detect_audio_backend 2>/dev/null) || audio_backend="none"
    model_path=$(mb_find_whisper_model 2>/dev/null) || model_path="not found"
    disk_free_mb=$(df -k "$MEETBALLS_DIR" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}') || disk_free_mb="unknown"
    if mb_check_command pactl && pactl info >/dev/null 2>&1; then
        pulse_status="running"
    else
        pulse_status="not running"
    fi
    echo "audio_backend=$audio_backend"
    echo "whisper_model_path=$model_path"
    echo "disk_free_mb=$disk_free_mb"
    echo "pulseaudio_status=$pulse_status"
    echo "timestamp=$(date '+%Y-%m-%d %H:%M:%S')"
}

# Structured diagnostic dump on failure
# Usage: mb_diagnostic_dump <error_msg> <exit_code> <failed_command> [stderr_log_path]
mb_diagnostic_dump() {
    local error_msg="$1" exit_code="$2" failed_cmd="$3" stderr_log="${4:-}"
    local dump=""
    dump+="=== DIAGNOSTIC DUMP ==="$'\n'
    dump+="error: $error_msg"$'\n'
    dump+="exit_code: $exit_code"$'\n'
    dump+="failed_command: $failed_cmd"$'\n'
    if [[ -n "$stderr_log" ]] && [[ -f "$stderr_log" ]]; then
        dump+="--- last 30 lines of stderr ---"$'\n'
        dump+="$(tail -n 30 "$stderr_log")"$'\n'
        dump+="--- end stderr ---"$'\n'
    fi
    dump+="--- system state ---"$'\n'
    dump+="$(mb_collect_system_state)"$'\n'
    dump+="=== END DIAGNOSTIC DUMP ==="
    if [[ -n "${MB_LOG_FILE:-}" ]]; then
        echo "$dump" >> "$MB_LOG_FILE"
    fi
    echo "$dump" >&2
}

# Check if a command exists
mb_check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Require a command to be available, or die with install hint
mb_require_command() {
    if ! mb_check_command "$1"; then
        mb_die "$1 not found. $2"
    fi
}

# Require a file to exist, or die with descriptive message
mb_require_file() {
    if [[ ! -f "$1" ]]; then
        mb_die "$2 not found: $1"
    fi
}

# Check disk space on MEETBALLS_DIR partition
# Returns 0 if >=500MB free, 1 if below
mb_check_disk_space() {
    local avail_kb
    avail_kb=$(df -k "$MEETBALLS_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    local avail_mb=$(( avail_kb / 1024 ))
    if (( avail_mb < MIN_DISK_MB )); then
        mb_warn "Low disk space: ${avail_mb}MB free (minimum ${MIN_DISK_MB}MB recommended)"
        return 1
    fi
    return 0
}

# Find whisper model file in standard paths
# Prints absolute path to stdout on success; returns 1 on failure
mb_find_whisper_model() {
    local model_file="ggml-${WHISPER_MODEL}.bin"
    local search_dirs=(
        "${WHISPER_CPP_MODEL_DIR:-}"
        "$HOME/whisper.cpp/models"
        "$HOME/.local/share/whisper.cpp/models"
        "/usr/local/share/whisper.cpp/models"
    )
    for dir in "${search_dirs[@]}"; do
        [[ -z "$dir" ]] && continue
        if [[ -f "$dir/$model_file" ]]; then
            echo "$dir/$model_file"
            return 0
        fi
    done
    return 1
}

# Find whisper model or die with download instructions
mb_require_whisper_model() {
    local model_path
    model_path=$(mb_find_whisper_model) || true
    if [[ -z "$model_path" ]]; then
        mb_die "Whisper model not found (ggml-${WHISPER_MODEL}.bin). Download: bash ~/whisper.cpp/models/download-ggml-model.sh $WHISPER_MODEL"
    fi
    echo "$model_path"
}

# Detect best available audio backend
# Priority: PipeWire > PulseAudio > ALSA
# Prints backend command name; returns 1 if none found
mb_detect_audio_backend() {
    if mb_check_command pw-record; then
        echo "pw-record"
    elif mb_check_command parecord; then
        echo "parecord"
    elif mb_check_command arecord; then
        echo "arecord"
    else
        return 1
    fi
}

# Format seconds as human-readable duration
# 0→"0s", 45→"45s", 90→"1m30s", 3720→"1h02m00s"
mb_format_duration() {
    local total_secs=$1
    local hours=$(( total_secs / 3600 ))
    local mins=$(( (total_secs % 3600) / 60 ))
    local secs=$(( total_secs % 60 ))

    if (( hours > 0 )); then
        printf "%dh%02dm%02ds\n" "$hours" "$mins" "$secs"
    elif (( mins > 0 )); then
        printf "%dm%02ds\n" "$mins" "$secs"
    else
        printf "%ds\n" "$secs"
    fi
}

# Calculate WAV file duration in seconds from file size
# Assumes 16kHz, mono, 16-bit PCM with 44-byte header
mb_wav_duration() {
    local file_size
    file_size=$(stat -c %s "$1")
    echo $(( (file_size - 44) / (16000 * 2) ))
}

# Echo ISO timestamp for filenames
mb_timestamp() {
    date +"%Y-%m-%dT%H-%M-%S"
}

# --- Session directory helpers ---

# Create a new session directory under SESSIONS_DIR with the given name.
# If no name given, uses a timestamp. Prints the created path.
mb_create_session_dir() {
    local name="${1:-$(mb_timestamp)}"
    local session_dir="$SESSIONS_DIR/$name"
    mkdir -p "$session_dir"
    echo "$session_dir"
}

# Write a blank session-state.md template to the given directory.
mb_init_session_state() {
    local session_dir="$1"
    cat > "$session_dir/session-state.md" <<'EOF'
# Session State

## Hat
listener

## Muted
true

## Speakers

## Agenda

## Action Items

## Decisions

## Research

## Duration
EOF
}

# List session directories sorted newest-first (by directory name).
# Prints one absolute path per line. Returns 1 if no sessions found.
mb_scan_sessions() {
    local sessions=()
    if [[ -d "$SESSIONS_DIR" ]]; then
        local entry
        while IFS= read -r entry; do
            [[ -d "$entry" ]] && sessions+=("$entry")
        done < <(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
    fi
    if [[ ${#sessions[@]} -eq 0 ]]; then
        return 1
    fi
    printf '%s\n' "${sessions[@]}"
}

# Parse a session folder name into metadata.
# Sets variables: SESSION_DATE, SESSION_YEAR, SESSION_TIME, SESSION_PARTICIPANTS, SESSION_TOPIC
# Input: folder name (not full path), e.g. "feb14-26-0800-andy-sarah-deployment-timeline"
mb_parse_session_name() {
    local name="$1"
    # Format: <mon><dd>-<yy>-<HHMM>-<participants...>-<topic...>
    # First token: month+day (e.g. feb14)
    # Second token: 2-digit year
    # Third token: 4-digit time
    # Remaining tokens: participants then topic — we can't perfectly distinguish
    # them without the session-state.md, so we store the raw tail.
    local IFS='-'
    read -ra parts <<< "$name"
    SESSION_DATE="${parts[0]:-}"           # e.g. feb14
    SESSION_YEAR="${parts[1]:-}"           # e.g. 26
    SESSION_TIME="${parts[2]:-}"           # e.g. 0800
    # Everything after the first 3 tokens is participants-and-topic
    local rest=""
    local i
    for (( i=3; i<${#parts[@]}; i++ )); do
        [[ -n "$rest" ]] && rest+="-"
        rest+="${parts[$i]}"
    done
    SESSION_NAME_TAIL="$rest"
}

# --- Project context gathering ---

MAX_CONTEXT_BYTES="${MAX_CONTEXT_BYTES:-102400}"

_MB_KEY_FILES=(
    README.md CLAUDE.md Makefile package.json Cargo.toml go.mod
    pyproject.toml setup.py setup.cfg requirements.txt
    CMakeLists.txt build.gradle pom.xml composer.json Gemfile
    .env.example tsconfig.json deno.json
)

# Gather context from files/directories for Claude
# Writes XML-wrapped content to stdout; warns on stderr
mb_gather_context() {
    local cumulative=0
    local path
    for path in "$@"; do
        if [[ ! -e "$path" ]]; then
            mb_warn "Context path not found: $path"
            continue
        fi

        if [[ -f "$path" ]]; then
            local size
            size=$(stat -c %s "$path" 2>/dev/null) || size=0
            if (( cumulative + size > MAX_CONTEXT_BYTES )); then
                mb_warn "Skipping $path — would exceed ${MAX_CONTEXT_BYTES}-byte context limit"
                continue
            fi
            cumulative=$(( cumulative + size ))
            echo "<file path=\"$path\">"
            cat "$path"
            echo "</file>"

        elif [[ -d "$path" ]]; then
            # Directory tree (max 3 levels, 200 lines)
            echo "<directory path=\"$path\">"
            echo "<tree>"
            find "$path" -maxdepth 3 -not -path '*/\.*' | head -200
            echo "</tree>"

            # Include key files found in this directory
            local key_file
            for key_file in "${_MB_KEY_FILES[@]}"; do
                local full="$path/$key_file"
                if [[ -f "$full" ]]; then
                    local size
                    size=$(stat -c %s "$full" 2>/dev/null) || size=0
                    if (( cumulative + size > MAX_CONTEXT_BYTES )); then
                        mb_warn "Skipping $full — would exceed ${MAX_CONTEXT_BYTES}-byte context limit"
                        continue
                    fi
                    cumulative=$(( cumulative + size ))
                    echo "<file path=\"$full\">"
                    cat "$full"
                    echo "</file>"
                fi
            done
            echo "</directory>"
        fi
    done
}
