---
status: completed
created: 2026-02-12
started: 2026-02-13
completed: 2026-02-13
---
# Task: Ask Command + Tests (TDD)

## Description
Implement the `meetballs ask` command that loads a transcript, builds a system prompt, and invokes the Claude Code CLI in either single-shot mode (with a question) or interactive mode (without a question). This is the Q&A interface — the command that makes transcripts useful.

## Background
The ask command has dual-mode behavior based on whether a question is provided:
- **With question**: `claude -p "$question" --append-system-prompt "$system_prompt"` — prints answer and exits
- **Without question**: `claude --append-system-prompt "$system_prompt"` — launches interactive session

The system prompt embeds the full transcript content so Claude can answer questions about the meeting. The `claude` CLI must be mocked in tests because it cannot run nested inside another Claude Code session (CLAUDECODE env var blocks it).

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.5 — Claude Q&A)

**Additional References:**
- specs/meetballs-cli/context.md (Claude CLI flags, nested session constraint)
- specs/meetballs-cli/plan.md (test_ask.bats test cases)
- specs/meetballs-cli/questions.md (Q1 answer: dual-mode rationale)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Entry function: `cmd_ask "$@"`
2. Handle `--help` flag — print usage with description and examples, exit 0
3. Validate argument: transcript file path must be provided and file must exist
4. Check `claude` CLI is available via `mb_check_command` — die with install URL if not
5. Read transcript content from file
6. Build system prompt:
   ```
   You are a meeting assistant. Answer questions based on the following meeting transcript.
   Be concise and specific. If the answer isn't in the transcript, say so.

   <transcript>
   {transcript_content}
   </transcript>
   ```
7. If question argument provided (second arg):
   - Single-shot mode: `claude -p "$question" --append-system-prompt "$system_prompt"`
8. If no question argument:
   - Interactive mode: `claude --append-system-prompt "$system_prompt"`
9. Pass through claude's exit code

## Dependencies
- Task 01 (common.sh: `mb_check_command`, `mb_die`)
- Task 02 (CLI dispatcher routes `ask` to this module)

## Implementation Approach
1. **RED**: Write `tests/test_ask.bats` with all test cases
2. **GREEN**: Implement `lib/ask.sh` with `cmd_ask` function
3. **REFACTOR**: Clean up system prompt construction

### Test cases (from plan):
- `--help` prints usage containing "Usage" and "ask", exit 0
- Errors on missing transcript arg (no args) → stderr contains error, exit 1
- Errors on nonexistent transcript (fake path) → stderr contains error, exit 1
- Errors when claude missing (no mock claude) → stderr contains error, exit 1
- Single-shot mode calls `claude -p` (mock claude, provide question) → mock claude receives `-p` flag
- Interactive mode calls `claude --append-system-prompt` (mock claude, no question) → mock claude receives `--append-system-prompt`
- System prompt contains transcript (mock claude that dumps args) → args contain transcript text

### Mock strategy:
- Mock `claude` as a script that:
  - Writes its received arguments to a file for later assertion
  - Echoes "Mock response" (or dumps args) to stdout
  - Exits 0
- Create fixture transcript files in `$MEETBALLS_DIR/transcripts/` with known content
- Verify the mock received the correct flags by reading the args file in assertions

## Acceptance Criteria

1. **Help flag**
   - Given the user runs `meetballs ask --help`
   - When output is examined
   - Then it contains "Usage" and "ask" and exits 0

2. **Missing transcript argument error**
   - Given no arguments are provided
   - When running `meetballs ask`
   - Then stderr contains an error and exits 1

3. **Nonexistent transcript error**
   - Given a path to a file that doesn't exist
   - When running `meetballs ask /fake/path.txt`
   - Then stderr contains an error and exits 1

4. **Missing claude CLI error**
   - Given claude is not on PATH
   - When running `meetballs ask <valid-transcript>`
   - Then stderr contains an error with install instructions and exits 1

5. **Single-shot mode invokes claude -p**
   - Given a valid transcript and a question argument
   - When running `meetballs ask <transcript> "What happened?"`
   - Then claude is called with `-p` flag and the question

6. **Interactive mode invokes claude --append-system-prompt**
   - Given a valid transcript and no question argument
   - When running `meetballs ask <transcript>`
   - Then claude is called with `--append-system-prompt` containing the transcript

7. **System prompt contains transcript content**
   - Given a transcript file with specific content
   - When running `meetballs ask <transcript> "question"`
   - Then the system prompt passed to claude contains the transcript text

8. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_ask.bats`
   - Then all tests pass

## Metadata
- **Complexity**: High
- **Labels**: command, ask, claude, Q&A
- **Required Skills**: Bash, bats-core testing, PATH mocking, argument handling
