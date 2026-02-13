# MeetBalls — Implementation Progress

## Task 00: Project Scaffolding — COMPLETED (2026-02-12)

### What was done
- Initialized git repository
- Created directory structure: `bin/`, `lib/`, `tests/`
- Created `bin/meetballs` (executable placeholder with shebang + `set -euo pipefail`)
- Created `lib/common.sh` (sourceable placeholder)
- Created `tests/test_helper.bash` with:
  - `MEETBALLS_DIR` temp dir isolation
  - `MOCK_BIN` on PATH for command mocking
  - `create_mock_command` helper
  - `teardown` cleanup
  - bats-support and bats-assert loading
- Created `install.sh` (idempotent bats-core installation)
- Created `.gitignore` with `tests/libs/`
- Created `tests/test_scaffolding.bats` — 7 verification tests, all passing

### Test Results
```
1..7
ok 1 MEETBALLS_DIR is an isolated temp directory
ok 2 MEETBALLS_DIR has recordings and transcripts subdirs
ok 3 MOCK_BIN is on PATH
ok 4 create_mock_command creates executable mock
ok 5 bin/meetballs is executable
ok 6 lib/common.sh is sourceable
ok 7 LIB_DIR points to lib directory
```

### Acceptance Criteria Status
- [x] Git repository initialized
- [x] Directory structure exists (bin/, lib/, tests/)
- [x] install.sh installs bats-core to tests/libs/
- [x] test_helper.bash provides isolation and PATH manipulation
- [x] bin/meetballs is executable
- [x] All bats libraries installed successfully

## Task 01: Common Utilities + Tests — COMPLETED (2026-02-12)

### What was done
- Implemented `lib/common.sh` with all shared utility functions:
  - Constants: `MEETBALLS_DIR`, `RECORDINGS_DIR`, `TRANSCRIPTS_DIR`, `WHISPER_MODEL`, `MIN_DISK_MB`
  - `mb_init` — creates recordings and transcripts directories (idempotent)
  - `mb_info`, `mb_success`, `mb_warn`, `mb_error`, `mb_die` — colored messaging (colors disabled when not a terminal)
  - `mb_check_command` — check if a command exists (return 0/1)
  - `mb_check_disk_space` — warn if <500MB free on MEETBALLS_DIR partition
  - `mb_detect_audio_backend` — PipeWire > PulseAudio > ALSA priority
  - `mb_format_duration` — format seconds as human-readable (0s, 45s, 1m30s, 1h02m00s)
  - `mb_recording_dir`, `mb_transcript_dir` — echo directory paths
  - `mb_timestamp` — ISO timestamp for filenames (YYYY-MM-DDTHH-MM-SS)
- Wrote `tests/test_common.bats` with 29 test cases covering all functions

### TDD Cycle
- **RED**: 29 tests written, all failing (common.sh was placeholder)
- **GREEN**: Implemented all functions, 29/29 passing
- **REFACTOR**: Code reviewed — clean, minimal, follows conventions

### Test Results
```
1..29
ok 1 MEETBALLS_DIR respects env override
ok 2 RECORDINGS_DIR is MEETBALLS_DIR/recordings
ok 3 TRANSCRIPTS_DIR is MEETBALLS_DIR/transcripts
ok 4 WHISPER_MODEL defaults to base.en
ok 5 MIN_DISK_MB is 500
ok 6 mb_init creates recordings and transcripts directories
ok 7 mb_init is idempotent
ok 8 mb_format_duration 0 returns 0s
ok 9 mb_format_duration 45 returns 45s
ok 10 mb_format_duration 90 returns 1m30s
ok 11 mb_format_duration 2712 returns 45m12s
ok 12 mb_format_duration 3720 returns 1h02m00s
ok 13 mb_format_duration 7200 returns 2h00m00s
ok 14 mb_timestamp matches YYYY-MM-DDTHH-MM-SS format
ok 15 mb_recording_dir echoes RECORDINGS_DIR
ok 16 mb_transcript_dir echoes TRANSCRIPTS_DIR
ok 17 mb_check_command returns 0 for existing command
ok 18 mb_check_command returns 1 for missing command
ok 19 mb_detect_audio_backend returns pw-record when all available
ok 20 mb_detect_audio_backend returns parecord when no pw-record
ok 21 mb_detect_audio_backend returns arecord as last fallback
ok 22 mb_detect_audio_backend returns 1 when none available
ok 23 mb_check_disk_space succeeds with sufficient space
ok 24 mb_check_disk_space warns with low space
ok 25 mb_info prints message
ok 26 mb_success prints message
ok 27 mb_warn prints to stderr
ok 28 mb_error prints to stderr
ok 29 mb_die prints error and exits 1
```

### Full Suite: 36/36 passing (7 scaffolding + 29 common)

### Acceptance Criteria Status
- [x] Duration formatting: 0→"0s", 45→"45s", 90→"1m30s", 2712→"45m12s", 3720→"1h02m00s", 7200→"2h00m00s"
- [x] Directory initialization: creates dirs, idempotent
- [x] Audio backend detection: PipeWire > PulseAudio > ALSA priority, returns 1 if none
- [x] Timestamp format: matches YYYY-MM-DDTHH-MM-SS regex
- [x] All 29 unit tests pass

## Task 03: Doctor Command — COMPLETED (2026-02-12)

### What was done
- Implemented `lib/doctor.sh` with `cmd_doctor()` entry function
- 5 dependency checks: audio backend, whisper-cli, whisper model, claude CLI, disk space
- Formatted output table with aligned columns
- Exit 0 if all pass, 1 if any fail
- Wrote `tests/test_doctor.bats` with 9 test cases

### TDD Cycle
- **RED**: 9 tests written, all failing (doctor.sh didn't exist)
- **GREEN**: Implemented all checks, 9/9 passing
- **REFACTOR**: Fixed test isolation — restricted PATH to prevent real system commands leaking in

### Full Suite: 53/53 passing (7 scaffolding + 29 common + 8 dispatcher + 9 doctor)

## Task 04: List Command — COMPLETED (2026-02-12)

### What was done
- Implemented `lib/list.sh` with `cmd_list()` entry function
- Scans `$RECORDINGS_DIR` for `.wav` files, sorted alphabetically (chronological by timestamp names)
- Computes duration from WAV file size: `(file_size - 44) / (16000 * 2)`
- Checks transcript existence in `$TRANSCRIPTS_DIR`
- Prints formatted table with RECORDING, DURATION, TRANSCRIPT columns
- "No recordings" message when directory is empty
- Wrote `tests/test_list.bats` with 9 test cases using `truncate` for instant WAV fixture creation

### TDD Cycle
- **RED**: 9 tests written, all failing (list.sh didn't exist)
- **GREEN**: Implemented cmd_list, 9/9 passing
- **REFACTOR**: Convention alignment verified — no changes needed

### Full Suite: 62/62 passing (7 scaffolding + 29 common + 8 dispatcher + 9 doctor + 9 list)

### Acceptance Criteria Status
- [x] Help flag: `--help` prints usage containing "Usage" and "list", exits 0
- [x] No recordings: prints "No recordings" message, exits 0
- [x] Recordings listed with filenames in table with header columns
- [x] Transcript status "yes" for recordings with matching .txt
- [x] Transcript status "no" for recordings without transcript
- [x] Duration displayed correctly (45m12s, 1h02m00s)
- [x] All 9 tests pass
