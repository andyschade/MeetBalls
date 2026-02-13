# MeetBalls — Implementation Plan

## Test Strategy

### Framework Setup
- **bats-core** + bats-support + bats-assert installed to `tests/libs/` via `git clone --depth 1`
- Run tests: `./tests/libs/bats/bin/bats tests/`
- Every test file uses `MEETBALLS_DIR=$(mktemp -d)` for isolation
- External commands mocked via PATH manipulation: mock scripts placed in a temp dir prepended to PATH

### Test Helpers (`tests/test_helper.bash`)
Shared setup loaded by all test files:
- Sets `MEETBALLS_DIR` to a temp directory
- Sets `LIB_DIR` and sources `common.sh`
- Provides `create_mock_command` helper to create executable mock scripts in `$MOCK_BIN`
- Prepends `$MOCK_BIN` to `PATH`
- Cleans up temp dirs in teardown

### Unit Tests — `tests/test_common.bats`

| Test | Inputs | Expected |
|------|--------|----------|
| `mb_format_duration 0` | 0 seconds | `"0s"` |
| `mb_format_duration 45` | 45 seconds | `"45s"` |
| `mb_format_duration 90` | 90 seconds | `"1m30s"` |
| `mb_format_duration 2712` | 45m12s | `"45m12s"` |
| `mb_format_duration 3720` | 1h2m | `"1h02m00s"` |
| `mb_format_duration 7200` | exactly 2h | `"2h00m00s"` |
| `mb_init` creates dirs | no prior dirs | `$MEETBALLS_DIR/{recordings,transcripts}` exist |
| `mb_init` idempotent | dirs already exist | no error, dirs still exist |
| `mb_timestamp` format | current time | matches `YYYY-MM-DDTHH-MM-SS` regex |
| `mb_detect_audio_backend` PipeWire first | pw-record, parecord, arecord all mocked | returns `pw-record` |
| `mb_detect_audio_backend` PulseAudio fallback | parecord and arecord mocked | returns `parecord` |
| `mb_detect_audio_backend` ALSA fallback | only arecord mocked | returns `arecord` |
| `mb_detect_audio_backend` none | nothing mocked | returns 1 |
| `mb_check_command` found | mock command exists | returns 0 |
| `mb_check_command` missing | no such command | returns 1 |
| `mb_recording_dir` | env set | echoes `$MEETBALLS_DIR/recordings` |
| `mb_transcript_dir` | env set | echoes `$MEETBALLS_DIR/transcripts` |

### Command Tests — `tests/test_record.bats`

| Test | Setup | Expected |
|------|-------|----------|
| `--help` prints usage | none | output contains "Usage" and "record", exit 0 |
| errors when no audio backend | no mocked backends | stderr contains error, exit 1 |
| starts and stops recording | mock pw-record that creates WAV on SIGTERM | output file exists, success message printed |
| output file named with timestamp | mock pw-record | filename matches `YYYY-MM-DDTHH-MM-SS.wav` |
| prints duration on completion | mock pw-record creates known-size WAV | output contains formatted duration |
| warns on low disk space | mock `df` returning low space | stderr contains warning |

### Command Tests — `tests/test_transcribe.bats`

| Test | Setup | Expected |
|------|-------|----------|
| `--help` prints usage | none | output contains "Usage" and "transcribe", exit 0 |
| errors on missing argument | no args | stderr contains error, exit 1 |
| errors on nonexistent file | fake path | stderr contains "not found" or similar, exit 1 |
| errors when whisper-cli missing | no mock whisper-cli | stderr contains error, exit 1 |
| successful transcription | mock whisper-cli creates .txt | transcript file exists in transcripts dir |
| output path printed | mock whisper-cli | stdout contains transcript path |
| handles empty output | mock whisper-cli creates empty .txt | exit 0, no error |

### Command Tests — `tests/test_ask.bats`

