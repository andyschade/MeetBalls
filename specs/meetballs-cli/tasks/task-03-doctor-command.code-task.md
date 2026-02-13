---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: Doctor Command + Tests (TDD)

## Description
Implement the `meetballs doctor` command that checks all system dependencies (audio backend, whisper-cli, whisper model, claude CLI, disk space) and reports their status. This is useful for debugging setup issues and is one of the simplest commands to implement since it has no complex state.

## Background
The doctor command checks five dependencies and prints a formatted status table. It exits 0 if all pass, 1 if any fail. Each check uses utilities from `common.sh` (like `mb_detect_audio_backend` and `mb_check_command`). All external commands are mocked in tests via PATH manipulation.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.7 — Dependency Check)

**Additional References:**
- specs/meetballs-cli/context.md (mock strategy)
- specs/meetballs-cli/plan.md (test_doctor.bats test cases)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Entry function: `cmd_doctor "$@"`
2. Handle `--help` flag — print usage with description and exit 0
3. Check audio backend via `mb_detect_audio_backend` — report which one found or MISSING
4. Check `whisper-cli` via `mb_check_command` — report OK or MISSING with install URL
5. Check whisper model file exists — look in common locations (`~/.local/share/whisper.cpp/models/`, `/usr/local/share/whisper.cpp/models/`, `$WHISPER_CPP_MODEL_DIR`) for `ggml-${WHISPER_MODEL}.bin`
6. Check `claude` CLI via `mb_check_command` — report OK or MISSING with install URL
7. Check disk space on `$MEETBALLS_DIR` partition — report GB free, warn if <500MB
8. Print formatted table with aligned columns
9. Print "All checks passed." if all pass, exit 0; otherwise exit 1

## Dependencies
- Task 01 (common.sh utilities: `mb_detect_audio_backend`, `mb_check_command`, `mb_check_disk_space`)
- Task 02 (CLI dispatcher routes `doctor` to this module)

## Implementation Approach
1. **RED**: Write `tests/test_doctor.bats` with all test cases
2. **GREEN**: Implement `lib/doctor.sh` with `cmd_doctor` function
3. **REFACTOR**: Clean up output formatting

### Test cases (from plan):
- `--help` prints usage containing "Usage" and "doctor", exit 0
- All checks pass (mock all deps present) → stdout contains "All checks passed", exit 0
- Missing audio backend (no audio mocks) → stdout contains "MISSING", exit 1
- Missing whisper-cli (no whisper mock) → stdout contains "MISSING", exit 1
- Missing claude (no claude mock) → stdout contains "MISSING", exit 1
- Reports disk space → stdout contains "GB free" or similar

### Mock strategy:
- Use `create_mock_command` from test_helper.bash to place/remove commands in `$MOCK_BIN`
- For "all pass" test: mock pw-record, whisper-cli, claude, and create a fake model file
- For "missing X" tests: omit the specific mock while providing others
- For disk space: mock `df` to return controlled values

## Acceptance Criteria

1. **Help flag**
   - Given the user runs `meetballs doctor --help`
   - When output is examined
   - Then it contains "Usage" and "doctor" and exits 0

2. **All dependencies present**
   - Given audio backend, whisper-cli, whisper model, and claude are all available
   - When running `meetballs doctor`
   - Then output shows "OK" for each check and "All checks passed", exit 0

3. **Missing audio backend detected**
   - Given no audio backend is installed
   - When running `meetballs doctor`
   - Then output shows "MISSING" for audio and exits 1

4. **Missing whisper-cli detected**
   - Given whisper-cli is not installed
   - When running `meetballs doctor`
   - Then output shows "MISSING" with install instructions and exits 1

5. **Missing claude detected**
   - Given claude CLI is not installed
   - When running `meetballs doctor`
   - Then output shows "MISSING" with install instructions and exits 1

6. **Disk space reported**
   - Given the system has measurable free space
   - When running `meetballs doctor`
   - Then output includes disk space information

7. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_doctor.bats`
   - Then all tests pass

## Metadata
- **Complexity**: Medium
- **Labels**: command, doctor, dependencies
- **Required Skills**: Bash, bats-core testing, PATH mocking
