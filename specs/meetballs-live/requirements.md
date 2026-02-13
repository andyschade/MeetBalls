# MeetBalls Live — Consolidated Requirements

## R1: Live Transcription TUI

`meetballs live` opens a tmux split-pane session:
- **Top pane (~80%)**: Real-time transcription from microphone via `whisper-stream`
- **Bottom pane (~20%)**: Interactive Q&A prompt powered by Claude Code CLI

## R2: Dependency Validation

Before launching, validate: `tmux`, `whisper-stream`, `claude` CLI, and a whisper model file.
Fail with clear error messages and install instructions for each missing dependency.

## R3: Session Directory Management

Each live session creates `~/.meetballs/live/<timestamp>/` containing:
- `transcript.txt` — growing transcript appended by whisper-stream
- `transcriber.sh` — generated helper script for top pane
- `asker.sh` — generated helper script for bottom pane
- Audio WAV file saved by `whisper-stream --save-audio`

## R4: Transcriber Helper Script

`transcriber.sh` runs in the top pane:
- Executes `whisper-stream` with `-m <model> --step 3000 --length 10000 --no-timestamps -f transcript.txt --save-audio -l en`
- CWD set to session directory so `--save-audio` writes there
- Output streams to terminal (user sees text in real-time)

## R5: Asker Helper Script

`asker.sh` runs in the bottom pane:
- Displays a `> ` prompt in a loop
- On each question: reads current `transcript.txt` content
- If transcript is empty: prints "(No transcript yet — keep talking!)"
- Otherwise: calls `claude -p "<question>" --append-system-prompt "<system_prompt>"`
- System prompt: meeting assistant context with full transcript embedded
- `quit` or `exit` commands kill the tmux session

## R6: Exit and Cleanup

Three exit paths, all trigger cleanup:
1. Ctrl+C in top pane → whisper-stream dies → transcriber kills tmux session
2. `quit`/`exit` in bottom pane → kills tmux session
3. tmux detach (Ctrl+B D) → main process detects detach, runs cleanup

Cleanup actions:
- Copy transcript to `~/.meetballs/transcripts/<timestamp>.txt`
- Copy audio WAV to `~/.meetballs/recordings/<timestamp>.wav`
- Print summary of saved file paths

## R7: Stale Session Handling

Kill any existing `meetballs-live` tmux session before creating a new one.

## R8: Shared Model Finder

Extract `mb_find_whisper_model()` into `common.sh` to eliminate duplication between `doctor.sh` and `transcribe.sh`. Returns the full path to the model file, or exits with error.

## R9: Doctor Live-Mode Checks

`meetballs doctor` adds checks for live-mode dependencies (`tmux`, `whisper-stream`, SDL2 library) in a separate section from core checks. Core commands still pass doctor if only live-mode deps are missing.

## R10: CLI Integration

- Add `live)` case to `bin/meetballs` dispatcher
- Add `live` to help text
- `meetballs live --help` prints usage with examples

## R11: Install Script Update

`install.sh` adds whisper-stream build:
- Check for `libsdl2-dev`
- Rebuild whisper.cpp with `-DWHISPER_SDL2=ON`
- Copy `whisper-stream` binary to `/usr/local/bin/`

## R12: Testing

- `meetballs live --help` test
- Missing dependency error tests (tmux, whisper-stream, claude, model)
- Session directory creation test
- All existing 94 tests continue to pass

## Q&A

### Q1: Audio Format Consistency

**Q:** Should we use `--save-audio` or a parallel recorder for consistent format?
**A:** Use `--save-audio`. Research confirmed whisper-stream produces 16kHz mono 16-bit PCM WAV — identical to `meetballs record`. Simpler, one process, no format mismatch.
