# MeetBalls — Live command: real-time transcription with Q&A via tmux split-pane

cmd_live() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs live

Start a live transcription session with interactive Q&A.

Opens a tmux split-pane TUI:
  Top pane:    Real-time transcript from whisper-stream
  Bottom pane: Interactive Q&A — ask Claude about the meeting so far

On exit, transcript and audio are saved to ~/.meetballs/.

Options:
  --help    Show this help message

Examples:
  meetballs live
EOF
        return 0
    fi

    # Validate dependencies (order matters — most fundamental first)
    mb_require_command tmux "Install: sudo apt install tmux"
    mb_require_command whisper-stream "Run install.sh to build it, or see whisper.cpp docs."
    mb_require_command claude "Install Claude Code CLI from https://docs.anthropic.com/en/docs/claude-code"

    local model_path
    model_path=$(mb_require_whisper_model)

    # Initialize directories and check disk space
    mb_init
    mb_check_disk_space || true

    # Pre-flight: verify PulseAudio is running (catches dead audio before launching tmux)
    if mb_check_command pactl; then
        if ! pactl info >/dev/null 2>&1; then
            mb_error "PulseAudio is not responding."
            mb_error "On WSL2: close all terminals, run 'wsl --shutdown' in PowerShell, then reopen."
            mb_die "Fix audio first, then retry 'meetballs live'."
        fi
    fi

    # Kill stale session if one exists
    if tmux has-session -t meetballs-live 2>/dev/null; then
        tmux kill-session -t meetballs-live
    fi

    # Create session directory
    local TIMESTAMP
    TIMESTAMP=$(mb_timestamp)
    local SESSION_DIR="$LIVE_DIR/$TIMESTAMP"
    mkdir -p "$SESSION_DIR"

    # Generate transcriber.sh (unquoted heredoc — variables expand at write time)
    cat > "$SESSION_DIR/transcriber.sh" <<EOF
#!/usr/bin/env bash
cd "$SESSION_DIR"

# --- Audio environment setup ---
# tmux/new shells don't inherit these; WSLg needs them for PulseAudio
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}"
if [[ -z "\${PULSE_SERVER:-}" ]] && [[ -S /mnt/wslg/PulseServer ]]; then
    export PULSE_SERVER="unix:/mnt/wslg/PulseServer"
fi

# Force SDL2 to use PulseAudio (skip ALSA which doesn't work on WSL2)
export SDL_AUDIODRIVER=pulse

# --- PulseAudio health check and recovery ---
wait_for_pulseaudio() {
    local attempt=0
    local max_attempts=15
    while [[ \$attempt -lt \$max_attempts ]]; do
        if pactl info >/dev/null 2>&1; then
            return 0
        fi
        attempt=\$((attempt + 1))
        if [[ \$attempt -eq 1 ]]; then
            echo "[Audio disconnected — waiting for PulseAudio to recover...]"
        fi
        sleep 2
    done
    echo "[PulseAudio not responding after \$((max_attempts * 2))s]"
    return 1
}

echo "Starting live transcription... (Ctrl+C to stop)"
echo "Model: $WHISPER_MODEL"
echo "---"

# --- Main loop: auto-restart on audio drops ---
# Resets retry counter on successful runs (>30s = real transcription, not instant crash)
max_retries=10
retry_count=0
user_quit=false

while [[ \$retry_count -lt \$max_retries ]] && [[ "\$user_quit" != true ]]; do
    # Wait for audio to be available before (re)starting
    if ! wait_for_pulseaudio; then
        retry_count=\$((retry_count + 1))
        echo "[No audio — retry \$retry_count/\$max_retries]"
        continue
    fi

    start_time=\$(date +%s)

    whisper-stream \\
        -m "$model_path" \\
        --step 3000 \\
        --length 10000 \\
        -f "$SESSION_DIR/transcript.txt" \\
        --save-audio \\
        -l en

    exit_code=\$?
    run_duration=\$(( \$(date +%s) - start_time ))

    # Ctrl+C (130) or clean exit (0) — user wants to stop
    if [[ \$exit_code -eq 0 ]] || [[ \$exit_code -eq 130 ]]; then
        user_quit=true
        break
    fi

    # If it ran for >30s, it was working — reset retry counter (audio blip, not broken)
    if [[ \$run_duration -gt 30 ]]; then
        retry_count=0
    fi

    retry_count=\$((retry_count + 1))
    echo ""
    echo "[whisper-stream stopped (code \$exit_code, ran \${run_duration}s) — restarting \$retry_count/\$max_retries...]"
    sleep 2
