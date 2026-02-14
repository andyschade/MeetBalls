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

On exit, session is saved to ~/.meetballs/sessions/<session-name>/.

Options:
  --context <path>   Add project file/directory as context for Q&A (repeatable)
  --save-here        Also copy session folder to ./meetballs/<session-name>/
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

    # Initialize session state in live dir (pipeline reads/updates this)
    mb_init_session_state "$SESSION_DIR"

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

    # Detect diarization tier for transcriber configuration
    local DIARIZE_TIER
    DIARIZE_TIER=$(mb_detect_diarization_tier)
    mb_log "diarization tier: $DIARIZE_TIER"

    local TINYDIARIZE_FLAG=""
    if [[ "$DIARIZE_TIER" == "tinydiarize" ]]; then
        TINYDIARIZE_FLAG=" --tinydiarize"
    fi
    # Store tier so cleanup knows whether to run LLM fallback
    echo "$DIARIZE_TIER" > "$SESSION_DIR/diarize-tier.txt"

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
        -l en${TINYDIARIZE_FLAG} 2>>"$SESSION_DIR/whisper-stream.stderr"

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

    # Generate pipeline.sh — two-stage background processing pipeline
    # Stage 1: bash pattern matching on every transcript line (free, instant)
    # Stage 2: LLM refinement when triggers fire (haiku, cheap)
    cat > "$SESSION_DIR/pipeline.sh" <<'PIPELINE_EOF'
#!/usr/bin/env bash
# MeetBalls — Background processing pipeline
# Reads new transcript lines via tail -f, applies Stage 1 pattern matching,
# and calls LLM (Stage 2) when triggers fire to update session-state.md.

SESSION_DIR="__SESSION_DIR__"
TRANSCRIPT_FILE="$SESSION_DIR/transcript.txt"
SESSION_STATE="$SESSION_DIR/session-state.md"
PIPELINE_LOG="$SESSION_DIR/pipeline.log"

log() {
    printf '[%s] pipeline: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$PIPELINE_LOG"
}

# --- Session state helpers ---

# Read a section value from session-state.md (first non-empty line after ## Header)
read_state_section() {
    local section="$1"
    if [[ ! -f "$SESSION_STATE" ]]; then
        echo ""
        return
    fi
    local in_section=false
    while IFS= read -r line; do
        if [[ "$line" == "## $section" ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == true ]]; then
            # Stop at next section header
            if [[ "$line" == "## "* ]]; then
                break
            fi
            # Return first non-empty line
            if [[ -n "$line" ]]; then
                echo "$line"
                return
            fi
        fi
    done < "$SESSION_STATE"
    echo ""
}

# Read current hat from session-state.md
read_hat() {
    read_state_section "Hat"
}

# Check if initialization concern is resolved
read_initialized() {
    read_state_section "Initialized"
}

# Check if a section has content (any non-empty lines between ## Header and next ##)
section_has_content() {
    local section="$1"
    if [[ ! -f "$SESSION_STATE" ]]; then
        return 1
    fi
    local in_section=false
    while IFS= read -r line; do
        if [[ "$line" == "## $section" ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == true ]]; then
            if [[ "$line" == "## "* ]]; then
                return 1
            fi
            if [[ -n "$line" ]] && [[ "$line" != "(none)" ]]; then
                return 0
            fi
        fi
    done < "$SESSION_STATE"
    return 1
}

# --- Stage 1: Pattern matching ---
# Returns space-separated trigger types, or empty string if no match.
stage1_detect() {
    local line="$1"
    local triggers=""

    # Wake word detection (case-insensitive)
    if echo "$line" | grep -qi "meetballs"; then
        triggers="${triggers:+$triggers }wake-word"
    fi

    # Action-item triggers
    if echo "$line" | grep -qiE "(I'll|I will|by friday|by monday|by tuesday|by wednesday|by thursday|by saturday|by sunday|by tomorrow|by next week|by end of|take that on|deadline|action item)"; then
        triggers="${triggers:+$triggers }action-item"
    fi

    # Decision triggers
    if echo "$line" | grep -qiE "(agreed|decided|let's go with|lets go with|consensus|final answer|we've decided|we decided|decision is|the call is)"; then
        triggers="${triggers:+$triggers }decision"
    fi

    # Initialization triggers (speakers/agenda) — suppressed once initialized
    if echo "$line" | grep -qiE "(Hi I'm|My name is|I'm [A-Z]|Today we're going to|The agenda is|Let's cover|we'll discuss|we will discuss|nice to meet)"; then
        triggers="${triggers:+$triggers }initialization"
    fi

    echo "$triggers"
}

