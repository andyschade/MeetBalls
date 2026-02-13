# MeetBalls — Doctor command: check system dependencies

cmd_doctor() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs doctor

Check that all dependencies are installed and report their status.

Options:
  --help    Show this help message

Examples:
  meetballs doctor
EOF
        return 0
    fi

    mb_init

    local failures=0

    mb_info "Checking dependencies..."

    # 1. Audio backend
    local backend
    if backend=$(mb_detect_audio_backend 2>/dev/null); then
        case "$backend" in
            pw-record) mb_info "  audio:       OK (PipeWire)" ;;
            parecord)  mb_info "  audio:       OK (PulseAudio)" ;;
            arecord)   mb_info "  audio:       OK (ALSA)" ;;
            *)         mb_info "  audio:       OK ($backend)" ;;
        esac
    else
        mb_info "  audio:       MISSING — install pipewire, pulseaudio, or alsa-utils"
        failures=$((failures + 1))
    fi

    # 2. whisper-cli
    if mb_check_command whisper-cli; then
        mb_info "  whisper-cli: OK"
    else
        mb_info "  whisper-cli: MISSING — see https://github.com/ggerganov/whisper.cpp"
        failures=$((failures + 1))
    fi

    # 3. Whisper model
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
    if $model_found; then
        mb_info "  model:       OK ($WHISPER_MODEL)"
    else
        mb_info "  model:       MISSING — run: whisper-cli -dl $WHISPER_MODEL"
        failures=$((failures + 1))
    fi

    # 4. claude CLI
    if mb_check_command claude; then
        mb_info "  claude:      OK (Claude Code CLI)"
    else
        mb_info "  claude:      MISSING — see https://docs.anthropic.com/en/docs/claude-code"
        failures=$((failures + 1))
    fi

    # 5. Disk space
    local avail_kb avail_mb avail_gb
    avail_kb=$(df -k "$MEETBALLS_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    avail_mb=$(( avail_kb / 1024 ))
    avail_gb=$(awk "BEGIN {printf \"%.1f\", $avail_mb / 1024}")
    if (( avail_mb >= MIN_DISK_MB )); then
        mb_info "  disk space:  OK (${avail_gb} GB free)"
    else
        mb_info "  disk space:  LOW — less than ${MIN_DISK_MB}MB free (${avail_gb} GB free)"
        failures=$((failures + 1))
    fi

    # Summary
    if (( failures == 0 )); then
        mb_success "All checks passed."
        return 0
    else
        mb_error "$failures check(s) failed."
        return 1
    fi
}
