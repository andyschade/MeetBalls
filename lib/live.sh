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
    if ! mb_check_command tmux; then
        mb_die "tmux not found. Install: sudo apt install tmux"
    fi
    if ! mb_check_command whisper-stream; then
        mb_die "whisper-stream not found. Run install.sh to build it, or see whisper.cpp docs."
    fi
    if ! mb_check_command claude; then
        mb_die "claude not found. Install Claude Code CLI from https://docs.anthropic.com/en/docs/claude-code"
    fi

    local model_path
    model_path=$(mb_find_whisper_model) || true
    if [[ -z "$model_path" ]]; then
        mb_die "Whisper model not found (ggml-${WHISPER_MODEL}.bin). Download: whisper-cli -dl ${WHISPER_MODEL}"
    fi

    # Initialize directories and check disk space
    mb_init
    mb_check_disk_space || true

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

echo "Starting live transcription... (Ctrl+C to stop)"
echo "Model: $WHISPER_MODEL"
echo "---"

whisper-stream \\
    -m "$model_path" \\
    --step 3000 \\
    --length 10000 \\
    --no-timestamps \\
    -f "$SESSION_DIR/transcript.txt" \\
    --save-audio \\
    -l en

# If whisper-stream exits (Ctrl+C or error), kill the tmux session
tmux kill-session -t meetballs-live 2>/dev/null
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
    tmux new-session -d -s meetballs-live -x 200 -y 50
    tmux split-window -v -t meetballs-live -p 20
    tmux send-keys -t meetballs-live:0.0 "bash $SESSION_DIR/transcriber.sh" Enter
    tmux send-keys -t meetballs-live:0.1 "bash $SESSION_DIR/asker.sh" Enter

    # Attach to session (blocks until user exits/detaches)
    tmux attach-session -t meetballs-live

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
