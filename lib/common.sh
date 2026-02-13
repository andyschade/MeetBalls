#!/usr/bin/env bash
# MeetBalls — Shared utilities sourced by all modules

# Constants
MEETBALLS_DIR="${MEETBALLS_DIR:-$HOME/.meetballs}"
RECORDINGS_DIR="$MEETBALLS_DIR/recordings"
TRANSCRIPTS_DIR="$MEETBALLS_DIR/transcripts"
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
    mkdir -p "$RECORDINGS_DIR" "$TRANSCRIPTS_DIR"
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

# Echo directory paths
mb_recording_dir() {
    echo "$RECORDINGS_DIR"
}

mb_transcript_dir() {
    echo "$TRANSCRIPTS_DIR"
}

# Echo ISO timestamp for filenames
mb_timestamp() {
    date +"%Y-%m-%dT%H-%M-%S"
}