| Test | Setup | Expected |
|------|-------|----------|
| `--help` prints usage | none | output contains "Usage" and "ask", exit 0 |
| errors on missing transcript arg | no args | stderr contains error, exit 1 |
| errors on nonexistent transcript | fake path | stderr contains error, exit 1 |
| errors when claude missing | no mock claude | stderr contains error, exit 1 |
| single-shot mode calls claude -p | mock claude, provide question | mock claude receives `-p` flag |
| interactive mode calls claude --append-system-prompt | mock claude, no question | mock claude receives `--append-system-prompt` |
| system prompt contains transcript | mock claude that dumps args | args contain transcript text |

### Command Tests — `tests/test_list.bats`

| Test | Setup | Expected |
|------|-------|----------|
| `--help` prints usage | none | output contains "Usage" and "list", exit 0 |
| no recordings prints message | empty recordings dir | output contains "No recordings" |
| lists recordings with columns | create fixture WAV files | output contains filenames |
| shows "yes" for transcribed | create WAV + matching TXT | output line contains "yes" |
| shows "no" for untranscribed | create WAV only | output line contains "no" |
| shows duration | create known-size WAV | output contains formatted duration |

### Command Tests — `tests/test_doctor.bats`

| Test | Setup | Expected |
|------|-------|----------|
| `--help` prints usage | none | output contains "Usage" and "doctor", exit 0 |
| all checks pass | mock all deps present | stdout contains "All checks passed", exit 0 |
| missing audio backend | no audio mocks | stdout contains "MISSING", exit 1 |
| missing whisper-cli | no whisper mock | stdout contains "MISSING", exit 1 |
| missing claude | no claude mock | stdout contains "MISSING", exit 1 |
| reports disk space | mock df | stdout contains "GB free" or similar |

### E2E Test Scenario (Manual Validation)

**Preconditions:** Audio backend + whisper-cli + claude CLI all installed.

1. `./install.sh` — sets up symlink and bats-core
2. `meetballs doctor` — all checks pass
3. `meetballs record` — speak for ~10 seconds, Ctrl+C — file saved with duration
4. `meetballs transcribe <recording>` — transcript created with spoken words
5. `meetballs ask <transcript> "What was said?"` — coherent answer returned
6. `meetballs list` — shows recording with transcript status "yes"
7. Each command with `--help` — prints usage with examples

**Expected:** All commands work end-to-end with no errors. Transcript is readable English. Ask returns relevant answer.

## Implementation Steps

### Step 0: Project Scaffolding
- Files: `bin/meetballs`, `lib/common.sh`, `install.sh`, `tests/test_helper.bash`
- Setup: `git init`, `install.sh` (install bats-core to tests/libs/), create directory structure
- Tests: None yet (scaffolding only)
- Demo: `./install.sh` completes successfully, `bats` is available at `tests/libs/bats/bin/bats`

### Step 1: Common Utilities + Tests
- Files: `lib/common.sh`, `tests/test_common.bats`
- Write failing tests first for: `mb_format_duration`, `mb_init`, `mb_timestamp`, `mb_detect_audio_backend`, `mb_check_command`, path helpers
- Implement `common.sh` with all shared functions and constants
- Tests that should pass: all `test_common.bats` tests
- Demo: `./tests/libs/bats/bin/bats tests/test_common.bats` — all green

### Step 2: CLI Dispatcher + Global Help
- Files: `bin/meetballs`, `tests/test_meetballs.bats` (optional, light)
- Implement case-based dispatcher with `--help`, `--version`, unknown command handling
- Each subcommand sources its module and calls its entry function
- Tests: `meetballs --help` prints global usage, `meetballs --version` prints version, unknown command prints error
- Demo: `bin/meetballs --help` prints nicely formatted help listing all commands

### Step 3: Doctor Command + Tests (TDD)
- Files: `lib/doctor.sh`, `tests/test_doctor.bats`
- Write failing tests first for all doctor scenarios
- Implement `cmd_doctor` — check audio backend, whisper-cli, whisper model, claude, disk space
- Tests that should pass: all `test_doctor.bats` tests
- Integrates with: Step 1's `common.sh` utilities (`mb_detect_audio_backend`, `mb_check_command`)
- Demo: `bin/meetballs doctor` runs and reports status of each dependency

