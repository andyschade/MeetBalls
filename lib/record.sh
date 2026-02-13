# MeetBalls — Record command: capture meeting audio

# Module-level variables for signal handler access
_RECORDER_PID=""
_OUTPUT_FILE=""

_mb_stop_recording() {
    # Kill the recorder process if still running
    if [[ -n "$_RECORDER_PID" ]]; then
        kill "$_RECORDER_PID" 2>/dev/null || true
        wait "$_RECORDER_PID" 2>/dev/null || true
    fi

    _mb_print_summary
    trap - INT TERM
    exit 0
}

_mb_print_summary() {
    if [[ -n "$_OUTPUT_FILE" && -f "$_OUTPUT_FILE" ]]; then
        local file_size
        file_size=$(stat -c %s "$_OUTPUT_FILE")
        local duration_secs=$(( (file_size - 44) / (16000 * 2) ))
        local duration
        duration=$(mb_format_duration "$duration_secs")
        mb_success "Saved: $_OUTPUT_FILE (duration: $duration)"
    else
        mb_error "Recording failed — no output file created."
    fi
}

cmd_record() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs record

Record meeting audio from the default system microphone.
Saves as WAV (16kHz, mono, 16-bit) to ~/.meetballs/recordings/.
Press Ctrl+C to stop recording.

Options:
  --help    Show this help message

Examples:
  meetballs record
EOF
        return 0
    fi

    mb_init

    # Check disk space (warn but don't abort)
    mb_check_disk_space || true

    # Detect audio backend
    local backend
    if ! backend=$(mb_detect_audio_backend); then
        mb_die "No audio backend found. Install pipewire, pulseaudio, or alsa-utils."
    fi

    # Generate output filename
    _OUTPUT_FILE="$RECORDINGS_DIR/$(mb_timestamp).wav"

    # Build recorder command based on backend
    local recorder_cmd=()
    case "$backend" in
        pw-record)
            recorder_cmd=(pw-record --rate=16000 --channels=1 --format=s16 "$_OUTPUT_FILE")
            ;;
        parecord)
            recorder_cmd=(parecord --rate=16000 --channels=1 --format=s16le --file-format=wav "$_OUTPUT_FILE")
            ;;
        arecord)
            recorder_cmd=(arecord -f S16_LE -r 16000 -c 1 -t wav "$_OUTPUT_FILE")
            ;;
    esac

    # Set up SIGINT trap before starting the recorder
    trap '_mb_stop_recording' INT TERM

    # Start recorder in the background
    "${recorder_cmd[@]}" &
    _RECORDER_PID=$!

    mb_info "Recording... (press Ctrl+C to stop)"

    # Wait for the recorder process
    wait "$_RECORDER_PID" || true
    _RECORDER_PID=""

    # If we get here, recorder exited on its own (not via signal)
    _mb_print_summary
    trap - INT TERM
}
