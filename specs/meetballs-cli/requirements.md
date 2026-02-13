# MeetBalls — Consolidated Requirements

## Source

Consolidated from PROMPT.md and Q&A during requirements honing (questions.md).

## R1: Audio Recording (`meetballs record`)

- R1.1: Record audio from the default system microphone
- R1.2: Auto-detect available audio backend: `pw-record` (PipeWire) > `parecord` (PulseAudio) > `arecord` (ALSA)
- R1.3: Save as 16-bit 16kHz mono WAV to `~/.meetballs/recordings/`
- R1.4: Name files with ISO timestamp: `YYYY-MM-DDTHH-MM-SS.wav`
- R1.5: Stop recording on Ctrl+C (SIGINT) with graceful cleanup
- R1.6: Print recording duration and file path on completion
- R1.7: Detect missing microphone and print clear error with fix suggestions
- R1.8: Check disk space before recording; warn if <500MB free

## R2: Transcription (`meetballs transcribe <recording>`)

- R2.1: Transcribe a recording file using Whisper.cpp (`whisper-cli`) — fully offline, no network
- R2.2: Output plain text transcript to `~/.meetballs/transcripts/<same-basename>.txt`
- R2.3: Show progress indicator during transcription
- R2.4: Print transcript path on completion
- R2.5: Validate recording file exists and is readable before transcribing
- R2.6: Handle silence/noise gracefully — produce empty or near-empty transcript, don't error
- R2.7: Warn about transcription time for recordings >2 hours
- R2.8: If whisper model is not downloaded, provide download instructions and exit

## R3: Q&A (`meetballs ask <transcript> [question]`)

- R3.1: **Single-shot mode** — `meetballs ask <transcript> "<question>"` uses `claude -p` with transcript as context, prints answer to stdout, exits. Pipe-friendly.
- R3.2: **Interactive mode** — `meetballs ask <transcript>` (no question) launches interactive Claude session with `claude --append-system-prompt` containing transcript content
- R3.3: Prepend system prompt instructing Claude to answer based on the transcript
- R3.4: Validate transcript file exists and is readable
- R3.5: Detect missing `claude` CLI and print install instructions

## R4: Listing (`meetballs list`)

- R4.1: List all recordings in `~/.meetballs/recordings/`
- R4.2: Show columns: filename, duration, transcript status (yes/no)
- R4.3: Determine transcript status by checking if corresponding `.txt` exists in `~/.meetballs/transcripts/`

## R5: Dependency Check (`meetballs doctor`)

- R5.1: Check for audio backend availability (any of: pw-record, parecord, arecord)
- R5.2: Check for `whisper-cli` and verify model is downloaded (default: `base.en`)
- R5.3: Check for `claude` CLI
- R5.4: Check available disk space
- R5.5: Report OK/MISSING status for each check with actionable fix instructions
- R5.6: Exit 0 if all pass, exit 1 if any fail

## R6: Cross-Cutting

- R6.1: All commands support `--help` with usage examples
- R6.2: `bin/meetballs` is the single entry point that dispatches to subcommands
- R6.3: Storage directories created automatically on first use: `~/.meetballs/{recordings,transcripts}`
- R6.4: Colored terminal output (errors in red, success in green, warnings in yellow)
- R6.5: `install.sh` sets up the tool from a fresh clone (symlink/PATH setup, bats-core install)
- R6.6: All shell scripts use `set -euo pipefail` for safety

## Non-Goals

- Speaker diarization
- Real-time transcription during recording
- Web UI or Electron app
- Cloud storage or sync
- Meeting calendar integration
- Video recording
- Multi-language support beyond English
- macOS / Windows native support