### Step 4: List Command + Tests (TDD)
- Files: `lib/list.sh`, `tests/test_list.bats`
- Write failing tests first (empty dir, with fixtures, transcript status)
- Implement `cmd_list` — scan recordings dir, compute durations, check transcript existence
- Tests that should pass: all `test_list.bats` tests
- Integrates with: Step 1's `mb_format_duration`, path helpers
- Demo: `bin/meetballs list` shows formatted table (or "no recordings" message)

### Step 5: Record Command + Tests (TDD)
- Files: `lib/record.sh`, `tests/test_record.bats`
- Write failing tests first (help, no backend, successful record with mock)
- Implement `cmd_record` — detect backend, start recording, SIGINT trap, duration display
- Tests that should pass: all `test_record.bats` tests
- Integrates with: Step 1's `mb_detect_audio_backend`, `mb_timestamp`, `mb_format_duration`, `mb_check_disk_space`
- Demo: `bin/meetballs record` with mock recorder starts/stops and reports duration

### Step 6: Transcribe Command + Tests (TDD)
- Files: `lib/transcribe.sh`, `tests/test_transcribe.bats`
- Write failing tests first (help, missing args, missing file, missing whisper, success, empty output)
- Implement `cmd_transcribe` — validate inputs, find model, invoke whisper-cli, handle output
- Tests that should pass: all `test_transcribe.bats` tests
- Integrates with: Step 1's path helpers, `mb_check_command`
- Demo: `bin/meetballs transcribe <file>` with mock whisper-cli creates transcript

### Step 7: Ask Command + Tests (TDD)
- Files: `lib/ask.sh`, `tests/test_ask.bats`
- Write failing tests first (help, missing args, missing file, missing claude, single-shot, interactive, system prompt content)
- Implement `cmd_ask` — validate inputs, build system prompt, dual-mode dispatch
- Tests that should pass: all `test_ask.bats` tests
- Integrates with: Step 1's `mb_check_command`, path helpers
- Demo: `bin/meetballs ask <transcript> "question"` with mock claude returns answer

### Step 8: Install Script + Full Test Suite
- Files: `install.sh` (finalize)
- Ensure install.sh: checks bash version, clones bats-core (if not present), creates symlink, runs doctor
- All tests pass: `./tests/libs/bats/bin/bats tests/`
- Demo: From a fresh state, `./install.sh` sets up everything, all `bats` tests pass

## Implementation Order Rationale

1. **Common first** — every other module depends on it
2. **Dispatcher second** — makes all subsequent commands immediately runnable via `bin/meetballs`
3. **Doctor third** — has no deps on other commands, validates the environment; useful for debugging during development
4. **List fourth** — filesystem-only, no external deps to mock; validates the storage/duration logic that record will also use
5. **Record fifth** — builds on common utilities, needs SIGINT handling (more complex)
6. **Transcribe sixth** — needs recording fixtures, builds on validated WAV handling from list/record
7. **Ask seventh** — needs transcript fixtures, most complex mock setup (claude CLI)
8. **Install last** — ties everything together, runs doctor as final validation

## Success Criteria Per Step

Each step is independently verifiable:
- Step 0: `ls tests/libs/bats/bin/bats` succeeds
- Step 1: `bats tests/test_common.bats` — all pass
- Step 2: `bin/meetballs --help` — prints usage for all 5 commands
- Step 3: `bats tests/test_doctor.bats` — all pass
- Step 4: `bats tests/test_list.bats` — all pass
- Step 5: `bats tests/test_record.bats` — all pass
- Step 6: `bats tests/test_transcribe.bats` — all pass
- Step 7: `bats tests/test_ask.bats` — all pass
- Step 8: `bats tests/` — ALL tests pass, `./install.sh` completes
