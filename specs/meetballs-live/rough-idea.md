# MeetBalls Live — Local-First Meeting Assistant CLI

## Primary Feature: `meetballs live`

Opens a tmux split-pane TUI:
- **Top pane (80%)**: Real-time transcript from `whisper-stream`, text appears as you speak
- **Bottom pane (20%)**: Interactive prompt where user types questions about the meeting so far

### How It Works

1. Validate dependencies: `tmux`, `whisper-stream`, `claude`, whisper model
2. Create session directory: `~/.meetballs/live/<timestamp>/`
3. Write two helper scripts to the session directory:
   - `transcriber.sh` — runs `whisper-stream` with mic capture, outputs to terminal + transcript file
   - `asker.sh` — input loop that reads the growing transcript file, passes to `claude -p`
4. Create tmux session with two panes, send scripts to each
5. Attach to session (user sees the TUI)
6. On exit: copy transcript to `~/.meetballs/transcripts/` and audio to `~/.meetballs/recordings/`

### Changes Required

- `lib/common.sh` — Add `LIVE_DIR` constant + `mb_find_whisper_model()` shared helper
- `lib/transcribe.sh` — Replace inline model search with shared helper
- `lib/doctor.sh` — Add live-mode checks (tmux, whisper-stream, SDL2), separate core vs live failures
- `lib/live.sh` — New file (core feature)
- `bin/meetballs` — Add `live` command to dispatcher + help
- `install.sh` — Add whisper-stream SDL2 build
- `tests/test_live.bats` — New tests for help, dependency checks, session directory
