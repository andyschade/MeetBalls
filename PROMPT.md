# MeetBalls — Local-First Meeting Assistant CLI

## Problem Statement

Meetings generate valuable information that is lost because note-taking is distracting,
recordings sit unwatched, and paid transcription services add cost and privacy concerns.
Developers need a zero-cost, privacy-respecting tool that captures meeting audio,
transcribes it locally in real-time, and enables interactive Q&A against the live transcript
using Claude Code CLI — all during the meeting, not after.

## What To Build

A minimal, opinionated, shell-script-driven CLI tool called **MeetBalls** that:

1. **Live transcribes** meeting audio from the microphone in real-time using `whisper-stream`
2. **Enables live Q&A** in a split-pane TUI where the user asks Claude questions against the growing transcript
3. Also supports **post-hoc** workflow: record → transcribe → ask for when real-time isn't needed

The **primary command** is `meetballs live`. The record/transcribe/ask commands are secondary.

## Existing Codebase

This project already has a working implementation of the secondary commands. The following
files exist and are functional with passing tests (94/94 bats tests):

- `bin/meetballs` — CLI dispatcher (routes to subcommands)
- `lib/common.sh` — Shared utilities (colors, paths, audio detection, formatting)
- `lib/record.sh` — Records mic audio to WAV via parecord/pw-record/arecord
- `lib/transcribe.sh` — Post-hoc transcription via `whisper-cli`
- `lib/ask.sh` — Q&A via `claude` CLI with transcript as system prompt
- `lib/list.sh` — Lists recordings with transcript status
- `lib/doctor.sh` — Dependency checker
- `install.sh` — Installs bats-core, creates symlink, runs doctor
- `tests/` — Full bats-core test suite (94 tests passing)

**DO NOT rewrite or break the existing code.** Build on top of it.

## Primary Feature: `meetballs live`

### What It Does

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

### whisper-stream Details

`whisper-stream` is built from whisper.cpp's `examples/stream/` directory. It requires:
- whisper.cpp rebuilt with `-DWHISPER_SDL2=ON`
- `libsdl2-dev` system package (for mic capture)

Key flags:
- `-m <model>` — path to whisper model file (e.g., `ggml-base.en.bin`)
- `--step 3000` — process audio every 3 seconds
- `--length 10000` — 10-second sliding window buffer
- `--no-timestamps` — clean text output without time markers
- `-f <file>` — append transcribed text to file (in addition to stdout)
- `--save-audio` — save captured audio as WAV
- `-l en` — English language

### asker.sh Details

The bottom-pane script:
- Shows a prompt (`> `)
- On each question: reads the **entire** current transcript file
- Builds a system prompt: "You are a meeting assistant. A meeting is in progress..."
- Calls `claude -p "<question>" --append-system-prompt "<system_prompt_with_transcript>"`
- Prints the answer, loops
- `quit` or `exit` kills the tmux session
- If transcript is empty, prints "(No transcript yet — keep talking!)"

### User Experience

```
$ meetballs live
Starting live session...

┌─────────────────────────────────────────────────────┐
│ Starting live transcription... (Ctrl+C to stop)     │
│ Model: base.en                                      │
│ ---                                                 │
│ So the main thing we need to discuss today is the   │
│ deployment timeline. I think we should aim for next  │
│ Friday at the latest. The QA team needs at least    │
│ three days to run their regression suite.           │
│ ...                                                 │
├─────────────────────────────────────────────────────┤
│ > What deadline was mentioned?                      │
│ Based on the transcript, the deployment deadline    │
│ mentioned is next Friday.                           │
│                                                     │
│ >                                                   │
└─────────────────────────────────────────────────────┘

# After exiting:
Session ended.
Transcript saved: ~/.meetballs/transcripts/2026-02-13T10-00-00.txt
Recording saved: ~/.meetballs/recordings/2026-02-13T10-00-00.wav
```

### Exit Handling

Three exit paths, all must run cleanup:
1. **Ctrl+C in top pane** → kills whisper-stream → transcriber script kills tmux session
2. **`quit` in bottom pane** → asker kills tmux session
3. **tmux detach (Ctrl+B D)** → cleanup runs, kills leftover session

Cleanup copies transcript + audio WAV to standard MeetBalls directories.

## Secondary Commands (Already Implemented)

### `meetballs record`
- Records mic audio via PulseAudio/PipeWire/ALSA (auto-detected)
- WAV 16kHz mono 16-bit to `~/.meetballs/recordings/<timestamp>.wav`
- Ctrl+C stops with graceful cleanup

### `meetballs transcribe <recording>`
- Post-hoc transcription via `whisper-cli` (not whisper-stream)
- Outputs to `~/.meetballs/transcripts/<basename>.txt`

