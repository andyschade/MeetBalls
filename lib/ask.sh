# MeetBalls — Ask command: Q&A against a meeting transcript via Claude Code CLI

cmd_ask() {
    local context_paths=()
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                cat <<'EOF'
Usage: meetballs ask [options] <transcript> ["question"]

Ask questions about a meeting transcript using Claude Code CLI.

With a question:  single-shot mode — prints answer and exits.
Without question:  interactive mode — launches Claude session with transcript loaded.

Options:
  --context <path>   Add project file/directory as context (repeatable)
  --help             Show this help message

Examples:
  meetballs ask transcript.txt "What action items were discussed?"
  meetballs ask --context ./src transcript.txt "Summarize the API discussion"
  meetballs ask transcript.txt
EOF
                return 0
                ;;
            --context)
                [[ -n "${2:-}" ]] || mb_die "--context requires a path argument"
                context_paths+=("$2")
                shift 2
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # Validate transcript argument
    if [[ ${#positional[@]} -lt 1 ]]; then
        mb_die "Missing transcript file argument. Usage: meetballs ask [--context <path>] <transcript> [\"question\"]"
    fi

    local transcript_file="${positional[0]}"

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

    # Append project context if provided
    if [[ ${#context_paths[@]} -gt 0 ]]; then
        local context
        context=$(mb_gather_context "${context_paths[@]}")
        if [[ -n "$context" ]]; then
            system_prompt="${system_prompt}

<project-context>
${context}
</project-context>"
        fi
    fi

    # Invoke claude in the appropriate mode
    if [[ ${#positional[@]} -ge 2 ]]; then
        # Single-shot mode: question provided as second argument
        local question="${positional[1]}"
        claude -p "$question" --append-system-prompt "$system_prompt"
    else
        # Interactive mode: no question, launch interactive session
        claude --append-system-prompt "$system_prompt"
    fi
}