# --- Wake word command parsing ---
# Extracts the command after "meetballs" from a line.
# Returns: hat name (research|fact-check|timekeeper|wrap-up) or state (mute|unmute) or empty
parse_wake_command() {
    local line="$1"
    # Extract text after "meetballs" (case-insensitive)
    local after
    after=$(echo "$line" | sed -n 's/.*[Mm][Ee][Ee][Tt][Bb][Aa][Ll][Ll][Ss]\s*//Ip')
    # Normalize to lowercase for matching
    local cmd
    cmd=$(echo "$after" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//' | cut -d' ' -f1)

    case "$cmd" in
        research)    echo "research" ;;
        fact-check|factcheck|fact)  echo "fact-check" ;;
        timekeeper|timer|time)      echo "timekeeper" ;;
        wrap-up|wrapup|wrap)        echo "wrap-up" ;;
        mute)        echo "mute" ;;
        unmute)      echo "unmute" ;;
        *)           echo "" ;;
    esac
}

# --- Handle wake word commands ---
# Processes wake word triggers: hat transitions, mute/unmute, wrap-up
handle_wake_word() {
    local line="$1"
    local cmd
    cmd=$(parse_wake_command "$line")

    case "$cmd" in
        research)
            log "hat-transition: research requested"
            log "research requested: $(echo "$line" | sed -n 's/.*[Mm][Ee][Ee][Tt][Bb][Aa][Ll][Ll][Ss]\s*[Rr]esearch\s*//p')"
            ;;
        fact-check)
            log "hat-transition: fact-check requested"
            log "fact-check requested: $(echo "$line" | sed -n 's/.*[Mm][Ee][Ee][Tt][Bb][Aa][Ll][Ll][Ss]\s*[^ ]*\s*//p')"
            ;;
        timekeeper)
            log "hat-transition: timekeeper activated"
            log "timekeeper activated"
            ;;
        wrap-up)
            log "hat-transition: wrap-up triggered"
            stage2_wrapup
            return
            ;;
        mute)
            log "state-change: mute"
            ;;
        unmute)
            log "state-change: unmute"
            ;;
        *)
            # Unknown command — let stage2 handle it
            return 1
            ;;
    esac

    # For hat transitions (not mute/unmute), update ## Hat in session-state.md
    if [[ "$cmd" != "mute" ]] && [[ "$cmd" != "unmute" ]] && [[ "$cmd" != "wrap-up" ]]; then
        # Active hats are mutually exclusive — new hat replaces current
        if [[ -f "$SESSION_STATE" ]]; then
            sed -i '/^## Hat$/,/^## /{/^## Hat$/!{/^## /!s/.*/'"$cmd"'/;}}' "$SESSION_STATE"
            # sed replaces all lines between ## Hat and next ## — but we only want the value line
            # Simpler: just replace the line after ## Hat
            local tmp
            tmp=$(awk -v hat="$cmd" '
                /^## Hat$/ { print; getline; print hat; next }
                { print }
            ' "$SESSION_STATE")
            echo "$tmp" > "$SESSION_STATE"
            log "hat updated to: $cmd"
        fi
    elif [[ "$cmd" == "mute" ]] || [[ "$cmd" == "unmute" ]]; then
        # Update ## Muted section
        local muted_val="true"
        [[ "$cmd" == "unmute" ]] && muted_val="false"
        if [[ -f "$SESSION_STATE" ]]; then
            local tmp
            tmp=$(awk -v val="$muted_val" '
                /^## Muted$/ { print; getline; print val; next }
                { print }
            ' "$SESSION_STATE")
            echo "$tmp" > "$SESSION_STATE"
            log "muted updated to: $muted_val"
        fi
    fi
}

# --- Stage 2: LLM refinement ---
# Called when Stage 1 detects triggers. Sends context to haiku for state update.
stage2_refine() {
    local triggered_line="$1"
    local trigger_types="$2"

    # Read current session state
    local state=""
    if [[ -f "$SESSION_STATE" ]]; then
        state=$(<"$SESSION_STATE")
    fi

    # Read last ~20 lines of transcript for context
    local context=""
    if [[ -f "$TRANSCRIPT_FILE" ]]; then
        context=$(tail -n 20 "$TRANSCRIPT_FILE")
    fi

    # Build system prompt with enhanced formatting rules for passive hats
    local system_prompt="You are MeetBalls, a meeting facilitation assistant. Given the current session state and recent transcript context, analyze the triggered line and update the session state.

Only modify sections that need updating. Return the COMPLETE updated session-state.md content.

Trigger types detected: ${trigger_types}

Rules:
- For 'initialization': extract speaker names into ## Speakers (one per line, prefixed with '- '), agenda items into ## Agenda (one per line, prefixed with '- '). Once both Speakers and Agenda have at least one entry each, set ## Initialized to 'true'.
- For 'action-item': add to ## Action Items with owner and deadline. Format: '- [ ] Owner: task description (by deadline)'. Infer the owner from who is speaking and the deadline from context. If no deadline mentioned, omit the parenthetical.
- For 'decision': add to ## Decisions with context. Format: '- Decision description — context/reasoning'. Include what was decided and brief context for why.
- For 'wake-word': parse the command after 'meetballs' and update ## Hat if it's a hat change (research, fact-check, timekeeper). Active hats are mutually exclusive — new hat replaces current.
- Keep existing entries — append, don't overwrite
- Preserve all sections including ## Initialized
- Return ONLY the markdown content, no explanations"

    local user_prompt="<session-state>
${state}
</session-state>

<recent-transcript>
${context}
</recent-transcript>

<triggered-line>
${triggered_line}
</triggered-line>"

    log "stage2: triggers=[$trigger_types] line=[${triggered_line:0:80}]"

    # Call haiku via claude CLI
    local updated_state
    if updated_state=$(claude -p "$user_prompt" --model haiku --append-system-prompt "$system_prompt" 2>>"$PIPELINE_LOG"); then
        # Write updated state back — only if we got non-empty output
        if [[ -n "$updated_state" ]]; then
            echo "$updated_state" > "$SESSION_STATE"
            log "stage2: session-state.md updated"
        else
            log "stage2: empty response from LLM, skipping update"
        fi
    else
        log "stage2: claude call failed (exit=$?)"
    fi
}

# --- Stage 2: Wrap-up summary (uses sonnet for quality) ---
stage2_wrapup() {
    local state=""
    if [[ -f "$SESSION_STATE" ]]; then
        state=$(<"$SESSION_STATE")
    fi

    local transcript=""
    if [[ -f "$TRANSCRIPT_FILE" ]]; then
        transcript=$(<"$TRANSCRIPT_FILE")
    fi

    local system_prompt="You are MeetBalls, a meeting facilitation assistant. The user has triggered a wrap-up. Produce a comprehensive meeting summary.

Include these sections:
1. **Meeting Summary** — 3-5 sentence overview of what was discussed
2. **Decisions Made** — bullet list of all decisions from the session state and transcript
3. **Action Items** — bullet list with owners and deadlines
4. **Unresolved Questions** — anything that was raised but not answered or decided

Use the session state for structured data (action items, decisions, speakers) and the transcript for narrative context. Be concise but thorough."

    local user_prompt="<session-state>
${state}
</session-state>

<transcript>
${transcript}
</transcript>"

    log "stage2_wrapup: generating summary with sonnet"

    local summary
    if summary=$(claude -p "$user_prompt" --model sonnet --append-system-prompt "$system_prompt" 2>>"$PIPELINE_LOG"); then
        if [[ -n "$summary" ]]; then
            echo "$summary" > "$SESSION_DIR/summary.txt"
            log "stage2_wrapup: summary.txt written"
            # Update hat to wrap-up in session state
            if [[ -f "$SESSION_STATE" ]]; then
                local tmp
                tmp=$(awk '
                    /^## Hat$/ { print; getline; print "wrap-up"; next }
                    { print }
                ' "$SESSION_STATE")
                echo "$tmp" > "$SESSION_STATE"
            fi
        else
            log "stage2_wrapup: empty response from LLM"
        fi
    else
        log "stage2_wrapup: claude call failed (exit=$?)"
    fi
}

# --- Main loop ---
log "pipeline started"

# Wait for transcript file to appear
while [[ ! -f "$TRANSCRIPT_FILE" ]]; do
    sleep 1
done

log "transcript file detected, starting tail -f"

# Process new lines as they appear
tail -f "$TRANSCRIPT_FILE" 2>/dev/null | while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Stage 1: detect triggers
    triggers=$(stage1_detect "$line")

    # Suppress initialization triggers once initialized
    if [[ "$triggers" == *"initialization"* ]]; then
        local initialized
        initialized=$(read_initialized)
        if [[ "$initialized" == "true" ]]; then
            # Remove initialization from triggers
            triggers=$(echo "$triggers" | sed 's/initialization//g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
        fi
    fi

    # If any triggers fired, process them
    if [[ -n "$triggers" ]]; then
        log "stage1: triggers=[$triggers] line=[${line:0:80}]"

        # Handle wake word commands directly (hat transitions, mute/unmute, wrap-up)
        if [[ "$triggers" == *"wake-word"* ]]; then
            if handle_wake_word "$line"; then
                # Wake word was handled — remove it from triggers for stage2
                triggers=$(echo "$triggers" | sed 's/wake-word//g' | tr -s ' ' | sed 's/^ *//;s/ *$//')
            fi
        fi

        # Remaining triggers go to stage2 for LLM refinement
        if [[ -n "$triggers" ]]; then
            stage2_refine "$line" "$triggers"
        fi
    fi
done

log "pipeline ended"
PIPELINE_EOF
    # Replace placeholder with actual session dir path
    sed -i "s|__SESSION_DIR__|${SESSION_DIR}|g" "$SESSION_DIR/pipeline.sh"
    chmod +x "$SESSION_DIR/pipeline.sh"

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
    # Launch pipeline as background process (not a tmux pane — runs silently)
    bash "$SESSION_DIR/pipeline.sh" &
    local PIPELINE_PID=$!
    mb_log "pipeline started (pid=$PIPELINE_PID)"
    tmux attach-session -t meetballs-live
    set -e

    # --- Cleanup: kill pipeline and save artifacts ---
    if [[ -n "${PIPELINE_PID:-}" ]] && kill -0 "$PIPELINE_PID" 2>/dev/null; then
        kill "$PIPELINE_PID" 2>/dev/null || true
        wait "$PIPELINE_PID" 2>/dev/null || true
        mb_log "pipeline stopped (pid=$PIPELINE_PID)"
    fi

    local FINAL_SESSION_DIR
    FINAL_SESSION_DIR=$(mb_create_session_dir "$TIMESTAMP")
    mb_log "saving session to $FINAL_SESSION_DIR"

    # Copy artifacts from live temp dir to session folder
    if [[ -f "$SESSION_DIR/transcript.txt" ]]; then
        cp "$SESSION_DIR/transcript.txt" "$FINAL_SESSION_DIR/transcript.txt" || true
    fi

    if ls "$SESSION_DIR"/*.wav 1>/dev/null 2>&1; then
        cp "$SESSION_DIR"/*.wav "$FINAL_SESSION_DIR/recording.wav" || true
    fi

    if [[ -f "$SESSION_DIR/qa.log" ]]; then
        cp "$SESSION_DIR/qa.log" "$FINAL_SESSION_DIR/qa.log" || true
    fi

    if [[ -f "$LOG_FILE" ]]; then
        cp "$LOG_FILE" "$FINAL_SESSION_DIR/session.log" || true
    fi

    if [[ -f "$SESSION_DIR/pipeline.log" ]]; then
        cp "$SESSION_DIR/pipeline.log" "$FINAL_SESSION_DIR/pipeline.log" || true
    fi

    # Copy pipeline-updated session state, or initialize a blank one
    if [[ -f "$SESSION_DIR/session-state.md" ]]; then
        cp "$SESSION_DIR/session-state.md" "$FINAL_SESSION_DIR/session-state.md" || true
    else
        mb_init_session_state "$FINAL_SESSION_DIR"
    fi

    # Speaker diarization: LLM post-process fallback
    # When no real-time diarization was available (tier = llm-fallback), tag the
    # transcript with speaker names using Sonnet at session end.
    local saved_tier=""
    if [[ -f "$SESSION_DIR/diarize-tier.txt" ]]; then
        saved_tier=$(<"$SESSION_DIR/diarize-tier.txt")
    fi
    if [[ "$saved_tier" == "llm-fallback" ]] && [[ -f "$FINAL_SESSION_DIR/transcript.txt" ]]; then
        local raw_transcript
        raw_transcript=$(<"$FINAL_SESSION_DIR/transcript.txt")
        if [[ -n "$raw_transcript" ]]; then
            mb_info "Tagging transcript with speaker names..."
            mb_log "diarization: starting LLM post-process fallback"

            local speakers=""
            if [[ -f "$FINAL_SESSION_DIR/session-state.md" ]]; then
                # Extract Speakers section content
                local in_section=false
                while IFS= read -r line; do
                    if [[ "$line" == "## Speakers" ]]; then
                        in_section=true
                        continue
                    fi
                    if [[ "$in_section" == true ]]; then
                        if [[ "$line" == "## "* ]]; then
                            break
                        fi
                        if [[ -n "$line" ]]; then
                            speakers="${speakers:+$speakers\n}$line"
                        fi
                    fi
                done < "$FINAL_SESSION_DIR/session-state.md"
            fi

            local diarize_system="You are a transcript tagger. Given a raw meeting transcript and a list of speakers, produce a speaker-tagged version.

Rules:
- Tag each line with the most likely speaker: [Speaker] text
- Use [Unknown] when you cannot determine the speaker
- Infer speakers from context: who responds to whom, name mentions, speaking patterns
- Preserve the original text exactly — only add speaker tags
- Return ONLY the tagged transcript, no explanations"

            local diarize_prompt="<speakers>
${speakers}
</speakers>

<transcript>
${raw_transcript}
</transcript>"

            local tagged_transcript
            if tagged_transcript=$(claude -p "$diarize_prompt" --model sonnet --append-system-prompt "$diarize_system" 2>>"${LOG_FILE:-/dev/null}"); then
                if [[ -n "$tagged_transcript" ]]; then
                    echo "$tagged_transcript" > "$FINAL_SESSION_DIR/transcript.txt"
                    mb_log "diarization: transcript tagged with speaker names"
                    mb_success "Transcript tagged with speaker names."
                else
                    mb_log "diarization: empty response from LLM, keeping raw transcript"
                fi
            else
                mb_log "diarization: claude call failed (exit=$?), keeping raw transcript"
            fi
        fi
    fi

    echo ""
    mb_info "Session ended."
    mb_success "Session saved: $FINAL_SESSION_DIR"

    # --save-here: copy session folder to ./meetballs/<session-name>/ in CWD
    if [[ "$save_here" == true ]]; then
        local session_name
        session_name=$(basename "$FINAL_SESSION_DIR")
        local save_dest="./meetballs/$session_name"
        mkdir -p "$save_dest"
        cp -r "$FINAL_SESSION_DIR"/. "$save_dest/" || true
        mb_success "Copied session to $save_dest"
    fi

    mb_log "session cleanup complete"
}
