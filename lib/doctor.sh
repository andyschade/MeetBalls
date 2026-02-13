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

    local core_failures=0
    local live_failures=0

    mb_info "Checking dependencies..."

    # 1. Audio backend
    local backend
    if backend=$(mb_detect_audio_backend 2>/dev/null); then
        case "$backend" in
            pw-record) mb_info "  audio:          OK (PipeWire)" ;;
            parecord)  mb_info "  audio:          OK (PulseAudio)" ;;
            arecord)   mb_info "  audio:          OK (ALSA)" ;;
            *)         mb_info "  audio:          OK ($backend)" ;;
        esac
    else
        mb_info "  audio:          MISSING — install pipewire, pulseaudio, or alsa-utils"
        core_failures=$((core_failures + 1))
    fi

    # 2. whisper-cli
    if mb_check_command whisper-cli; then
        mb_info "  whisper-cli:    OK"
    else
        mb_info "  whisper-cli:    MISSING — see https://github.com/ggerganov/whisper.cpp"
        core_failures=$((core_failures + 1))
    fi

    # 3. Whisper model
    if mb_find_whisper_model >/dev/null 2>&1; then
        mb_info "  model:          OK ($WHISPER_MODEL)"
    else
        mb_info "  model:          MISSING — download with: whisper-cli -dl $WHISPER_MODEL"
        core_failures=$((core_failures + 1))
    fi

    # 4. claude CLI
    if mb_check_command claude; then
        mb_info "  claude:         OK (Claude Code CLI)"
    else
        mb_info "  claude:         MISSING — see https://docs.anthropic.com/en/docs/claude-code"
        core_failures=$((core_failures + 1))
    fi

    # 5. Disk space
    local avail_kb avail_mb avail_gb
    avail_kb=$(df -k "$MEETBALLS_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    avail_mb=$(( avail_kb / 1024 ))
    avail_gb=$(awk "BEGIN {printf \"%.1f\", $avail_mb / 1024}")
    if (( avail_mb >= MIN_DISK_MB )); then
        mb_info "  disk space:     OK (${avail_gb} GB free)"
    else
        mb_info "  disk space:     LOW — less than ${MIN_DISK_MB}MB free (${avail_gb} GB free)"
        core_failures=$((core_failures + 1))
    fi

    # Live mode checks
    mb_info ""
    mb_info "Live mode:"

    # 6. tmux
    if mb_check_command tmux; then
        mb_info "  tmux:           OK"
    else
        mb_info "  tmux:           MISSING — install: sudo apt install tmux"
        live_failures=$((live_failures + 1))
    fi

    # 7. whisper-stream
    if mb_check_command whisper-stream; then
        mb_info "  whisper-stream: OK"
    else
        mb_info "  whisper-stream: MISSING — run install.sh to build, or see whisper.cpp docs"
        live_failures=$((live_failures + 1))
    fi

    # 8. libsdl2
    if dpkg -s libsdl2-dev >/dev/null 2>&1; then
        mb_info "  libsdl2:        OK"
    else
        mb_info "  libsdl2:        MISSING — install: sudo apt install libsdl2-dev"
        live_failures=$((live_failures + 1))
    fi

    # Summary
    mb_info ""
    if (( core_failures == 0 && live_failures == 0 )); then
        mb_success "All checks passed."
        return 0
    elif (( core_failures == 0 )); then
        mb_warn "All core checks passed. $live_failures live-mode check(s) failed."
        return 0
    else
        mb_error "$core_failures check(s) failed."
        return 1
    fi
}
