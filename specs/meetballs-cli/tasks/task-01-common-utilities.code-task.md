---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: Common Utilities + Tests

## Description
Implement `lib/common.sh` with all shared utility functions and write comprehensive tests in `tests/test_common.bats`. This module is sourced by every other module — it provides path helpers, formatting, audio backend detection, disk space checking, and colored output.

## Background
All MeetBalls commands depend on shared utilities for directory initialization, duration formatting, audio backend detection, and messaging. Building and testing this first ensures a solid foundation for all subsequent commands.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.2 — Shared Utilities)

**Additional References:**
- specs/meetballs-cli/context.md (codebase patterns)
- specs/meetballs-cli/plan.md (test cases for common.sh)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Script starts with `set -euo pipefail`
2. Constants: `MEETBALLS_DIR`, `RECORDINGS_DIR`, `TRANSCRIPTS_DIR`, `WHISPER_MODEL`, `MIN_DISK_MB`
3. `MEETBALLS_DIR` defaults to `$HOME/.meetballs` but respects env override
4. Functions to implement:
   - `mb_init` — create recordings and transcripts directories
   - `mb_info`, `mb_success`, `mb_warn`, `mb_error`, `mb_die` — colored messaging (colors disabled when not a terminal)
   - `mb_check_command` — check if a command exists (return 0/1)
   - `mb_check_disk_space` — warn if <500MB free on MEETBALLS_DIR partition
   - `mb_detect_audio_backend` — return best available: pw-record > parecord > arecord
   - `mb_format_duration` — format seconds as human-readable (0s, 45s, 1m30s, 1h02m00s)
   - `mb_recording_dir`, `mb_transcript_dir` — echo directory paths
   - `mb_timestamp` — echo ISO timestamp for filenames (`YYYY-MM-DDTHH-MM-SS`)

## Dependencies
- Task 00 (project scaffolding — bats-core installed, test_helper.bash exists)

## Implementation Approach
1. **RED**: Write all `tests/test_common.bats` tests first (they will fail since common.sh is a placeholder)
2. **GREEN**: Implement each function in `lib/common.sh` to make tests pass
3. **REFACTOR**: Clean up any duplication while keeping tests green

### Test cases to implement (from plan):
- `mb_format_duration`: 0→"0s", 45→"45s", 90→"1m30s", 2712→"45m12s", 3720→"1h02m00s", 7200→"2h00m00s"
- `mb_init`: creates dirs, idempotent (no error on re-run)
- `mb_timestamp`: matches `YYYY-MM-DDTHH-MM-SS` regex
- `mb_detect_audio_backend`: PipeWire first, PulseAudio fallback, ALSA fallback, none returns 1
- `mb_check_command`: found returns 0, missing returns 1
- `mb_recording_dir` / `mb_transcript_dir`: echo correct paths

## Acceptance Criteria

1. **Duration formatting**
   - Given various second values
   - When calling `mb_format_duration`
   - Then output matches expected format: 0→"0s", 45→"45s", 90→"1m30s", 2712→"45m12s", 3720→"1h02m00s"

2. **Directory initialization**
   - Given `MEETBALLS_DIR` points to a temp directory
   - When calling `mb_init`
   - Then `$MEETBALLS_DIR/recordings` and `$MEETBALLS_DIR/transcripts` exist

3. **Audio backend detection priority**
   - Given pw-record, parecord, and arecord are all available
   - When calling `mb_detect_audio_backend`
   - Then it returns "pw-record" (PipeWire first)

4. **Audio backend fallback**
   - Given only arecord is available
   - When calling `mb_detect_audio_backend`
   - Then it returns "arecord"

5. **No audio backend**
   - Given no audio backends are available
   - When calling `mb_detect_audio_backend`
   - Then it returns exit code 1

6. **Timestamp format**
   - Given current system time
   - When calling `mb_timestamp`
   - Then output matches regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}$`

7. **Unit tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_common.bats`
   - Then all tests pass

## Metadata
- **Complexity**: Medium
- **Labels**: core, utilities, TDD
- **Required Skills**: Bash, bats-core testing
