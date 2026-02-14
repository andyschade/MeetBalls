# MeetBalls — Ask command: Q&A against a meeting transcript via Claude Code CLI

cmd_ask() {
    if [[ "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: meetballs ask <transcript> ["question"]

Ask questions about a meeting transcript using Claude Code CLI.

With a question:  single-shot mode — prints answer and exits.
Without question:  interactive mode — launches Claude session with transcript loaded.

Options:
  --help    Show this help message

Examples:
  meetballs ask ~/.meetballs/transcripts/2026-02-12T14-30-00.txt "What action items were discussed?"
  meetballs ask ~/.meetballs/transcripts/2026-02-12T14-30-00.txt
EOF
        return 0
    fi

    # Validate transcript argument
    if [[ $# -lt 1 ]]; then
        mb_die "Missing transcript file argument. Usage: meetballs ask <transcript> [\"question\"]"
    fi

    local transcript_file="$1"

    mb_require_file "$transcript_file" "Transcript file"
    mb_require_command claude "Install Claude Code CLI from https://docs.anthropic.com/en/docs/claude-code"

    # Read transcript content
    local transcript_content
    transcript_content=$(<"$transcript_file")

    # Build system prompt with embedded transcript
    local system_prompt
    system_prompt="You are a meeting assistant. Answer questions based on the following meeting transcript.
Be concise and specific. If the answer isn't in the transcript, say so.

<transcript>
${transcript_content}
</transcript>"

    # Invoke claude in the appropriate mode
    if [[ $# -ge 2 ]]; then
        # Single-shot mode: question provided as second argument
        local question="$2"
        claude -p "$question" --append-system-prompt "$system_prompt"
    else
        # Interactive mode: no question, launch interactive session
        claude --append-system-prompt "$system_prompt"
    fi
}
