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

    if [[ ! -f "$recording_file" ]]; then
        mb_die "Recording file not found: $recording_file"
    fi

    # Check whisper-cli is available
    if ! mb_check_command whisper-cli; then
        mb_die "whisper-cli not found. Install it from https://github.com/ggerganov/whisper.cpp"
    fi

    # Find whisper model
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

    if [[ -z "$model_path" ]]; then
        mb_die "Whisper model not found ($model_file). Download it with: whisper-cli -dl $WHISPER_MODEL"
    fi

    mb_init

    # Warn if recording is longer than 2 hours
    local file_size
    file_size=$(stat -c %s "$recording_file")
    local duration_secs=$(( (file_size - 44) / (16000 * 2) ))
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
