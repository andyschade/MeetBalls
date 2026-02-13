# MeetBalls — Inquisitor Questions

## Q1: `meetballs ask` interaction model

The spec says `meetballs ask <transcript> "<question>"` should "stream Claude's response to stdout"
AND "support follow-up questions (launch interactive Claude session with transcript loaded)."

**Question:** For `meetballs ask`, should providing a question (e.g., `meetballs ask transcript.txt "What were the action items?"`) give a single answer and exit, while omitting the question (e.g., `meetballs ask transcript.txt`) launch an interactive Claude session with the transcript preloaded — or should it always be interactive with the first question just being the initial prompt in the session?

This determines whether we use `claude -p "..."` (single-shot, pipe-friendly) or `claude` in
interactive mode, which are fundamentally different invocation patterns.

**Answer:**

Both modes, determined by whether a question argument is provided:

1. **`meetballs ask <transcript> "<question>"`** — Single-shot mode.
   Uses `claude -p` with the transcript piped as context via `--append-system-prompt`.
   Prints the answer to stdout and exits. This is pipe-friendly (`meetballs ask t.txt "summary" | pbcopy`).

2. **`meetballs ask <transcript>`** (no question) — Interactive mode.
   Launches `claude --system-prompt "..."` with the transcript content as system context.
   The user gets an interactive Claude session where they can ask multiple follow-up questions.

**Rationale:**
- The PROMPT.md UX example shows single-shot usage with a question argument, which implies pipe-friendly stdout output.
- "Support follow-up questions" maps naturally to interactive mode when no question is given.
- This dual behavior follows Unix conventions: provide arguments for scripting, omit for interactive use.
- Claude CLI supports both patterns natively: `-p` for single-shot, bare `claude` for interactive.

**Key implementation details:**
- Both modes prepend a system prompt instructing Claude to answer based on the transcript content.
- System prompt template: "You are a meeting assistant. Answer questions based on the following meeting transcript. Be concise and specific. If the answer isn't in the transcript, say so.\n\n<transcript>\n{content}\n</transcript>"
- Single-shot: `claude -p "$system_context\n\nQuestion: $question"` or `claude --append-system-prompt "$transcript_context" -p "$question"`
- Interactive: `claude --append-system-prompt "$transcript_context"`

**Status:** Answered