done

if [[ "\$user_quit" == true ]]; then
    tmux kill-session -t meetballs-live 2>/dev/null
elif [[ \$retry_count -ge \$max_retries ]]; then
    echo ""
    echo "whisper-stream failed \$max_retries times. Audio device may be unavailable."
    echo "Check: is your mic connected? Try 'pactl info' in another terminal."
    echo "Press Enter to close session..."
    read -r
    tmux kill-session -t meetballs-live 2>/dev/null
fi
EOF
    chmod +x "$SESSION_DIR/transcriber.sh"

    # Generate asker.sh (unquoted heredoc — variables expand at write time)
    cat > "$SESSION_DIR/asker.sh" <<EOF
#!/usr/bin/env bash
TRANSCRIPT_FILE="$SESSION_DIR/transcript.txt"

echo "Meeting Q&A — type a question, or 'quit' to end session"
echo ""

while true; do
    printf "> "
    read -r question || break  # EOF = exit

    # Handle exit commands
    case "\$question" in
        quit|exit) break ;;
        "") continue ;;
    esac

    # Read current transcript
    transcript=""
    if [[ -f "\$TRANSCRIPT_FILE" ]]; then
        transcript=\$(<"\$TRANSCRIPT_FILE")
    fi

    if [[ -z "\$transcript" ]]; then
        echo "(No transcript yet — keep talking!)"
        echo ""
        continue
    fi

    # Build system prompt and call Claude
    system_prompt="You are a meeting assistant. A meeting is in progress.
Answer questions based on the transcript so far.
Be concise and specific. If the answer isn't in the transcript, say so.

<transcript>
\${transcript}
</transcript>"

    claude -p "\$question" --append-system-prompt "\$system_prompt"
    echo ""
done

# Kill tmux session on exit
tmux kill-session -t meetballs-live 2>/dev/null
EOF
    chmod +x "$SESSION_DIR/asker.sh"

    # Create tmux session and split panes
    mb_info "Starting live session..."

    # Create bare-shell panes first, then send commands via send-keys.
    # This avoids two issues:
    #   1. Hardcoded :0.0 indices break when user has base-index 1
    #   2. If a command exits immediately, the pane stays alive showing the error
    set +e
    tmux new-session -d -s meetballs-live
    tmux split-window -v -t meetballs-live -l 10
    # Bottom pane is active after split — send asker command there
    tmux send-keys -t meetballs-live "bash '${SESSION_DIR}/asker.sh'" Enter
    # Select top pane and send transcriber command
    tmux select-pane -U -t meetballs-live
    tmux send-keys -t meetballs-live "bash '${SESSION_DIR}/transcriber.sh'" Enter
    tmux attach-session -t meetballs-live
    set -e

    # --- Cleanup ---
    local saved_transcript=false
    local saved_recording=false

    if [[ -f "$SESSION_DIR/transcript.txt" ]]; then
        cp "$SESSION_DIR/transcript.txt" "$TRANSCRIPTS_DIR/$TIMESTAMP.txt" || true
        saved_transcript=true
    fi

    if ls "$SESSION_DIR"/*.wav 1>/dev/null 2>&1; then
        cp "$SESSION_DIR"/*.wav "$RECORDINGS_DIR/$TIMESTAMP.wav" || true
        saved_recording=true
    fi

    echo ""
    mb_info "Session ended."
    if [[ "$saved_transcript" == true ]]; then
        mb_success "Transcript saved: $TRANSCRIPTS_DIR/$TIMESTAMP.txt"
    else
        mb_info "No transcript to save."
    fi
    if [[ "$saved_recording" == true ]]; then
        mb_success "Recording saved: $RECORDINGS_DIR/$TIMESTAMP.wav"
    else
        mb_info "No recording to save."
    fi

    # Remove session directory only after successful copy of both files
    if [[ "$saved_transcript" == true ]] && [[ "$saved_recording" == true ]]; then
        rm -rf "$SESSION_DIR"
    fi
}
