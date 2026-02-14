#!/usr/bin/env bash
# MeetBalls — Shared utilities sourced by all modules

# Constants
MEETBALLS_DIR="${MEETBALLS_DIR:-$HOME/.meetballs}"
RECORDINGS_DIR="$MEETBALLS_DIR/recordings"
TRANSCRIPTS_DIR="$MEETBALLS_DIR/transcripts"
LIVE_DIR="$MEETBALLS_DIR/live"
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
    mkdir -p "$RECORDINGS_DIR" "$TRANSCRIPTS_DIR" "$LIVE_DIR"
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
