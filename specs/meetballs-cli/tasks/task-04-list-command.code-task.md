---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: List Command + Tests (TDD)

## Description
Implement the `meetballs list` command that scans the recordings directory, computes duration from WAV headers, checks for corresponding transcripts, and prints a formatted table. This is filesystem-only — no external dependencies to mock.

## Background
The list command gives users an overview of their recordings and transcript status. It uses WAV header arithmetic to compute duration (`(file_size - 44) / (16000 * 2)` for 16kHz mono 16-bit WAV) and checks for matching `.txt` files in the transcripts directory. This validates the storage/duration logic that the record command will also use.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.6 — Listing)

**Additional References:**
- specs/meetballs-cli/context.md (WAV header arithmetic)
- specs/meetballs-cli/plan.md (test_list.bats test cases)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Entry function: `cmd_list "$@"`
2. Handle `--help` flag — print usage with description and exit 0
3. Call `mb_init` to ensure directories exist
4. Scan `$RECORDINGS_DIR` for `.wav` files (sorted by name = chronological since names are timestamps)
5. For each WAV file:
   - Compute duration using WAV header arithmetic: `(file_size - 44) / (16000 * 2)`
   - Format duration via `mb_format_duration`
   - Check if `$TRANSCRIPTS_DIR/<basename>.txt` exists → "yes" or "no"
6. Print formatted table with header: `RECORDING`, `DURATION`, `TRANSCRIPT`
7. If no recordings found, print: `No recordings found in <path>`
8. Use `printf` for column alignment

## Dependencies
- Task 01 (common.sh: `mb_init`, `mb_format_duration`, path helpers)
- Task 02 (CLI dispatcher routes `list` to this module)

## Implementation Approach
1. **RED**: Write `tests/test_list.bats` with all test cases using fixture WAV files
2. **GREEN**: Implement `lib/list.sh` with `cmd_list` function
3. **REFACTOR**: Clean up table formatting

### Test cases (from plan):
- `--help` prints usage containing "Usage" and "list", exit 0
- No recordings → output contains "No recordings"
- Lists recordings with columns → create fixture WAV files, output contains filenames
- Shows "yes" for transcribed → create WAV + matching TXT, output line contains "yes"
- Shows "no" for untranscribed → create WAV only, output line contains "no"
- Shows duration → create known-size WAV, output contains formatted duration

### Test fixture strategy:
- Create minimal valid WAV files in `$MEETBALLS_DIR/recordings/` during test setup
- A minimal WAV file: 44-byte header + N bytes of zero data
- For a known duration (e.g., 10 seconds): header + 320000 bytes (16000 * 2 * 10)
- Create matching `.txt` files in `$MEETBALLS_DIR/transcripts/` for transcript tests

## Acceptance Criteria

1. **Help flag**
   - Given the user runs `meetballs list --help`
   - When output is examined
   - Then it contains "Usage" and "list" and exits 0

2. **No recordings message**
   - Given the recordings directory is empty
   - When running `meetballs list`
   - Then output contains "No recordings" and exits 0

3. **Recordings listed with filenames**
   - Given WAV files exist in the recordings directory
   - When running `meetballs list`
   - Then output contains the filenames in a table with header columns

4. **Transcript status yes**
   - Given a WAV file and a matching TXT file exist
   - When running `meetballs list`
   - Then the line for that recording shows "yes"

5. **Transcript status no**
   - Given a WAV file exists but no matching TXT file
   - When running `meetballs list`
   - Then the line for that recording shows "no"

6. **Duration displayed**
   - Given a WAV file of known size exists
   - When running `meetballs list`
   - Then the duration column shows the correct formatted duration

7. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_list.bats`
   - Then all tests pass

## Metadata
- **Complexity**: Medium
- **Labels**: command, list, filesystem
- **Required Skills**: Bash, bats-core testing, WAV format basics
