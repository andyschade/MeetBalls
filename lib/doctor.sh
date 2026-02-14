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

    # 1. Audio backend (command exists)
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

    # 1b. Audio connectivity (can actually reach the audio server)
    if mb_check_command pactl; then
        if pactl info >/dev/null 2>&1; then
            local source_count
            source_count=$(pactl list sources short 2>/dev/null | wc -l)
            mb_info "  audio server:   OK ($source_count source(s) available)"
        else
            mb_info "  audio server:   DOWN — PulseAudio not responding"
            mb_info "                  WSL2 fix: close all terminals, run 'wsl --shutdown' in PowerShell"
            core_failures=$((core_failures + 1))
        fi
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
        mb_info "  model:          MISSING — download: bash ~/whisper.cpp/models/download-ggml-model.sh $WHISPER_MODEL"
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

    # Speaker diarization checks
    mb_info ""
    mb_info "Speaker diarization:"

    # 9. tinydiarize (whisper-stream built-in)
    local has_tinydiarize=false
    if mb_check_command whisper-stream; then
        if whisper-stream --help 2>&1 | grep -q "tinydiarize"; then
            mb_info "  tinydiarize:    OK (built-in)"
            has_tinydiarize=true
        else
            mb_info "  tinydiarize:    NOT AVAILABLE — whisper-stream lacks --tinydiarize support"
        fi
    else
        mb_info "  tinydiarize:    NOT AVAILABLE — whisper-stream not installed"
    fi

    # 10. pyannote-audio
    if python3 -c "import pyannote.audio" 2>/dev/null; then
        mb_info "  pyannote-audio: OK"
    else
        mb_info "  pyannote-audio: NOT INSTALLED"
        mb_info "                  For better speaker diarization, install pyannote-audio"
        mb_info "                  (recommended: 8GB+ RAM, dedicated GPU)"
        mb_info "                  pip install pyannote.audio"
    fi

    # 11. LLM fallback (always available if claude is present)
    mb_info "  llm-fallback:   OK (via claude CLI)"

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
