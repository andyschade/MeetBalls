# MeetBalls — List command: show recordings and transcript status

cmd_list() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs list

List all recordings and their transcript status.

Options:
  --help    Show this help message

Examples:
  meetballs list
EOF
        return 0
    fi

    mb_init

    local wav_files=()
    while IFS= read -r -d '' f; do
        wav_files+=("$f")
    done < <(find "$RECORDINGS_DIR" -maxdepth 1 -name '*.wav' -print0 | sort -z)

    if [[ ${#wav_files[@]} -eq 0 ]]; then
        mb_info "No recordings found in $RECORDINGS_DIR"
        return 0
    fi

    # Print table header
    printf "%-35s  %-10s  %s\n" "RECORDING" "DURATION" "TRANSCRIPT"

    local wav basename_noext duration_secs duration transcript_status
    for wav in "${wav_files[@]}"; do
        basename_noext="$(basename "$wav" .wav)"

        duration_secs=$(mb_wav_duration "$wav")
        duration=$(mb_format_duration "$duration_secs")

        # Check transcript existence
        if [[ -f "$TRANSCRIPTS_DIR/${basename_noext}.txt" ]]; then
            transcript_status="yes"
        else
            transcript_status="no"
        fi

        printf "%-35s  %-10s  %s\n" "$(basename "$wav")" "$duration" "$transcript_status"
    done
}
