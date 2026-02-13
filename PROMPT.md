# MeetBalls — Local-First Meeting Assistant CLI

## Problem Statement

Meetings generate valuable information that is lost because note-taking is distracting,
recordings sit unwatched, and paid transcription services add cost and privacy concerns.
Developers need a zero-cost, privacy-respecting tool that captures meeting audio,
transcribes it locally, and enables interactive Q&A against the transcript using Claude Code CLI.

## What To Build

A minimal, opinionated, shell-script-driven CLI tool called **MeetBalls** that:

1. **Records** meeting audio from the system microphone
2. **Transcribes** the recording locally using a free, offline speech-to-text engine
3. **Enables Q&A** by feeding the transcript as context to Claude Code CLI for interactive querying

This is the **MVP** — no extras, no web UI, no cloud services.

## Commands

### `meetballs record`
- Start recording audio from the default system microphone
- Save as a standard audio format (WAV or OGG) to `~/.meetballs/recordings/`
- Name files with ISO timestamp: `2026-02-12T14-30-00.wav`
- Stop recording on `Ctrl+C` (SIGINT) with graceful cleanup
- Print recording duration and file path on completion

### `meetballs transcribe <recording>`
- Transcribe a recording file using a **free, local, offline** speech-to-text engine
- Candidate engines (evaluate during design): Whisper.cpp, Vosk, or similar
- Output transcript as plain text to `~/.meetballs/transcripts/<same-basename>.txt`
- Show progress indicator during transcription
- Print transcript path on completion

### `meetballs ask <transcript> "<question>"`
- Pipe the transcript file as context to Claude Code CLI (`claude` command)
- Prepend a system prompt that instructs Claude to answer based on the transcript
- Stream Claude's response to stdout
- Support follow-up questions (launch interactive Claude session with transcript loaded)

### `meetballs list`
- List all recordings and their corresponding transcripts (if any)
- Show: filename, date, duration, transcript status (yes/no)

## Technical Constraints

- **Language**: Bash shell scripts (primary), with minimal Python only if a dependency requires it
- **No paid services**: All processing is local and free — no API keys for transcription
- **No Claude API**: Uses `claude` CLI command (Claude Code), not the Anthropic API
- **Audio capture**: Use `arecord` (ALSA), `parecord` (PulseAudio), or `pw-record` (PipeWire) — auto-detect available backend
- **Speech-to-text**: Must run fully offline — evaluate Whisper.cpp (via `whisper-cli` or compiled binary) as primary candidate
- **Storage**: `~/.meetballs/` directory with `recordings/`, `transcripts/`, and `config` subdirectories
- **Dependencies**: Minimize — document all required system packages in install check
- **Platform**: Linux first (WSL2 compatible). macOS is out of scope for PFM

## Non-Goals (Explicitly Out of Scope)

- Speaker diarization (who said what)
- Real-time transcription during recording
- Web UI or Electron app
- Cloud storage or sync
- Meeting calendar integration
- Video recording
- Multi-language support beyond English for PFM
- macOS / Windows native support

## Success Criteria

1. `meetballs record` captures clear audio from the system mic and saves to file
2. `meetballs transcribe` produces a readable English transcript from the recording with no network calls
3. `meetballs ask` loads the transcript into Claude Code CLI and returns a coherent answer to the question
4. `meetballs list` shows recordings with transcript status
5. All commands have `--help` with usage examples
6. A `meetballs doctor` command checks that all dependencies are installed and reports missing ones
7. Total install footprint is documented — user can go from zero to working in under 10 minutes

## Edge Cases and Error Handling

- **No microphone available**: Detect and print clear error with fix suggestions
- **Recording interrupted abruptly** (kill -9): Partial WAV should still be readable; validate on transcribe
- **Transcription of silence/noise**: Produce empty or near-empty transcript gracefully, don't error
- **Very long recordings** (>2 hours): Warn about transcription time; chunk if the engine requires it
- **Claude CLI not installed**: `meetballs ask` and `meetballs doctor` detect and report
- **Whisper model not downloaded**: `meetballs doctor` checks for model; `meetballs transcribe` provides download instructions
- **Disk space**: Check before recording; warn if <500MB free

## User Experience

```
$ meetballs record
Recording... (press Ctrl+C to stop)
^C
Saved: ~/.meetballs/recordings/2026-02-12T14-30-00.wav (duration: 45m12s)

$ meetballs transcribe ~/.meetballs/recordings/2026-02-12T14-30-00.wav
Transcribing... [=========>          ] 47%
Done: ~/.meetballs/transcripts/2026-02-12T14-30-00.txt

$ meetballs ask ~/.meetballs/transcripts/2026-02-12T14-30-00.txt "What action items were discussed?"
Based on the transcript, the following action items were discussed:
1. Andy will update the deployment script by Friday
2. Team agreed to switch to weekly standups
3. ...

$ meetballs list
RECORDING                          DURATION  TRANSCRIPT
2026-02-12T14-30-00.wav           45m12s    yes
2026-02-11T09-00-00.wav           1h02m     no

$ meetballs doctor
Checking dependencies...
  arecord:     OK (ALSA)
  whisper-cli: OK (model: base.en)
  claude:      OK (Claude Code CLI)
  disk space:  OK (12.4 GB free)
All checks passed.
```

## Project Structure

```
MeetBalls/
├── bin/
│   └── meetballs              # Main entry point (bash)
├── lib/
│   ├── record.sh              # Recording logic
│   ├── transcribe.sh          # Transcription logic
│   ├── ask.sh                 # Claude CLI integration
│   ├── list.sh                # Listing logic
│   ├── doctor.sh              # Dependency checking
│   └── common.sh              # Shared utilities (colors, paths, validation)
├── tests/
│   ├── test_record.sh         # Recording tests
│   ├── test_transcribe.sh     # Transcription tests
│   ├── test_ask.sh            # Ask command tests
│   ├── test_list.sh           # List command tests
│   ├── test_doctor.sh         # Doctor command tests
│   └── test_common.sh         # Utility tests
├── install.sh                 # Installation script
├── PROMPT.md                  # This file
├── ralph.yml                  # Ralph orchestrator config
└── README.md                  # User documentation (generated after implementation)
```

## Testing Strategy

- Use [bats-core](https://github.com/bats-core/bats-core) as the bash test framework
- Unit tests mock external commands (`arecord`, `whisper-cli`, `claude`) using bats stubs
- Integration tests run real commands where safe (e.g., record 2 seconds of silence, transcribe a known WAV fixture)
- E2E scenario: record 5 seconds → transcribe → ask a question → verify coherent response

## Definition of Done

- [ ] All five commands work (`record`, `transcribe`, `ask`, `list`, `doctor`)
- [ ] `meetballs doctor` validates all dependencies
- [ ] Transcription runs fully offline with no paid services
- [ ] Claude Q&A works via `claude` CLI (not API)
- [ ] bats-core tests pass for all commands
- [ ] `install.sh` sets up the tool from a fresh clone
- [ ] `--help` on every command prints usage with examples