### `meetballs ask <transcript> ["question"]`
- Single-shot (with question) or interactive (without) via `claude` CLI
- Transcript injected as system prompt context

### `meetballs list`
- Shows recordings with duration and transcript status

### `meetballs doctor`
- Checks all dependencies and reports status

## Changes Required

### `lib/common.sh` — Add shared helper
- Add `LIVE_DIR="$MEETBALLS_DIR/live"` constant
- Extract `mb_find_whisper_model()` function that returns model path (currently duplicated in transcribe.sh and doctor.sh)

### `lib/transcribe.sh` — Refactor
- Replace inline model search with `mb_find_whisper_model` call

### `lib/doctor.sh` — Add live-mode checks
- Replace inline model search with `mb_find_whisper_model`
- Add checks for: `tmux`, `whisper-stream`, `libsdl2-dev`
- Separate "core" vs "live-mode" failures (existing commands should still pass doctor if only live deps are missing)

### `lib/live.sh` — New file (core feature)
- `cmd_live` entry point with `--help`
- Dependency validation
- Session directory setup
- Helper script generation (transcriber.sh, asker.sh)
- tmux session creation and pane management
- Post-session cleanup

### `bin/meetballs` — Add live command
- Add `live)` case to dispatcher
- Add `live` to help text

### `install.sh` — Add whisper-stream build
- Check for `libsdl2-dev`, prompt to install if missing
- Rebuild whisper.cpp with `-DWHISPER_SDL2=ON`
- Copy `whisper-stream` binary to `/usr/local/bin/`

### `tests/test_live.bats` — New tests
- `--help` output
- Missing dependency errors (tmux, whisper-stream, claude, model)
- Session directory creation

## Technical Constraints

- **Language**: Bash shell scripts (primary)
- **No paid services**: All processing is local and free
- **No Claude API**: Uses `claude` CLI command (Claude Code), not the Anthropic API
- **Real-time transcription**: `whisper-stream` (from whisper.cpp, requires SDL2)
- **Post-hoc transcription**: `whisper-cli` (already installed)
- **TUI**: tmux (already installed, v3.4)
- **Audio capture**: Microphone only via PulseAudio (WSL2 Ubuntu)
- **Storage**: `~/.meetballs/` with `recordings/`, `transcripts/`, `live/` subdirectories
- **Platform**: Linux / WSL2. macOS out of scope

## Non-Goals (Explicitly Out of Scope)

- Speaker diarization (who said what)
- System/application audio capture (Zoom/Teams speaker output)
- Web UI or Electron app
- Cloud storage or sync
- Meeting calendar integration
- Video recording
- Multi-language support beyond English
- macOS / Windows native support

## Edge Cases and Error Handling

- **No microphone**: `whisper-stream` fails with "audio.init() failed!" — detect and show clear error
- **SDL2 missing**: `whisper-stream` won't build — doctor reports with install instructions
- **tmux not installed**: live command exits with install instructions
- **Empty transcript when asking**: Print "(No transcript yet — keep talking!)" instead of sending empty context to Claude
- **Very long meetings** (3+ hours): Transcript may approach Claude's context limit — acceptable for MVP
- **Stale tmux session**: Kill any existing `meetballs-live` session before creating a new one
- **Disk space**: Warn if <500MB free before starting

## Success Criteria

1. `meetballs live` opens a split-pane TUI with live transcript on top and Q&A prompt on bottom
2. Speaking into the mic produces real-time text in the top pane
3. Typing a question in the bottom pane returns a Claude answer based on the transcript so far
4. Exiting saves both transcript and audio recording to standard directories
5. `meetballs list` shows recordings from live sessions
6. `meetballs doctor` reports live-mode dependencies separately from core dependencies
7. All existing 94 bats tests continue to pass (no regressions)
8. New tests cover `meetballs live --help` and dependency validation

## Definition of Done

- [ ] `meetballs live` opens tmux split-pane TUI
- [ ] Top pane shows real-time transcription from mic via `whisper-stream`
- [ ] Bottom pane accepts questions and returns Claude answers using current transcript
- [ ] Exiting saves transcript to `~/.meetballs/transcripts/` and audio to `~/.meetballs/recordings/`
- [ ] `meetballs doctor` checks tmux, whisper-stream, and SDL2
- [ ] `install.sh` builds whisper-stream with SDL2 support
- [ ] `mb_find_whisper_model` shared helper replaces duplicated model search
- [ ] All existing tests pass (no regressions)
- [ ] New tests for `meetballs live` (help, dependency checks)
- [ ] `--help` on live command prints usage with examples
