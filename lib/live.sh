# MeetBalls — Live command: real-time transcription with Q&A via tmux split-pane

cmd_live() {
    local context_paths=()
    local save_here=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                cat <<'EOF'
Usage: meetballs live [options]

Start a live transcription session with interactive Q&A.

Opens a tmux split-pane TUI:
  Top pane:    Real-time transcript from whisper-stream
  Bottom pane: Interactive Q&A — ask Claude about the meeting so far

On exit, transcript and audio are saved to ~/.meetballs/.

Options:
  --context <path>   Add project file/directory as context for Q&A (repeatable)
  --save-here        Also save transcript, recording, and Q&A log to ./meetballs/
  --help             Show this help message

Examples:
  meetballs live
  meetballs live --context .
  meetballs live --context ./src --context README.md --save-here
EOF
                return 0
                ;;
            --context)
                [[ -n "${2:-}" ]] || mb_die "--context requires a path argument"
                context_paths+=("$2")
                shift 2
                ;;
            --save-here)
                save_here=true
                shift
                ;;
            *)
                mb_die "Unknown option: $1. Run 'meetballs live --help' for usage."
                ;;
        esac
    done

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

    # Session logging
    local LOG_FILE="$SESSION_DIR/session.log"
    local WHISPER_STDERR="$SESSION_DIR/whisper-stream.stderr"
    local CLAUDE_STDERR="$SESSION_DIR/claude.stderr"
    export MB_LOG_FILE="$LOG_FILE"
    mb_log "session started"

    # Generate project context if --context was used
    if [[ ${#context_paths[@]} -gt 0 ]]; then
        mb_gather_context "${context_paths[@]}" > "$SESSION_DIR/project-context.txt"
        mb_log "project context generated (${#context_paths[@]} paths)"
    fi

    # Generate transcriber.sh (unquoted heredoc — variables expand at write time)
    cat > "$SESSION_DIR/transcriber.sh" <<EOF
#!/usr/bin/env bash
source "$LIB_DIR/common.sh"
export MB_LOG_FILE="$SESSION_DIR/session.log"
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

printf "Loading model... (this takes a few seconds)"

# Background watcher: replace loading line once transcript appears
(
    while true; do
        if [[ -f "$SESSION_DIR/transcript.txt" ]] && [[ -s "$SESSION_DIR/transcript.txt" ]]; then
            printf "\rReady — listening.                        \n"
            echo "---"
            break
        fi
        sleep 0.5
    done
) &
_WATCHER_PID=\$!

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

    mb_log "whisper-stream starting (attempt \$((retry_count + 1)))"
    whisper-stream \\
        -m "$model_path" \\
        --step 3000 \\
        --length 10000 \\
        -f "$SESSION_DIR/transcript.txt" \\
        --save-audio \\
        -l en 2>>"$SESSION_DIR/whisper-stream.stderr"

    exit_code=\$?
    run_duration=\$(( \$(date +%s) - start_time ))

    # Ctrl+C (130) or clean exit (0) — user wants to stop
    if [[ \$exit_code -eq 0 ]] || [[ \$exit_code -eq 130 ]]; then
        mb_log "user quit (exit_code=\$exit_code)"
        user_quit=true
        break
    fi

    # If it ran for >30s, it was working — reset retry counter (audio blip, not broken)
    if [[ \$run_duration -gt 30 ]]; then
        retry_count=0
    fi

    retry_count=\$((retry_count + 1))
    mb_log "whisper-stream stopped (code=\$exit_code, ran=\${run_duration}s, retry=\$retry_count/\$max_retries)"
    echo ""
    echo "[whisper-stream stopped (code \$exit_code, ran \${run_duration}s) — restarting \$retry_count/\$max_retries...]"
    sleep 2
done

kill \$_WATCHER_PID 2>/dev/null || true

if [[ "\$user_quit" == true ]]; then
    mb_log "session ended by user"
    tmux kill-session -t meetballs-live 2>/dev/null
elif [[ \$retry_count -ge \$max_retries ]]; then
    mb_diagnostic_dump "whisper-stream failed \$max_retries times" "\$exit_code" "whisper-stream" "$SESSION_DIR/whisper-stream.stderr"
    echo ""
    echo "whisper-stream failed \$max_retries times. Audio device may be unavailable."
    echo "Check: is your mic connected? Try 'pactl info' in another terminal."
    echo "Diagnostic dump saved — run 'meetballs logs --last' to view."
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
QA_LOG="$SESSION_DIR/qa.log"

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

    # Append project context if available
    if [[ -f "$SESSION_DIR/project-context.txt" ]]; then
        system_prompt="\${system_prompt}

<project-context>
\$(<"$SESSION_DIR/project-context.txt")
</project-context>"
    fi

    # Log question
    echo "Q: \$question" >> "\$QA_LOG"

    # Call Claude, tee answer to log and terminal
    answer=\$(claude -p "\$question" --append-system-prompt "\$system_prompt" 2>>"$SESSION_DIR/claude.stderr")
    echo "\$answer"
    echo "A: \$answer" >> "\$QA_LOG"
    echo "---" >> "\$QA_LOG"
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
    local saved_qa=false

    if [[ -f "$SESSION_DIR/transcript.txt" ]]; then
        cp "$SESSION_DIR/transcript.txt" "$TRANSCRIPTS_DIR/$TIMESTAMP.txt" || true
        saved_transcript=true
    fi

    if ls "$SESSION_DIR"/*.wav 1>/dev/null 2>&1; then
        cp "$SESSION_DIR"/*.wav "$RECORDINGS_DIR/$TIMESTAMP.wav" || true
        saved_recording=true
    fi

    if [[ -f "$SESSION_DIR/qa.log" ]]; then
        cp "$SESSION_DIR/qa.log" "$LOGS_DIR/$TIMESTAMP.qa.log" || true
        saved_qa=true
    fi

    # Copy session log to logs directory
    if [[ -f "$LOG_FILE" ]]; then
        cp "$LOG_FILE" "$LOGS_DIR/$TIMESTAMP.log" || true
    fi

    echo ""
    mb_info "Session ended."
    if [[ "$saved_transcript" == true ]]; then
        mb_success "Transcript saved: $TRANSCRIPTS_DIR/$TIMESTAMP.txt"
    fi
    if [[ "$saved_recording" == true ]]; then
        mb_success "Recording saved: $RECORDINGS_DIR/$TIMESTAMP.wav"
    fi
    if [[ "$saved_qa" == true ]]; then
        mb_success "Q&A log saved: $LOGS_DIR/$TIMESTAMP.qa.log"
    fi

    # --save-here: copy artifacts to ./meetballs/ in the working directory
    if [[ "$save_here" == true ]]; then
        mkdir -p ./meetballs
        if [[ "$saved_transcript" == true ]]; then
            cp "$TRANSCRIPTS_DIR/$TIMESTAMP.txt" ./meetballs/transcript.txt || true
            mb_success "Copied transcript to ./meetballs/transcript.txt"
        fi
        if [[ "$saved_recording" == true ]]; then
            cp "$RECORDINGS_DIR/$TIMESTAMP.wav" ./meetballs/recording.wav || true
            mb_success "Copied recording to ./meetballs/recording.wav"
        fi
        if [[ "$saved_qa" == true ]]; then
            cp "$LOGS_DIR/$TIMESTAMP.qa.log" ./meetballs/qa.log || true
            mb_success "Copied Q&A log to ./meetballs/qa.log"
        fi
    fi

    mb_log "session cleanup complete"
}
