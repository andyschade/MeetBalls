# MeetBalls — Transcribe command: convert recording to text via whisper-cli

cmd_transcribe() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs transcribe <recording-file>

Transcribe a WAV recording to text using whisper-cli (offline).
Saves the transcript to ~/.meetballs/transcripts/<basename>.txt.

Options:
  --help    Show this help message

Examples:
  meetballs transcribe ~/.meetballs/recordings/2026-02-12T14-30-00.wav
  meetballs transcribe recording.wav
EOF
        return 0
    fi

    # Validate argument
    if [[ $# -lt 1 ]]; then
        mb_die "Missing recording file argument. Usage: meetballs transcribe <recording-file>"
    fi

    local recording_file="$1"

    mb_require_file "$recording_file" "Recording file"
    mb_require_command whisper-cli "Install it from https://github.com/ggerganov/whisper.cpp"

    local model_path
    model_path=$(mb_require_whisper_model)

    mb_init

    # Warn if recording is longer than 2 hours
    local duration_secs
    duration_secs=$(mb_wav_duration "$recording_file")
    if (( duration_secs > 7200 )); then
        mb_warn "Recording is over 2 hours ($(mb_format_duration "$duration_secs")). Transcription may take a while."
    fi

    # Determine output path
    local basename
    basename=$(basename "$recording_file" .wav)
    local transcript_base="$TRANSCRIPTS_DIR/$basename"

    mb_info "Transcribing..."

    # Invoke whisper-cli
    whisper-cli \
        -m "$model_path" \
        -f "$recording_file" \
        --output-txt \
        --output-file "$transcript_base" \
        --print-progress

    mb_success "Done: ${transcript_base}.txt"
}
