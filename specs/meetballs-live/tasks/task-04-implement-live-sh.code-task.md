---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Implement `lib/live.sh` — core live transcription feature

## Description
Create `lib/live.sh` containing `cmd_live()` — the core feature that opens a tmux split-pane TUI with real-time transcription in the top pane and interactive Q&A in the bottom pane. This includes dependency validation, session setup, helper script generation, tmux orchestration, and post-session cleanup.

## Background
This is the highest-risk and most complex task. `cmd_live()` orchestrates the entire live session lifecycle:
1. Validates dependencies (tmux, whisper-stream, claude, whisper model)
2. Creates a session directory under `~/.meetballs/live/<timestamp>/`
3. Generates two helper scripts (`transcriber.sh` and `asker.sh`)
4. Launches a tmux session with split panes running the helper scripts
5. Blocks until the user exits/detaches
6. Runs cleanup: copies transcript and audio to standard MeetBalls directories

The generated scripts are standalone bash scripts (not functions), so they must NOT use the `local` keyword.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Sections 4.1, 4.2, 4.3, 5, 6)

**Additional References:**
- specs/meetballs-live/context.md (all integration points, esp. "Variable Expansion in Generated Scripts" and "No `local` in Generated Scripts")
- specs/meetballs-live/plan.md (Step 4)
- specs/meetballs-live/research/existing-patterns.md (Pattern 1: Module Structure, Pattern 3: Help Pattern, Pattern 5: Dependency Checking)
- specs/meetballs-live/requirements.md (R1-R7)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements

### Help
1. `cmd_live --help` prints usage information containing "Usage:" and exits 0
2. Help text uses heredoc with `'EOF'` (quoted, no variable expansion)

### Dependency Validation
3. Check dependencies in this exact order: `tmux`, `whisper-stream`, `claude`, whisper model
4. Each missing dep prints an actionable error via `mb_die` and exits 1
5. Error messages per design Section 6:
   - tmux: `tmux not found. Install: sudo apt install tmux`
   - whisper-stream: `whisper-stream not found. Run install.sh to build it, or see whisper.cpp docs.`
   - claude: `claude not found. Install Claude Code CLI from https://docs.anthropic.com/en/docs/claude-code`
   - model: `Whisper model not found (ggml-base.en.bin). Download: whisper-cli -dl base.en`

### Session Setup
6. Call `mb_init` and `mb_check_disk_space || true`
7. Kill stale session: `tmux has-session -t meetballs-live 2>/dev/null && tmux kill-session -t meetballs-live`
8. Create session dir: `SESSION_DIR="$LIVE_DIR/$(mb_timestamp)"; mkdir -p "$SESSION_DIR"`

### Helper Script Generation
9. Generate `transcriber.sh` via unquoted heredoc (`<<EOF`) — variables expand at write time
10. `transcriber.sh` must: `cd` to session dir, run `whisper-stream` with correct flags, kill tmux session on exit
11. Generate `asker.sh` via unquoted heredoc
12. `asker.sh` must: prompt loop, read transcript, handle empty transcript, call `claude -p`, handle `quit`/`exit`, kill tmux session on exit
13. Both scripts must NOT use `local` keyword (standalone scripts, not functions)
14. Both scripts must be marked executable (`chmod +x`)

### tmux Orchestration
15. Create tmux session: `tmux new-session -d -s meetballs-live -x 200 -y 50`
16. Split pane: `tmux split-window -v -t meetballs-live -p 20`
17. Send scripts to panes: `tmux send-keys -t meetballs-live:0.0 "bash ..." Enter` and `meetballs-live:0.1`
18. Attach: `tmux attach-session -t meetballs-live` (blocks until detach/kill)

### Cleanup
19. Copy transcript: `[[ -f "$SESSION_DIR/transcript.txt" ]] && cp "$SESSION_DIR/transcript.txt" "$TRANSCRIPTS_DIR/$TIMESTAMP.txt"` with `|| true`
20. Copy audio: `cp "$SESSION_DIR"/*.wav "$RECORDINGS_DIR/$TIMESTAMP.wav"` with existence check and `|| true`
21. Print summary of saved paths (or "No transcript to save" / "No recording to save")
22. Remove session directory only after successful copy of both files

## Dependencies
- Task 01: `mb_find_whisper_model()`, `LIVE_DIR`, updated `mb_init()`

## Implementation Approach
1. **RED**: Write 8 failing tests in new `tests/test_live.bats`:
   - B1: `--help` prints usage
   - C2: Missing tmux exits 1 with error message
   - C3: Missing whisper-stream exits 1 (tmux mocked)
   - C4: Missing claude exits 1 (tmux + whisper-stream mocked)
   - C5: Missing model exits 1 (all commands mocked, no model file)
   - D6: Session directory created (all deps mocked, tmux attach returns immediately)
   - D7: Helper scripts generated (transcriber.sh and asker.sh exist in session dir)
   - D8: Stale session killed (tmux `has-session` returns 0, verify `kill-session` called before `new-session`)
2. **GREEN**: Implement `lib/live.sh` with `cmd_live()`
3. **REFACTOR**: Ensure consistent style with existing modules
4. **VERIFY**: Run `tests/test_live.bats` — all 8 tests pass

### tmux Mock Strategy
The tmux mock needs to handle multiple subcommands:
```bash
create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session) exit 0 ;;
    *) exit 0 ;;
esac'
```
Use `$MEETBALLS_DIR/.tmux-calls` file to assert specific tmux commands were called. Use `TMUX_HAS_SESSION_EXIT` env var to control stale session behavior.

### PATH Restriction
Tests must use restricted PATH: `PATH="$MOCK_BIN:/usr/bin:/bin"` to prevent real tmux/whisper-stream/claude from being found.

## Acceptance Criteria

1. **Help output**
   - Given `cmd_live` is called with `--help`
   - When the output is inspected
   - Then it contains "Usage:" and exits 0

2. **Missing tmux detected**
   - Given tmux is not on PATH
   - When `cmd_live` is called
   - Then it exits 1 with error mentioning "tmux"

3. **Missing whisper-stream detected**
   - Given tmux is available but whisper-stream is not
   - When `cmd_live` is called
   - Then it exits 1 with error mentioning "whisper-stream"

4. **Missing claude detected**
   - Given tmux and whisper-stream are available but claude is not
   - When `cmd_live` is called
   - Then it exits 1 with error mentioning "claude"

5. **Missing model detected**
   - Given all commands available but no whisper model file exists
   - When `cmd_live` is called
   - Then it exits 1 with error mentioning "model"

6. **Session directory created**
   - Given all dependencies are available (mocked)
   - When `cmd_live` runs to completion
   - Then a timestamped directory exists under `$LIVE_DIR`

7. **Helper scripts generated**
   - Given all dependencies are available (mocked)
   - When `cmd_live` runs to completion
   - Then `transcriber.sh` and `asker.sh` exist in the session directory

8. **Stale session killed**
   - Given a stale `meetballs-live` tmux session exists (has-session returns 0)
   - When `cmd_live` starts
   - Then `kill-session` is called before `new-session` in the tmux call log

9. **Unit tests pass**
   - Given the implementation is complete
   - When running `tests/test_live.bats`
   - Then all 8 tests pass

## Metadata
- **Complexity**: High
- **Labels**: live, core-feature, tmux, whisper-stream
- **Required Skills**: Bash, tmux, bats testing, heredocs
